from __future__ import annotations

import uuid
from datetime import datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, BackgroundTasks, Depends, Header, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import (
    CalendarEventModel,
    ScheduleModel,
    ScheduleRunModel,
    SessionLocal,
    UserDeviceModel,
    get_db,
)
from app.core.errors import ApiError
from app.core.idempotency import check_idempotency, compute_request_hash, save_idempotency
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now

router = APIRouter(prefix="/builder", tags=["schedules"])

VALID_TEMPLATES = {"daily-brief", "idea-generator"}


def _safe_zone(tz_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz_name)
    except Exception:
        return ZoneInfo("Asia/Almaty")


def _compute_next_run_utc(
    timing: dict[str, Any],
    tz_name: str,
    now_utc: datetime | None = None,
) -> str:
    base_now = now_utc or utc_now()
    tz = _safe_zone(tz_name)
    local_now = base_now.astimezone(tz)
    local_time_str = str(timing.get("localTime", "07:30"))
    try:
        parts = [int(p) for p in local_time_str.split(":")]
        target_time = time(parts[0], parts[1] if len(parts) > 1 else 0)
    except Exception:
        target_time = time(7, 30)

    frequency = str(timing.get("frequency", "daily")).lower()
    candidate_date = local_now.date()
    for offset in range(0, 15):
        day = candidate_date + timedelta(days=offset)
        weekday = day.isoweekday()  # 1=Mon .. 7=Sun
        if frequency == "weekdays" and weekday > 5:
            continue
        if frequency == "weekly":
            days_of_week = timing.get("daysOfWeek") or [1]
            if weekday not in [int(d) if str(d).isdigit() else 1 for d in days_of_week]:
                continue
        candidate_dt = datetime.combine(day, target_time, tzinfo=tz)
        if candidate_dt > local_now:
            return format_utc(candidate_dt.astimezone(timezone.utc))

    fallback = datetime.combine(candidate_date + timedelta(days=1), target_time, tzinfo=tz)
    return format_utc(fallback.astimezone(timezone.utc))


def _serialize_run(
    run: ScheduleRunModel,
    template: str | None = None,
    include_result: bool = False,
) -> dict[str, Any]:
    data: dict[str, Any] = {
        "id": run.id,
        "scheduleId": run.schedule_id,
        "template": template,
        "status": run.status,
        "statusReason": run.status_reason,
        "trigger": run.trigger,
        "scheduledForUtc": run.scheduled_for_utc,
        "createdAtUtc": run.created_at_utc,
        "finishedAtUtc": run.finished_at_utc,
        "delivery": run.delivery,
    }
    if include_result:
        data["result"] = run.result_json
    return data


def _serialize_schedule(
    row: ScheduleModel,
    last_run: ScheduleRunModel | None = None,
) -> dict[str, Any]:
    return {
        "id": row.id,
        "template": row.template,
        "enabled": row.enabled,
        "timeZone": row.time_zone,
        "timing": row.timing_json or {},
        "parameters": row.parameters_json or {},
        "extraContext": row.extra_context,
        "consentRevision": row.consent_revision,
        "nextRunAtUtc": row.next_run_at_utc if row.enabled else None,
        "lastRun": _serialize_run(last_run, row.template, include_result=False) if last_run else None,
        "version": row.version,
        "createdAtUtc": row.created_at_utc,
        "updatedAtUtc": row.updated_at_utc,
    }


async def _get_last_run(db: AsyncSession, schedule_id: str) -> ScheduleRunModel | None:
    res = await db.execute(
        select(ScheduleRunModel)
        .where(ScheduleRunModel.schedule_id == schedule_id)
        .order_by(ScheduleRunModel.created_at_utc.desc())
        .limit(1)
    )
    return res.scalar_one_or_none()


