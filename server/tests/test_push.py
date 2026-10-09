import pytest

from app import push

TOKEN = "t" * 40


class Sent(list):
    """What would have gone to Firebase, plus per-token answers to give back."""

    def __init__(self):
        super().__init__()
        self.outcomes: dict[str, push.Outcome] = {}


@pytest.fixture
def sent(monkeypatch):
    """Turn push on and record what would go to Firebase instead of sending it."""
    calls = Sent()

    def fake(token: str, kind: str) -> push.Outcome:
        calls.append((token, kind))
        return calls.outcomes.get(token, push.Outcome(ok=True))

    monkeypatch.setattr(push, "enabled", lambda: True)
    monkeypatch.setattr(push, "transport", fake)
    return calls


def register(person, token=TOKEN, platform="android"):
    return person.put("/me/devices", json={"token": token, "platform": platform})


def test_a_request_notifies_the_person_asked(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    assert register(bob, "b" * 40).status_code == 204
    assert register(ana, "a" * 40).status_code == 204
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201
    assert sent == [("b" * 40, "friend_request")]


def test_accepting_notifies_the_person_who_asked(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(ana, "a" * 40)
    register(bob, "b" * 40)
    ana.post("/friends/requests", json={"user_id": bob.id})
    sent.clear()
    assert bob.post(f"/friends/requests/{ana.id}/accept").status_code == 200
    assert sent == [("a" * 40, "friend_accepted")]


def test_asking_back_counts_as_accepting(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(ana, "a" * 40)
    register(bob, "b" * 40)
    ana.post("/friends/requests", json={"user_id": bob.id})
    sent.clear()
    assert bob.post("/friends/requests", json={"user_id": ana.id}).status_code == 201
    assert sent == [("a" * 40, "friend_accepted")]


def test_failed_or_refused_requests_notify_nobody(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(bob, "b" * 40)
    ana.post("/friends/requests", json={"user_id": bob.id})
    sent.clear()
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 409
    assert ana.post(f"/friends/requests/{bob.id}/accept").status_code == 404
    bob.put(f"/blocks/{ana.id}")
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 404
    assert sent == []


def test_every_phone_of_the_account_is_notified(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(bob, "b" * 40)
    register(bob, "c" * 40)
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert sorted(t for t, _ in sent) == ["b" * 40, "c" * 40]


def test_a_dead_token_is_forgotten_and_a_failure_changes_nothing(signup, sent):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    register(bob, "b" * 40)
    sent.outcomes["b" * 40] = push.Outcome(ok=False, dead=True)
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201
    assert len(sent) == 1
    sent.clear()
    cris.post("/friends/requests", json={"user_id": bob.id})
    assert sent == []  # the dead token is gone


def test_a_transport_that_raises_never_breaks_the_request(signup, monkeypatch):
    def boom(token, kind):
        raise RuntimeError("no network")

    monkeypatch.setattr(push, "enabled", lambda: True)
    monkeypatch.setattr(push, "transport", boom)
    ana, bob = signup("ana"), signup("bob")
    register(bob, "b" * 40)
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201


def test_push_is_off_without_credentials(signup, monkeypatch):
    def fail(token, kind):
        raise AssertionError("must not send")

    monkeypatch.setattr(push, "transport", fail)
    ana, bob = signup("ana"), signup("bob")
    register(bob, "b" * 40)
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 201


def test_the_message_names_nobody(signup):
    for title, body in push.MESSAGES.values():
        assert "@" not in title + body


def test_a_token_follows_the_last_account_to_register_it(signup, sent):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    register(ana)
    register(bob)  # same phone, now signed in as bob
    cris.post("/friends/requests", json={"user_id": ana.id})
    assert sent == []
    cris.post("/friends/requests", json={"user_id": bob.id})
    assert sent == [(TOKEN, "friend_request")]


def test_registering_twice_keeps_one_row(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(bob)
    register(bob)
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert sent == [(TOKEN, "friend_request")]


def test_remove_stops_pushes_and_only_removes_your_own(signup, sent):
    ana, bob, cris = signup("ana"), signup("bob"), signup("cris")
    register(bob)
    assert cris.post("/me/devices/remove", json={"token": TOKEN}).status_code == 204
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert len(sent) == 1  # cris could not remove bob's phone
    sent.clear()
    assert bob.post("/me/devices/remove", json={"token": TOKEN}).status_code == 204
    assert bob.post("/me/devices/remove", json={"token": TOKEN}).status_code == 204
    cris.post("/friends/requests", json={"user_id": bob.id})
    assert sent == []


def test_device_input_is_validated_and_needs_sign_in(client, signup):
    ana = signup("ana")
    assert register(ana, "short").status_code == 422
    assert register(ana, platform="windows").status_code == 422
    assert (
        ana.put("/me/devices", json={"token": TOKEN, "platform": "android", "x": 1}).status_code
        == 422
    )
    assert client.put("/me/devices", json={"token": TOKEN, "platform": "ios"}).status_code == 401
    assert client.post("/me/devices/remove", json={"token": TOKEN}).status_code == 401


def test_only_the_newest_ten_phones_are_kept(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    for i in range(12):
        assert register(bob, f"{i:02d}" * 20).status_code == 204
    ana.post("/friends/requests", json={"user_id": bob.id})
    assert len(sent) == 10


def test_deleting_the_account_removes_the_tokens(signup, sent):
    ana, bob = signup("ana"), signup("bob")
    register(bob)
    assert bob.request("DELETE", "/me", json={"password": "correct horse battery"}).status_code == 204
    assert ana.post("/friends/requests", json={"user_id": bob.id}).status_code == 404
    from sqlalchemy import text

    from app.db import get_engine

    with get_engine().connect() as conn:
        assert conn.execute(text("select count(*) from device_tokens")).scalar() == 0


class FakeCredentials:
    valid = True
    token = "access-token"
    project_id = "demo-project"


@pytest.mark.parametrize(
    ("status", "ok", "dead"), [(200, True, False), (404, False, True), (500, False, False)]
)
def test_the_firebase_request(monkeypatch, status, ok, dead):
    import requests

    seen = {}

    class Reply:
        status_code = status

        @property
        def ok(self):
            return status < 400

    def post(url, headers, json, timeout):
        seen.update(url=url, headers=headers, json=json)
        return Reply()

    monkeypatch.setattr(push, "_load_credentials", lambda: FakeCredentials())
    monkeypatch.setattr(requests, "post", post)
    outcome = push.transport("device-token", "friend_request")
    assert (outcome.ok, outcome.dead) == (ok, dead)
    assert seen["url"] == "https://fcm.googleapis.com/v1/projects/demo-project/messages:send"
    assert seen["headers"] == {"Authorization": "Bearer access-token"}
    message = seen["json"]["message"]
    assert message["token"] == "device-token"
    assert message["data"] == {"type": "friend_request"}
    assert message["android"]["notification"]["channel_id"] == push.CHANNEL_ID
