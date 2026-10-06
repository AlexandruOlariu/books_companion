from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import ratelimit
from app.config import get_settings
from app.db import get_session
from app.deps import client_ip
from app.models import RefreshToken, User
from app.schemas import LoginIn, RefreshIn, RegisterIn, TokensOut
from app.security import (
    create_access_token,
    hash_password,
    hash_token,
    new_refresh_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def issue_tokens(session: Session, user: User) -> TokensOut:
    refresh = new_refresh_token()
    session.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_token(refresh),
            expires_at=datetime.now(timezone.utc)
            + timedelta(days=get_settings().refresh_token_days),
        )
    )
    session.commit()
    return TokensOut(access_token=create_access_token(user.id), refresh_token=refresh)


def revoke_all(session: Session, user_id) -> None:
    session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(timezone.utc))
    )


@router.post("/register", response_model=TokensOut, status_code=201)
def register(body: RegisterIn, request: Request, session: Session = Depends(get_session)):
    ratelimit.hit(f"register:{client_ip(request)}", limit=20, window_seconds=3600)
    taken = session.scalar(
        select(User).where((User.email == body.email) | (User.username == body.username))
    )
    if taken is not None:
        # Without email verification there is no way to hide this, and a signup
        # form has to say why it failed. It is rate-limited per address.
        field = "email" if taken.email == body.email else "username"
        raise HTTPException(status_code=409, detail=f"That {field} is already taken.")
    user = User(
        email=body.email,
        password_hash=hash_password(body.password),
        username=body.username,
        first_name=body.first_name,
        last_name=body.last_name,
    )
    session.add(user)
    try:
        session.flush()
    except IntegrityError:  # lost a race with a concurrent signup
        session.rollback()
        raise HTTPException(
            status_code=409, detail="That email or username is already taken."
        )
    return issue_tokens(session, user)


@router.post("/login", response_model=TokensOut)
def login(body: LoginIn, request: Request, session: Session = Depends(get_session)):
    ratelimit.hit(f"login-ip:{client_ip(request)}", limit=60, window_seconds=900)
    ratelimit.hit(f"login-email:{body.email}", limit=10, window_seconds=900)
    user = session.scalar(select(User).where(User.email == body.email))
    if not verify_password(body.password, user.password_hash if user else None):
        raise HTTPException(status_code=401, detail="Wrong email or password.")
    return issue_tokens(session, user)


@router.post("/refresh", response_model=TokensOut)
def refresh(body: RefreshIn, request: Request, session: Session = Depends(get_session)):
    ratelimit.hit(f"refresh-ip:{client_ip(request)}", limit=120, window_seconds=900)
    token = session.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_token(body.refresh_token))
    )
    invalid = HTTPException(status_code=401, detail="Sign in again.")
    if token is None:
        raise invalid
    if token.revoked_at is not None:
        # A rotated-out token showing up again means it was copied. Close every
        # session of that account; the real owner signs in again.
        revoke_all(session, token.user_id)
        session.commit()
        raise invalid
    if token.expires_at <= datetime.now(timezone.utc):
        raise invalid
    user = session.get(User, token.user_id)
    if user is None:
        raise invalid
    token.revoked_at = datetime.now(timezone.utc)
    return issue_tokens(session, user)


@router.post("/logout", status_code=204)
def logout(body: RefreshIn, session: Session = Depends(get_session)):
    token = session.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_token(body.refresh_token))
    )
    if token is not None and token.revoked_at is None:
        token.revoked_at = datetime.now(timezone.utc)
        session.commit()
