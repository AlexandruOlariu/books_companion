from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import ratelimit
from app.db import get_session
from app.deps import blocked_ids, current_user
from app.models import User
from app.phone import to_e164
from app.schemas import ContactsMatchIn, PersonOut
from app.security import phone_hash

router = APIRouter(tags=["people"])


def person(user: User) -> PersonOut:
    return PersonOut(
        id=user.id,
        username=user.username,
        display_name=f"{user.first_name} {user.last_name}",
    )


@router.get("/users/lookup", response_model=PersonOut)
def lookup_username(
    username: str = Query(min_length=3, max_length=30),
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Find one person by their exact username. There is deliberately no prefix
    or name search: it would let anyone list the whole user base."""
    ratelimit.hit(f"lookup:{me.id}", limit=60, window_seconds=3600)
    found = session.scalar(select(User).where(User.username == username.strip().lower()))
    if found is None or found.id == me.id or found.id in blocked_ids(session, me.id):
        raise HTTPException(status_code=404, detail="No one has that username.")
    return person(found)


@router.post("/contacts/match", response_model=list[PersonOut])
def match_contacts(
    body: ContactsMatchIn,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Which of these phone numbers belong to people who chose to be findable?

    The numbers are normalised, hashed, compared, and forgotten: the request is
    never stored or logged. Each number counts against a daily budget, so the
    endpoint cannot be used to sweep through number ranges.
    """
    count = len(body.numbers)
    if count == 0:
        return []
    ratelimit.hit(f"contacts-calls:{me.id}", limit=20, window_seconds=3600)
    ratelimit.hit(f"contacts-numbers:{me.id}", limit=3000, window_seconds=86400, cost=count)

    hashes = set()
    for raw in body.numbers:
        e164 = to_e164(raw, body.region)
        if e164 is not None:
            hashes.add(phone_hash(e164))
    if not hashes:
        return []
    excluded = blocked_ids(session, me.id) | {me.id}
    users = session.scalars(
        select(User)
        .where(User.phone_hash.in_(list(hashes)), User.discoverable_by_phone.is_(True))
        .order_by(User.username)
    )
    return [person(u) for u in users if u.id not in excluded]
