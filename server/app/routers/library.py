from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import ratelimit
from app.db import get_session
from app.deps import current_user
from app.models import Library, User
from app.schemas import LibraryIn, LibraryMeta, LibraryOut

router = APIRouter(tags=["library"])

# Notes and sessions of a very large library are still a few MB; covers are not
# stored here, only where to fetch them again.
MAX_LIBRARY_BYTES = 20 * 1024 * 1024


@router.get("/me/library/meta", response_model=LibraryMeta)
def library_meta(
    me: User = Depends(current_user), session: Session = Depends(get_session)
):
    """The revision only, so the app can check cheaply whether it is behind."""
    row = session.execute(
        select(Library.revision, Library.updated_at).where(Library.user_id == me.id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="No library saved yet.")
    return LibraryMeta(revision=row.revision, updated_at=row.updated_at)


@router.get("/me/library", response_model=LibraryOut)
def get_library(
    me: User = Depends(current_user), session: Session = Depends(get_session)
):
    row = session.get(Library, me.id)
    if row is None:
        raise HTTPException(status_code=404, detail="No library saved yet.")
    return LibraryOut(revision=row.revision, updated_at=row.updated_at, data=row.payload)


@router.put("/me/library", response_model=LibraryMeta)
async def put_library(
    request: Request,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Replace the saved library. `base_revision` is the revision the app last
    saw (0 for none); if the server has moved on, nothing is written and the
    answer is 409 with the current revision, so one phone never silently
    overwrites another's newer changes."""
    ratelimit.hit(f"library:{me.id}", limit=600, window_seconds=3600)
    raw = await request.body()
    if len(raw) > MAX_LIBRARY_BYTES:
        raise HTTPException(status_code=413, detail="Your library is too large to save.")
    try:
        body = LibraryIn.model_validate_json(raw)
    except ValidationError as e:
        # Same shape as FastAPI's own 422, without echoing the library back.
        raise HTTPException(
            status_code=422,
            detail=e.errors(include_input=False, include_url=False, include_context=False),
        )
    row = session.scalar(select(Library).where(Library.user_id == me.id).with_for_update())
    current = row.revision if row else 0
    if current != body.base_revision:
        raise HTTPException(
            status_code=409,
            detail="Your library changed on another device.",
            headers={"X-Library-Revision": str(current)},
        )
    if row is None:
        row = Library(user_id=me.id, revision=1, payload=body.data)
        session.add(row)
    else:
        row.revision = current + 1
        row.payload = body.data
        row.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(row)
    return LibraryMeta(revision=row.revision, updated_at=row.updated_at)
