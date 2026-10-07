# Changelog

What changed, newest first. One entry per working session or meaningful change. Add entries with `update-docs`; do not rewrite history.

## 2026-10-07: release v0.1.1

- Version `0.1.1`: the first release with Friends (the Settings screen shows the same version). Published by the tag workflow as a public GitHub Release because the repository is public (see `release.md`, D30).
- Policy placeholders in `privacy-policy.md` (host location, backup period, URL) and the Google Play web account-deletion page are **still open**; the release was published anyway at the owner's request.

## 2026-10-07: friends in the app

- **Friends (optional)** in Settings: sign in or create an account, publish a shelf for friends (with a confirmation of exactly what is sent), friend requests, find by exact username or from contacts, be found by phone (opt-in), block, sign out, delete the account (D36). A friend's shelf is read-only and separate from the reader's own library.
- New: `lib/features/friends/`, `lib/core/storage/session_store.dart`, four providers, routes `/friends` and `/friends/:id`. New plugins `flutter_secure_storage` and `flutter_contacts`; Android `READ_CONTACTS` and iOS `NSContactsUsageDescription`.
- **Privacy change:** `privacy-policy.md` and `store-privacy.md` now describe accounts, shared data, contacts, and deletion. Still to do before a store release: fill the policy's bracketed items and add the web account-deletion page Google Play requires.
- The nginx route for `https://ai.duk-tech.com/books-api/` was installed (`backend.md`).
- Fixed in the new code: the delete-account dialog disposed its controller too early.
- Tests: 135 unit and widget tests (was 85). Verified on the emulator against the live server (see `testing.md`).

## 2026-10-07: backend for friends (server only)

- **New `server/`:** Python (FastAPI) and PostgreSQL service with email and password accounts, friend requests and blocks, username lookup, phone-number contact matching (opt-in, hashed with a pepper), and a published shelf that friends can read (D35, `backend.md`). Runs with Docker Compose on `127.0.0.1:8300`; public path `https://ai.duk-tech.com/books-api/` via an nginx include (`server/deploy/`), which needs a one-time `sudo` step.
- 46 server tests against a real Postgres, run by a new `server-tests` CI job.
- At the time of this entry the app did not use it yet; the client followed the same day (entry above).

## 2026-10-07: series, sorting, one Finished choice

- **One "Finished" choice** when adding a book; "Read in the past" removed (D31).
- **Series** (name and number) on books, with quick picks and an "Add another" that moves the number on; shown in the selection panel and on the details page; matched by search (D32). First real migration: schema version 2, `from1To2`; verified on an emulator database that was still version 1.
- **Sorting:** Title (default), Author, or Recently added, remembered between launches; series stay together in order; articles and diacritics ignored (D33). A small preferences store was added.
- `lib/dev_seed.dart` now creates sample series (Dune, Harry Potter, Middle-earth).
- **"Want to read" renamed to "Wishlist"** (label only; D34).
- Tests: 85 unit and widget tests (was 57).

## 2026-10-06 (late night): first release

- Created the Android upload key (kept in `~/.config/reading-library-signing/`, mirrored into repository secrets), ran the release workflow by hand, then tagged `v0.1.0`: CI built, signed, and published the first GitHub Release (APK plus SHA-256). Verified the published APK's checksum, signer, and version.
- The repository is private, so testers need collaborator access or a direct file.

## 2026-10-06 (late night): first CI run

- Both jobs of `checks.yml` passed on GitHub for commit `2f53858`: the Linux checks and the macOS iOS simulator build. First evidence that the iOS build compiles and that the docs check works on a clean checkout. Release workflow not yet run.

## 2026-10-06 (late night): release automation

- `.github/workflows/release.yml`: a `v*` tag runs format, analyze, tests, and the docs check, builds an APK, and publishes a GitHub Release with a checksum; it can also be run by hand to produce an artifact (D30). Helpers `tool/release_version.sh` and `tool/ci_prepare_signing.sh`, both tested locally. Not yet run on GitHub.

## 2026-10-06 (late night): repository hygiene

- Built APKs are no longer tracked: `dist/`, `*.apk`, and `*.aab` are git-ignored, after a first push carried a 60 MB APK (GitHub warns above 50 MB). See `release.md` for sharing builds as release assets.

## 2026-10-06 (night): Journal months

- **Journal reworked (D29):** a **Months** view is now the default: one row per year with covers for All time, twelve month tiles for a year, a separate "Sometime in <year>" tile for year-only finishes, and a **Date unknown** row. The session calendar became **Days** with an explanation, an empty-state message, and a dot for finishes instead of a ring. **History** unchanged.
- New `JournalBuckets` domain logic; Journal widget tests; a flaky shelf test fixed (an ambiguous tap on "Want to read").
- Tests: 57 unit and widget tests (was 49). Screenshots of the Journal refreshed.

## 2026-10-06 (evening): docs, bookcase shelf, search, keepsakes

- Documentation set added: `README.md` (index), `features.md`, `architecture.md`, `design-system.md`, `decisions.md`, `testing.md`, `rebuild-guide.md`, this changelog. Screenshots refreshed from a seeded library.
- Docs are kept current by the `update-docs` skill, a `CLAUDE.md` rule, `tool/check_docs.sh` (also run in CI), and a stop hook.
- **Shelf redesigned as a bookcase:** packed rows of spines on wooden planks with a back panel and frame, face-out covers for books being read, gilt-banded spines, 14 colours with an FNV-1a hash (D22).
- **Keepsakes:** seven painted objects earned by finished-book count only, spread evenly through the shelf, with a note under the shelf (D23).
- **Library search rewritten:** diacritic-insensitive, order-free, ranked; a filter that hides matches is explained and can be cleared; a search miss no longer says "Add your first book"; clear button (D20).
- **Layout fixes found at 360 px:** status filters now wrap (D21); the selection panel grows with its content; empty-state buttons clear the floating button.
- `lib/dev_seed.dart` added to fill a development device with ~45 sample books and real covers.
- Tests: 49 unit and widget tests plus the emulator integration test (was 12).

## 2026-10-06 (afternoon): online search, drafts, migrations, release prep

- **Optional Open Library search** with local cover download, "no cover" and failure messaging, a cover preview in the form, and a labelled any-word fallback for misspellings (D14 to D18).
- **Draft recovery** for the add form and the page, session, and pin sheets (D11).
- **Cover cleanup** at startup (D12).
- **Migration framework:** frozen v1 schema, `stepByStep()`, upgrade tests (D10).
- **Release prep:** signing config that fails without a key, `INTERNET` permission, `tool/set_bundle_id.sh`, `release.md`, `privacy-policy.md`, `store-privacy.md` (D24, D25).
- Android SDK components updated (emulator 37.2.12, platform-tools 37.0.1, Android 36 system images revision 7); `cmdline-tools` installed.
- Release APK built (debug-signed) and given to a tester.

## 2026-10-06 (morning): first working POC

Milestones 0 to 4 of `product-plan.md`: foundation and visual prototype, local catalogue and library, reading and history with partial dates, statistics and calendar from sessions, pins, JSON backup and restore, on-device share images. Android debug APK, 12 tests, emulator integration test, analyzer clean. Details of that pass are in `implementation-status.md`.
