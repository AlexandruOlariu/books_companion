# Backend (`server/`)

A small Python service that gives readers accounts, a saved copy of their whole library, friends, and a published shelf their friends can see. It replaces the "share by NFC or share sheet" idea (see D35 in `decisions.md`). The Flutter app requires an account and saves the library to it (D38; see `features.md`, "Account and saving", and `architecture.md`, "Account sync"); friends are optional (Settings > Friends and sharing).

Public address: `https://ai.duk-tech.com/books-api/` (nginx strips the prefix; the service itself serves from `/`).

## Stack

| Piece | Choice |
| --- | --- |
| Language, framework | Python 3.12, FastAPI 0.142 (synchronous endpoints), uvicorn |
| Database | PostgreSQL 17, SQLAlchemy 2 (psycopg 3), Alembic migrations |
| Passwords, tokens | argon2id (`argon2-cffi`); short-lived JWT access tokens (`PyJWT`, HS256); rotating opaque refresh tokens |
| Phone numbers | `phonenumbers` to normalise, HMAC-SHA256 with a server-side pepper |
| Runtime | Docker Compose (`server/docker-compose.yml`): `db` (no published port) and `api` (bound to `127.0.0.1:8300`) |
| Tests | pytest against a real Postgres (72 tests) |

Pinned versions are in `server/requirements.txt` and `server/requirements-dev.txt`.

## File map

| Path | Role |
| --- | --- |
| `server/app/main.py` | the FastAPI app, router wiring, `/healthz`; interactive docs are disabled |
| `server/app/config.py` | settings from the environment; refuses to start without the two secrets |
| `server/app/db.py` | engine and session |
| `server/app/models.py` | tables (below) |
| `server/app/schemas.py` | request and response shapes, including the shelf and its date rules |
| `server/app/security.py` | password hashing, JWTs, refresh-token hashing, phone hashing |
| `server/app/phone.py` | phone number to E.164 |
| `server/app/ratelimit.py` | Postgres-backed rate limits |
| `server/app/deps.py` | current user, friendship and block helpers |
| `server/app/routers/auth.py` | register, login, refresh, logout |
| `server/app/routers/me.py` | profile, phone, password, account deletion |
| `server/app/routers/people.py` | username lookup, contact matching |
| `server/app/routers/friends.py` | friend requests, friends, blocks |
| `server/app/routers/shelf.py` | publish and read shelves |
| `server/app/routers/library.py` | save and read the account's whole library |
| `server/app/routers/books.py` | book search for the app (no sign-in) |
| `server/app/booksearch.py` | Open Library search rules, stop words, in-memory cache |
| `server/migrations/` | Alembic (`0001_initial_schema.py`, `0002_libraries.py`) |
| `server/tests/` | pytest suite |
| `server/Dockerfile`, `server/docker-compose.yml`, `server/.env.example` | packaging and secrets template |
| `server/deploy/nginx-books-api.conf`, `server/deploy/install-nginx.sh` | the nginx location and a one-time installer |

## Data model

All ids are UUIDs. Foreign keys cascade on delete, so deleting a user removes everything tied to them.

- `users`: email (lower case, unique), argon2 `password_hash`, `username` (3 to 30 of `a-z 0-9 _ .`, unique), first and last name, `phone_hash` (nullable), `discoverable_by_phone` (default false).
- `refresh_tokens`: SHA-256 of the token, expiry (60 days), `revoked_at`.
- `friendships`: one row per pair with `user_a < user_b` enforced by a check constraint, `requested_by`, `status` (`pending` or `accepted`).
- `blocks`: `(blocker_id, blocked_id)`.
- `shelves`: one JSONB snapshot per user, replaced whole.
- `libraries`: one row per user: `revision` (starts at 1, +1 per save), the whole library as JSONB `payload`, `updated_at`.
- `rate_events`: `(key, cost, created_at)` for rate limiting.

## API

Bearer access token on everything except `/auth/*`, `/books/search` and `/healthz`. Errors are `{"detail": ...}`.

