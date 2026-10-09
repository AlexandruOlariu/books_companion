import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import push, ratelimit
from app.db import get_session
from app.deps import blocked_either_way, current_user, get_friendship, pair
from app.models import Block, Friendship, User
from app.routers.people import person
from app.schemas import FriendRequestIn, FriendRequestsOut, PersonOut

router = APIRouter(tags=["friends"])

NOT_FOUND = HTTPException(status_code=404, detail="Not found.")


def _people(session: Session, ids: list[uuid.UUID]) -> list[PersonOut]:
    if not ids:
        return []
    users = session.scalars(select(User).where(User.id.in_(ids)).order_by(User.username))
    return [person(u) for u in users]


@router.get("/friends", response_model=list[PersonOut])
def list_friends(me: User = Depends(current_user), session: Session = Depends(get_session)):
    rows = session.scalars(
        select(Friendship).where(
            Friendship.status == "accepted",
            or_(Friendship.user_a == me.id, Friendship.user_b == me.id),
        )
    )
    return _people(session, [f.user_b if f.user_a == me.id else f.user_a for f in rows])


@router.delete("/friends/{user_id}", status_code=204)
def remove_friend(
    user_id: uuid.UUID,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    friendship = get_friendship(session, me.id, user_id)
    if friendship is None or friendship.status != "accepted":
        raise NOT_FOUND
    session.delete(friendship)
    session.commit()


@router.get("/friends/requests", response_model=FriendRequestsOut)
def list_requests(me: User = Depends(current_user), session: Session = Depends(get_session)):
    rows = list(
        session.scalars(
            select(Friendship).where(
                Friendship.status == "pending",
                or_(Friendship.user_a == me.id, Friendship.user_b == me.id),
            )
        )
    )
    incoming, outgoing = [], []
    for f in rows:
        other = f.user_b if f.user_a == me.id else f.user_a
        (outgoing if f.requested_by == me.id else incoming).append(other)
    return FriendRequestsOut(
        incoming=_people(session, incoming), outgoing=_people(session, outgoing)
    )


@router.post("/friends/requests", response_model=PersonOut, status_code=201)
def send_request(
    body: FriendRequestIn,
    background: BackgroundTasks,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    ratelimit.hit(f"friend-requests:{me.id}", limit=50, window_seconds=86400)
    target = session.get(User, body.user_id)
    # A missing user, yourself, and a block in either direction all look the
    # same, so a block cannot be detected by trying to send a request.
    if target is None or target.id == me.id or blocked_either_way(session, me.id, target.id):
        raise NOT_FOUND
    existing = get_friendship(session, me.id, target.id)
    if existing is not None:
        if existing.status == "accepted":
            raise HTTPException(status_code=409, detail="You are already friends.")
        if existing.requested_by == me.id:
            raise HTTPException(status_code=409, detail="Request already sent.")
        # They already asked you: asking back is accepting.
        existing.status = "accepted"
        session.commit()
        background.add_task(push.notify, target.id, "friend_accepted")
        return person(target)
    low, high = pair(me.id, target.id)
    session.add(Friendship(user_a=low, user_b=high, requested_by=me.id))
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="Request already sent.")
    background.add_task(push.notify, target.id, "friend_request")
    return person(target)


@router.post("/friends/requests/{user_id}/accept", response_model=PersonOut)
def accept_request(
    user_id: uuid.UUID,
    background: BackgroundTasks,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    friendship = get_friendship(session, me.id, user_id)
    if (
        friendship is None
        or friendship.status != "pending"
        or friendship.requested_by == me.id  # only the person asked can accept
    ):
        raise NOT_FOUND
    friendship.status = "accepted"
    session.commit()
    background.add_task(push.notify, user_id, "friend_accepted")
    return person(session.get(User, user_id))


@router.delete("/friends/requests/{user_id}", status_code=204)
def decline_or_cancel_request(
    user_id: uuid.UUID,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Decline an incoming request or cancel one you sent."""
    friendship = get_friendship(session, me.id, user_id)
    if friendship is None or friendship.status != "pending":
        raise NOT_FOUND
    session.delete(friendship)
    session.commit()


@router.get("/blocks", response_model=list[PersonOut])
def list_blocks(me: User = Depends(current_user), session: Session = Depends(get_session)):
    ids = list(session.scalars(select(Block.blocked_id).where(Block.blocker_id == me.id)))
    return _people(session, ids)


@router.put("/blocks/{user_id}", status_code=204)
def block(
    user_id: uuid.UUID,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    if user_id == me.id or session.get(User, user_id) is None:
        raise NOT_FOUND
    if session.get(Block, (me.id, user_id)) is None:
        session.add(Block(blocker_id=me.id, blocked_id=user_id))
    friendship = get_friendship(session, me.id, user_id)
    if friendship is not None:
        session.delete(friendship)
    session.commit()


@router.delete("/blocks/{user_id}", status_code=204)
def unblock(
    user_id: uuid.UUID,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    block_row = session.get(Block, (me.id, user_id))
    if block_row is None:
        raise NOT_FOUND
    session.delete(block_row)
    session.commit()