async def execute_schedule_run(run_id: str) -> None:
    async with SessionLocal() as db:
        res = await db.execute(select(ScheduleRunModel).where(ScheduleRunModel.id == run_id))
        run = res.scalar_one_or_none()
        if run is None:
            return

        s_res = await db.execute(select(ScheduleModel).where(ScheduleModel.id == run.schedule_id))
        schedule = s_res.scalar_one_or_none()
        now_str = format_utc(utc_now())
        run.status = "running"
        await db.commit()

        template = schedule.template if schedule else "daily-brief"
        params = (schedule.parameters_json if schedule else None) or {}
        extra_context = (schedule.extra_context if schedule else None) or ""

        if template == "daily-brief":
            ev_res = await db.execute(
                select(CalendarEventModel)
                .where(CalendarEventModel.user_id == run.user_id)
                .order_by(CalendarEventModel.start_local.asc())
                .limit(10)
            )
            events = list(ev_res.scalars().all())
            event_items = (
                [f"{e.title} ({e.start_local})" for e in events]
                if events
                else ["На сегодня запланированных событий в календаре нет — отличное время для глубокой работы."]
            )
            focus_items = [
                "Проверьте ключевые приоритеты дня и выделите 1 главную задачу до обеда.",
                "Запланируйте короткий перерыв после основного блока встреч.",
            ]
            if extra_context:
                focus_items.append(f"Контекст: {extra_context}")

            sections = [
                {"title": "Расписание на сегодня", "items": event_items},
                {"title": "Фокус и рекомендации", "items": focus_items},
            ]
            sources = [
                {
                    "type": "calendar",
                    "label": "Календарь Craft AI",
                    "itemCount": len(events),
                }
            ]
        else:
            subject = str(params.get("subject") or params.get("topic") or "Учебный проект")
            grade = params.get("grade")
            grade_label = f" ({grade} класс)" if grade else ""
            ideas = [
                f"Интерактивный мини-кейс по теме «{subject}»{grade_label}: работа в группах на 15 минут.",
                f"Визуальная карта понятий для быстрой проверки понимания темы «{subject}».",
                "Практическое задание с самопроверкой по чек-листу и рефлексией в конце урока.",
            ]
            if extra_context:
                ideas.append(f"Учтён дополнительный контекст: {extra_context}")
            sections = [
                {"title": f"Идеи: {subject}{grade_label}", "items": ideas},
                {
                    "title": "Шаги подготовки",
                    "items": [
                        "Выберите 1 идею для ближайшего занятия.",
                        "Подготовьте 3 контрольных вопроса для быстрой обратной связи.",
                    ],
                },
            ]
            sources = [
                {
                    "type": "template",
                    "label": "Генератор педагогических идей Craft AI",
                    "itemCount": len(ideas),
                }
            ]

        dev_res = await db.execute(
            select(UserDeviceModel).where(UserDeviceModel.user_id == run.user_id)
        )
        devices = list(dev_res.scalars().all())

        completed_str = format_utc(utc_now())
        result_payload = {
            "format": "structured",
            "sections": sections,
            "sources": sources,
            "gaps": [],
            "dataSnapshotAtUtc": now_str,
            "generatedAtUtc": completed_str,
            "modelCategory": "standard",
        }
        run.status = "succeeded"
        run.finished_at_utc = completed_str
        run.delivery = "sent" if devices else "not-registered"
        run.result_json = result_payload
        await db.commit()


@router.get("/schedules")
async def list_schedules(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    res = await db.execute(
        select(ScheduleModel)
        .where(ScheduleModel.user_id == user.user_id)
        .order_by(ScheduleModel.created_at_utc.asc())
    )
    schedules = list(res.scalars().all())
    items: list[dict[str, Any]] = []
    for s in schedules:
        last_run = await _get_last_run(db, s.id)
        items.append(_serialize_schedule(s, last_run))
    return {"items": items}


@router.put("/schedules/{template}")
async def upsert_schedule(
    template: str,
    payload: dict[str, Any],
    response: Response,
    if_match: str | None = Header(default=None, alias="If-Match"),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if template not in VALID_TEMPLATES:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="schedule.invalid-template",
            message=f"Unsupported schedule template '{template}'.",
        )

    route_key = f"PUT:/builder/schedules/{template}"
    req_hash = compute_request_hash(payload)
    cached = await check_idempotency(
        db,
        user_id=user.user_id,
        route=route_key,
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        status_code, body = cached
        response.status_code = status_code
        return body

    parameters = payload.get("parameters") or {}
    if not isinstance(parameters, dict):
        parameters = {}

    if "grade" in parameters and parameters["grade"] is not None:
        try:
            grade_val = int(parameters["grade"])
        except (TypeError, ValueError):
            raise ApiError(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="schedule.invalid-grade",
                message="Grade must be an integer between 1 and 11.",
            )
        if grade_val < 1 or grade_val > 11:
            raise ApiError(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="schedule.invalid-grade",
                message="Grade must be between 1 and 11.",
            )

    timing = payload.get("timing") or {"frequency": "daily", "localTime": "07:30"}
    tz_name = str(payload.get("timeZone") or "Asia/Almaty")
    enabled = bool(payload.get("enabled", True))
    extra_context = payload.get("extraContext")
    if extra_context is not None:
        extra_context = str(extra_context)[:500]
    consent_revision = str(payload.get("consentRevision") or "schedules-2026-10-v1")

    res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.user_id == user.user_id,
            ScheduleModel.template == template,
        )
    )
    row = res.scalar_one_or_none()
    now = utc_now()
    now_str = format_utc(now)
    next_run = _compute_next_run_utc(timing, tz_name, now) if enabled else None

    if row is None:
        row = ScheduleModel(
            id=str(uuid.uuid4()),
            user_id=user.user_id,
            template=template,
            enabled=enabled,
            time_zone=tz_name,
            timing_json=timing,
            parameters_json=parameters,
            extra_context=extra_context,
            consent_revision=consent_revision,
            next_run_at_utc=next_run,
            version=1,
            created_at_utc=now_str,
            updated_at_utc=now_str,
        )
        db.add(row)
    else:
        if if_match is not None:
            clean_etag = if_match.strip().strip('"')
            if clean_etag != str(row.version):
                raise ApiError(
                    status_code=status.HTTP_412_PRECONDITION_FAILED,
                    code="schedule.version-conflict",
                    message="Schedule version does not match If-Match header.",
                )
        row.enabled = enabled
        row.time_zone = tz_name
        row.timing_json = timing
        row.parameters_json = parameters
        row.extra_context = extra_context
        row.consent_revision = consent_revision
        row.next_run_at_utc = next_run
        row.version += 1
        row.updated_at_utc = now_str

    await db.commit()
    last_run = await _get_last_run(db, row.id)
    body = _serialize_schedule(row, last_run)
    response.headers["ETag"] = f'"{row.version}"'
    await save_idempotency(
        db,
        user_id=user.user_id,
        route=route_key,
        key=idempotency_key,
        request_hash=req_hash,
        status_code=200,
        response_json=body,
    )
    return body


