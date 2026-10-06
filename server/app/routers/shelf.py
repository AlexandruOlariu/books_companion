import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db import get_session
from app.deps import are_friends, current_user
from app.models import Shelf, User
from app.schemas import ShelfIn, ShelfOut

router = APIRouter(tags=["shelf"])


def _out(shelf: Shelf) -> ShelfOut:
    return ShelfOut(books=shelf.payload["books"], updated_at=shelf.updated_at)


@router.put("/me/shelf", response_model=ShelfOut)
def publish_shelf(
    body: ShelfIn,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    """Publish a snapshot of the shelf for friends. It replaces the previous
    one. Only titles, authors, status and finish dates are accepted; notes,
    pins and sessions have no field here and are rejected if sent."""
    shelf = session.get(Shelf, me.id)
    payload = body.model_dump(mode="json")
    if shelf is None:
        shelf = Shelf(user_id=me.id, payload=payload)
        session.add(shelf)
    else:
        shelf.payload = payload
        shelf.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(shelf)
    return _out(shelf)


@router.get("/me/shelf", response_model=ShelfOut)
def my_published_shelf(
    me: User = Depends(current_user), session: Session = Depends(get_session)
):
    shelf = session.get(Shelf, me.id)
    if shelf is None:
        raise HTTPException(status_code=404, detail="Nothing published.")
    return _out(shelf)


@router.delete("/me/shelf", status_code=204)
def unpublish_shelf(
    me: User = Depends(current_user), session: Session = Depends(get_session)
):
    shelf = session.get(Shelf, me.id)
    if shelf is not None:
        session.delete(shelf)
        session.commit()


@router.get("/friends/{user_id}/shelf", response_model=ShelfOut)
def friends_shelf(
    user_id: uuid.UUID,
    me: User = Depends(current_user),
    session: Session = Depends(get_session),
):
    # Not a friend and nothing published answer the same, so this cannot be
    # used to learn whether a stranger has a shelf.
    shelf = session.get(Shelf, user_id)
    if shelf is None or not are_friends(session, me.id, user_id):
        raise HTTPException(status_code=404, detail="Not found.")
    return _out(shelf)
