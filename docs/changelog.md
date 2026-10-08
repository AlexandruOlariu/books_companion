# Changelog

What changed, newest first. One entry per working session or meaningful change. Add entries with `update-docs`; do not rewrite history.

## 2026-10-08: account page, finished books lose their seal, suggestions that refresh

- **Your account** (`/account`, Settings > **Edit my account**): the reader can change first name, last name and username, and the password. New `lib/features/friends/presentation/account_screen.dart` and `domain/account_rules.dart`; `FriendsApi` gained `updateProfile` (`PATCH /me`, only changed fields) and `changePassword` (`POST /me/password`, stores the fresh tokens). The server already supported both; only the client was missing (backend.md updated). Decision D43. Sign out and delete stay on the Friends page; the email cannot be changed yet.
- **Privacy:** two new client calls to the same server, carrying the same kinds of data the account already holds (name, username, password for the check). `docs/privacy-policy.md` now says the account page can change them; `store-privacy.md` needs no change (same data types, nothing new collected).
- **Finished books no longer carry a seal** on the shelf (the owner asked); the Finished and All chips lose theirs too. Reading and Wishlist keep theirs. Amends D42.
- **"What to read next" did nothing for a reader whose friends were added later** (a friend's real report). Cause: friends' shelves were read through session-long cached providers, so a first look with no friend, or before the friend had published, stayed empty until the app restarted. Now each visit asks again (remembered for a minute; an empty or failed answer is not remembered). Second cause, by design: a reader with books but no series, Wishlist by a known author or friends got no section at all, which looked broken; it now says what makes an idea appear. Decision D44. What Bianca's phone really showed was not inspected (her library is private).
- Tests: 246 (was 233): `account_rules_test.dart` (4), `account_screen_test.dart` (7), two in `recommendations_widget_test.dart`. Checked on the emulator: no seal on finished books, the account page, and a real name change saved to the throwaway account on the live server and reverted. Not checked: a username change, a password change and the suggestions fix on a real phone. A 9 px overflow in the demo build's app-bar title at 360 px (`READING ROOM · DEMO`) was seen in a test and is not fixed.

## 2026-10-08: tapping a shelf book opens it like a real book

- Amends D42. The Hero cover flight is replaced by `bookOpeningTransition` (new `lib/core/widgets/book_opening.dart`): the tapped book's bounds travel to `/book/:id` as a `BookOpening` (`extra`), the cover grows to full screen, swings open on its left edge and the details page appears (800 ms, 520 ms back). Other ways into a book keep the soft rise. The details page no longer wraps its cover in a Hero; `bookFlight` is removed from `book_cover.dart`. Reduced motion: no transition.
- `test/shelf_test.dart` covers the pull-out and the page opening. Checked on the emulator (Pixel_9_Pro, API 36) frame by frame, with animations slowed 8 times in a throwaway build (not committed): spine grows into the cover, fills the screen, swings open and shows the page. That run found two faults, both fixed: the title on the big cover had the yellow double underline of unstyled text (the cover is drawn above the page, outside any `Scaffold`, so it now sits in a transparent `Material`), and a spine fading into a cover left a ghostly half-transparent book (the cover now stays solid and the spine fades off it). The way back (closing) and reduced motion were not checked on the emulator.

## 2026-10-08: the Library heading carries the reader's first name

- The Library tab's title reads "Alex’s Library" (the signed-in account's first name) instead of "My library"; with no account or no first name it reads "My Library". New `lib/features/library/domain/library_title.dart`; the screen watches `accountProvider`. No new network call: the account is already loaded for Friends.
- 2 new tests (233 total; `test/library_title_test.dart`, plus heading checks in `test/sync_widget_test.dart`). Not yet checked on the emulator.

## 2026-10-08: status seals on the shelf, and a tap opens the book

