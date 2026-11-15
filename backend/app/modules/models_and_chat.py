import asyncio
import json
import re
from collections.abc import AsyncGenerator
from typing import Any

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.core.config import settings
from app.core.database import SessionLocal, TokenUsageLedgerModel
from app.core.errors import ApiError, get_request_id
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now

router = APIRouter()

CATALOG_REVISION = "rev-2026-10-v1"

MODEL_CATALOG: dict[str, dict[str, Any]] = {
    "fast": {
        "category": "fast",
        "modelId": "google/gemini-2.5-flash",
        "available": True,
        "streaming": True,
        "tools": True,
        "languages": ["ru", "kk"],
        "contextWindow": 128000,
    },
    "standard": {
        "category": "standard",
        "modelId": "qwen/qwen-2.5-72b-instruct",
        "available": True,
        "streaming": True,
        "tools": True,
        "languages": ["ru", "kk"],
        "contextWindow": 128000,
    },
    "advanced": {
        "category": "advanced",
        "modelId": "deepseek/deepseek-chat-v3",
        "available": True,
        "streaming": True,
        "tools": True,
        "languages": ["ru", "kk"],
        "contextWindow": 128000,
    },
}


@router.get("/builder/models")
async def get_models_catalog(
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    return {
        "revision": CATALOG_REVISION,
        "models": list(MODEL_CATALOG.values()),
        "fetchedAtUtc": format_utc(utc_now()),
    }


class ChatCompletionRequest(BaseModel):
    category: str = "standard"
    catalogRevision: str = CATALOG_REVISION
    messages: list[dict[str, Any]] = Field(min_length=1, max_length=200)
    tools: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
    toolStep: int = Field(default=0, ge=0, le=10)


def _format_sse(event_type: str, event_id: str, payload: dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False)
    return f"event: {event_type}\nid: {event_id}\ndata: {data}\n\n"


def _build_educational_reply(messages: list[dict[str, Any]]) -> str:
    user_text = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            user_text = str(msg.get("content", "")).strip()
            break

    lower = user_text.lower()
    if "закон ома" in lower or "ом" in lower:
        return (
            "**Закон Ома для участка цепи:**\n\n"
            "Сила тока $I$ на участке цепи прямо пропорциональна напряжению $U$ "
            "и обратно пропорциональна сопротивлению $R$: `I = U / R`.\n\n"
            "1. **Сила тока (А)** — сколько заряда проходит через проводник за секунду.\n"
            "2. **Напряжение (В)** — работа электрического поля по перемещению заряда.\n"
            "3. **Сопротивление (Ом)** — свойство проводника препятствовать току."
        )
    if "план урока" in lower or "сабақ жоспар" in lower or "конспект" in lower:
        return (
            "### План урока (45 минут)\n\n"
            "1. **Организационный момент и актуализация (5 мин):** постановка цели урока на понятном ученикам примере.\n"
            "2. **Объяснение нового материала (15 мин):** ключевое понятие, наглядная схема и разбор типового примера.\n"
            "3. **Практическая работа по уровням (15 мин):**\n"
            "   - Базовый уровень: закрепление определения и формулы;\n"
            "   - Средний уровень: задача на применение;\n"
            "   - Повышенный уровень: нестандартная ситуация.\n"
            "4. **Проверка и рефлексия (10 мин):** разбор частых ошибок и краткий итог."
        )
    return (
        f"Готово! Я проанализировал ваш запрос: «{user_text[:120]}».\n\n"
        "Ключевые рекомендации для занятия:\n"
        "- Сформулируйте измеримую учебную цель для учащихся;\n"
        "- Разделите объяснение на короткие смысловые блоки с примерами;\n"
        "- Предложите 2–3 проверочных вопроса с ключами для быстрой самопроверки."
    )


async def _record_token_usage(
    *,
    request_id: str,
    user_id: str,
    model_id: str,
    input_tokens: int,
    output_tokens: int,
    partial: bool,
) -> None:
    try:
        async with SessionLocal() as db:
            existing = (
                await db.execute(
                    select(TokenUsageLedgerModel).where(TokenUsageLedgerModel.request_id == request_id)
                )
            ).scalar_one_or_none()
            if existing is None:
                db.add(
                    TokenUsageLedgerModel(
                        request_id=request_id,
                        user_id=user_id,
                        model_id=model_id,
                        input_tokens=input_tokens,
                        output_tokens=output_tokens,
                        total_tokens=input_tokens + output_tokens,
                        partial=partial,
                        created_at_utc=format_utc(utc_now()),
                    )
                )
                await db.commit()
    except Exception:
        pass


@router.post("/builder/chat/completions")
async def stream_chat_completion(
    request: Request,
    body: ChatCompletionRequest,
    current_user: CurrentUser = Depends(get_current_user),
) -> StreamingResponse:
    category = body.category.strip().lower()
    descriptor = MODEL_CATALOG.get(category)
    if descriptor is None or not descriptor.get("available", False):
        raise ApiError(
            status_code=503,
            code="MODEL_UNAVAILABLE",
            message=f"Model category '{body.category}' is currently unavailable.",
        )

    model_id = str(descriptor["modelId"])
    req_id = get_request_id(request)

    async def event_generator() -> AsyncGenerator[str, None]:
        seq = 1
        yield _format_sse(
            "start",
            f"evt_{seq}",
            {
                "type": "start",
                "requestId": req_id,
                "sequence": seq,
                "eventId": f"evt_{seq}",
                "modelId": model_id,
            },
        )

        # If OpenRouter key is configured, stream live from OpenRouter
        if settings.openrouter_api_key.strip():
            input_tokens = 0
            output_tokens = 0
            try:
                payload: dict[str, Any] = {
                    "model": model_id,
                    "messages": body.messages,
                    "stream": True,
                }
                if body.tools:
                    payload["tools"] = body.tools

                async with httpx.AsyncClient(timeout=60.0) as client:
                    async with client.stream(
                        "POST",
                        f"{settings.openrouter_base_url.rstrip('/')}/chat/completions",
                        headers={
                            "Authorization": f"Bearer {settings.openrouter_api_key}",
                            "Content-Type": "application/json",
                        },
                        json=payload,
                    ) as resp:
                        if resp.status_code != 200:
                            seq += 1
                            yield _format_sse(
                                "terminal",
                                f"evt_{seq}",
                                {
                                    "type": "terminal",
                                    "requestId": req_id,
                                    "sequence": seq,
                                    "eventId": f"evt_{seq}",
                                    "state": "error",
                                    "code": "UPSTREAM_ERROR",
                                },
                            )
                            return

                        async for line in resp.aiter_lines():
                            if await request.is_disconnected():
                                await _record_token_usage(
                                    request_id=req_id,
                                    user_id=current_user.user_id,
                                    model_id=model_id,
                                    input_tokens=input_tokens,
                                    output_tokens=output_tokens,
                                    partial=True,
                                )
                                return

                            if not line.startswith("data:"):
                                continue
                            raw_data = line[5:].strip()
                            if raw_data == "[DONE]":
                                break
                            try:
                                chunk = json.loads(raw_data)
                            except Exception:
                                continue

                            choices = chunk.get("choices") or []
                            if choices:
                                delta = choices[0].get("delta") or {}
                                content_piece = delta.get("content")
                                if content_piece:
                                    seq += 1
                                    output_tokens += max(1, len(content_piece) // 4)
                                    yield _format_sse(
                                        "text_delta",
                                        f"evt_{seq}",
                                        {
                                            "type": "text_delta",
                                            "requestId": req_id,
                                            "sequence": seq,
                                            "eventId": f"evt_{seq}",
                                            "text": content_piece,
                                        },
                                    )

                            usage_obj = chunk.get("usage")
                            if isinstance(usage_obj, dict):
                                input_tokens = int(usage_obj.get("prompt_tokens", input_tokens))
                                output_tokens = int(usage_obj.get("completion_tokens", output_tokens))

                if input_tokens == 0:
                    input_tokens = max(10, sum(len(str(m.get("content", ""))) for m in body.messages) // 4)

                seq += 1
                yield _format_sse(
                    "usage",
                    f"evt_{seq}",
                    {
                        "type": "usage",
                        "requestId": req_id,
                        "sequence": seq,
                        "eventId": f"evt_{seq}",
                        "tokens": {
                            "inputTokens": input_tokens,
                            "outputTokens": output_tokens,
                            "totalTokens": input_tokens + output_tokens,
                        },
                        "partial": False,
                    },
                )
                await _record_token_usage(
                    request_id=req_id,
                    user_id=current_user.user_id,
                    model_id=model_id,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    partial=False,
                )
                seq += 1
                yield _format_sse(
                    "terminal",
                    f"evt_{seq}",
                    {
                        "type": "terminal",
                        "requestId": req_id,
                        "sequence": seq,
                        "eventId": f"evt_{seq}",
                        "state": "completed",
                        "finishReason": "stop",
                    },
                )
                return
            except Exception:
                seq += 1
                yield _format_sse(
                    "terminal",
                    f"evt_{seq}",
                    {
                        "type": "terminal",
                        "requestId": req_id,
                        "sequence": seq,
                        "eventId": f"evt_{seq}",
                        "state": "error",
                        "code": "UPSTREAM_FAILURE",
                    },
                )
                return

        # Local deterministic streaming mode when OpenRouter key is not set
        full_reply = _build_educational_reply(body.messages)
        words = re.findall(r"\S+\s*", full_reply)
        chunk_size = 4
        output_tokens = 0
        input_tokens = max(12, sum(len(str(m.get("content", ""))) for m in body.messages) // 4)

        for i in range(0, len(words), chunk_size):
            if await request.is_disconnected():
                await _record_token_usage(
                    request_id=req_id,
                    user_id=current_user.user_id,
                    model_id=model_id,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    partial=True,
                )
                return
            piece = "".join(words[i : i + chunk_size])
            seq += 1
            output_tokens += len(words[i : i + chunk_size])
            yield _format_sse(
                "text_delta",
                f"evt_{seq}",
                {
                    "type": "text_delta",
                    "requestId": req_id,
                    "sequence": seq,
                    "eventId": f"evt_{seq}",
                    "text": piece,
                },
            )
            await asyncio.sleep(0.01)

        seq += 1
        yield _format_sse(
            "usage",
            f"evt_{seq}",
            {
                "type": "usage",
                "requestId": req_id,
                "sequence": seq,
                "eventId": f"evt_{seq}",
                "tokens": {
                    "inputTokens": input_tokens,
                    "outputTokens": output_tokens,
                    "totalTokens": input_tokens + output_tokens,
                },
                "partial": False,
            },
        )
        await _record_token_usage(
            request_id=req_id,
            user_id=current_user.user_id,
            model_id=model_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            partial=False,
        )

        seq += 1
        yield _format_sse(
            "terminal",
            f"evt_{seq}",
            {
                "type": "terminal",
                "requestId": req_id,
                "sequence": seq,
                "eventId": f"evt_{seq}",
                "state": "completed",
                "finishReason": "stop",
            },
        )

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream; charset=utf-8",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "X-Request-Id": req_id,
        },
    )
