from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app import ratelimit
from app.db import get_session
from app.deps import current_user
from app.models import DeviceToken, User
from app.schemas import DeviceIn, DeviceRemoveIn

router = APIRouter(prefix="/me/devices", tags=["devices"])

# More phones than anyone owns; keeps a buggy client from filling the table.
MAX_DEVICES = 10


@router.put("", status_code=204)
def register_device(
    body: DeviceIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Remember this phone's push token. A token belongs to one account: if the
    phone was last used by someone else, it moves to this account."""
    ratelimit.hit(f"devices:{user.id}", limit=60, window_seconds=86400)
    row = session.scalar(select(DeviceToken).where(DeviceToken.token == body.token))
    if row is None:
        session.add(DeviceToken(user_id=user.id, token=body.token, platform=body.platform))
    else:
        row.user_id = user.id
        row.platform = body.platform
    session.flush()
    mine = list(
        session.scalars(
            select(DeviceToken)
            .where(DeviceToken.user_id == user.id)
            .order_by(DeviceToken.created_at.desc(), DeviceToken.id)
        )
    )
    for old in mine[MAX_DEVICES:]:
        session.delete(old)
    session.commit()
    return Response(status_code=204)


@router.post("/remove", status_code=204)
def remove_device(
    body: DeviceRemoveIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Stop pushing to this phone. Answers the same whether or not the token was
    known, and only ever touches the caller's own tokens."""
    session.execute(
        delete(DeviceToken).where(
            DeviceToken.user_id == user.id, DeviceToken.token == body.token
        )
    )
    session.commit()
    return Response(status_code=204)
