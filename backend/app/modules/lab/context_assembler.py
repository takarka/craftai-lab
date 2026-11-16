from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any


DEFAULT_PLATFORM_RULES = (
    "Ты ИИ-помощник учителя в CraftAI Lab. Отвечай точно, по делу и на русском языке, "
    "если пользователь не попросил иной язык. Не выдумывай факты и не используй "
    "инструменты вне выданных разрешений."
)


@dataclass(frozen=True)
class SkillContextItem:
    slug: str
    title: str
    content: str
    override_text: str | None = None


@dataclass(frozen=True)
class HistoryMessage:
    role: str  # "user" | "assistant"
    content: str
    status: str = "completed"


@dataclass(frozen=True)
class AssembledContext:
    messages: list[dict[str, Any]]
    estimated_tokens: int
    reserved_tokens: int
    included_history_count: int


class LabContextAssembler:
    """Port of Builder ContextAssembler with fixed PRD §2.3 ordering:
    platform rules -> agent instruction -> enabled skills -> fragments & memory -> history -> user prompt.
    """

    def __init__(self, default_reserved_tokens: int = 4096) -> None:
        self.default_reserved_tokens = default_reserved_tokens

    @staticmethod
    def estimate_tokens(text: str) -> int:
        if not text:
            return 0
        return math.ceil(len(text) / 3.5) + 2

    def assemble(
        self,
        *,
        user_prompt: str,
        context_window: int = 128000,
        reserved_tokens: int | None = None,
        platform_rules: str = DEFAULT_PLATFORM_RULES,
        instruction: str | None = None,
        skills: list[SkillContextItem] | None = None,
        knowledge_chunks: list[str] | None = None,
        memory_facts: list[str] | None = None,
        conversation_history: list[HistoryMessage] | None = None,
        image_data_uris: list[str] | None = None,
    ) -> AssembledContext:
        reserved = reserved_tokens if reserved_tokens is not None else self.default_reserved_tokens
        budget = (context_window - reserved) if context_window > reserved else (context_window // 2)

        system_parts: list[str] = []

        if platform_rules and platform_rules.strip():
            system_parts.append(f"Правила платформы:\n{platform_rules.strip()}")

        if instruction and instruction.strip():
            system_parts.append(f"Инструкция агента:\n{instruction.strip()}")

        if skills:
            skill_blocks: list[str] = []
            for skill in skills:
                block = f"[{skill.title} ({skill.slug})]\n{skill.content.strip()}"
                if skill.override_text and skill.override_text.strip():
                    block += f"\nДополнение учителя:\n{skill.override_text.strip()}"
                skill_blocks.append(block)
            if skill_blocks:
                system_parts.append("Включённые скиллы:\n" + "\n\n".join(skill_blocks))

        if knowledge_chunks:
            clean_chunks = [c.strip() for c in knowledge_chunks if c and c.strip()]
            if clean_chunks:
                system_parts.append(
                    "Фрагменты материалов:\n"
                    + "\n\n".join(f"[Источник]: {chunk}" for chunk in clean_chunks)
                )

        if memory_facts:
            clean_facts = [f.strip() for f in memory_facts if f and f.strip()]
            if clean_facts:
                system_parts.append(
                    "Факты памяти:\n" + "\n".join(f"- {fact}" for fact in clean_facts)
                )

        wire_messages: list[dict[str, Any]] = []
        current_tokens = 0

        if system_parts:
            system_prompt = "\n\n".join(system_parts)
            current_tokens += self.estimate_tokens(system_prompt)
            wire_messages.append({"role": "system", "content": system_prompt})

        current_tokens += self.estimate_tokens(user_prompt)

        history = [
            m
            for m in (conversation_history or [])
            if m.status in ("completed", "interrupted") and m.role in ("user", "assistant")
        ]

        budgeted_history: list[dict[str, Any]] = []
        for msg in reversed(history):
            msg_tokens = self.estimate_tokens(msg.content)
            if current_tokens + msg_tokens > budget:
                break
            current_tokens += msg_tokens
            budgeted_history.insert(0, {"role": msg.role, "content": msg.content})

        wire_messages.extend(budgeted_history)

        if image_data_uris:
            content_parts: list[dict[str, Any]] = [{"type": "text", "text": user_prompt}]
            for uri in image_data_uris:
                content_parts.append({"type": "image_url", "image_url": {"url": uri}})
            wire_messages.append({"role": "user", "content": content_parts})
        else:
            wire_messages.append({"role": "user", "content": user_prompt})

        return AssembledContext(
            messages=wire_messages,
            estimated_tokens=current_tokens,
            reserved_tokens=reserved,
            included_history_count=len(budgeted_history),
        )
