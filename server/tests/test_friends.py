def names(people):
    return sorted(p["username"] for p in people)


def test_request_accept_flow(signup):
    ana, bob = signup("ana"), signup("bob")
    r = ana.post("/friends/requests", json={"user_id": bob.id})
    assert r.status_code == 201 and r.json()["username"] == "bob"

    assert names(ana.get("/friends/requests").json()["outgoing"]) == ["bob"]
    assert names(bob.get("/friends/requests").json()["incoming"]) == ["ana"]
    assert ana.get("/friends").json() == [] and bob.get("/friends").json() == []

    assert bob.post(f"/friends/requests/{ana.id}/accept").status_code == 200
    assert names(ana.get("/friends").json()) == ["bob"]
    assert names(bob.get("/friends").json()) == ["ana"]
    assert bob.get("/friends/requests").json() == {"incoming": [], "outgoing": []}


def test_the_sender_cannot_accept_their_own_request(signup):
    ana, bob = signup("ana"), signup("bob")
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert ana.post(f"/friends/requests/{bob.id}/accept").status_code == 404
    assert ana.get("/friends").json() == []


def test_asking_back_accepts(signup):
    ana, bob = signup("ana"), signup("bob")
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert bob.post("/friends/requests", json={"user_id": ana.id}).status_code == 201
    assert names(ana.get("/friends").json()) == ["bob"]


def test_duplicate_requests_and_existing_friends(signup, befriend):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    ana.post("/friends/requests", json={"user_id": cris.id})
    assert ana.post("/friends/requests", json={"user_id": cris.id}).status_code == 409
    befriend(ana, bob)
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 409
    assert bob.post("/friends/requests", json={"user_id": ana.id}).status_code == 409


def test_cannot_befriend_yourself_or_a_stranger_id(signup):
    ana = signup("ana")
    assert ana.post("/friends/requests", json={"user_id": ana.id}).status_code == 404
    random_id = "00000000-0000-4000-8000-000000000000"
    assert ana.post("/friends/requests", json={"user_id": random_id}).status_code == 404


def test_decline_and_cancel(signup):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert bob.delete(f"/friends/requests/{ana.id}").status_code == 204  # decline
    assert ana.get("/friends/requests").json()["outgoing"] == []
    ana.post("/friends/requests", json={"user_id": cris.id})
    assert ana.delete(f"/friends/requests/{cris.id}").status_code == 204  # cancel
    assert cris.get("/friends/requests").json()["incoming"] == []
    # Declining does not block: they may ask again.
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201


def test_remove_friend(signup, befriend):
    ana, bob = signup("ana"), signup("bob")
    befriend(ana, bob)
    assert ana.delete(f"/friends/{bob.id}").status_code == 204
    assert ana.get("/friends").json() == [] and bob.get("/friends").json() == []
    assert ana.delete(f"/friends/{bob.id}").status_code == 404


def test_block_removes_friendship_and_prevents_contact(signup, befriend):
    ana, bob = signup("ana"), signup("bob")
    befriend(ana, bob)
    assert ana.put(f"/blocks/{bob.id}").status_code == 204
    assert ana.get("/friends").json() == [] and bob.get("/friends").json() == []
    assert names(ana.get("/blocks").json()) == ["bob"]
    # Neither side can send a request, and the answer does not reveal the block.
    assert bob.post("/friends/requests", json={"user_id": ana.id}).status_code == 404
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 404
    assert bob.get("/users/lookup", params={"username": "ana"}).status_code == 404
    # Unblocking restores the ability to ask, not the friendship.
    assert ana.delete(f"/blocks/{bob.id}").status_code == 204
    assert ana.get("/friends").json() == []
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201


def test_blocking_twice_is_fine_and_unblocking_a_stranger_is_not(signup):
    ana, bob = signup("ana"), signup("bob")
    assert ana.put(f"/blocks/{bob.id}").status_code == 204
    assert ana.put(f"/blocks/{bob.id}").status_code == 204
    assert ana.delete(f"/blocks/{bob.id}").status_code == 204
    assert ana.delete(f"/blocks/{bob.id}").status_code == 404


def test_friends_lists_are_private_to_each_person(signup, befriend):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    befriend(ana, bob)
    assert cris.get("/friends").json() == []
    assert cris.get("/friends/requests").json() == {"incoming": [], "outgoing": []}