- Decision D42. Every book on the shelf has a small seal for its status (check, open book, heart), and the filter chips carry the same seals as a legend. Tapping a book now tilts it out of the shelf and opens its details page, with the cover flying across (Hero) and a soft page rise; the "selected-book panel" is removed. New `lib/core/widgets/status_badge.dart`; `BookCover` gained `showStatus` and `bookFlight`; `SliverShelf` takes `onOpen` instead of `selectedId`/`onSelect`; the `/book/:id` route has a custom transition.
- New test in `test/shelf_test.dart` (231 tests, was 230). Checked on the emulator (Pixel_9_Pro, API 36): seals on spines and chips, the pull-out visible mid-animation, then the details page. The flight back and reduced motion were not checked on the emulator.

## 2026-10-08: bottom of pushed screens clear of the system navigation bar

- Bug: on a phone whose Android draws the navigation bar over the app (edge-to-edge), the last item of a pushed screen was half hidden and could not be tapped (**Remove from library** on the book page). Pushed screens have no bottom bar, and a list with explicit padding gets no system inset. New `screenPadding` (`lib/core/widgets/common.dart`) adds the inset to the bottom padding; used by the book page, Settings, Friends, a friend's shelf, the account panel and the add/edit book form. The tabs already sit above their own bar; book search already used `SafeArea`.
- New `test/system_inset_test.dart` (230 tests, was 229). On the emulator (Pixel_9_Pro, API 36, three-button navigation) the old code cut **Remove from library** off at the bottom, as on the reporter's phone, and the fix shows it fully above the bar. Not checked on the phone that showed the bug.

## 2026-10-08: ratings

- Decision D41 (amends D6). Finished books can be rated 1 to 5 stars on the book's page, and optionally when adding a book as Finished. Private, never inferred, never shared with friends, no keepsakes. Tap the chosen star again to clear.
- **Schema version 4:** `user_books.rating` (nullable), step `from3To4`, frozen dump `drift_schema_v4.json`, a migration test. `LibraryRepository.setRating`; backups and the account copy carry `rating` (envelope still version 1; old backups restore unrated; restore refuses a bad rating). The server is unchanged.
- Suggestions use it: 1 or 2 stars do not count towards an author and stop the next volume of that series; 4 or 5 stars count as loved and are quoted in the reason.
- **Privacy:** ratings are saved to the account with the rest of the library (they were not stored before). Sign-in panel text, the share-shelf dialog ("Your ratings, notes, pins... are never shared"), `privacy-policy.md` and `store-privacy.md` now name ratings.
- New `lib/core/widgets/rating_stars.dart`; a test found that a labelled star had no tap action for screen readers and it was fixed. 229 tests (was 208). On the emulator the v3 to v4 upgrade kept the 52-book library and the signed-in account, and tapping five stars showed "Your rating: 5 of 5."; not checked on a device: that the rating survives an app restart and reaches the server copy.

## 2026-10-08: "What to read next" suggestions

