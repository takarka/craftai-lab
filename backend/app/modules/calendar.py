import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Header, Query, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import (
    CalendarChangeLogModel,
    CalendarEventModel,
    CalendarOccurrenceOverrideModel,
    get_db,
)
from app.core.errors import ApiError
from app.core.idempotency import check_idempotency, compute_request_hash, save_idempotency
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now

router = APIRouter()

WEEKDAY_NAMES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
MAX_EVENTS_PER_USER = 2000


def _weekday_num(name: str) -> int:
    try:
        return WEEKDAY_NAMES.index(name.lower()) + 1
    except ValueError as exc:
        raise ApiError(
            status_code=422,
            code="calendar.invalid-recurrence",
            message=f"Неизвестный день недели: {name}",
        ) from exc


def _parse_date_only(value: str) -> date:
    try:
        return date.fromisoformat(value[:10])
    except ValueError as exc:
        raise ApiError(
            status_code=422,
            code="calendar.invalid-time",
            message=f"Некорректная дата: {value}",
        ) from exc


def _parse_local_dt(value: str, all_day: bool) -> datetime:
    try:
        if all_day:
            d = date.fromisoformat(value[:10])
            return datetime(d.year, d.month, d.day)
        return datetime.fromisoformat(value[:19])
    except ValueError as exc:
        raise ApiError(
            status_code=422,
            code="calendar.invalid-time",
            message=f"Некорректное время события: {value}",
        ) from exc


def _format_local_dt(dt: datetime, all_day: bool) -> str:
    if all_day:
        return dt.strftime("%Y-%m-%d")
    return dt.strftime("%Y-%m-%dT%H:%M:%S")


def _to_utc_str(local_str: str, tz_name: str | None, all_day: bool) -> str | None:
    if all_day or not tz_name:
        return None
    try:
        tz = ZoneInfo(tz_name)
        dt = datetime.fromisoformat(local_str[:19]).replace(tzinfo=tz)
        return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None


def expand_recurrence_dates(
    start_d: date,
    rule: dict[str, Any] | None,
    from_d: date,
    to_d: date,
) -> list[date]:
    if to_d < from_d:
        return []
    if not rule:
        if from_d <= start_d <= to_d:
            return [start_d]
        return []

    freq = str(rule.get("frequency", "")).lower()
    interval = int(rule.get("interval", 1))
    if interval < 1 or interval > 52:
        raise ApiError(status_code=422, code="calendar.invalid-recurrence", message="Интервал должен быть 1–52.")

    excluded = {str(x)[:10] for x in (rule.get("excludedDates") or [])}
    until_str = rule.get("until")
    until_d = _parse_date_only(until_str) if until_str else None
    count = rule.get("count")
    count_limit = int(count) if count is not None else None

    result: list[date] = []
    guard = 0
    max_guard = 10000

    if freq == "daily":
        first_idx = 0
        if from_d > start_d:
            gap = (from_d - start_d).days
            first_idx = (gap + interval - 1) // interval
        idx = first_idx if count_limit is None else 0
        while guard < max_guard:
            guard += 1
            if count_limit is not None and idx >= count_limit:
                break
            cur = start_d + timedelta(days=idx * interval)
            idx += 1
            if cur > to_d or (until_d and cur > until_d):
                break
            if cur >= from_d and cur.isoformat() not in excluded:
                result.append(cur)
        return result

    if freq == "weekly":
        by_weekday_raw = rule.get("byWeekday") or []
        if by_weekday_raw:
            weekday_offsets = sorted({_weekday_num(str(w)) - 1 for w in by_weekday_raw})
        else:
            weekday_offsets = [start_d.isoweekday() - 1]

        week_start = start_d - timedelta(days=start_d.isoweekday() - 1)
        stride = 7 * interval
        first_week = 0
        if count_limit is None and from_d > week_start:
            weeks = (from_d - week_start).days // stride - 1
            first_week = max(0, weeks)

        occ = 0
        week = first_week
        while guard < max_guard:
            guard += 1
            week_base = week_start + timedelta(days=week * stride)
            week += 1
            if week_base > to_d:
                break
            for offset in weekday_offsets:
                cur = week_base + timedelta(days=offset)
                if cur < start_d:
                    continue
                if count_limit is not None and occ >= count_limit:
                    return result
                occ += 1
                if cur > to_d or (until_d and cur > until_d):
                    return result
                if cur >= from_d and cur.isoformat() not in excluded:
                    result.append(cur)
        return result

    raise ApiError(status_code=422, code="calendar.invalid-recurrence", message=f"Неподдерживаемая частота: {freq}")


