from __future__ import annotations

import hashlib
import json
import time
import uuid
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Any, Awaitable, Callable, Protocol

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ApiError
from app.core.security import format_utc, utc_now
from app.modules.lab.context_assembler import (
    DEFAULT_PLATFORM_RULES,
    HistoryMessage,
    LabContextAssembler,
    SkillContextItem,
)
from app.modules.lab.model_provider import (
    DEFAULT_LAB_MODELS,
    ModelDescriptor,
    ModelProvider,
)
from app.modules.lab.runtime_models import (
    LabPendingActionModel,
    LabRunEventModel,
    LabRunModel,
    LabUsageLedgerModel,
)

MAX_TOOL_CALLS = 3
ACTIVE_TIMEOUT_SECONDS = 60
CONFIRMATION_TTL_SECONDS = 15 * 60  # 15 minutes
DEFAULT_PILOT_BUDGET_USD = 5.0

_FORBIDDEN_EVENT_KEYS = frozenset(
    {
        "reasoning",
        "thinking",
        "hidden_reasoning",
        "reasoning_content",
        "api_key",
        "apikey",
        "authorization",
        "secret",
        "password",
        "access_token",
        "refresh_token",
    }
)


def compute_params_hash(params: dict[str, Any]) -> str:
    canonical = json.dumps(params, sort_keys=True, ensure_ascii=False, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def sanitize_event_payload(value: Any) -> Any:
    """Recursively strip secrets and hidden reasoning fields from run event payloads."""
    if isinstance(value, dict):
        cleaned: dict[str, Any] = {}
        for k, v in value.items():
            if str(k).lower() in _FORBIDDEN_EVENT_KEYS:
                continue
            cleaned[k] = sanitize_event_payload(v)
        return cleaned
    if isinstance(value, list):
        return [sanitize_event_payload(item) for item in value]
    return value


@dataclass(frozen=True)
class AgentSnapshot:
    agent_id: str
    agent_version_id: str
    owner_id: str
    epoch: int
    model_id: str
    instruction: str | None = None
    skills: list[SkillContextItem] = field(default_factory=list)
    knowledge_chunks: list[str] = field(default_factory=list)
    memory_facts: list[str] = field(default_factory=list)
    conversation_history: list[HistoryMessage] = field(default_factory=list)
    allow_save: bool = False
    allow_search: bool = False
    platform_rules: str = DEFAULT_PLATFORM_RULES
    max_tool_calls: int = MAX_TOOL_CALLS
    active_timeout_seconds: int = ACTIVE_TIMEOUT_SECONDS
    confirmation_ttl_seconds: int = CONFIRMATION_TTL_SECONDS

    def to_snapshot_dict(self) -> dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "agent_version_id": self.agent_version_id,
            "epoch": self.epoch,
            "model_id": self.model_id,
            "instruction": self.instruction,
            "skills": [
                {"slug": s.slug, "title": s.title, "content": s.content, "override_text": s.override_text}
                for s in self.skills
            ],
            "knowledge_chunks": list(self.knowledge_chunks),
            "memory_facts": list(self.memory_facts),
            "allow_save": self.allow_save,
            "allow_search": self.allow_search,
            "platform_rules": self.platform_rules,
            "max_tool_calls": self.max_tool_calls,
            "active_timeout_seconds": self.active_timeout_seconds,
            "confirmation_ttl_seconds": self.confirmation_ttl_seconds,
        }


class ToolExecutor(Protocol):
    async def execute(
        self,
        *,
        owner_id: str,
        agent_id: str,
        tool_name: str,
        params: dict[str, Any],
    ) -> dict[str, Any]: ...


