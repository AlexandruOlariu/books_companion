# Architecture

How the POC is built. Behaviour is in `features.md`; visuals are in `design-system.md`; rationale is in `decisions.md`.

## Stack

Flutter 3.47.6 / Dart 3.13.5. Direct dependencies are pinned in `pubspec.yaml`; transitive versions are locked in `pubspec.lock`.

| Package | Version | Used for |
| --- | --- | --- |
| flutter_riverpod | 3.4.3 | state and dependency injection |
| go_router | 18.0.2 | navigation |
| drift + sqlite3 | 2.35.1 / 3.7.0 | local SQLite, migrations |
| path_provider, path | 2.1.6 / 1.9.1 | app directories, paths |
| uuid | 4.6.0 | stable local ids |
| image_picker | 1.2.4 | choosing a cover |
| file_picker | 13.1.0 | saving and choosing backup files |
| share_plus (+ cross_file) | 13.3.1 / 0.3.5+5 | native share sheet |
| flutter_secure_storage | 11.2.0 | the optional friends sign-in tokens (Keychain on iOS, an encrypted store on Android) |
| flutter_contacts | 2.6.0 | read-only phone numbers for "Find friends from contacts"; asked for only when the reader taps it |
| intl | 0.20.3 | date formatting |
| dev: drift_dev, build_runner, flutter_lints | 2.35.1, 2.16.1, 6.0.0 | codegen, migration tooling, lints |

Fonts are bundled (DM Sans, Literata, both OFL) with their licences registered at startup. There is no Freezed, json_serializable, Dio, or cached_network_image despite the plan: domain models are small hand-written classes, and the optional online lookup and the friends client use `dart:io` directly.

Targets: Android 7.0+ (API 24; target 36), iOS 15.0+. The iOS simulator build compiles in CI on macOS (first green run 2026-10-06, commit `2f53858`, as shown in the GitHub UI). It has never been compiled on this Linux host, and no iOS simulator or device run has happened.

## Layers

```
presentation (widgets)  ->  LibraryRepository (interface)  ->  LocalLibraryRepository  ->  Drift / SQLite
                                  ^ domain rules live in plain Dart (models.dart, search.dart, sorting.dart)
```

- Screens call `LibraryRepository`, never Drift. A remote implementation could be added later behind the same interface; no sync code exists. The optional friends feature (accounts, friends, a published shelf) talks to a separate server (`server/`, see `backend.md`) through `FriendsApi`; it is independent of the library layer and never reads Drift. See "Friends client" below.
- Domain rules (date precision, validation, search ranking, shelf packing, keepsake thresholds) are plain Dart functions so tests can cover them without widgets.
- `LibraryRepository.load()` returns an immutable `LibrarySnapshot` (books, completions, sessions, pins) that the UI reads; writes invalidate `libraryProvider`.

## Startup (`lib/main.dart`)

1. Register font licences.
2. Open `reading-library.sqlite` in the documents directory with `NativeDatabase.createInBackground`, build `LocalLibraryRepository`, and call `load()` once to fail early.
3. Create `FileDraftStore` (`drafts.json` in the application-support directory) and flush it when the app goes inactive or paused.
4. Fire-and-forget cover cleanup (`CoverStore.collectGarbage`), whose errors are ignored.
5. `runApp` with provider overrides. If steps 2 to 4 throw, a plain "Your library could not be opened" screen with **Try again** is shown and nothing on disk is touched.

`lib/demo.dart` runs the same app on an in-memory sample library. `lib/dev_seed.dart` fills a development device's real library and then calls `main()`. Both are separate entry points and never part of a release.

## Providers (`lib/app/providers.dart`)

| Provider | Meaning |
| --- | --- |
| `repositoryProvider` | must be overridden (local repository, or the demo one) |
| `libraryProvider` | `FutureProvider<LibrarySnapshot>`; invalidate after writes |
| `demoProvider` | true in the demo build (labels the app bar) |
| `draftStoreProvider` | in-memory by default; file-backed in `main.dart` |
| `preferencesProvider` | in-memory by default; file-backed (`preferences.json` in the support directory) in `main.dart`; holds the shelf's sort choice |
| `bookLookupProvider` | `OpenLibraryLookup`; tests override with a fake |
| `sessionStoreProvider` | in-memory by default; `SecureSessionStore` (secure storage) in `main.dart`; holds the friends sign-in tokens |
| `friendsApiProvider` | `HttpFriendsApi` on the session store; tests override with a fake |
| `contactsSourceProvider` | `DeviceContactsSource` (permission and numbers); tests override with a fake |
| `regionProvider` | the device's country code (for reading phone numbers written without a country code); tests override |

