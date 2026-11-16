from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Protocol

import httpx

from app.core.config import settings
from app.core.errors import ApiError


@dataclass(frozen=True)
class ModelDescriptor:
    model_id: str
    display_name: str
    supports_tools: bool
    supports_vision: bool
    context_window: int = 128000
    input_cost_per_1m_usd: float = 0.0
    output_cost_per_1m_usd: float = 0.0


# Default 2-model catalog aligned with PRD 0.2 (configurable / overridable via Q-2)
DEFAULT_LAB_MODELS: dict[str, ModelDescriptor] = {
    "google/gemini-2.5-flash": ModelDescriptor(
        model_id="google/gemini-2.5-flash",
        display_name="Gemini 2.5 Flash",
        supports_tools=True,
        supports_vision=True,
        context_window=128000,
        input_cost_per_1m_usd=0.15,
        output_cost_per_1m_usd=0.60,
    ),
    "qwen/qwen-2.5-72b-instruct": ModelDescriptor(
        model_id="qwen/qwen-2.5-72b-instruct",
        display_name="Qwen 2.5 72B Instruct",
        supports_tools=True,
        supports_vision=False,
        context_window=128000,
        input_cost_per_1m_usd=0.35,
        output_cost_per_1m_usd=0.40,
    ),
}


@dataclass(frozen=True)
class ToolCallRequest:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class ModelCompletionResult:
    content: str
    tool_calls: list[ToolCallRequest] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    finish_reason: str = "stop"


class ModelProvider(Protocol):
    async def complete(
        self,
        *,
        model_id: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> ModelCompletionResult: ...


class OpenRouterModelProvider:
    """Real OpenRouter client supporting tool_calls loop without exposing reasoning or secrets."""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout_seconds: float = 60.0,
    ) -> None:
        self._api_key = api_key if api_key is not None else settings.openrouter_api_key
        self._base_url = (base_url or settings.openrouter_base_url).rstrip("/")
        self._timeout = timeout_seconds

    async def complete(
        self,
        *,
        model_id: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> ModelCompletionResult:
        if not self._api_key or not self._api_key.strip():
            raise ApiError(
                status_code=503,
                code="provider.not-configured",
                message="Провайдер моделей (OpenRouter) не настроен.",
            )

        payload: dict[str, Any] = {
            "model": model_id,
            "messages": messages,
            "stream": False,
        }
        if tools:
            payload["tools"] = tools

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                resp = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
        except httpx.TimeoutException as exc:
            raise ApiError(
                status_code=504,
                code="provider.timeout",
                message="Превышено время ожидания ответа от модели.",
            ) from exc
        except httpx.HTTPError as exc:
            raise ApiError(
                status_code=502,
                code="provider.network-error",
                message="Ошибка сети при обращении к провайдеру моделей.",
            ) from exc

        if resp.status_code >= 400:
            raise ApiError(
                status_code=502,
                code="provider.upstream-error",
                message=f"Провайдер моделей вернул ошибку ({resp.status_code}).",
            )

        data = resp.json()
        choices = data.get("choices") or []
        if not choices:
            raise ApiError(
                status_code=502,
                code="provider.empty-response",
                message="Модель вернула пустой ответ.",
            )

        choice = choices[0]
        message = choice.get("message") or {}
        content = str(message.get("content") or "")

        parsed_calls: list[ToolCallRequest] = []
        for idx, raw_call in enumerate(message.get("tool_calls") or []):
            fn = raw_call.get("function") or {}
            name = str(fn.get("name") or "")
            raw_args = fn.get("arguments")
            if isinstance(raw_args, dict):
                args = raw_args
            elif isinstance(raw_args, str) and raw_args.strip():
                try:
                    args = json.loads(raw_args)
                    if not isinstance(args, dict):
                        args = {"raw": args}
                except json.JSONDecodeError:
                    args = {"raw": raw_args}
            else:
                args = {}
            parsed_calls.append(
                ToolCallRequest(
                    id=str(raw_call.get("id") or f"call_{idx + 1}"),
                    name=name,
                    arguments=args,
                )
            )

        usage = data.get("usage") or {}
        return ModelCompletionResult(
            content=content,
            tool_calls=parsed_calls,
            input_tokens=int(usage.get("prompt_tokens") or 0),
            output_tokens=int(usage.get("completion_tokens") or 0),
            finish_reason=str(choice.get("finish_reason") or "stop"),
        )
