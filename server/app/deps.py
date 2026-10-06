import uuid

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.db import get_session
from app.models import Block, Friendship, User
from app.security import decode_access_token

_bearer = HTTPBearer(auto_error=False)


def client_ip(request: Request) -> str:
    # Behind nginx; uvicorn applies X-Forwarded-For (see deploy docs), and the
    # port is only reachable from localhost.
    return request.client.host if request.client else "unknown"


def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_session),
) -> User:
    unauthorized = HTTPException(
        status_code=401,
        detail="Not signed in.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if creds is None:
        raise unauthorized
    user_id = decode_access_token(creds.credentials)
    user = session.get(User, user_id) if user_id else None
    if user is None:
        raise unauthorized
    return user


def pair(a: uuid.UUID, b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    return (a, b) if a < b else (b, a)


def get_friendship(session: Session, a: uuid.UUID, b: uuid.UUID) -> Friendship | None:
    low, high = pair(a, b)
    return session.scalar(
        select(Friendship).where(Friendship.user_a == low, Friendship.user_b == high)
    )


def are_friends(session: Session, a: uuid.UUID, b: uuid.UUID) -> bool:
    friendship = get_friendship(session, a, b)
    return friendship is not None and friendship.status == "accepted"


def blocked_either_way(session: Session, a: uuid.UUID, b: uuid.UUID) -> bool:
    return (
        session.scalar(
            select(Block).where(
                or_(
                    (Block.blocker_id == a) & (Block.blocked_id == b),
                    (Block.blocker_id == b) & (Block.blocked_id == a),
                )
            )
        )
        is not None
    )


def blocked_ids(session: Session, me: uuid.UUID) -> set[uuid.UUID]:
    """Everyone who must not see or be seen by `me` in discovery."""
    rows = session.execute(
        select(Block.blocker_id, Block.blocked_id).where(
            or_(Block.blocker_id == me, Block.blocked_id == me)
        )
    )
    return {x for row in rows for x in row if x != me}
