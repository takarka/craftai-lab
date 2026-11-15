import asyncio

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.database import SessionLocal, UserModel
from app.modules.lab.catalog import seed_catalog
from app.modules.lab.models import (
    AgentSkillOverrideModel,
    AgentVersionModel,
    ConversationModel,
    MaterialModel,
    MemoryEntryModel,
    MessageModel,
    SkillVersionModel,
    new_id,
    timestamp,
)
from app.modules.lab.runtime_models import LabPendingActionModel, LabRunModel
from app.modules.lab.schemas import MaterialInput

ROOT = "/lab/v1"


@pytest.fixture
async def owners(client, monkeypatch):
    monkeypatch.setattr(settings, "lab_model_1_id", "test/model-a")
    monkeypatch.setattr(settings, "lab_model_1_supports_tools", True)
    monkeypatch.setattr(settings, "lab_model_1_supports_vision", True)
    monkeypatch.setattr(settings, "lab_model_2_id", "test/model-b")
    login = await client.post(
        "/mobile/auth/login",
        json={
            "email": "local-dev@craft-ai.local",
            "password": "LocalDevPass123!",
        },
    )
    register = await client.post(
        "/mobile/auth/register",
        json={
            "name": "Other owner",
            "email": "other@craft-ai.local",
            "password": "StrongPassword123",
            "termsRevision": "2026.1-ru",
            "privacyRevision": "2026.1-ru",
            "language": "ru",
        },
    )
    assert login.status_code == register.status_code == 200
    return tuple({"Authorization": f"Bearer {response.json()['accessToken']}"} for response in (login, register))


async def create(client, headers, **changes):
    response = await client.post(f"{ROOT}/agents", headers=headers, json={"name": "Задания", **changes})
    assert response.status_code == 201, response.text
    return response.json()


async def populate(agent):
    async with SessionLocal() as db:
        owner_id = await db.scalar(select(UserModel.id).where(UserModel.email == "local-dev@craft-ai.local"))
        scope = {"owner_id": owner_id, "agent_id": agent["id"], "epoch": agent["epoch"]}
        conversation = ConversationModel(**scope, title="Диалог")
        db.add(conversation)
        await db.flush()
        db.add_all(
            [
                MaterialModel(**scope, title="Материал", text="Текст"),
                MemoryEntryModel(**scope, text="Память"),
                MessageModel(**scope, conversation_id=conversation.id, role="user", content="Вопрос"),
            ]
        )
        await db.commit()


async def counts(agent_id):
    async with SessionLocal() as db:
        return [
            await db.scalar(select(func.count()).select_from(model).where(model.agent_id == agent_id))
            for model in (MaterialModel, MemoryEntryModel, ConversationModel, MessageModel)
        ]


async def test_ownership_on_every_agent_action(client, owners):
    a, b = owners
    agent = await create(client, a, instruction="Секретная инструкция")
    other = await create(client, b, name="Другой агент")
    for method, suffix, body in (
        ("GET", "", None),
        ("PATCH", "", {"name": "Взлом"}),
        ("POST", "/copy", {}),
        ("POST", "/reset", {}),
        ("DELETE", "", None),
    ):
        response = await client.request(method, f"{ROOT}/agents/{agent['id']}{suffix}", headers=b, json=body)
        assert response.status_code == 404
    result = await client.get(f"{ROOT}/agents", headers=b)
    assert [item["id"] for item in result.json()["agents"]] == [other["id"]]
    assert (await client.get(f"{ROOT}/agents/{agent['id']}", headers=a)).json()["instruction"] == "Секретная инструкция"
    assert (await client.get(f"{ROOT}/agents/missing", headers=a)).status_code == 404


async def test_versions_are_immutable_and_pin_skill_text(client, owners):
    a, _ = owners
    agent = await create(
        client,
        a,
        instruction="v1",
        model_id="test/model-a",
        skills=[
            {
                "skill_id": "prepare_tasks",
                "instruction_override": "Для пятого класса",
            }
        ],
    )
    path = f"{ROOT}/agents/{agent['id']}"
    updated = await client.patch(path, headers=a, json={"instruction": "v2", "name": "Новое имя"})
    assert updated.status_code == 200
    assert updated.json()["version"] == 2
    assert updated.json()["version_id"] != agent["version_id"]
    assert updated.json()["skills"] == agent["skills"]
    assert (await client.patch(path, headers=a, json={})).json()["version"] == 2
    assert (await client.patch(path, headers=a, json={"instruction": None})).status_code == 422
    async with SessionLocal() as db:
        old = await db.get(AgentVersionModel, agent["version_id"])
        assert old.configuration["instruction"] == "v1"
        assert await db.scalar(select(func.count()).select_from(AgentSkillOverrideModel)) == 2
    listed = (await client.get(f"{ROOT}/agents", headers=a)).json()["agents"]
    assert len(listed) == 1 and listed[0]["version"] == 2


