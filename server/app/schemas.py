import re
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

USERNAME_RE = re.compile(r"^[a-z0-9_.]{3,30}$")


class Strict(BaseModel):
    """Unknown fields are an error, not ignored: a client bug must not be able
    to slip extra data (such as a private note) onto the server."""

    model_config = ConfigDict(extra="forbid")


# --- accounts ---------------------------------------------------------------


def _clean_name(value: str) -> str:
    value = " ".join(value.split())
    if not value:
        raise ValueError("must not be empty")
    return value


class RegisterIn(Strict):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)
    username: str
    first_name: str = Field(max_length=60)
    last_name: str = Field(max_length=60)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        return v.lower()

    @field_validator("username")
    @classmethod
    def _username(cls, v: str) -> str:
        v = v.strip().lower()
        if not USERNAME_RE.match(v):
            raise ValueError("3 to 30 characters: letters, digits, '_' or '.'")
        return v

    _names = field_validator("first_name", "last_name")(_clean_name)


class LoginIn(Strict):
    email: EmailStr
    password: str = Field(max_length=128)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        return v.lower()


class RefreshIn(Strict):
    refresh_token: str = Field(max_length=200)


class TokensOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"


class MeOut(BaseModel):
    id: uuid.UUID
    email: str
    username: str
    first_name: str
    last_name: str
    has_phone: bool
    discoverable_by_phone: bool


class MeUpdate(Strict):
    first_name: str | None = Field(default=None, max_length=60)
    last_name: str | None = Field(default=None, max_length=60)
    username: str | None = None
    discoverable_by_phone: bool | None = None

    @field_validator("username")
    @classmethod
    def _username(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip().lower()
        if not USERNAME_RE.match(v):
            raise ValueError("3 to 30 characters: letters, digits, '_' or '.'")
        return v

    @field_validator("first_name", "last_name")
    @classmethod
    def _names(cls, v: str | None) -> str | None:
        return None if v is None else _clean_name(v)


class PhoneIn(Strict):
    phone: str = Field(min_length=3, max_length=40)
    region: str | None = Field(default=None, min_length=2, max_length=2)


class PasswordChangeIn(Strict):
    current_password: str = Field(max_length=128)
    new_password: str = Field(min_length=10, max_length=128)


class DeleteAccountIn(Strict):
    password: str = Field(max_length=128)


# --- people -----------------------------------------------------------------


class PersonOut(BaseModel):
    """What another person may see about someone: never email or phone."""

    id: uuid.UUID
    username: str
    display_name: str


class ContactsMatchIn(Strict):
    region: str | None = Field(default=None, min_length=2, max_length=2)
    numbers: list[str] = Field(max_length=1000)

    @field_validator("numbers")
    @classmethod
    def _numbers(cls, v: list[str]) -> list[str]:
        if any(len(n) > 40 for n in v):
            raise ValueError("a phone number is at most 40 characters")
        return v


class FriendRequestIn(Strict):
    user_id: uuid.UUID


class FriendRequestsOut(BaseModel):
    incoming: list[PersonOut]
    outgoing: list[PersonOut]


# --- shelf ------------------------------------------------------------------


class FinishedOn(Strict):
    """A remembered finish date. Mirrors the app's PartialDate: the precision
    says how much of the date is known, and nothing beyond it may be set, so a
    remembered year can never turn into a January 1."""

    precision: Literal["day", "month", "year", "unknown"]
    year: int | None = None
    month: int | None = None
    day: int | None = None

    @model_validator(mode="after")
    def _consistent(self) -> "FinishedOn":
        want = {
            "unknown": (False, False, False),
            "year": (True, False, False),
            "month": (True, True, False),
            "day": (True, True, True),
        }[self.precision]
        have = (self.year is not None, self.month is not None, self.day is not None)
        if have != want:
            raise ValueError(f"fields do not match precision '{self.precision}'")
        if self.year is not None and not 1000 <= self.year <= 9999:
            raise ValueError("year out of range")
        try:
            first = date(self.year or 2000, self.month or 1, self.day or 1)
        except ValueError as exc:
            raise ValueError("not a real date") from exc
        # A finish cannot be in the future (a day of slack for time zones).
        limit = datetime.now(timezone.utc).date() + timedelta(days=1)
        if self.year is not None and first > limit:
            raise ValueError("a finish date cannot be in the future")
        return self


class ShelfBook(Strict):
    id: str = Field(min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=300)
    author: str = Field(default="", max_length=300)
    status: Literal["reading", "want_to_read", "finished"]
    # One entry per completion (a re-read adds another).
    finishes: list[FinishedOn] = Field(default_factory=list, max_length=50)

    @model_validator(mode="after")
    def _finishes_match_status(self) -> "ShelfBook":
        # A book being re-read keeps its earlier finishes; a wishlist book has none.
        if self.status == "want_to_read" and self.finishes:
            raise ValueError("a wishlist book has no finishes")
        if self.status == "finished" and not self.finishes:
            raise ValueError("a finished book needs at least one finish")
        return self


class ShelfIn(Strict):
    books: list[ShelfBook] = Field(max_length=5000)

    @model_validator(mode="after")
    def _unique_ids(self) -> "ShelfIn":
        ids = [b.id for b in self.books]
        if len(ids) != len(set(ids)):
            raise ValueError("book ids must be unique")
        return self


class ShelfOut(BaseModel):
    books: list[ShelfBook]
    updated_at: datetime


# --- book search ------------------------------------------------------------


class BookSearchIn(Strict):
    # Sent in the body, not the URL, so the text never reaches a request log.
    q: str = Field(min_length=1, max_length=200)


class BookOut(BaseModel):
    title: str
    author: str
    page_count: int | None
    first_publish_year: int | None
    language: str | None
    cover_id: int | None


class BookSearchOut(BaseModel):
    # True when nothing matched every word, so these are only close matches.
    approximate: bool
    books: list[BookOut]


# --- library sync -----------------------------------------------------------

# The tables of the app's backup data. Anything else is refused, so a client bug
# cannot park unrelated data here. The contents are validated by the app when
# it restores them; the server only keeps the shape and the size in check.
LIBRARY_TABLES = (
    "books",
    "authors",
    "bookAuthors",
    "editions",
    "userBooks",
    "records",
    "sessions",
    "pins",
)
MAX_LIBRARY_ROWS = 100_000


class LibraryIn(Strict):
    base_revision: int = Field(ge=0)
    data: dict

    @field_validator("data")
    @classmethod
    def _shape(cls, data: dict) -> dict:
        if data.get("version") != 1:
            raise ValueError("unsupported library version")
        extra = set(data) - set(LIBRARY_TABLES) - {"version"}
        if extra:
            raise ValueError(f"unknown tables: {', '.join(sorted(extra))}")
        for table in LIBRARY_TABLES:
            rows = data.get(table)
            if not isinstance(rows, list) or len(rows) > MAX_LIBRARY_ROWS:
                raise ValueError(f"{table} must be a list of at most {MAX_LIBRARY_ROWS} rows")
            if not all(isinstance(row, dict) for row in rows):
                raise ValueError(f"{table} must contain objects")
        return data


class LibraryMeta(BaseModel):
    revision: int
    updated_at: datetime


class LibraryOut(LibraryMeta):
    data: dict


# --- push notifications -----------------------------------------------------


class DeviceIn(Strict):
    token: str = Field(min_length=20, max_length=4096)
    platform: Literal["android", "ios"]


class DeviceRemoveIn(Strict):
    token: str = Field(min_length=1, max_length=4096)
