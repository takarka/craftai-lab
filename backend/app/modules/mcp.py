from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Depends

from app.core.security import CurrentUser, get_current_user

router = APIRouter(tags=["mcp"])

LESSON_CATALOG: list[dict[str, Any]] = [
    {
        "id": "lesson-math-fractions-5",
        "title": "Обыкновенные дроби и визуальное моделирование",
        "subject": "Математика",
        "grade": 5,
        "language": "ru",
        "summary": "Пошаговый план урока на 45 минут с практическими задачами на сложение дробей с одинаковыми знаменателями.",
        "objectives": [
            "Понимать смысл числителя и знаменателя обыкновенной дроби",
            "Складывать и вычитать дроби с одинаковыми знаменателями",
        ],
        "activities": [
            "Разминка (5 мин): визуальное сравнение долей круга",
            "Основная часть (25 мин): решение прикладных задач в парах",
            "Рефлексия и мини-тест (15 мин): 4 задачи с самопроверкой",
        ],
    },
    {
        "id": "lesson-physics-kinematics-9",
        "title": "Равноускоренное прямолинейное движение",
        "subject": "Физика",
        "grade": 9,
        "language": "ru",
        "summary": "Исследование графиков скорости и перемещения при равноускоренном движении.",
        "objectives": [
            "Записывать уравнения скорости и координаты",
            "Анализировать график зависимости v(t)",
        ],
        "activities": [
            "Демонстрационный эксперимент с наклонным желобом",
            "Построение и чтение графиков движения",
            "Разбор 3 разноуровневых задач",
        ],
    },
    {
        "id": "lesson-informatics-python-8",
        "title": "Алгоритмы ветвления и циклы в Python",
        "subject": "Информатика",
        "grade": 8,
        "language": "ru",
        "summary": "Практикум по написанию циклов for/while и условных конструкций if-elif-else.",
        "objectives": [
            "Применять оператор условия для разветвляющихся алгоритмов",
            "Использовать цикл for с функцией range()",
        ],
        "activities": [
            "Код-ревью 3 коротких примеров с ошибками",
            "Мини-проект: генератор таблицы умножения и фильтрация чисел",
        ],
    },
    {
        "id": "lesson-kazakh-history-7",
        "title": "Культура и наука средневекового Казахстана",
        "subject": "История Казахстана",
        "grade": 7,
        "language": "ru",
        "summary": "Обзор трудов Аль-Фараби, Юсуфа Баласагуни и Махмуда Кашгари, развитие городов на Великом Шёлковом пути.",
        "objectives": [
            "Оценивать вклад учёных средневековья в мировую науку",
            "Характеризовать роль Великого Шёлкового пути в развитии городской культуры",
        ],
        "activities": [
            "Работа с исторической картой и источниками",
            "Групповая дискуссия: научное наследие Аль-Фараби",
        ],
    },
]

MCP_TOOLS: list[dict[str, Any]] = [
    {
        "name": "search_lessons",
        "description": "Поиск готовых планов уроков и методических материалов по предмету, классу или ключевому слову.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Поисковый запрос или тема урока"},
                "grade": {"type": "integer", "description": "Класс обучения (1-11)"},
            },
        },
    },
    {
        "name": "get_lesson",
        "description": "Получение полного плана урока и упражнений по идентификатору урока.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Идентификатор урока (например, lesson-math-fractions-5)"},
            },
            "required": ["id"],
        },
    },
]


@router.post("/mcp/v1")
async def handle_mcp_jsonrpc(
    payload: dict[str, Any],
    _user: CurrentUser = Depends(get_current_user),
) -> dict[str, Any]:
    rpc_id = payload.get("id")
    method = str(payload.get("method") or "")
    params = payload.get("params") or {}

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {"tools": MCP_TOOLS},
        }

    if method == "tools/call":
        tool_name = str(params.get("name") or "")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            arguments = {}

        if tool_name == "search_lessons":
            query = str(arguments.get("query") or "").strip().lower()
            grade = arguments.get("grade")
            matched = []
            for item in LESSON_CATALOG:
                if grade is not None:
                    try:
                        if int(grade) != item["grade"]:
                            continue
                    except (TypeError, ValueError):
                        pass
                if query:
                    haystack = f"{item['title']} {item['subject']} {item['summary']}".lower()
                    if query not in haystack:
                        continue
                matched.append(
                    {
                        "id": item["id"],
                        "title": item["title"],
                        "subject": item["subject"],
                        "grade": item["grade"],
                        "summary": item["summary"],
                    }
                )
            if not matched:
                matched = [
                    {
                        "id": item["id"],
                        "title": item["title"],
                        "subject": item["subject"],
                        "grade": item["grade"],
                        "summary": item["summary"],
                    }
                    for item in LESSON_CATALOG
                ]
            return {
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({"items": matched}, ensure_ascii=False),
                        }
                    ],
                    "isError": False,
                },
            }

        if tool_name == "get_lesson":
            lesson_id = str(arguments.get("id") or "").strip()
            found = next((i for i in LESSON_CATALOG if i["id"] == lesson_id), None)
            if found is None:
                return {
                    "jsonrpc": "2.0",
                    "id": rpc_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": f"Урок с идентификатором '{lesson_id}' не найден.",
                            }
                        ],
                        "isError": True,
                    },
                }
            return {
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(found, ensure_ascii=False),
                        }
                    ],
                    "isError": False,
                },
            }

        return {
            "jsonrpc": "2.0",
            "id": rpc_id,
            "error": {
                "code": -32601,
                "message": f"Unknown tool '{tool_name}'.",
            },
        }

    return {
        "jsonrpc": "2.0",
        "id": rpc_id,
        "error": {
            "code": -32601,
            "message": f"Method '{method}' not found.",
        },
    }
