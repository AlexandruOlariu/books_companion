"""Push notifications through Firebase Cloud Messaging (HTTP v1).

Off unless `FCM_CREDENTIALS_FILE` names a Firebase service-account key; then
every call here is a no-op, so the server runs (and the tests pass) without
Google. A notification never carries a name, a username or a book: only that
something happened, because the text passes through Google and shows on a
locked screen. The app looks up the details itself once it is opened.

Sending never raises into the request that caused it: a friend request must
succeed even when Google cannot be reached.
"""

import logging
import uuid
from dataclasses import dataclass

from sqlalchemy import delete, select

from app.config import get_settings
from app.db import new_session
from app.models import DeviceToken

log = logging.getLogger("push")

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
# The id of the Android notification channel the app creates (MainActivity).
CHANNEL_ID = "friends"

MESSAGES = {
    "friend_request": (
        "New friend request",
        "Someone wants to be friends. Open Reading Library to answer.",
    ),
    "friend_accepted": (
        "Friend request accepted",
        "A friend request you sent was accepted.",
    ),
}


@dataclass
class Outcome:
    ok: bool
    # Firebase says this token will never work again: forget it.
    dead: bool = False


_credentials = None


def _load_credentials():
    global _credentials
    if _credentials is None:
        from google.oauth2 import service_account

        _credentials = service_account.Credentials.from_service_account_file(
            get_settings().fcm_credentials_file, scopes=[SCOPE]
        )
    return _credentials


def enabled() -> bool:
    return bool(get_settings().fcm_credentials_file)


def transport(token: str, kind: str) -> Outcome:
    """Send one message. Replaced in tests; the only code that talks to Google."""
    import requests
    from google.auth.transport.requests import Request

    credentials = _load_credentials()
    if not credentials.valid:
        credentials.refresh(Request())
    title, body = MESSAGES[kind]
    response = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{credentials.project_id}/messages:send",
        headers={"Authorization": f"Bearer {credentials.token}"},
        json={
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {"type": kind},
                "android": {
                    "priority": "high",
                    "notification": {"channel_id": CHANNEL_ID},
                },
            }
        },
        timeout=10,
    )
    if response.ok:
        return Outcome(ok=True)
    # UNREGISTERED (HTTP 404): the app was uninstalled or its token replaced.
    dead = response.status_code == 404
    if not dead:
        log.warning("FCM answered %s", response.status_code)
    return Outcome(ok=False, dead=dead)


def notify(user_id: uuid.UUID, kind: str) -> None:
    """Tell every phone of `user_id` that `kind` happened. Never raises."""
    if not enabled():
        return
    try:
        with new_session() as session:
            tokens = list(
                session.scalars(select(DeviceToken.token).where(DeviceToken.user_id == user_id))
            )
        dead = []
        for token in tokens:
            try:
                if transport(token, kind).dead:
                    dead.append(token)
            except Exception:  # one unreachable phone must not stop the others
                log.exception("push to one device failed")
        if dead:
            with new_session() as session:
                session.execute(delete(DeviceToken).where(DeviceToken.token.in_(dead)))
                session.commit()
    except Exception:
        log.exception("push failed")