class DefaultStubToolExecutor:
    """Fallback executor used before Phase 3 MCP 'Materials' is wired."""

    async def execute(
        self,
        *,
        owner_id: str,
        agent_id: str,
        tool_name: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        if tool_name == "save_material":
            return {"status": "saved", "material_id": str(uuid.uuid4()), "title": params.get("title", "")}
        if tool_name == "search_materials":
            return {"status": "ok", "items": []}
        raise ApiError(status_code=400, code="tool.unknown", message=f"Неизвестный инструмент: {tool_name}")


EpochLookupFn = Callable[[AsyncSession, str, str], Awaitable[int | None]]


def build_tool_schemas(*, allow_save: bool, allow_search: bool) -> list[dict[str, Any]]:
    tools: list[dict[str, Any]] = []
    if allow_save:
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": "save_material",
                    "description": "Сохранить учебный материал в библиотеку текущего агента.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "description": "Название материала"},
                            "content": {"type": "string", "description": "Текст материала"},
                        },
                        "required": ["title", "content"],
                    },
                },
            }
        )
    if allow_search:
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": "search_materials",
                    "description": "Найти ранее сохранённые материалы текущего агента по запросу.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Поисковый запрос"},
                        },
                        "required": ["query"],
                    },
                },
            }
        )
    return tools