async def test_copy_configuration_without_data(client, owners):
    a, _ = owners
    source = await create(
        client,
        a,
        instruction="Копируемая инструкция",
        skills=[{"skill_id": "check_answer"}],
        permissions={"save_material": True, "search_materials": False},
    )
    await populate(source)
    response = await client.post(f"{ROOT}/agents/{source['id']}/copy", headers=a, json={"name": "Копия"})
    assert response.status_code == 201
    copied = response.json()
    assert copied["id"] != source["id"]
    for field in ("instruction", "model_id", "skills", "permissions", "limits"):
        assert copied[field] == source[field]
    assert copied["version"] == 1 and copied["epoch"] == 0
    assert await counts(copied["id"]) == [0, 0, 0, 0]
    assert await counts(source["id"]) == [1, 1, 1, 1]


async def test_reset_and_delete_preserve_other_agent_and_course(client, owners):
    a, b = owners
    first = await create(client, a, instruction="Сохранить настройки")
    second = await create(client, a)
    await populate(first)
    await populate(second)
    progress_path = f"{ROOT}/course/progress"
    response = await client.put(progress_path, headers=a, json={"completed_lessons": [1, 2], "current_lesson": 3})
    assert response.status_code == 200
    progress = response.json()
    reset = await client.post(f"{ROOT}/agents/{first['id']}/reset", headers=a)
    assert reset.status_code == 200
    assert reset.json()["epoch"] == 1
    assert reset.json()["version_id"] == first["version_id"]
    assert reset.json()["instruction"] == first["instruction"]
    assert await counts(first["id"]) == [0, 0, 0, 0]
    assert await counts(second["id"]) == [1, 1, 1, 1]
    assert (await client.get(progress_path, headers=a)).json() == progress
    assert (await client.get(progress_path, headers=b)).json()["completed_lessons"] == []
    await populate(first)
    path = f"{ROOT}/agents/{first['id']}"
    assert (await client.delete(path, headers=a)).status_code == 204
    assert (await client.delete(path, headers=a)).status_code == 204
    assert (await client.delete(path, headers=b)).status_code == 404
    assert (await client.get(path, headers=a)).status_code == 404
    assert (await client.post(f"{path}/reset", headers=a)).status_code == 404
    assert (await client.post(f"{path}/copy", headers=a)).status_code == 404
    assert (await client.patch(path, headers=a, json={"name": "Вернуть"})).status_code == 404
    assert await counts(first["id"]) == [0, 0, 0, 0]
    assert await counts(second["id"]) == [1, 1, 1, 1]
    async with SessionLocal() as db:
        assert (
            await db.scalar(
                select(func.count())
                .select_from(AgentVersionModel)
                .where(
                    AgentVersionModel.agent_id == first["id"],
                )
            )
            == 0
        )
    assert (await client.get(progress_path, headers=a)).json() == progress


async def test_limit_concurrent_creation_copy_and_slot_reuse(client, owners):
    a, b = owners
    results = await asyncio.gather(
        *[client.post(f"{ROOT}/agents", headers=a, json={"name": f"Агент {i}"}) for i in range(7)]
    )
    assert sorted(response.status_code for response in results) == [201] * 5 + [409] * 2
    assert all(response.json()["code"] == "agents.limit-reached" for response in results if response.status_code == 409)
    first = next(response.json() for response in results if response.status_code == 201)
    assert (await client.post(f"{ROOT}/agents/{first['id']}/copy", headers=a)).status_code == 409
    assert (await client.delete(f"{ROOT}/agents/{first['id']}", headers=a)).status_code == 204
    await create(client, a, name="Свободный слот")
    assert len((await client.get(f"{ROOT}/agents", headers=a)).json()["agents"]) == 5
    await create(client, b)


async def test_concurrent_patches_serialize_versions(client, owners):
    a, _ = owners
    agent = await create(client, a)
    responses = await asyncio.gather(
        *[
            client.patch(f"{ROOT}/agents/{agent['id']}", headers=a, json={"instruction": str(index)})
            for index in range(4)
        ]
    )
    assert all(response.status_code == 200 for response in responses)
    assert sorted(response.json()["version"] for response in responses) == [2, 3, 4, 5]