The friends screens add their own data providers in `lib/features/friends/presentation/friends_providers.dart` (`accountProvider`, `friendsProvider`, `friendRequestsProvider`, `blockedProvider`, `mySharedShelfProvider`, `friendShelfProvider`), invalidated together by `resetFriendsData` on sign-in, sign-out, and account deletion, and an action wrapper `runFriends` that turns failures into messages and a lost session into the sign-in panel.

## Data model

Schema version **2**, defined in `lib/core/storage/database.dart` with Drift. Foreign keys are on. Ids are UUID strings. Writes that touch several tables run in a transaction.

| Table | Columns | Notes |
| --- | --- | --- |
| `books` | id, title, series_name?, series_number?, created_at, updated_at | catalogue entry; the series columns were added in version 2 (a number needs a name and is 1 or more) |
| `authors` | id, name | one author per saved book; orphans are pruned |
| `book_authors` | book_id (cascade), author_id, position | PK (book_id, author_id) |
| `editions` | id, book_id (cascade), page_count?, language?, cover_local_path?, metadata_source ('manual' or 'open_library') | the selected edition |
| `user_books` | id, book_id (cascade), edition_id, status, current_page (default 0), added_at, updated_at | the reader's copy; status is `reading`, `want_to_read` (shown as Wishlist), or `finished` |
| `reading_records` | id, user_book_id (cascade), finished_value?, finished_precision, source, created_at | completion claims; source is `tracked_in_app` or `entered_past` |
| `reading_sessions` | id, user_book_id (cascade), started_at, start_page?, end_page?, duration_seconds?, created_at | the only source of activity |
| `pins` | id, user_book_id (cascade), text_content, type, page?, progress_percent?, created_at, updated_at | private notes |

Series is a name and a number on the book, not a separate table, so renaming a series means editing each book. Deliberately absent from the plan's model: subtitle, description, ISBNs, publisher, publication year, cover source URL, ratings, start dates, custom shelves.

### Dates

