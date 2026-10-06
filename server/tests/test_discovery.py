def make_findable(person, number, region="RO"):
    assert person.put("/me/phone", json={"phone": number, "region": region}).status_code == 200
    assert person.patch("/me", json={"discoverable_by_phone": True}).status_code == 200


def test_lookup_by_exact_username_only(signup):
    ana, bob = signup("ana"), signup("bobby")
    r = ana.get("/users/lookup", params={"username": "BOBBY"})
    assert r.status_code == 200
    assert r.json() == {"id": bob.id, "username": "bobby", "display_name": "Bobby Test"}
    # No prefix search, no partial match: that would let anyone list users.
    assert ana.get("/users/lookup", params={"username": "bob"}).status_code == 404
    assert ana.get("/users/lookup", params={"username": "nobody"}).status_code == 404
    # Not yourself.
    assert ana.get("/users/lookup", params={"username": "ana"}).status_code == 404


def test_lookup_never_exposes_email_or_phone(signup):
    ana, bob = signup("ana"), signup("bobby")
    make_findable(bob, "+40712345678")
    body = ana.get("/users/lookup", params={"username": "bobby"}).json()
    assert set(body) == {"id", "username", "display_name"}


def test_lookup_requires_sign_in(client, signup):
    signup("bobby")
    assert client.get("/users/lookup", params={"username": "bobby"}).status_code == 401


def test_contacts_match_finds_only_people_who_opted_in(signup):
    ana, bob, cris, dana = signup("ana"), signup("bob"), signup("cris"), signup("dana")
    make_findable(bob, "+40712345678")
    cris.put("/me/phone", json={"phone": "+40722222222"})  # has a phone, not findable
    # dana has no phone at all
    r = ana.post(
        "/contacts/match",
        json={"region": "RO", "numbers": ["0712 345 678", "0722222222", "0733333333", "garbage"]},
    )
    assert r.status_code == 200
    assert [p["username"] for p in r.json()] == ["bob"]


def test_contacts_match_normalises_formats(signup):
    ana, bob = signup("ana"), signup("bob")
    make_findable(bob, "0712 345 678", region="RO")
    for written in ("+40712345678", "0040712345678", "0712-345-678", "(0712) 345 678"):
        r = ana.post("/contacts/match", json={"region": "RO", "numbers": [written]})
        assert [p["username"] for p in r.json()] == ["bob"], written


def test_contacts_match_skips_self_and_blocked(signup):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    make_findable(ana, "+40711111111")
    make_findable(bob, "+40722222222")
    make_findable(cris, "+40733333333")
    numbers = ["+40711111111", "+40722222222", "+40733333333"]
    assert [p["username"] for p in ana.post("/contacts/match", json={"numbers": numbers}).json()] == [
        "bob",
        "cris",
    ]
    ana.put(f"/blocks/{bob.id}")
    assert [p["username"] for p in ana.post("/contacts/match", json={"numbers": numbers}).json()] == ["cris"]
    # Blocked in the other direction too: bob cannot find ana either.
    assert bob.post("/contacts/match", json={"numbers": numbers}).json() == [
        {"id": cris.id, "username": "cris", "display_name": "Cris Test"}
    ]


def test_contacts_match_is_budgeted(signup):
    ana = signup("ana")
    numbers = [f"+4071{n:07d}" for n in range(1000)]
    for _ in range(3):
        assert ana.post("/contacts/match", json={"numbers": numbers}).status_code == 200
    # 3000 numbers a day is the budget.
    assert ana.post("/contacts/match", json={"numbers": ["+40712345678"]}).status_code == 429


def test_contacts_match_rejects_oversized_lists(signup):
    ana = signup("ana")
    r = ana.post("/contacts/match", json={"numbers": ["+40712345678"] * 1001})
    assert r.status_code == 422


def test_contacts_are_not_stored(signup):
    from sqlalchemy import text

    from app.db import get_engine

    ana = signup("ana")
    ana.post("/contacts/match", json={"numbers": ["+40799999999"]})
    with get_engine().connect() as conn:
        dump = "".join(
            str(conn.execute(text(f"select * from {t}")).all())
            for t in ("users", "rate_events", "friendships", "shelves")
        )
    assert "99999999" not in dump