def _serialize_event(row: CalendarEventModel) -> dict[str, Any]:
    out: dict[str, Any] = {
        "id": row.id,
        "version": row.version,
        "title": row.title,
        "allDay": row.all_day,
        "start": row.start_local,
        "end": row.end_local,
        "reminders": list(row.reminders_json or []),
        "createdAtUtc": row.created_at_utc,
        "updatedAtUtc": row.updated_at_utc,
    }
    if row.notes is not None:
        out["notes"] = row.notes
    if not row.all_day and row.time_zone:
        out["timeZone"] = row.time_zone
    if row.recurrence_json:
        out["recurrence"] = row.recurrence_json
    if row.subject is not None:
        out["subject"] = row.subject
    if row.grade is not None:
        out["grade"] = row.grade
    return out


def expand_user_occurrences(
    events: list[CalendarEventModel],
    overrides: list[CalendarOccurrenceOverrideModel],
    from_str: str,
    to_str: str,
) -> list[dict[str, Any]]:
    from_d = _parse_date_only(from_str)
    to_d = _parse_date_only(to_str)
    if (to_d - from_d).days > 62 or to_d < from_d:
        raise ApiError(
            status_code=422,
            code="calendar.range-too-large",
            message="Диапазон дат календаря не должен превышать 62 дня.",
        )

    over_map = {f"{o.event_id}|{o.occurrence_date}": o for o in overrides}
    items: list[tuple[datetime, str, dict[str, Any]]] = []

    for ev in events:
        start_dt = _parse_local_dt(ev.start_local, ev.all_day)
        end_dt = _parse_local_dt(ev.end_local, ev.all_day)
        start_d = _parse_date_only(ev.start_local)
        end_d = _parse_date_only(ev.end_local)
        span_days = max(0, (end_d - start_d).days)

        if not ev.recurrence_json and (start_d > to_d or end_d < from_d):
            continue

        dates = expand_recurrence_dates(
            start_d,
            ev.recurrence_json,
            from_d - timedelta(days=span_days),
            to_d,
        )
        for d in dates:
            date_iso = d.isoformat()
            over = over_map.get(f"{ev.id}|{date_iso}")
            if over is not None and over.canceled:
                continue

            if over is not None and over.start_local and over.end_local:
                occ_start_str = over.start_local
                occ_end_str = over.end_local
                occ_start_dt = _parse_local_dt(occ_start_str, ev.all_day)
            else:
                span = end_dt - start_dt
                occ_start_dt = datetime(d.year, d.month, d.day, start_dt.hour, start_dt.minute, start_dt.second)
                occ_end_dt = occ_start_dt + span
                occ_start_str = _format_local_dt(occ_start_dt, ev.all_day)
                occ_end_str = _format_local_dt(occ_end_dt, ev.all_day)

            if _parse_date_only(occ_end_str) < from_d:
                continue

            title = over.title if (over and over.title is not None) else ev.title
            notes = over.notes if (over and over.notes is not None) else ev.notes

            occ_dict: dict[str, Any] = {
                "eventId": ev.id,
                "occurrenceDate": date_iso,
                "title": title,
                "allDay": ev.all_day,
                "start": occ_start_str,
                "end": occ_end_str,
                "isOverride": over is not None,
                "reminders": list(ev.reminders_json or []),
            }
            if notes is not None:
                occ_dict["notes"] = notes
            if not ev.all_day and ev.time_zone:
                occ_dict["timeZone"] = ev.time_zone
                start_utc = _to_utc_str(occ_start_str, ev.time_zone, ev.all_day)
                end_utc = _to_utc_str(occ_end_str, ev.time_zone, ev.all_day)
                if start_utc:
                    occ_dict["startUtc"] = start_utc
                if end_utc:
                    occ_dict["endUtc"] = end_utc

            items.append((occ_start_dt, title, occ_dict))

    items.sort(key=lambda t: (t[0], t[1]))
    return [t[2] for t in items[:500]]


class CalendarEventInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=1000)
    allDay: bool = False
    start: str
    end: str
    timeZone: str | None = "Asia/Almaty"
    recurrence: dict[str, Any] | None = None
    reminders: list[int] = Field(default_factory=list, max_length=3)
    subject: str | None = Field(default=None, max_length=100)
    grade: int | None = Field(default=None, ge=1, le=11)


def _validate_event_input(body: CalendarEventInput) -> None:
    start_dt = _parse_local_dt(body.start, body.allDay)
    end_dt = _parse_local_dt(body.end, body.allDay)
    if end_dt < start_dt or (not body.allDay and end_dt <= start_dt):
        raise ApiError(
            status_code=422,
            code="calendar.invalid-time",
            message="Время окончания должно быть позже времени начала.",
        )
    if not body.allDay:
        if not body.timeZone:
            raise ApiError(status_code=422, code="calendar.invalid-time", message="Укажите часовой пояс (timeZone).")
        try:
            ZoneInfo(body.timeZone)
        except ZoneInfoNotFoundError as exc:
            raise ApiError(status_code=422, code="calendar.invalid-time", message="Неизвестный часовой пояс.") from exc

    for r in body.reminders:
        if r < 0 or r > 10080:
            raise ApiError(status_code=422, code="calendar.invalid-time", message="Напоминание должно быть от 0 до 10080 минут.")

    if body.recurrence:
        expand_recurrence_dates(_parse_date_only(body.start), body.recurrence, _parse_date_only(body.start), _parse_date_only(body.start) + timedelta(days=14))


async def _log_calendar_change(db: AsyncSession, user_id: str, event_id: str, change_type: str) -> None:
    db.add(
        CalendarChangeLogModel(
            user_id=user_id,
            event_id=event_id,
            change_type=change_type,
            changed_at_utc=format_utc(utc_now()),
        )
    )