`PartialDate(precision, value)` stores `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, or null for `unknown`. The constructor rejects a value that does not match its precision, an invalid calendar date, and a non-null value for `unknown`. `addedAt` is never used to infer a date. Rereading keeps earlier records.

### Rules enforced in the repository

- Title and author required; page count above zero; finishing a new book requires a confirmed finish.
- `updatePage` is bounded by the edition's page count. `logSession` validates pages and duration (`validateSession`), rejects future dates, advances progress only forward, and never rewinds it.
- Editing an edition is rejected if it would invalidate current page, existing sessions, or pins.
- `setStatus(finished)` requires a finish, refuses an already-finished book, and writes a record.
- `deleteBook` cascades and prunes orphan authors.
- Pins: non-empty text, a known type, page within the total, percent in 0..100.

## Backup and restore (`lib/core/storage/backup_service.dart`)

Envelope: `{ "format": "reading-library", "version": 1, "data": { "version": 1, books, authors, bookAuthors, editions, userBooks, records, sessions, pins }, "covers": { "<editionId>.cover": "<base64>" } }`.

- Export embeds cover bytes under portable keys instead of device paths, and fails clearly if a cover file is missing.
- Restore checks size (150 MB; covers 20 MB each) and format, rejects keys that are not `[a-zA-Z0-9-]+.cover`, stages cover files under fresh names, then validates every record (values, precisions, relations, pages, pins) and replaces all tables in one transaction. On any failure staged files are deleted and the existing library is untouched.
- Android automatic backup is disabled; the explicit file is the only copy and contains private notes.

## Migrations

`schemaVersion` is 2. `onUpgrade` uses Drift's `stepByStep()` from `lib/core/storage/migrations/schema_versions.dart`; the only step is `from1To2` (two nullable columns on `books`, so existing rows keep their data and simply have no series). An unknown upgrade throws instead of dropping data. Frozen schemas are `drift_schemas/drift_schema_v1.json` and `..._v2.json`, with generated test helpers in `test/generated_migrations/`. `test/migration_test.dart` upgrades the frozen v1 schema to the current one, checks the current schema equals the frozen v2 dump, and checks a v1 library survives with null series. The v1 to v2 upgrade also ran for real on an emulator whose database was still version 1. Procedure for the next version is in the root `README.md`.

**Backups across versions:** the backup envelope stays at version 1 because the series fields are additive and optional. A backup made before series existed restores (the keys are absent and read as null); an invalid series (number below 1, number without a name, blank name) is rejected and the existing library is left untouched.

## Online lookup (`lib/features/book_search`)

`BookLookup` (domain) has `search(query)` and `fetchCover(suggestion)`. `OpenLibraryLookup` (data) uses `dart:io` `HttpClient` with an 8 s connect timeout, 15 s response timeout, size caps (2 MB JSON, 5 MB image), a `ReadingLibrary/0.1` user agent, and no identifiers. Cover bytes are accepted only if they are JPEG or PNG by content. All failures become a friendly `LookupException`; the looser retry for misspellings never raises an error and leaves out a short stop-word list (English, Romanian, a few French, German and Spanish articles), because an any-word query containing "the" makes Open Library return HTTP 500 after about 10 s. Hosts are injectable for tests.

## Shelf rendering (`lib/features/library/presentation/shelf.dart`)

`packShelves(books, width, keepsakes)` returns rows of `BookSlot` and `KeepsakeSlot` no wider than the width, with keepsakes spaced evenly. `SliverShelf` builds rows lazily in a sliver list so a large library stays cheap. Slot sizes derive from `bookSeed(title)` (a stable FNV-1a hash) and page count. Details in `design-system.md`.

## Friends client (`lib/features/friends/`)

Optional and entirely separate from the library. Nothing here runs until the reader opens Friends and acts, and the app never reads or writes the library through it except to build what the reader chose to publish.

- `FriendsApi` is the interface; `HttpFriendsApi` implements it against `https://ai.duk-tech.com/books-api` (`HttpFriendsApi.defaultOrigin`; injectable for tests). 8 s connect and 20 s response timeouts, an 8 MB response cap, a `ReadingLibrary/0.1` user agent.
- **Sessions:** the access and refresh tokens live in `SessionStore` (secure storage in production), never in `preferences.json` and never in a backup. A 401 triggers one refresh (shared by concurrent calls, `_refreshing`) and a retry. Only a refusal by the server ends the session; a network failure, timeout, or server error never signs the reader out.
- **Errors:** every failure becomes a `FriendsException` with a message that is safe to show (the server's own `detail` text when it has one, a generic text for 429 or 5xx, the first validation error named by field for 422). `signedOut` marks a lost session.
- `sharedBooksFrom(LibrarySnapshot)` is the only code that decides what leaves the device: `id`, `title`, `author`, `status`, and one finish per completion with its precision. `SharedBook` has no field for notes, pins, sessions, progress, covers, or series, so leaving them out does not depend on remembering to. A finished book with no recorded finish is sent as `unknown`; a wishlist book carries none; titles and authors are clipped to 300 characters.
- **Publishing is explicit:** a button, a confirmation that states what is sent, and a replace of the previous snapshot. There is no background sync; friends see the shelf as of the last publish.
- **Contacts:** `DeviceContactsSource` requests the read permission only after the reader confirms a dialog, reads phone numbers only (no names, emails, or photos), sends at most 3000 numbers in batches of 1000 with the device region, and keeps nothing. People already friends or with a pending request are not offered again.
- A friend's shelf is shown from `friendShelfProvider` and is never merged into `LibrarySnapshot`, so it cannot affect statistics, the Journal, or keepsakes.
- The Settings entry is hidden in the demo build.

## Drafts (`lib/core/storage/draft_store.dart`)

`DraftStore` (`load`, `save`, `clear`) with `MemoryDraftStore` and `FileDraftStore` (debounced writes, atomic rename, 30-day expiry, damaged file ignored). `DraftBinding` ties one form to one key and clears the draft when all text is blank. Keys: `book:new` and `action:<userBookId>:<page|session|pin>`.

## Platform configuration

- **Android:** `applicationId` `app.readingroom.reading_library` (a placeholder; change with `tool/set_bundle_id.sh`), Kotlin namespace unchanged. `allowBackup=false`. The main manifest requests `INTERNET` (optional search, and the optional friends server) and `READ_CONTACTS` (only used by "Find friends from contacts"; read-only; checked in the built APK's merged manifest). Nothing else is requested. Release signing reads `android/key.properties`; without it a release build fails unless `READING_LIBRARY_DEBUG_SIGNING=1` is set for a local, non-uploadable build.
- **iOS:** bundle id `app.readingroom.readingLibrary` (placeholder), `NSPhotoLibraryUsageDescription` and `NSContactsUsageDescription` set, automatic signing with no team committed. No app-level privacy manifest yet.
- **CI** (`.github/workflows/checks.yml`): format check, analyze, tests, `tool/check_docs.sh`, debug APK on Linux; unsigned simulator build on macOS.
- **Release CI** (`.github/workflows/release.yml`): on a `v*` tag, the same checks, then a release APK published as a GitHub Release (signed when the `ANDROID_KEYSTORE_*` secrets exist, otherwise debug-signed and marked pre-release). Helpers: `tool/release_version.sh` (tag must match `pubspec.yaml`), `tool/ci_prepare_signing.sh` (secrets to `android/key.properties`). See `release.md`.

## File map

Every Dart source file and what it owns. `tool/check_docs.sh` fails if a file under `lib/` is missing from this table.

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | production entry point and startup sequence |
| `lib/demo.dart` | in-memory sample library entry point |
| `lib/dev_seed.dart` | development-only seeding of a device's real library, with real covers when online |
| `lib/app/app.dart` | router, bottom-navigation shell, destination loading and error states |
| `lib/app/providers.dart` | Riverpod providers |
| `lib/core/storage/database.dart` | Drift tables and migration strategy |
| `lib/core/storage/database.g.dart` | generated Drift code (checked in) |
| `lib/core/storage/migrations/schema_versions.dart` | generated step-by-step migration helper |
| `lib/core/storage/backup_service.dart` | export, inspect, and atomic restore |
| `lib/core/storage/cover_store.dart` | import, save, and clean up cover files |
| `lib/core/storage/draft_store.dart` | draft persistence and the form binding |
| `lib/core/storage/preferences_store.dart` | small device-local settings (memory and file stores) |
| `lib/core/storage/session_store.dart` | friends sign-in tokens: memory store and secure-storage store |
| `lib/core/theme/app_theme.dart` | colour tokens and `roomTheme()` |
| `lib/core/widgets/book_cover.dart` | cover, generated cover, spine, palette, `bookSeed` |
| `lib/core/widgets/common.dart` | eyebrow, empty state, snackbar, discard dialog, form sheet |
| `lib/features/library/domain/models.dart` | domain classes, `PartialDate`, validation, `LibraryRepository` interface |
| `lib/features/library/domain/search.dart` | diacritic-insensitive multi-word search and ranking (title, author, series) |
| `lib/features/library/domain/sorting.dart` | title and author sort keys, series grouping, `LibrarySort` |
| `lib/features/library/data/local_library_repository.dart` | Drift implementation, export and restore validation |
| `lib/features/library/presentation/library_screen.dart` | Library tab: filters, search, empty states, selection panel |
| `lib/features/library/presentation/shelf.dart` | shelf packing, rows, planks, keepsake note |
| `lib/features/library/presentation/keepsakes.dart` | keepsake enum, thresholds, painters |
| `lib/features/library/presentation/book_form.dart` | add and edit form, search entry, drafts |
| `lib/features/book_search/domain/book_lookup.dart` | lookup interface, suggestion, ISBN detection |
| `lib/features/book_search/data/open_library_lookup.dart` | Open Library client |
| `lib/features/book_search/presentation/book_search_screen.dart` | online search screen |
| `lib/features/reading/presentation/reading_screen.dart` | Reading tab |
| `lib/features/reading/presentation/reading_actions.dart` | page, session, pin, finish sheets with drafts |
| `lib/features/history/presentation/finish_date_field.dart` | finish-date precision picker |
| `lib/features/history/domain/journal_buckets.dart` | groups finishes by month, year-only, year, and undated without inventing precision |
| `lib/features/history/presentation/journal_months.dart` | Journal Months view: year rows, month tiles, cover fans |
| `lib/features/history/presentation/journal_screen.dart` | Journal tab: summary, Months / Days / History views, session calendar |
| `lib/features/book_details/presentation/book_details_screen.dart` | book details, pins, history, remove |
| `lib/features/settings/presentation/settings_screen.dart` | export, restore, licences |
| `lib/features/sharing/data/share_image.dart` | on-device share images |
| `lib/features/friends/domain/friends_models.dart` | `Person`, `Account`, `SharedBook`, `SharedShelf`, `FriendsException`, the `FriendsApi` interface, and `sharedBooksFrom` (what is published) |
| `lib/features/friends/data/http_friends_api.dart` | `FriendsApi` over HTTPS with `dart:io`: tokens, refresh, error messages |
| `lib/features/friends/data/contacts_source.dart` | contacts permission and phone numbers (numbers only) |
| `lib/features/friends/presentation/friends_providers.dart` | friends data providers, `resetFriendsData`, `runFriends` |
| `lib/features/friends/presentation/friends_screen.dart` | `/friends`: account, shelf sharing, requests, friends, phone, blocked, sign out, delete account |
| `lib/features/friends/presentation/account_panel.dart` | sign-in and create-account panel |
| `lib/features/friends/presentation/find_friends.dart` | find by username and from contacts |
| `lib/features/friends/presentation/friend_shelf_screen.dart` | `/friends/:id`: a friend's read-only shelf, remove, block |
| `lib/features/friends/presentation/person_row.dart` | a person with their actions |

Other tooling: `tool/flutterw` (finds the Flutter SDK), `tool/set_bundle_id.sh`, `tool/check_docs.sh`, `tool/docs_stop_hook.sh`, `tool/release_version.sh`, `tool/ci_prepare_signing.sh`.