@router.post("/schedules/{schedule_id}/pause")
async def pause_schedule(
    schedule_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.id == schedule_id,
            ScheduleModel.user_id == user.user_id,
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.not-found",
            message="Schedule not found.",
        )
    row.enabled = False
    row.next_run_at_utc = None
    row.version += 1
    row.updated_at_utc = format_utc(utc_now())
    await db.commit()
    last_run = await _get_last_run(db, row.id)
    return _serialize_schedule(row, last_run)


@router.post("/schedules/{schedule_id}/resume")
async def resume_schedule(
    schedule_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.id == schedule_id,
            ScheduleModel.user_id == user.user_id,
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.not-found",
            message="Schedule not found.",
        )
    timing = row.timing_json or {}
    now = utc_now()
    row.enabled = True
    row.next_run_at_utc = _compute_next_run_utc(timing, row.time_zone, now)
    row.version += 1
    row.updated_at_utc = format_utc(now)
    await db.commit()
    last_run = await _get_last_run(db, row.id)
    return _serialize_schedule(row, last_run)


@router.delete("/schedules/{schedule_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_schedule(
    schedule_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.id == schedule_id,
            ScheduleModel.user_id == user.user_id,
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.not-found",
            message="Schedule not found.",
        )
    await db.delete(row)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/schedules/{schedule_id}/run-now", status_code=status.HTTP_202_ACCEPTED)
