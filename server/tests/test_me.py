from sqlalchemy import text

from app.db import get_engine
from conftest import PASSWORD


def test_update_profile(signup):
    ana = signup("ana")
    r = ana.patch("/me", json={"first_name": "  Anna   Maria ", "username": "Anna_M"})
    assert r.status_code == 200
    assert r.json()["first_name"] == "Anna Maria"
    assert r.json()["username"] == "anna_m"


def test_username_conflict(signup):
    signup("bob")
    ana = signup("ana")
    assert ana.patch("/me", json={"username": "bob"}).status_code == 409


def test_phone_is_stored_only_as_a_hash(signup):
    ana = signup("ana")
    r = ana.put("/me/phone", json={"phone": "0712 345 678", "region": "RO"})
    assert r.status_code == 200 and r.json()["has_phone"] is True
    with get_engine().connect() as conn:
        stored = conn.execute(text("select phone_hash from users")).scalar_one()
        everything = str(conn.execute(text("select * from users")).all())
    assert len(stored) == 64
    assert "712345678" not in everything and "40712" not in everything


def test_invalid_phone_is_rejected(signup):
    ana = signup("ana")
    assert ana.put("/me/phone", json={"phone": "abc", "region": "RO"}).status_code == 422
    assert ana.put("/me/phone", json={"phone": "12", "region": "RO"}).status_code == 422


def test_discoverable_needs_a_phone_and_removal_turns_it_off(signup):
    ana = signup("ana")
    assert ana.patch("/me", json={"discoverable_by_phone": True}).status_code == 422
    ana.put("/me/phone", json={"phone": "+40712345678"})
    r = ana.patch("/me", json={"discoverable_by_phone": True})
    assert r.json()["discoverable_by_phone"] is True
    body = ana.delete("/me/phone").json()
    assert body["has_phone"] is False and body["discoverable_by_phone"] is False


def test_change_password_signs_other_devices_out(client, signup):
    ana = signup("ana")
    old_refresh = ana.tokens["refresh_token"]
    wrong = ana.post("/me/password", json={"current_password": "x", "new_password": "a new long password"})
    assert wrong.status_code == 403
    r = ana.post(
        "/me/password",
        json={"current_password": PASSWORD, "new_password": "a new long password"},
    )
    assert r.status_code == 200
    # The new session works; the old one is dead (replaying it is refused).
    assert client.post("/auth/refresh", json={"refresh_token": r.json()["refresh_token"]}).status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": old_refresh}).status_code == 401
    login = client.post("/auth/login", json={"email": "ana@example.com", "password": "a new long password"})
    assert login.status_code == 200


def test_delete_account_erases_everything(client, signup, befriend):
    ana, bob = signup("ana"), signup("bob")
    befriend(ana, bob)
    ana.put("/me/shelf", json={"books": []})
    ana.put("/me/phone", json={"phone": "+40712345678"})
    assert ana.request("DELETE", "/me", json={"password": "wrong"}).status_code == 403
    assert ana.request("DELETE", "/me", json={"password": PASSWORD}).status_code == 204
    assert ana.get("/me").status_code == 401
    assert bob.get("/friends").json() == []
    with get_engine().connect() as conn:
        for table in ("friendships", "shelves", "refresh_tokens"):
            rows = conn.execute(text(f"select count(*) from {table}")).scalar_one()
            if table == "refresh_tokens":
                assert rows == 1  # only bob's
            else:
                assert rows == 0, table
        assert conn.execute(text("select count(*) from users")).scalar_one() == 1
