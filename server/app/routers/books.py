from fastapi import APIRouter, HTTPException, Request

from app import booksearch, ratelimit
from app.deps import client_ip
from app.schemas import BookSearchIn, BookSearchOut

router = APIRouter(tags=["books"])


@router.post("/books/search", response_model=BookSearchOut)
def search_books(body: BookSearchIn, request: Request):
    """Search Open Library for the app. No sign-in: the app works without an
    account, and an account would tie searches to a person. The text is used
    for the search and an in-memory cache, never stored or logged."""
    if not body.q.strip():
        raise HTTPException(status_code=422, detail="Enter a title, author, or ISBN.")
    ratelimit.hit(f"books-ip:{client_ip(request)}", limit=120, window_seconds=3600)
    try:
        return booksearch.cached_search(body.q)
    except booksearch.CatalogueUnavailable:
        raise HTTPException(status_code=502, detail="Could not reach Open Library.")
