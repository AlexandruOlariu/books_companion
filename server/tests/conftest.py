import os
import secrets

# Settings are read when the app is first imported, so set them first. Tests run
# against a real Postgres (the schema uses JSONB and database constraints that
# SQLite would not exercise). CI provides one; locally see docs/backend.md.
TEST_DB = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://postgres:test@127.0.0.1:55432/books_test",
)
# The `schema` fixture below drops everything in the database. Refuse to run
# against anything that is not clearly a throwaway test database.
if not TEST_DB.split("?")[0].endswith("_test"):
    raise SystemExit("TEST_DATABASE_URL must name a database ending in _test")
os.environ["DATABASE_URL"] = TEST_DB
os.environ.setdefault("JWT_SECRET", secrets.token_urlsafe(48))
os.environ.setdefault("PHONE_PEPPER", secrets.token_urlsafe(48))

import pytest  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.db import get_engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def schema():
    """Build the schema the way production does: by running the migrations."""
    with get_engine().begin() as conn:
        conn.execute(text("drop schema public cascade"))
        conn.execute(text("create schema public"))
    command.upgrade(Config("alembic.ini"), "head")


@pytest.fixture(autouse=True)
def clean(schema):
    yield
    with get_engine().begin() as conn:
        conn.execute(
            text(
                "truncate users, refresh_tokens, friendships, blocks, shelves, libraries, "
                "device_tokens, rate_events cascade"
            )
        )


@pytest.fixture
def client():
    return TestClient(app)


class Person:
    def __init__(self, client: TestClient, name: str, tokens: dict, user_id: str):
        self.client = client
        self.name = name
        self.tokens = tokens
        self.id = user_id

    @property
    def auth(self) -> dict:
        return {"Authorization": f"Bearer {self.tokens['access_token']}"}

    def get(self, url, **kw):
        return self.client.get(url, headers=self.auth, **kw)

    def post(self, url, **kw):
        return self.client.post(url, headers=self.auth, **kw)

    def put(self, url, **kw):
        return self.client.put(url, headers=self.auth, **kw)

    def patch(self, url, **kw):
        return self.client.patch(url, headers=self.auth, **kw)

    def delete(self, url, **kw):
        return self.client.delete(url, headers=self.auth, **kw)

    def request(self, method, url, **kw):
        return self.client.request(method, url, headers=self.auth, **kw)


PASSWORD = "correct horse battery"


@pytest.fixture
def signup(client):
    def make(name: str = "ana", **overrides) -> Person:
        body = {
            "email": f"{name}@example.com",
            "password": PASSWORD,
            "username": name,
            "first_name": name.capitalize(),
            "last_name": "Test",
        } | overrides
        r = client.post("/auth/register", json=body)
        assert r.status_code == 201, r.text
        tokens = r.json()
        me = client.get(
            "/me", headers={"Authorization": f"Bearer {tokens['access_token']}"}
        ).json()
        return Person(client, name, tokens, me["id"])

    return make


@pytest.fixture
def befriend():
    def make(a: Person, b: Person) -> None:
        assert a.post("/friends/requests", json={"user_id": b.id}).status_code == 201
        assert b.post(f"/friends/requests/{a.id}/accept").status_code == 200

    return make
