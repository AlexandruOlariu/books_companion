BOOK = {
    "id": "b1",
    "title": "Dune",
    "author": "Frank Herbert",
    "status": "finished",
    "finishes": [{"precision": "month", "year": 2024, "month": 3, "day": None}],
}


def test_publish_replace_and_read_back(signup):
    ana = signup("ana")
    assert ana.get("/me/shelf").status_code == 404
    r = ana.put("/me/shelf", json={"books": [BOOK]})
    assert r.status_code == 200
    assert r.json()["books"] == [BOOK]
    other = BOOK | {"id": "b2", "title": "Emma", "author": "Jane Austen"}
    r = ana.put("/me/shelf", json={"books": [other]})
    assert [b["id"] for b in r.json()["books"]] == ["b2"]  # replaced, not merged
    assert [b["id"] for b in ana.get("/me/shelf").json()["books"]] == ["b2"]


def test_only_friends_can_read_a_shelf(signup, befriend):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    ana.put("/me/shelf", json={"books": [BOOK]})
    assert bob.get(f"/friends/{ana.id}/shelf").status_code == 404
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert bob.get(f"/friends/{ana.id}/shelf").status_code == 404  # still pending
    bob.post(f"/friends/requests/{ana.id}/accept")
    assert bob.get(f"/friends/{ana.id}/shelf").json()["books"] == [BOOK]
    assert cris.get(f"/friends/{ana.id}/shelf").status_code == 404
    # No shelf published looks the same as not being a friend.
    befriend(cris, bob)
    assert cris.get(f"/friends/{bob.id}/shelf").status_code == 404


def test_unfriending_or_unpublishing_takes_the_shelf_away(signup, befriend):
    ana, bob = signup("ana"), signup("bob")
    befriend(ana, bob)
    ana.put("/me/shelf", json={"books": [BOOK]})
    assert bob.get(f"/friends/{ana.id}/shelf").status_code == 200
    assert ana.delete("/me/shelf").status_code == 204
    assert bob.get(f"/friends/{ana.id}/shelf").status_code == 404
    ana.put("/me/shelf", json={"books": [BOOK]})
    ana.delete(f"/friends/{bob.id}")
    assert bob.get(f"/friends/{ana.id}/shelf").status_code == 404


def test_private_fields_are_rejected_not_ignored(signup):
    ana = signup("ana")
    for extra in ("note", "notes", "pins", "sessions", "cover", "isbn"):
        r = ana.put("/me/shelf", json={"books": [BOOK | {extra: "private"}]})
        assert r.status_code == 422, extra
    assert ana.put("/me/shelf", json={"books": [], "notes": "x"}).status_code == 422


def test_dates_keep_their_precision(signup):
    ana = signup("ana")

    def finish(**fields):
        return ana.put(
            "/me/shelf", json={"books": [BOOK | {"finishes": [fields]}]}
        ).status_code

    assert finish(precision="year", year=2020) == 200
    assert finish(precision="month", year=2020, month=2) == 200
    assert finish(precision="day", year=2020, month=2, day=29) == 200
    assert finish(precision="unknown") == 200
    # A remembered year must not carry an invented month or day, and vice versa.
    assert finish(precision="year", year=2020, month=1, day=1) == 422
    assert finish(precision="month", year=2020) == 422
    assert finish(precision="day", year=2020, month=2) == 422
    assert finish(precision="unknown", year=2020) == 422
    assert finish(precision="day", year=2021, month=2, day=29) == 422  # not a real date
    assert finish(precision="day", year=2020, month=13, day=1) == 422
    assert finish(precision="year") == 422
    assert finish(precision="week", year=2020) == 422


def test_finishes_must_match_status(signup):
    ana = signup("ana")

    def put(**fields):
        return ana.put("/me/shelf", json={"books": [BOOK | fields]}).status_code

    assert put(status="finished", finishes=[]) == 422
    assert put(status="want_to_read", finishes=[{"precision": "unknown"}]) == 422
    assert put(status="want_to_read", finishes=[]) == 200
    assert put(status="reading", finishes=[]) == 200
    # A re-read: currently reading, with an earlier finish.
    assert put(status="reading", finishes=[{"precision": "year", "year": 2019}]) == 200
    assert put(status="abandoned", finishes=[]) == 422


def test_future_finish_dates_are_rejected(signup):
    ana = signup("ana")
    r = ana.put(
        "/me/shelf",
        json={"books": [BOOK | {"finishes": [{"precision": "year", "year": 9000}]}]},
    )
    assert r.status_code == 422


def test_limits(signup):
    ana = signup("ana")
    dup = ana.put("/me/shelf", json={"books": [BOOK, BOOK]})
    assert dup.status_code == 422
    long_title = ana.put("/me/shelf", json={"books": [BOOK | {"title": "x" * 301}]})
    assert long_title.status_code == 422
    empty_title = ana.put("/me/shelf", json={"books": [BOOK | {"title": ""}]})
    assert empty_title.status_code == 422
    many = [BOOK | {"id": str(i), "status": "want_to_read", "finishes": []} for i in range(5001)]
    assert ana.put("/me/shelf", json={"books": many}).status_code == 422


def test_shelf_requires_sign_in(client):
    assert client.put("/me/shelf", json={"books": []}).status_code == 401