async def run_schedule_now(
    schedule_id: str,
    background_tasks: BackgroundTasks,
    response: Response,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    route_key = f"POST:/builder/schedules/{schedule_id}/run-now"
    req_hash = compute_request_hash({"scheduleId": schedule_id})
    cached = await check_idempotency(
        db,
        user_id=user.user_id,
        route=route_key,
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        status_code, body = cached
        response.status_code = status_code
        return body

    res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.id == schedule_id,
            ScheduleModel.user_id == user.user_id,
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.not-found",
            message="Schedule not found.",
        )

    now_str = format_utc(utc_now())
    run = ScheduleRunModel(
        id=str(uuid.uuid4()),
        schedule_id=row.id,
        user_id=user.user_id,
        status="queued",
        trigger="manual",
        scheduled_for_utc=now_str,
        created_at_utc=now_str,
        delivery="pending",
    )
    db.add(run)
    await db.commit()

    body = _serialize_run(run, row.template, include_result=False)
    await save_idempotency(
        db,
        user_id=user.user_id,
        route=route_key,
        key=idempotency_key,
        request_hash=req_hash,
        status_code=202,
        response_json=body,
    )
    background_tasks.add_task(execute_schedule_run, run.id)
    return body


@router.get("/schedules/{schedule_id}/runs")
async def list_schedule_runs(
    schedule_id: str,
    limit: int = 20,
    cursor: str | None = None,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    s_res = await db.execute(
        select(ScheduleModel).where(
            ScheduleModel.id == schedule_id,
            ScheduleModel.user_id == user.user_id,
        )
    )
    sched = s_res.scalar_one_or_none()
    if sched is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.not-found",
            message="Schedule not found.",
        )

    safe_limit = max(1, min(limit, 50))
    stmt = (
        select(ScheduleRunModel)
        .where(
            ScheduleRunModel.schedule_id == schedule_id,
            ScheduleRunModel.user_id == user.user_id,
        )
        .order_by(ScheduleRunModel.created_at_utc.desc())
        .limit(safe_limit)
    )
    if cursor:
        stmt = stmt.where(ScheduleRunModel.created_at_utc < cursor)

    res = await db.execute(stmt)
    runs = list(res.scalars().all())
    return {
        "items": [_serialize_run(r, sched.template, include_result=False) for r in runs],
        "nextCursor": None,
    }


@router.get("/runs/{run_id}")
async def get_schedule_run(
    run_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    res = await db.execute(
        select(ScheduleRunModel).where(
            ScheduleRunModel.id == run_id,
            ScheduleRunModel.user_id == user.user_id,
        )
    )
    run = res.scalar_one_or_none()
    if run is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.run-not-found",
            message="Schedule run not found.",
        )
    s_res = await db.execute(select(ScheduleModel).where(ScheduleModel.id == run.schedule_id))
    sched = s_res.scalar_one_or_none()
    return _serialize_run(run, sched.template if sched else None, include_result=True)


@router.delete("/runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_schedule_run(
    run_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    res = await db.execute(
        select(ScheduleRunModel).where(
            ScheduleRunModel.id == run_id,
            ScheduleRunModel.user_id == user.user_id,
        )
    )
    run = res.scalar_one_or_none()
    if run is None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="schedule.run-not-found",
            message="Schedule run not found.",
        )
    await db.delete(run)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/devices/{installation_id}")
async def register_device(
    installation_id: str,
    payload: dict[str, Any],
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    platform = str(payload.get("platform") or "android").lower()
    push_token = str(payload.get("pushToken") or "").strip()
    locale = str(payload.get("locale") or "ru")
    app_version = str(payload.get("appVersion") or "0.1.0")

    if not push_token:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="device.invalid-token",
            message="pushToken is required.",
        )

    res = await db.execute(
        select(UserDeviceModel).where(
            UserDeviceModel.user_id == user.user_id,
            UserDeviceModel.installation_id == installation_id,
        )
    )
    row = res.scalar_one_or_none()
    now_str = format_utc(utc_now())
    if row is None:
        row = UserDeviceModel(
            installation_id=installation_id,
            user_id=user.user_id,
            platform=platform,
            push_token=push_token,
            locale=locale,
            app_version=app_version,
            updated_at_utc=now_str,
        )
        db.add(row)
    else:
        row.platform = platform
        row.push_token = push_token
        row.locale = locale
        row.app_version = app_version
        row.updated_at_utc = now_str

    await db.commit()
    return {
        "installationId": row.installation_id,
        "registeredAtUtc": row.updated_at_utc,
    }


@router.delete("/devices/{installation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(
    installation_id: str,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    res = await db.execute(
        select(UserDeviceModel).where(
            UserDeviceModel.installation_id == installation_id,
            UserDeviceModel.user_id == user.user_id,
        )
    )
    row = res.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


async def run_scheduler_tick() -> None:
    now = utc_now()
    now_str = format_utc(now)
    due_run_ids: list[str] = []
    async with SessionLocal() as db:
        res = await db.execute(
            select(ScheduleModel).where(
                ScheduleModel.enabled.is_(True),
                ScheduleModel.next_run_at_utc.is_not(None),
                ScheduleModel.next_run_at_utc <= now_str,
            )
        )
        due_schedules = list(res.scalars().all())
        for sched in due_schedules:
            run = ScheduleRunModel(
                id=str(uuid.uuid4()),
                schedule_id=sched.id,
                user_id=sched.user_id,
                status="queued",
                trigger="scheduled",
                scheduled_for_utc=sched.next_run_at_utc or now_str,
                created_at_utc=now_str,
                delivery="pending",
            )
            db.add(run)
            timing = sched.timing_json or {}
            sched.next_run_at_utc = _compute_next_run_utc(timing, sched.time_zone, now)
            sched.updated_at_utc = now_str
            due_run_ids.append(run.id)
        if due_schedules:
            await db.commit()

    for run_id in due_run_ids:
        await execute_schedule_run(run_id)
