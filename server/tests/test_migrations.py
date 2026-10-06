from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext

from app.db import get_engine
from app.main import app
from app.models import Base


def test_models_match_the_migrations():
    """A model change without a migration would work in tests built from the
    models and fail in production. The schema here is built from migrations, so
    any drift shows up as a difference."""
    with get_engine().connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == []


def test_health(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_interactive_docs_are_off(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404
