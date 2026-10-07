import pytest

EMPTY = {
    "version": 1,
    "books": [],
    "authors": [],
    "bookAuthors": [],
    "editions": [],
    "userBooks": [],
    "records": [],
    "sessions": [],
    "pins": [],
}


def lib(**changes):
    return EMPTY | changes


NOTE = {"id": "p1", "userBookId": "u1", "textContent": "a private thought", "type": "Thought"}


def save(person, data, base):
    return person.put("/me/library", json={"base_revision": base, "data": data})


def test_nothing_saved_yet(signup):
    ana = signup("ana")
    assert ana.get("/me/library").status_code == 404
    assert ana.get("/me/library/meta").status_code == 404


def test_requires_sign_in(client):
    assert client.get("/me/library").status_code == 401
    assert client.put("/me/library", json={"base_revision": 0, "data": EMPTY}).status_code == 401


def test_save_and_read_back_everything_including_notes(signup):
    ana = signup("ana")
    r = save(ana, lib(pins=[NOTE]), 0)
    assert r.status_code == 200
    assert r.json()["revision"] == 1
    got = ana.get("/me/library").json()
    assert got["revision"] == 1
    assert got["data"]["pins"] == [NOTE]
    assert ana.get("/me/library/meta").json()["revision"] == 1


def test_each_save_moves_the_revision_on(signup):
    ana = signup("ana")
    assert save(ana, EMPTY, 0).json()["revision"] == 1
    assert save(ana, EMPTY, 1).json()["revision"] == 2
    assert save(ana, lib(pins=[NOTE]), 2).json()["revision"] == 3
    assert ana.get("/me/library").json()["data"]["pins"] == [NOTE]


def test_a_stale_save_is_refused_and_changes_nothing(signup):
    ana = signup("ana")
    save(ana, lib(pins=[NOTE]), 0)
    save(ana, lib(pins=[NOTE, NOTE | {"id": "p2"}]), 1)
    # A second phone that still thinks it is at revision 1.
    r = save(ana, EMPTY, 1)
    assert r.status_code == 409
    assert r.headers["X-Library-Revision"] == "2"
    # A first save from a phone that never synced is refused the same way.
    assert save(ana, EMPTY, 0).status_code == 409
    got = ana.get("/me/library").json()
    assert got["revision"] == 2
    assert len(got["data"]["pins"]) == 2


def test_libraries_are_private_to_their_owner(signup):
    ana, bob = signup("ana"), signup("bob")
    save(ana, lib(pins=[NOTE]), 0)
    assert bob.get("/me/library").status_code == 404
    # Bob saving does not touch Ana's library.
    assert save(bob, EMPTY, 0).status_code == 200
    assert ana.get("/me/library").json()["data"]["pins"] == [NOTE]


def test_an_unknown_table_is_refused(signup):
    ana = signup("ana")
    assert save(ana, lib(contacts=[{"n": "1"}]), 0).status_code == 422
    assert ana.get("/me/library").status_code == 404


@pytest.mark.parametrize(
    "bad",
    [
        {"version": 2},
        {"books": "nope"},
        {"books": [1, 2]},
        {"pins": None},
    ],
)
def test_a_malformed_library_is_refused(signup, bad):
    ana = signup("ana")
    assert save(ana, lib(**bad), 0).status_code == 422


def test_a_missing_table_is_refused(signup):
    ana = signup("ana")
    data = dict(EMPTY)
    del data["pins"]
    assert save(ana, data, 0).status_code == 422


def test_an_oversized_library_is_refused(signup, monkeypatch):
    from app.routers import library

    monkeypatch.setattr(library, "MAX_LIBRARY_BYTES", 500)
    ana = signup("ana")
    big = lib(pins=[NOTE | {"textContent": "x" * 1000}])
    assert save(ana, big, 0).status_code == 413
    assert ana.get("/me/library").status_code == 404


def test_the_error_does_not_echo_the_library_back(signup):
    ana = signup("ana")
    r = save(ana, lib(contacts=[{"secret": "do-not-echo"}]), 0)
    assert r.status_code == 422
    assert "do-not-echo" not in r.text


def test_saving_is_rate_limited(signup, monkeypatch):
    from app.routers import library

    calls = []
    monkeypatch.setattr(library.ratelimit, "hit", lambda *a, **k: calls.append((a, k)))
    ana = signup("ana")
    calls.clear()
    save(ana, EMPTY, 0)
    assert [c[0][0] for c in calls] == [f"library:{ana.id}"]


def test_deleting_the_account_deletes_the_library(signup, client):
    from sqlalchemy import text

    from app.db import get_engine

    ana = signup("ana")
    save(ana, lib(pins=[NOTE]), 0)
    r = ana.request("DELETE", "/me", json={"password": "correct horse battery"})
    assert r.status_code == 204, r.text
    with get_engine().connect() as conn:
        assert conn.execute(text("select count(*) from libraries")).scalar() == 0