| Method and path | Purpose |
| --- | --- |
| `POST /auth/register` | email, password (10 to 128 chars), username, first and last name; returns tokens. 409 if email or username is taken |
| `POST /auth/login` | returns tokens; the same 401 for a wrong password and an unknown email |
| `POST /auth/refresh` | exchanges a refresh token for a new pair; the old one is revoked. Replaying a revoked token revokes every session of that account |
| `POST /auth/logout` | revokes a refresh token |
| `GET /me`, `PATCH /me` | profile (names, username, `discoverable_by_phone`); `has_phone` instead of the number |
| `PUT /me/phone`, `DELETE /me/phone` | set (with optional `region`) or remove the phone number; removing also turns discoverability off |
| `POST /me/password` | change password; signs out every other device and returns new tokens |
| `DELETE /me` | erase the account (needs the password) |
| `GET /users/lookup?username=` | find one person by exact username |
| `POST /contacts/match` | `{region, numbers[]}` (at most 1000): which numbers belong to people who opted in |
| `GET /friends`, `DELETE /friends/{id}` | list, remove |
| `GET /friends/requests`, `POST /friends/requests` | incoming and outgoing; send `{user_id}` (asking someone who already asked you accepts) |
| `POST /friends/requests/{id}/accept`, `DELETE /friends/requests/{id}` | accept; decline or cancel |
| `GET /blocks`, `PUT /blocks/{id}`, `DELETE /blocks/{id}` | block (also removes any friendship), unblock |
| `PUT /me/shelf`, `GET /me/shelf`, `DELETE /me/shelf` | publish, read, unpublish your snapshot |
| `GET /me/library/meta`, `GET /me/library`, `PUT /me/library` | the saved library. `meta` is `{revision, updated_at}`; `GET` adds `data`; both 404 when nothing is saved. `PUT {base_revision, data}` saves when `base_revision` equals the stored revision (0 when none) and returns the new `{revision, updated_at}`; otherwise 409 (header `X-Library-Revision`) and nothing is written. See "Saved libraries" |
| `POST /books/search` | `{q}` (1 to 200 chars); `{approximate, books: [{title, author, page_count, first_publish_year, language, cover_id}]}`. No sign-in. 502 when Open Library cannot be reached. See "Book search" |
| `GET /friends/{id}/shelf` | a friend's snapshot; 404 for anyone who is not an accepted friend, and for friends who have not published |

Another person is only ever shown as `{id, username, display_name}`. Email and phone are never returned to anyone but their owner, and the phone is never returned at all.

## What a published shelf contains

A list of books, each with `id`, `title`, `author`, `status` (`reading`, `want_to_read`, `finished`) and `finishes`: one date per completion with the same precision rule as the app (`day`, `month`, `year`, `unknown`). Fields beyond the precision must be absent, so a remembered year cannot carry an invented month or day; a finish cannot be in the future; a finished book needs at least one finish and a wishlist book has none. Limits: 5000 books, 300 characters for titles and authors, 50 finishes per book.

Unknown fields are rejected with 422 rather than ignored. Notes, pins, sessions and covers have no field, so a client bug cannot upload a private note. A friend's shelf is shown to the reader as that friend's data; it never enters the reader's own statistics, journal or keepsakes (the rules in `features.md` about invented activity apply).

## Saved libraries

`data` is the app's backup data (`LibraryRepository.exportData`) without cover images: `version: 1` and the lists `books`, `authors`, `bookAuthors`, `editions`, `userBooks`, `records`, `sessions`, `pins`, each a list of objects. The server checks only the shape: the version, that no other table is present and each of those is a list of at most 100000 objects, and the size (20 MB, 413 beyond; nginx allows 22 MB). It does not look inside the rows; the app validates everything again when it restores them. A 422 never echoes the library back. 600 saves per account per hour. The row is replaced whole and the 409 rule stops one phone from overwriting another's newer save, so the server never merges. Unlike a published shelf, a saved library **does** contain private notes, pins and sessions: it is the account's own copy, readable only by that account (no friend endpoint reads it) but readable by whoever runs the server, because it is not encrypted at rest or end to end (D38). Deleting the account cascades to it. Request bodies are not logged.

## Book search

The app's online search goes through `POST /books/search` so the search rules can be fixed on the server without an app release (D37). The server queries `openlibrary.org/search.json` with its own user agent: the exact text first (or `isbn:` for an ISBN), then, if a query of two or more real words matches nothing, an any-word retry (`a OR b`) labelled `approximate`. Words under 3 letters and common words (`STOP_WORDS`: English, Romanian, a few French, German, Spanish) are left out of the retry, because an any-word query with "the" makes Open Library answer 500 after about 10 s. A failed retry returns the empty exact result; a failed exact search is 502, and the app then asks Open Library itself.

- **No sign-in**, because an account would tie searches to a person. Rate limit 120 per address per hour.
- **The text is in the body, not the URL**, so nginx and uvicorn request logs show only `POST /books/search`. It is never written to the database (tested); answers are cached in memory for 6 hours (500 entries, per worker, lost on restart). Failures are not cached.
- Only a cover id is returned; the app builds the cover address itself and downloads covers from Open Library directly.

## Security and privacy design