- Decision D40. The Reading tab ends with a **What to read next** section: the next book of a series being finished (offered from the Wishlist or as "Series, book N" to add), Wishlist books by authors already finished, and books friends finished that the reader lacks. Each says why; **Not interested** hides it on this phone (with Undo); nothing is added unless the reader saves the add form, which `/add` can now open prefilled (`title`, `author`, `series`, `number`; `BookPrefill`). No ratings, no catalogue, no AI.
- New `lib/features/recommendations/` (rules in plain Dart, providers, section). No schema change, no new endpoint, field, or permission, so the privacy policy and store declarations are unchanged (friends' shelves are read through the existing calls).
- 21 new tests (`recommendations_test.dart`, `recommendations_widget_test.dart`); 208 in all. Checked on the emulator in the demo build with a seeded series library: the cards render and **Add to Wishlist** opens the form prefilled. Not checked on a device: the friends group (needs a second account with a published shelf).

## 2026-10-07: every push to main publishes a release

- Decision D39. `.github/workflows/release.yml` now also runs on pushes to `main`: after the usual checks it builds the APK and creates the next release (`tool/next_release_version.sh`: newest `vX.Y.Z` tag with the patch raised, or the `pubspec.yaml` version when newer; the first will be `v0.1.2`) on the tested commit. `[skip release]` in the head commit message skips it; a hand-pushed `v*` tag still releases under its own name. New `tool/test_release_scripts.sh` (7 checks, also run in `checks.yml`). Not run on GitHub yet: the workflow was validated as YAML and the version script by its tests, but only the first push to `main` will exercise it.

## 2026-10-07: the library is saved to a required account

- **Decision D38, a privacy change.** The owner asked for everything to be saved in the backend. The app now opens on an account page until someone is signed in, and the whole library (books, dates, sessions, private notes and pins) is saved to the account on the developer's server in the background. The phone is still written first and works offline; changes are saved about 3 s after the last one, on return to the app, and after signing in, and retried every minute while offline. `privacy-policy.md` and `store-privacy.md` were rewritten (the library, notes included, is on the server, readable by the developer, not end-to-end encrypted; an account is required). The demo build needs no account.
- **Never merged:** a phone and an account that both hold a library show "Which library do you want to keep?" with both book counts; the other is replaced. A newer account copy is downloaded when the phone has no unsaved change. The server refuses a save based on an old revision (409).
- **Schema version 3:** `editions.cover_source` (Open Library cover address only; checked on save and restore). Online covers are fetched again on a phone that lacks the file; gallery covers and older covers are not recoverable elsewhere. Frozen dump `drift_schema_v3.json`, step `from2To3`, 2 migration tests; the real upgrade kept all 51 books of a seeded emulator library.
- **Server:** table `libraries`, migration `0002`, `GET /me/library/meta`, `GET` and `PUT /me/library`, 16 tests (72 in all); deployed on this machine. The nginx body limit is raised to 22 MB in `server/deploy/nginx-books-api.conf` and nginx was reloaded by the owner (a 6 MB body then reached the API and got 401, where the old 5 MB limit gave 413).
- **App:** new `lib/features/sync/` (`SyncEngine`, `SyncingRepository`, `SyncController`, `conflict_dialog.dart`, `welcome_screen.dart`), `LibrarySyncApi` on `HttpFriendsApi`, `FriendsApi.signedIn()`, router gate, Settings saving status with **Save now**, `BookLookup.fetchCoverFromUrl`. 186 Flutter tests (was 138).
- Account deletion now also erases the saved library; the phone's library stays and is saved again if a new account is made. Copy changed in the add form, Settings, the sign-in panel, and the delete dialog.
- Verified on the emulator against the real server (see `testing.md`). Not verified: a second real phone, nginx's new limit, iOS.

## 2026-10-07: Share shelf shows every book, in the Library's order

- Found by the owner testing a real 29-book shelf: **Share shelf** cut the image to 24 covers ("a selection of 24") and ignored the chosen sort. It now includes every finished book and follows the saved Library sort (`librarySortPreference`). The Journal screen became a `ConsumerStatefulWidget` to read it. An image taller than 8000 px is scaled down instead of truncated (not exercised on a device; a 29-book shelf is about 2000 px tall).
- No decision reversed. Keepsakes still hide while a status/year filter or search is active (D23); a cover that is a photo of a book's back is the stored cover image, not a rendering fault.

## 2026-10-07: online search through the server

- Online search now goes through the Reading Library server (`POST /books/search`, no account needed), so search fixes no longer need an app release. If the server cannot be reached, the app asks Open Library directly, as before. Covers still come straight from Open Library (D37).
- New: `server/app/booksearch.py`, `server/app/routers/books.py` (10 server tests), `lib/features/book_search/data/server_book_lookup.dart` (3 Flutter tests). The search screen note now reads "Searches Open Library through the Reading Library server...".
- **Privacy change:** the search text now reaches the developer's server even without an account. It is sent in the request body (not logged), never stored, cached in memory for up to 6 hours. `privacy-policy.md` and `store-privacy.md` updated. Deployed to `https://ai.duk-tech.com/books-api/` and checked there.

## 2026-10-07: online search fix for titles with "the"

- The misspelling retry in online search now leaves out common words ("the", "and", "din", ...). A typo in a title containing "The" (for example "Frieda The Coworker") used to send `... OR The OR ...`, which Open Library failed to answer, so nothing was shown. Now it finds *The Coworker* by Freida McFadden (D18). Not yet checked on the emulator.

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
