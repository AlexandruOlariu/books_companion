from fastapi import FastAPI

from app.routers import auth, books, friends, library, me, people, shelf

# Served at https://ai.duk-tech.com/books-api/ ; nginx strips the prefix, so the
# app itself lives at the root. The interactive docs are off in production.
app = FastAPI(
    title="Reading Library server",
    version="0.1.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

app.include_router(auth.router)
app.include_router(me.router)
app.include_router(people.router)
app.include_router(friends.router)
app.include_router(shelf.router)
app.include_router(books.router)
app.include_router(library.router)


@app.get("/healthz", tags=["ops"])
def healthz():
    return {"status": "ok"}
