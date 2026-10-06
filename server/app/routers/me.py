from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import ratelimit
from app.db import get_session
from app.deps import current_user
from app.models import User
from app.phone import to_e164
from app.routers.auth import issue_tokens, revoke_all
from app.schemas import (
    DeleteAccountIn,
    MeOut,
    MeUpdate,
    PasswordChangeIn,
    PhoneIn,
    TokensOut,
)
from app.security import hash_password, phone_hash, verify_password

router = APIRouter(prefix="/me", tags=["me"])


def _out(user: User) -> MeOut:
    return MeOut(
        id=user.id,
        email=user.email,
        username=user.username,
        first_name=user.first_name,
        last_name=user.last_name,
        has_phone=user.phone_hash is not None,
        discoverable_by_phone=user.discoverable_by_phone,
    )


@router.get("", response_model=MeOut)
def get_me(user: User = Depends(current_user)):
    return _out(user)


@router.patch("", response_model=MeOut)
def update_me(
    body: MeUpdate,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    if "discoverable_by_phone" in changes and changes["discoverable_by_phone"]:
        if user.phone_hash is None:
            raise HTTPException(status_code=422, detail="Add a phone number first.")
    for field, value in changes.items():
        setattr(user, field, value)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="That username is already taken.")
    return _out(user)


@router.put("/phone", response_model=MeOut)
def set_phone(
    body: PhoneIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Store the number as a keyed hash. Nothing proves the number is yours
    (there is no SMS check), which is why finding someone by phone stays opt-in
    and only ever leads to a friend request they can decline."""
    ratelimit.hit(f"phone:{user.id}", limit=10, window_seconds=86400)
    e164 = to_e164(body.phone, body.region)
    if e164 is None:
        raise HTTPException(status_code=422, detail="That is not a valid phone number.")
    user.phone_hash = phone_hash(e164)
    session.commit()
    return _out(user)


@router.delete("/phone", response_model=MeOut)
def remove_phone(
    user: User = Depends(current_user), session: Session = Depends(get_session)
):
    user.phone_hash = None
    user.discoverable_by_phone = False
    session.commit()
    return _out(user)


@router.post("/password", response_model=TokensOut)
def change_password(
    body: PasswordChangeIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    ratelimit.hit(f"password:{user.id}", limit=10, window_seconds=900)
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=403, detail="Wrong password.")
    user.password_hash = hash_password(body.new_password)
    # Every other device is signed out; this one gets fresh tokens.
    revoke_all(session, user.id)
    return issue_tokens(session, user)


@router.delete("", status_code=204)
def delete_account(
    body: DeleteAccountIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Erases the account and everything tied to it (foreign keys cascade:
    tokens, friendships, blocks, shelf)."""
    ratelimit.hit(f"delete:{user.id}", limit=5, window_seconds=900)
    if not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=403, detail="Wrong password.")
    session.delete(user)
    session.commit()