async def test_reset_cancels_only_target_agent_active_work(client, owners):
    a, _ = owners
    first = await create(client, a)
    second = await create(client, a)
    async with SessionLocal() as db:
        owner_id = await db.scalar(select(UserModel.id).where(UserModel.email == "local-dev@craft-ai.local"))
        runs = []
        for agent, status in ((first, "running"), (first, "completed"), (second, "running")):
            run = LabRunModel(
                id=new_id(),
                owner_id=owner_id,
                agent_id=agent["id"],
                agent_version_id=agent["version_id"],
                epoch=agent["epoch"],
                model_id="test/model-a",
                version_snapshot_json={},
                user_prompt="Тест",
                status=status,
                created_at_utc=timestamp(),
                updated_at_utc=timestamp(),
            )
            db.add(run)
            runs.append(run)
        await db.flush()
        action = LabPendingActionModel(
            id=new_id(),
            run_id=runs[0].id,
            owner_id=owner_id,
            agent_id=first["id"],
            tool_call_id="call-1",
            tool_name="save_material",
            params_json={},
            params_hash="hash",
            created_at_utc=timestamp(),
            expires_at_utc="2099-01-01T00:00:00Z",
        )
        db.add(action)
        await db.commit()
        run_ids, action_id = [run.id for run in runs], action.id
    assert (await client.post(f"{ROOT}/agents/{first['id']}/reset", headers=a)).status_code == 200
    async with SessionLocal() as db:
        assert [(await db.get(LabRunModel, run_id)).status for run_id in run_ids] == [
            "cancelled",
            "completed",
            "running",
        ]
        assert (await db.get(LabPendingActionModel, action_id)).status == "cancelled"


@pytest.mark.parametrize(
    "field,value",
    [
        ("instruction", "я" * 5001),
        ("skills", [{"skill_id": "prepare_tasks", "instruction_override": "я" * 5001}]),
        ("skills", [{"skill_id": "missing"}]),
        ("skills", [{"skill_id": "prepare_tasks", "version": 99}]),
        ("skills", [{"skill_id": "prepare_tasks"}] * 2),
        ("model_id", "not/in/catalog"),
        ("owner_id", "another-owner"),
        ("name", "  "),
    ],
)
async def test_invalid_configuration_has_no_side_effects(client, owners, field, value):
    a, _ = owners
    response = await client.post(f"{ROOT}/agents", headers=a, json={"name": "Агент", field: value})
    assert response.status_code == 422
    assert (await client.get(f"{ROOT}/agents", headers=a)).json()["agents"] == []
    agent = await create(client, a)
    response = await client.patch(f"{ROOT}/agents/{agent['id']}", headers=a, json={field: value})
    assert response.status_code == 422
    assert (await client.get(f"{ROOT}/agents/{agent['id']}", headers=a)).json()["version"] == 1


async def test_text_boundaries_and_material_db_constraint(client, owners):
    a, _ = owners
    agent = await create(
        client,
        a,
        instruction="я" * 5000,
        skills=[
            {
                "skill_id": "prepare_tasks",
                "instruction_override": "я" * 5000,
            }
        ],
    )
    assert len(agent["instruction"]) == 5000
    assert len(MaterialInput(title="Текст", text="я" * 10000).text) == 10000
    with pytest.raises(ValidationError):
        MaterialInput(title="Текст", text="я" * 10001)
    async with SessionLocal() as db:
        owner_id = await db.scalar(select(UserModel.id).where(UserModel.email == "local-dev@craft-ai.local"))
        db.add(MaterialModel(owner_id=owner_id, agent_id=agent["id"], title="Текст", text="я" * 10001))
        with pytest.raises(IntegrityError):
            await db.commit()
        await db.rollback()


async def test_catalog_and_progress_merge(client, owners, monkeypatch):
    a, b = owners
    models = (await client.get(f"{ROOT}/models", headers=a)).json()["models"]
    assert len(models) == 2
    assert models[0]["supports_tools"] and models[0]["supports_vision"]
    assert not models[1]["supports_tools"]
    monkeypatch.setattr(settings, "lab_model_2_id", "")
    models = (await client.get(f"{ROOT}/models", headers=a)).json()["models"]
    assert not models[1]["available"] and models[1]["model_id"] is None
    async with SessionLocal() as db:
        await seed_catalog(db)
        await seed_catalog(db)
        await db.commit()
        assert await db.scalar(select(func.count()).select_from(SkillVersionModel)) == 2
    skills = (await client.get(f"{ROOT}/skills", headers=a)).json()["skills"]
    assert len(skills) == 2 and all(skill["version"] == 1 for skill in skills)
    path = f"{ROOT}/course/progress"
    await client.put(path, headers=a, json={"completed_lessons": [1, 2], "current_lesson": 3})
    progress = await client.put(path, headers=a, json={"course_version": "0.3", "completed_lessons": [3]})
    assert progress.json()["completed_lessons"] == [1, 2, 3]
    assert progress.json()["course_version"] == "0.3"
    assert (await client.get(path, headers=b)).json()["completed_lessons"] == []
    assert (await client.put(path, headers=a, json={"completed_lessons": [8]})).status_code == 422


@pytest.mark.parametrize("path", ["agents", "models", "skills", "course/progress"])
async def test_lab_requires_authentication(client, path):
    assert (await client.get(f"{ROOT}/{path}")).status_code == 401