@router.get("/builder/calendar/events")
async def list_calendar_occurrences(
    from_: str = Query(alias="from"),
    to: str = Query(alias="to"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    events = (
        await db.execute(select(CalendarEventModel).where(CalendarEventModel.user_id == current_user.user_id))
    ).scalars().all()
    overrides = (
        await db.execute(
            select(CalendarOccurrenceOverrideModel).where(
                CalendarOccurrenceOverrideModel.user_id == current_user.user_id
            )
        )
    ).scalars().all()

    items = expand_user_occurrences(list(events), list(overrides), from_, to)
    return {"from": from_, "to": to, "items": items}


@router.get("/builder/calendar/events/{event_id}")
async def get_calendar_event(
    event_id: str,
     response: Response,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    ev = (
        await db.execute(
            select(CalendarEventModel).where(
                CalendarEventModel.id == event_id,
                CalendarEventModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if ev is None:
        raise ApiError(status_code=404, code="calendar.not-found", message="Событие не найдено.")
    response.headers["ETag"] = f'"{ev.version}"'
    return _serialize_event(ev)


@router.post("/builder/calendar/events", status_code=201)
async def create_calendar_event(
    body: CalendarEventInput,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    req_hash = compute_request_hash(body.model_dump())
    cached = await check_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/calendar/events",
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        return JSONResponse(status_code=cached[0], content=cached[1])

    _validate_event_input(body)

    now_str = format_utc(utc_now())
    ev = CalendarEventModel(
        id=str(uuid.uuid4()),
        user_id=current_user.user_id,
        title=body.title.strip(),
        notes=body.notes,
        all_day=body.allDay,
        start_local=body.start,
        end_local=body.end,
        time_zone=None if body.allDay else (body.timeZone or "Asia/Almaty"),
        recurrence_json=body.recurrence,
        reminders_json=body.reminders,
        subject=body.subject,
        grade=body.grade,
        version=1,
        created_at_utc=now_str,
        updated_at_utc=now_str,
    )
    db.add(ev)
    await _log_calendar_change(db, current_user.user_id, ev.id, "upsert")
    await db.commit()

    payload = _serialize_event(ev)
    await save_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/calendar/events",
        key=idempotency_key,
        request_hash=req_hash,
        status_code=201,
        response_json=payload,
    )
    return JSONResponse(status_code=201, content=payload, headers={"ETag": '"1"'})


def _parse_if_match(if_match: str | None) -> int | None:
    if not if_match:
        return None
    cleaned = if_match.strip().strip('"')
    try:
        return int(cleaned)
    except ValueError:
        return -1


@router.put("/builder/calendar/events/{event_id}")
async def replace_calendar_event(
    event_id: str,
    body: CalendarEventInput,
    if_match: str | None = Header(default=None, alias="If-Match"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    ev = (
        await db.execute(
            select(CalendarEventModel).where(
                CalendarEventModel.id == event_id,
                CalendarEventModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if ev is None:
        raise ApiError(status_code=404, code="calendar.not-found", message="Событие не найдено.")

    expected_ver = _parse_if_match(if_match)
    if expected_ver is None or expected_ver != ev.version:
        raise ApiError(
            status_code=412,
            code="calendar.version-conflict",
            message="Событие было изменено в другой сессии.",
        )

    _validate_event_input(body)

    ev.title = body.title.strip()
    ev.notes = body.notes
    ev.all_day = body.allDay
    ev.start_local = body.start
    ev.end_local = body.end
    ev.time_zone = None if body.allDay else (body.timeZone or "Asia/Almaty")
    ev.recurrence_json = body.recurrence
    ev.reminders_json = body.reminders
    ev.subject = body.subject
    ev.grade = body.grade
    ev.version += 1
    ev.updated_at_utc = format_utc(utc_now())

    await _log_calendar_change(db, current_user.user_id, ev.id, "upsert")
    await db.commit()

    return JSONResponse(status_code=200, content=_serialize_event(ev), headers={"ETag": f'"{ev.version}"'})


@router.delete("/builder/calendar/events/{event_id}", status_code=204)
async def delete_calendar_event(
    event_id: str,
    scope: str = Query(default="all"),
    from_: str | None = Query(default=None, alias="from"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    ev = (
        await db.execute(
            select(CalendarEventModel).where(
                CalendarEventModel.id == event_id,
                CalendarEventModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if ev is None:
        raise ApiError(status_code=404, code="calendar.not-found", message="Событие не найдено.")

    if scope == "following" and from_ and ev.recurrence_json:
        cut_date = _parse_date_only(from_)
        start_d = _parse_date_only(ev.start_local)
        if cut_date <= start_d:
            await db.execute(
                delete(CalendarOccurrenceOverrideModel).where(CalendarOccurrenceOverrideModel.event_id == ev.id)
            )
            await db.delete(ev)
            await _log_calendar_change(db, current_user.user_id, ev.id, "delete")
        else:
            rec = dict(ev.recurrence_json)
            rec.pop("count", None)
            rec["until"] = (cut_date - timedelta(days=1)).isoformat()
            ev.recurrence_json = rec
            ev.version += 1
            ev.updated_at_utc = format_utc(utc_now())
            await db.execute(
                delete(CalendarOccurrenceOverrideModel).where(
                    CalendarOccurrenceOverrideModel.event_id == ev.id,
                    CalendarOccurrenceOverrideModel.occurrence_date >= cut_date.isoformat(),
                )
            )
            await _log_calendar_change(db, current_user.user_id, ev.id, "upsert")
    else:
        await db.execute(
            delete(CalendarOccurrenceOverrideModel).where(CalendarOccurrenceOverrideModel.event_id == ev.id)
        )
        await db.delete(ev)
        await _log_calendar_change(db, current_user.user_id, ev.id, "delete")

    await db.commit()
    return Response(status_code=204)


class OccurrenceOverrideInput(BaseModel):
    canceled: bool = False
    title: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=1000)
    start: str | None = None
    end: str | None = None


@router.put("/builder/calendar/events/{event_id}/occurrences/{occ_date}")
async def override_calendar_occurrence(
    event_id: str,
    occ_date: str,
    body: OccurrenceOverrideInput,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    _parse_date_only(occ_date)
    ev = (
        await db.execute(
            select(CalendarEventModel).where(
                CalendarEventModel.id == event_id,
                CalendarEventModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if ev is None:
        raise ApiError(status_code=404, code="calendar.not-found", message="Событие не найдено.")

    existing = (
        await db.execute(
            select(CalendarOccurrenceOverrideModel).where(
                CalendarOccurrenceOverrideModel.event_id == event_id,
                CalendarOccurrenceOverrideModel.occurrence_date == occ_date[:10],
            )
        )
    ).scalar_one_or_none()

    if existing is None:
        existing = CalendarOccurrenceOverrideModel(
            event_id=event_id,
            user_id=current_user.user_id,
            occurrence_date=occ_date[:10],
            canceled=body.canceled,
            title=body.title,
            notes=body.notes,
            start_local=body.start,
            end_local=body.end,
        )
        db.add(existing)
    else:
        existing.canceled = body.canceled
        existing.title = body.title
        existing.notes = body.notes
        existing.start_local = body.start
        existing.end_local = body.end

    ev.version += 1
    ev.updated_at_utc = format_utc(utc_now())
    await _log_calendar_change(db, current_user.user_id, ev.id, "upsert")
    await db.commit()
    return {"status": "ok", "eventId": event_id, "occurrenceDate": occ_date[:10]}


@router.get("/builder/calendar/changes")
async def get_calendar_changes(
    cursor: str | None = Query(default=None),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    after_seq = 0
    if cursor and cursor.strip():
        try:
            after_seq = int(cursor.strip())
        except ValueError:
            after_seq = 0

    logs = (
        await db.execute(
            select(CalendarChangeLogModel)
            .where(
                CalendarChangeLogModel.user_id == current_user.user_id,
                CalendarChangeLogModel.seq > after_seq,
            )
            .order_by(CalendarChangeLogModel.seq.asc())
            .limit(201)
        )
    ).scalars().all()

    has_more = len(logs) > 200
    page_logs = logs[:200]

    # Deduplicate to latest change per event_id within page
    latest_by_event: dict[str, CalendarChangeLogModel] = {}
    for log_row in page_logs:
        latest_by_event[log_row.event_id] = log_row

    event_ids = [eid for eid, lrow in latest_by_event.items() if lrow.change_type == "upsert"]
    events_map: dict[str, CalendarEventModel] = {}
    if event_ids:
        ev_rows = (
            await db.execute(
                select(CalendarEventModel).where(
                    CalendarEventModel.user_id == current_user.user_id,
                    CalendarEventModel.id.in_(event_ids),
                )
            )
        ).scalars().all()
        events_map = {e.id: e for e in ev_rows}

    items: list[dict[str, Any]] = []
    for eid, lrow in latest_by_event.items():
        if lrow.change_type == "delete" or eid not in events_map:
            items.append({"type": "delete", "eventId": eid})
        else:
            items.append({"type": "upsert", "eventId": eid, "event": _serialize_event(events_map[eid])})

    next_cursor = str(page_logs[-1].seq) if page_logs else str(after_seq)
    return {
        "items": items,
        "nextCursor": next_cursor,
        "hasMore": has_more,
    }
