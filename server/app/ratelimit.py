from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import delete, func, select

from app.db import new_session
from app.models import RateEvent


def hit(key: str, limit: int, window_seconds: int, cost: int = 1) -> None:
    """Count `cost` against `key`; raise 429 once `limit` is used in the window.

    Counts live in Postgres so they are shared by every worker, and they are
    committed in their own transaction so a request that later fails still
    counts (a wrong password must not be free).
    """
    now = datetime.now(timezone.utc)
    since = now - timedelta(seconds=window_seconds)
    with new_session() as session:
        used = session.scalar(
            select(func.coalesce(func.sum(RateEvent.cost), 0)).where(
                RateEvent.key == key, RateEvent.created_at > since
            )
        )
        if used + cost > limit:
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Try again later.",
                headers={"Retry-After": str(window_seconds)},
            )
        session.add(RateEvent(key=key, cost=cost))
        # Housekeeping: nothing here is needed for more than a day.
        session.execute(
            delete(RateEvent).where(
                RateEvent.key == key, RateEvent.created_at < now - timedelta(days=1)
            )
        )
        session.commit()
