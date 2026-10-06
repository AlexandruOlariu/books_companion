from conftest import PASSWORD


def test_register_returns_tokens_and_hides_secrets(client, signup):
    ana = signup("ana")
    me = ana.get("/me").json()
    assert me["email"] == "ana@example.com"
    assert me["username"] == "ana"
    assert me["has_phone"] is False
    assert "password" not in str(me) and "password_hash" not in me


def test_register_rejects_weak_or_malformed_input(client):
    base = {
        "email": "x@example.com",
        "password": PASSWORD,
        "username": "xavier",
        "first_name": "X",
        "last_name": "Y",
    }
    for bad in (
        {"password": "short"},
        {"email": "not-an-email"},
        {"username": "ab"},
        {"username": "has space"},
        {"first_name": "   "},
        {"role": "admin"},  # unknown fields are refused
    ):
        r = client.post("/auth/register", json=base | bad)
        assert r.status_code == 422, bad


def test_email_and_username_are_normalised_and_unique(client, signup):
    signup("ana")
    r = client.post(
        "/auth/register",
        json={
            "email": "ANA@Example.com",
            "password": PASSWORD,
            "username": "other",
            "first_name": "A",
            "last_name": "B",
        },
    )
    assert r.status_code == 409
    r = client.post(
        "/auth/register",
        json={
            "email": "new@example.com",
            "password": PASSWORD,
            "username": "ANA",
            "first_name": "A",
            "last_name": "B",
        },
    )
    assert r.status_code == 409


def test_login(client, signup):
    signup("ana")
    ok = client.post("/auth/login", json={"email": "Ana@example.com", "password": PASSWORD})
    assert ok.status_code == 200 and ok.json()["access_token"]
    wrong = client.post("/auth/login", json={"email": "ana@example.com", "password": "nope"})
    unknown = client.post("/auth/login", json={"email": "who@example.com", "password": "nope"})
    # Same answer for a wrong password and an unknown email.
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_login_is_rate_limited_per_email(client, signup):
    signup("ana")
    codes = [
        client.post("/auth/login", json={"email": "ana@example.com", "password": "bad"}).status_code
        for _ in range(12)
    ]
    assert codes[:10] == [401] * 10
    assert codes[10:] == [429, 429]
    # Even the right password is refused while locked out.
    r = client.post("/auth/login", json={"email": "ana@example.com", "password": PASSWORD})
    assert r.status_code == 429


def test_protected_routes_need_a_valid_token(client):
    assert client.get("/me").status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer garbage"}).status_code == 401


def test_refresh_rotates_and_reuse_closes_every_session(client, signup):
    ana = signup("ana")
    first = ana.tokens["refresh_token"]
    r = client.post("/auth/refresh", json={"refresh_token": first})
    assert r.status_code == 200
    second = r.json()["refresh_token"]
    assert second != first
    # The old token is dead...
    assert client.post("/auth/refresh", json={"refresh_token": first}).status_code == 401
    # ...and replaying it also revoked the new one (it may have been stolen).
    assert client.post("/auth/refresh", json={"refresh_token": second}).status_code == 401


def test_logout_revokes_the_refresh_token(client, signup):
    ana = signup("ana")
    token = ana.tokens["refresh_token"]
    assert client.post("/auth/logout", json={"refresh_token": token}).status_code == 204
    assert client.post("/auth/refresh", json={"refresh_token": token}).status_code == 401
