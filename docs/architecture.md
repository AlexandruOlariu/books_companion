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
| intl | 0.20.3 | date formatting |
| dev: drift_dev, build_runner, flutter_lints | 2.35.1, 2.16.1, 6.0.0 | codegen, migration tooling, lints |

Fonts are bundled (DM Sans, Literata, both OFL) with their licences registered at startup. There is no Freezed, json_serializable, Dio, or cached_network_image despite the plan: domain models are small hand-written classes, and the optional online lookup uses `dart:io` directly.

Targets: Android 7.0+ (API 24; target 36), iOS 15.0+. The iOS build has never been compiled on this Linux host (CI has a macOS job).

## Layers

```
presentation (widgets)  ->  LibraryRepository (interface)  ->  LocalLibraryRepository  ->  Drift / SQLite
                                  ^ domain rules live in plain Dart (models.dart, search.dart)
```

- Screens call `LibraryRepository`, never Drift. A remote implementation could be added later behind the same interface; no sync code exists.
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
| `bookLookupProvider` | `OpenLibraryLookup`; tests override with a fake |

## Data model

Schema version **1**, defined in `lib/core/storage/database.dart` with Drift. Foreign keys are on. Ids are UUID strings. Writes that touch several tables run in a transaction.

| Table | Columns | Notes |
| --- | --- | --- |
| `books` | id, title, created_at, updated_at | catalogue entry |
| `authors` | id, name | one author per saved book; orphans are pruned |
| `book_authors` | book_id (cascade), author_id, position | PK (book_id, author_id) |
| `editions` | id, book_id (cascade), page_count?, language?, cover_local_path?, metadata_source ('manual' or 'open_library') | the selected edition |
| `user_books` | id, book_id (cascade), edition_id, status, current_page (default 0), added_at, updated_at | the reader's copy; status is `reading`, `want_to_read`, or `finished` |
| `reading_records` | id, user_book_id (cascade), finished_value?, finished_precision, source, created_at | completion claims; source is `tracked_in_app` or `entered_past` |
| `reading_sessions` | id, user_book_id (cascade), started_at, start_page?, end_page?, duration_seconds?, created_at | the only source of activity |
| `pins` | id, user_book_id (cascade), text_content, type, page?, progress_percent?, created_at, updated_at | private notes |

Deliberately absent from the plan's model: subtitle, description, ISBNs, publisher, publication year, cover source URL, ratings, start dates, custom shelves.

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

`schemaVersion` is 1. `onUpgrade` uses Drift's `stepByStep()` from `lib/core/storage/migrations/schema_versions.dart`; there are no steps yet, so an unknown upgrade throws instead of dropping data. The frozen v1 schema is `drift_schemas/drift_schema_v1.json`, with generated test helpers in `test/generated_migrations/`. `test/migration_test.dart` fails if the schema changes without a version bump and checks a v1 library survives. Procedure for version 2 is in the root `README.md`.

## Online lookup (`lib/features/book_search`)

`BookLookup` (domain) has `search(query)` and `fetchCover(suggestion)`. `OpenLibraryLookup` (data) uses `dart:io` `HttpClient` with an 8 s connect timeout, 15 s response timeout, size caps (2 MB JSON, 5 MB image), a `ReadingLibrary/0.1` user agent, and no identifiers. Cover bytes are accepted only if they are JPEG or PNG by content. All failures become a friendly `LookupException`; the looser retry for misspellings never raises an error. Hosts are injectable for tests.

## Shelf rendering (`lib/features/library/presentation/shelf.dart`)

`packShelves(books, width, keepsakes)` returns rows of `BookSlot` and `KeepsakeSlot` no wider than the width, with keepsakes spaced evenly. `SliverShelf` builds rows lazily in a sliver list so a large library stays cheap. Slot sizes derive from `bookSeed(title)` (a stable FNV-1a hash) and page count. Details in `design-system.md`.

## Drafts (`lib/core/storage/draft_store.dart`)

`DraftStore` (`load`, `save`, `clear`) with `MemoryDraftStore` and `FileDraftStore` (debounced writes, atomic rename, 30-day expiry, damaged file ignored). `DraftBinding` ties one form to one key and clears the draft when all text is blank. Keys: `book:new` and `action:<userBookId>:<page|session|pin>`.

## Platform configuration

- **Android:** `applicationId` `app.readingroom.reading_library` (a placeholder; change with `tool/set_bundle_id.sh`), Kotlin namespace unchanged. `allowBackup=false`. The main manifest requests only `INTERNET` (optional search). Release signing reads `android/key.properties`; without it a release build fails unless `READING_LIBRARY_DEBUG_SIGNING=1` is set for a local, non-uploadable build.
- **iOS:** bundle id `app.readingroom.readingLibrary` (placeholder), `NSPhotoLibraryUsageDescription` set, automatic signing with no team committed. No app-level privacy manifest yet.
- **CI** (`.github/workflows/checks.yml`): format check, analyze, tests, debug APK on Linux; unsigned simulator build on macOS; `tool/check_docs.sh`.

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
| `lib/core/theme/app_theme.dart` | colour tokens and `roomTheme()` |
| `lib/core/widgets/book_cover.dart` | cover, generated cover, spine, palette, `bookSeed` |
| `lib/core/widgets/common.dart` | eyebrow, empty state, snackbar, discard dialog, form sheet |
| `lib/features/library/domain/models.dart` | domain classes, `PartialDate`, validation, `LibraryRepository` interface |
| `lib/features/library/domain/search.dart` | diacritic-insensitive multi-word search and ranking |
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

Other tooling: `tool/flutterw` (finds the Flutter SDK), `tool/set_bundle_id.sh`, `tool/check_docs.sh`, `tool/docs_stop_hook.sh`.