- **Rate limits** (stored in Postgres, shared by every worker, counted even when the request fails): login 10 per email and 60 per address per 15 minutes; register 20 per address per hour; refresh 120 per address per 15 minutes; username lookup 60 per hour; contact matching 20 calls per hour and 3000 numbers per day; friend requests 50 per day; phone changes 10 per day; book search 120 per address per hour.
- **Discovery is exact-match only.** There is no name, prefix or substring search, so the user base cannot be listed. Phone discovery is opt-in and off by default.
- **Phone numbers** are normalised to E.164 and stored only as an HMAC with `PHONE_PEPPER`. Contact sync sends raw numbers over HTTPS (a hash made on the phone would be trivially reversible, because phone numbers are guessable); the server hashes them, compares, answers, and keeps nothing: the numbers are not written to any table (tested against the database), and the service does not log request bodies (uvicorn logs the request line only). A match only ever produces a name that can be asked to be friends; nothing is shared until the other person accepts.
- **Blocks** hide both people from each other in lookup and contact matching, and a request to or from a blocked person answers 404, the same as an unknown id.
- **Tokens:** access tokens last 15 minutes; refresh tokens are random, stored only as a hash, and rotate on every use.
- **Transport:** TLS ends at nginx. The API port is bound to `127.0.0.1` only. The client address for rate limits comes from `X-Forwarded-For`, which nginx overwrites with the real address.

## Known gaps

- **Phone numbers are not verified.** There is no SMS check, so someone can claim a number that is not theirs. The damage is bounded (they appear under their own chosen name to people who have that number, and a request must still be accepted), but it is real. Verification needs an SMS provider, which is a cost and a new data processor.
- **No email verification and no password reset.** Both need a mailer. A forgotten password currently means a lost account. Registration reports "email already taken", which reveals that an address has an account (rate limited).
- **No push notifications**, so a friend request is only seen when the app asks.
- **No change of password or profile in the app yet.** The server supports them (`POST /me/password`, `PATCH /me`); the client does not call them.
- **Logs contain searched usernames:** `GET /users/lookup?username=` puts the username in nginx's and uvicorn's request line. Request bodies are not logged.
- **Access tokens cannot be revoked before they expire** (15 minutes); deleting an account or changing a password takes effect on the next refresh, although the deleted user's token stops working immediately because the user row is gone.
- A single host, a single Postgres container, no replication. Back up the `books-db` volume and `server/.env` (the pepper especially: without it every stored phone hash is useless).

## Run it

```sh
cd server
cp .env.example .env            # then fill the three secrets (see the file)
docker compose up -d --build    # api on 127.0.0.1:8300; migrations run on start
curl http://127.0.0.1:8300/healthz
./deploy/install-nginx.sh       # once, needs sudo; adds one include line to the ai.duk-tech.com site
curl https://ai.duk-tech.com/books-api/healthz
```

Update after a change: `docker compose up -d --build`. After editing `deploy/nginx-books-api.conf` run `sudo nginx -t && sudo nginx -s reload` (the include points into the repository, so only the reload is needed). Logs: `docker compose logs -f api`. Backup: `docker compose exec db pg_dump -U books books > books.sql`.

Tests need a Postgres whose database name ends in `_test` (the suite drops the schema and refuses anything else):

```sh
docker run -d --name books-test-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=books_test -p 127.0.0.1:55432:5432 postgres:17-alpine
cd server && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
python -m pytest -q             # TEST_DATABASE_URL overrides the default 127.0.0.1:55432
```

A model change needs a migration: `alembic revision --autogenerate -m "..."` with `DATABASE_URL` pointing at a scratch database, then review it. `test_models_match_the_migrations` fails when they drift. CI runs the suite in the `server-tests` job.

## Client checklist (the app side)

The client is built. What the privacy rules required, and where it stands:

1. `privacy-policy.md` and `store-privacy.md` describe accounts, the data sent, contacts, and deletion. Done in the draft; the bracketed items (host location, backup period, URL) are still for the owner to fill in.
2. ~~The app stays fully usable without an account.~~ Reversed by D38: an account is required and the library is saved to it; Friends stays opt-in under Settings. The privacy documents say so.
3. The reader sees what is published before it is sent (confirmation dialog) and can unpublish (**Stop sharing**). Done.
4. Contacts are requested only after the reader taps **Find friends from contacts** and confirms a dialog explaining that only phone numbers are sent and not kept. Done; the Android and iOS permission texts say the same.
5. Account deletion exists in the app (Google Play and the App Store require it). Done. **Google Play also requires a web page for deletion requests; it does not exist yet.**
6. Release checklist: the server address is `HttpFriendsApi.defaultOrigin` (`release.md` lists the remaining steps). Not done: a decision on how long a signed-in reader is kept signed in when the server is unreachable (today they stay signed in; only a refusal by the server ends a session).