class LabHarness:
    def __init__(
        self,
        *,
        model_provider: ModelProvider,
        tool_executor: ToolExecutor | None = None,
        models_catalog: dict[str, ModelDescriptor] | None = None,
        context_assembler: LabContextAssembler | None = None,
        pilot_budget_usd: float = DEFAULT_PILOT_BUDGET_USD,
        epoch_lookup: EpochLookupFn | None = None,
    ) -> None:
        self.model_provider = model_provider
        self.tool_executor = tool_executor or DefaultStubToolExecutor()
        self.models_catalog = models_catalog or DEFAULT_LAB_MODELS
        self.context_assembler = context_assembler or LabContextAssembler()
        self.pilot_budget_usd = pilot_budget_usd
        self.epoch_lookup = epoch_lookup

    def validate_model_compatibility(self, snapshot: AgentSnapshot, *, has_photo: bool) -> ModelDescriptor:
        descriptor = self.models_catalog.get(snapshot.model_id)
        if descriptor is None:
            raise ApiError(
                status_code=422,
                code="model.unknown",
                message=f"Модель '{snapshot.model_id}' не входит в каталог Lab.",
            )
        if has_photo and not descriptor.supports_vision:
            raise ApiError(
                status_code=422,
                code="model.incompatible-vision",
                message="Выбранная модель не поддерживает анализ изображений. Смените модель в настройках агента.",
            )
        if (snapshot.allow_save or snapshot.allow_search) and not descriptor.supports_tools:
            raise ApiError(
                status_code=422,
                code="model.incompatible-tools",
                message="Выбранная модель не поддерживает вызов инструментов. Отключите инструменты или смените модель.",
            )
        return descriptor

    async def check_pilot_budget(self, db: AsyncSession, *, owner_id: str) -> None:
        stmt = select(func.coalesce(func.sum(LabUsageLedgerModel.estimated_cost_usd), 0.0)).where(
            LabUsageLedgerModel.owner_id == owner_id
        )
        spent = float((await db.execute(stmt)).scalar_one() or 0.0)
        if spent >= self.pilot_budget_usd:
            raise ApiError(
                status_code=402,
                code="budget.exceeded",
                message="Бюджет пилота исчерпан. Дальнейшие запуски остановлены.",
            )

    async def _is_epoch_current(self, db: AsyncSession, run: LabRunModel) -> bool:
        if self.epoch_lookup is None:
            return True
        current_epoch = await self.epoch_lookup(db, run.owner_id, run.agent_id)
        if current_epoch is None:
            return False
        return current_epoch == run.epoch

    async def _next_sequence(self, db: AsyncSession, run_id: str) -> int:
        stmt = select(func.coalesce(func.max(LabRunEventModel.sequence), 0)).where(
            LabRunEventModel.run_id == run_id
        )
        return int((await db.execute(stmt)).scalar_one() or 0) + 1

    async def append_event(
        self,
        db: AsyncSession,
        run: LabRunModel,
        event_type: str,
        payload: dict[str, Any],
    ) -> LabRunEventModel | None:
        if not await self._is_epoch_current(db, run):
            return None
        seq = await self._next_sequence(db, run.id)
        event = LabRunEventModel(
            id=str(uuid.uuid4()),
            run_id=run.id,
            owner_id=run.owner_id,
            agent_id=run.agent_id,
            epoch=run.epoch,
            sequence=seq,
            event_type=event_type,
            payload_json=sanitize_event_payload(payload),
            created_at_utc=format_utc(utc_now()),
        )
        db.add(event)
        await db.commit()
        return event

    async def _record_usage(
        self,
        db: AsyncSession,
        *,
        run: LabRunModel,
        descriptor: ModelDescriptor,
        input_tokens: int,
        output_tokens: int,
    ) -> float:
        cost = (
            (input_tokens / 1_000_000.0) * descriptor.input_cost_per_1m_usd
            + (output_tokens / 1_000_000.0) * descriptor.output_cost_per_1m_usd
        )
        entry = LabUsageLedgerModel(
            id=str(uuid.uuid4()),
            run_id=run.id,
            owner_id=run.owner_id,
            model_id=descriptor.model_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            total_tokens=input_tokens + output_tokens,
            estimated_cost_usd=cost,
            partial=False,
            created_at_utc=format_utc(utc_now()),
        )
        db.add(entry)
        await db.commit()
        return cost

    async def start_run(
        self,
        db: AsyncSession,
        *,
        snapshot: AgentSnapshot,
        user_prompt: str,
        conversation_id: str | None = None,
        idempotency_key: str | None = None,
        image_data_uris: list[str] | None = None,
        dialogue_run_id: str | None = None,
        dialogue_request_hash: str | None = None,
        dialogue_created_at: str | None = None,
    ) -> LabRunModel:
        has_photo = bool(image_data_uris)
        descriptor = self.validate_model_compatibility(snapshot, has_photo=has_photo)
        await self.check_pilot_budget(db, owner_id=snapshot.owner_id)

        now_str = format_utc(utc_now())
        version_snapshot = snapshot.to_snapshot_dict()
        if dialogue_request_hash is not None:
            version_snapshot["dialogue_request_hash"] = dialogue_request_hash
            version_snapshot["dialogue_history"] = [
                {"role": item.role, "content": item.content, "status": item.status}
                for item in snapshot.conversation_history
            ]
        run = LabRunModel(
            id=dialogue_run_id or str(uuid.uuid4()),
            owner_id=snapshot.owner_id,
            agent_id=snapshot.agent_id,
            agent_version_id=snapshot.agent_version_id,
            conversation_id=conversation_id,
            epoch=snapshot.epoch,
            model_id=snapshot.model_id,
            version_snapshot_json=version_snapshot,
            status="running",
            idempotency_key=idempotency_key,
            user_prompt=user_prompt,
            created_at_utc=dialogue_created_at or now_str,
            updated_at_utc=now_str,
        )
        db.add(run)
        await db.commit()

        await self.append_event(
            db,
            run,
            "run_started",
            {
                "run_id": run.id,
                "agent_id": run.agent_id,
                "agent_version_id": run.agent_version_id,
                "model_id": run.model_id,
                "epoch": run.epoch,
            },
        )

        assembled = self.context_assembler.assemble(
            user_prompt=user_prompt,
            context_window=descriptor.context_window,
            platform_rules=snapshot.platform_rules,
            instruction=snapshot.instruction,
            skills=snapshot.skills,
            knowledge_chunks=snapshot.knowledge_chunks,
            memory_facts=snapshot.memory_facts,
            conversation_history=snapshot.conversation_history,
            image_data_uris=image_data_uris,
        )

        if dialogue_request_hash is not None:
            budget = (
                descriptor.context_window - assembled.reserved_tokens
                if descriptor.context_window > assembled.reserved_tokens
                else descriptor.context_window // 2
            )
            if (
                assembled.included_history_count != len(snapshot.conversation_history)
                or assembled.estimated_tokens > budget
            ):
                return await self.fail_dialogue_run(
                    db, run, "dialogue.context-limit",
                    "Этот диалог достиг предела контекста. История сохранена.",
                )
        try:
            return await self._execute_loop(
                db=db,
                run=run,
                snapshot=snapshot,
                descriptor=descriptor,
                messages=assembled.messages,
            )
        except ApiError as error:
            if dialogue_request_hash is None:
                raise
            return await self.fail_dialogue_run(db, run, error.code, error.message)

    async def fail_dialogue_run(
        self, db: AsyncSession, run: LabRunModel, code: str, message: str,
    ) -> LabRunModel:
        await db.refresh(run)
        if run.status == "cancelled":
            return run
        run.status = "failed"
        run.stop_reason = code
        run.error_code = code
        run.error_message = message
        run.updated_at_utc = format_utc(utc_now())
        run.completed_at_utc = run.updated_at_utc
        await db.commit()
        await self.append_event(db, run, "run_failed", {"error_code": code})
        return run

    async def resolve_action(
        self,
        db: AsyncSession,
        *,
        run: LabRunModel,
        action: LabPendingActionModel,
        decision: str,
        params: dict[str, Any] | None = None,
    ) -> LabRunModel:
        if action.status != "pending":
            raise ApiError(
                status_code=409,
                code="action.already-resolved",
                message="Запрос подтверждения уже обработан.",
            )

        now = utc_now()
        now_str = format_utc(now)
        if now_str > action.expires_at_utc:
            action.status = "expired"
            action.resolved_at_utc = now_str
            run.status = "completed"
            run.stop_reason = "confirmation_expired"
            run.final_output = "Время ожидания подтверждения истекло (15 минут). Действие не выполнено."
            run.updated_at_utc = now_str
            run.completed_at_utc = now_str
            await db.commit()
            await self.append_event(db, run, "action_expired", {"action_id": action.id, "tool_name": action.tool_name})
            await self.append_event(
                db, run, "run_completed", {"stop_reason": run.stop_reason, "final_output": run.final_output}
            )
            raise ApiError(
                status_code=409,
                code="action.expired",
                message="Время ожидания подтверждения истекло. Действие не выполнено.",
            )

        if params is not None and compute_params_hash(params) != action.params_hash:
            raise ApiError(
                status_code=409,
                code="action.params-changed",
                message="Параметры действия изменились и требуют нового подтверждения.",
            )

        if decision == "deny":
            action.status = "denied"
            action.resolved_at_utc = now_str
            run.status = "completed"
            run.stop_reason = "action_denied"
            run.final_output = "Действие отклонено пользователем. Запись не создана."
            run.updated_at_utc = now_str
            run.completed_at_utc = now_str
            await db.commit()
            await self.append_event(
                db,
                run,
                "action_resolved",
                {"action_id": action.id, "tool_name": action.tool_name, "decision": "denied"},
            )
            await self.append_event(
                db, run, "run_completed", {"stop_reason": run.stop_reason, "final_output": run.final_output}
            )
            return run

        if decision != "approve":
            raise ApiError(status_code=400, code="action.invalid-decision", message="Недопустимое решение.")

        action.status = "approved"
        action.resolved_at_utc = now_str
        run.status = "running"
        run.updated_at_utc = now_str
        await db.commit()
        await self.append_event(
            db,
            run,
            "action_resolved",
            {"action_id": action.id, "tool_name": action.tool_name, "decision": "approved"},
        )

        # Execute the approved tool and resume the model loop
        t0 = time.monotonic()
        tool_result = await self.tool_executor.execute(
            owner_id=run.owner_id,
            agent_id=run.agent_id,
            tool_name=action.tool_name,
            params=action.params_json,
        )
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        run.active_elapsed_ms += elapsed_ms
        await db.commit()

        await self.append_event(
            db,
            run,
            "tool_result",
            {
                "tool_call_id": action.tool_call_id,
                "tool_name": action.tool_name,
                "result": tool_result,
            },
        )

        snap_data = run.version_snapshot_json
        snapshot = AgentSnapshot(
            agent_id=run.agent_id,
            agent_version_id=run.agent_version_id,
            owner_id=run.owner_id,
            epoch=run.epoch,
            model_id=run.model_id,
            instruction=snap_data.get("instruction"),
            skills=[SkillContextItem(**s) for s in snap_data.get("skills", [])],
            knowledge_chunks=snap_data.get("knowledge_chunks", []),
            memory_facts=snap_data.get("memory_facts", []),
            conversation_history=[HistoryMessage(**m) for m in snap_data.get("dialogue_history", [])],
            allow_save=bool(snap_data.get("allow_save", False)),
            allow_search=bool(snap_data.get("allow_search", False)),
            platform_rules=snap_data.get("platform_rules", DEFAULT_PLATFORM_RULES),
            max_tool_calls=int(snap_data.get("max_tool_calls", MAX_TOOL_CALLS)),
            active_timeout_seconds=int(snap_data.get("active_timeout_seconds", ACTIVE_TIMEOUT_SECONDS)),
            confirmation_ttl_seconds=int(snap_data.get("confirmation_ttl_seconds", CONFIRMATION_TTL_SECONDS)),
        )
        descriptor = self.models_catalog[run.model_id]
        assembled = self.context_assembler.assemble(
            user_prompt=run.user_prompt,
            context_window=descriptor.context_window,
            platform_rules=snapshot.platform_rules,
            instruction=snapshot.instruction,
            skills=snapshot.skills,
            knowledge_chunks=snapshot.knowledge_chunks,
            memory_facts=snapshot.memory_facts,
            conversation_history=snapshot.conversation_history,
        )
        messages = assembled.messages + [
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": action.tool_call_id,
                        "type": "function",
                        "function": {
                            "name": action.tool_name,
                            "arguments": json.dumps(action.params_json, ensure_ascii=False),
                        },
                    }
                ],
            },
            {
                "role": "tool",
                "tool_call_id": action.tool_call_id,
                "content": json.dumps(tool_result, ensure_ascii=False),
            },
        ]
        return await self._execute_loop(
            db=db,
            run=run,
            snapshot=snapshot,
            descriptor=descriptor,
            messages=messages,
        )

    async def _execute_loop(
        self,
        *,
        db: AsyncSession,
        run: LabRunModel,
        snapshot: AgentSnapshot,
        descriptor: ModelDescriptor,
        messages: list[dict[str, Any]],
    ) -> LabRunModel:
        tools = build_tool_schemas(allow_save=snapshot.allow_save, allow_search=snapshot.allow_search)

        while True:
            await db.refresh(run)
            if run.status == "cancelled":
                return run

            if not await self._is_epoch_current(db, run):
                run.status = "cancelled"
                run.stop_reason = "agent_reset"
                run.updated_at_utc = format_utc(utc_now())
                run.completed_at_utc = run.updated_at_utc
                await db.commit()
                return run

            if run.active_elapsed_ms >= snapshot.active_timeout_seconds * 1000:
                run.status = "completed"
                run.stop_reason = "time_limit"
                run.final_output = run.final_output or "Превышен лимит времени активного выполнения (60 с)."
                run.updated_at_utc = format_utc(utc_now())
                run.completed_at_utc = run.updated_at_utc
                await db.commit()
                await self.append_event(
                    db,
                    run,
                    "run_completed",
                    {"stop_reason": run.stop_reason, "final_output": run.final_output},
                )
                return run

            t0 = time.monotonic()
            result = await self.model_provider.complete(
                model_id=descriptor.model_id,
                messages=messages,
                tools=tools or None,
            )
            elapsed_ms = int((time.monotonic() - t0) * 1000)
            run.active_elapsed_ms += elapsed_ms
            await db.commit()

            if not await self._is_epoch_current(db, run):
                run.status = "cancelled"
                run.stop_reason = "agent_reset"
                run.updated_at_utc = format_utc(utc_now())
                run.completed_at_utc = run.updated_at_utc
                await db.commit()
                return run

            await self._record_usage(
                db,
                run=run,
                descriptor=descriptor,
                input_tokens=result.input_tokens,
                output_tokens=result.output_tokens,
            )

            if not result.tool_calls:
                run.status = "completed"
                run.stop_reason = "completed"
                run.final_output = result.content
                run.updated_at_utc = format_utc(utc_now())
                run.completed_at_utc = run.updated_at_utc
                await db.commit()
                await self.append_event(
                    db,
                    run,
                    "run_completed",
                    {
                        "stop_reason": run.stop_reason,
                        "final_output": run.final_output,
                        "tool_calls_count": run.tool_calls_count,
                    },
                )
                return run

            assistant_tool_calls: list[dict[str, Any]] = []
            tool_result_messages: list[dict[str, Any]] = []

            for call in result.tool_calls:
                if run.tool_calls_count >= snapshot.max_tool_calls:
                    run.status = "completed"
                    run.stop_reason = "tool_limit"
                    run.final_output = result.content or f"Достигнут лимит вызовов инструментов ({snapshot.max_tool_calls})."
                    run.updated_at_utc = format_utc(utc_now())
                    run.completed_at_utc = run.updated_at_utc
                    await db.commit()
                    await self.append_event(
                        db,
                        run,
                        "run_completed",
                        {
                            "stop_reason": run.stop_reason,
                            "final_output": run.final_output,
                            "tool_calls_count": run.tool_calls_count,
                        },
                    )
                    return run

                allowed = (
                    (call.name == "save_material" and snapshot.allow_save)
                    or (call.name == "search_materials" and snapshot.allow_search)
                )
                if not allowed:
                    await self.append_event(
                        db,
                        run,
                        "tool_rejected",
                        {"tool_call_id": call.id, "tool_name": call.name, "reason": "permission_denied"},
                    )
                    assistant_tool_calls.append(
                        {
                            "id": call.id,
                            "type": "function",
                            "function": {
                                "name": call.name,
                                "arguments": json.dumps(call.arguments, ensure_ascii=False),
                            },
                        }
                    )
                    tool_result_messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": call.id,
                            "content": json.dumps(
                                {"error": "tool_not_allowed", "tool": call.name}, ensure_ascii=False
                            ),
                        }
                    )
                    continue

                if call.name == "save_material":
                    now = utc_now()
                    p_hash = compute_params_hash(call.arguments)
                    action = LabPendingActionModel(
                        id=str(uuid.uuid4()),
                        run_id=run.id,
                        owner_id=run.owner_id,
                        agent_id=run.agent_id,
                        tool_call_id=call.id,
                        tool_name=call.name,
                        params_json=call.arguments,
                        params_hash=p_hash,
                        status="pending",
                        created_at_utc=format_utc(now),
                        expires_at_utc=format_utc(now + timedelta(seconds=snapshot.confirmation_ttl_seconds)),
                    )
                    db.add(action)
                    run.tool_calls_count += 1
                    run.status = "awaiting_confirmation"
                    run.updated_at_utc = format_utc(now)
                    await db.commit()
                    await self.append_event(
                        db,
                        run,
                        "action_required",
                        {
                            "action_id": action.id,
                            "tool_call_id": call.id,
                            "tool_name": call.name,
                            "params": call.arguments,
                            "params_hash": p_hash,
                            "expires_at_utc": action.expires_at_utc,
                        },
                    )
                    return run

                # Read-only tool execution (search_materials)
                run.tool_calls_count += 1
                run.updated_at_utc = format_utc(utc_now())
                await db.commit()
                await self.append_event(
                    db,
                    run,
                    "tool_call",
                    {"tool_call_id": call.id, "tool_name": call.name, "params": call.arguments},
                )

                t_tool = time.monotonic()
                tool_res = await self.tool_executor.execute(
                    owner_id=run.owner_id,
                    agent_id=run.agent_id,
                    tool_name=call.name,
                    params=call.arguments,
                )
                run.active_elapsed_ms += int((time.monotonic() - t_tool) * 1000)
                await db.commit()

                await self.append_event(
                    db,
                    run,
                    "tool_result",
                    {"tool_call_id": call.id, "tool_name": call.name, "result": tool_res},
                )

                assistant_tool_calls.append(
                    {
                        "id": call.id,
                        "type": "function",
                        "function": {
                            "name": call.name,
                            "arguments": json.dumps(call.arguments, ensure_ascii=False),
                        },
                    }
                )
                tool_result_messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call.id,
                        "content": json.dumps(tool_res, ensure_ascii=False),
                    }
                )

            messages.append({"role": "assistant", "content": result.content, "tool_calls": assistant_tool_calls})
            messages.extend(tool_result_messages)
