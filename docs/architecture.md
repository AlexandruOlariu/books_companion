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
| flutter_secure_storage | 11.2.0 | the account sign-in tokens (Keychain on iOS, an encrypted store on Android) |
| firebase_core, firebase_messaging | 4.15.0 / 16.7.0 | friend notifications (Firebase Cloud Messaging, Android only for now; see "Push notifications"); on Android the Google services Gradle plugin 4.5.0 is applied only when `android/app/google-services.json` exists |
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

- Screens call `LibraryRepository`, never Drift. The account, friends and sync features talk to a separate server (`server/`, see `backend.md`) through `FriendsApi` and `LibrarySyncApi`, both implemented by one `HttpFriendsApi`. The friends client never reads Drift; the sync engine reads and replaces the library only through `LibraryRepository` (`exportData` / `restoreData`). See "Friends client" and "Account sync" below.
- Domain rules (date precision, validation, search ranking, shelf packing, keepsake thresholds) are plain Dart functions so tests can cover them without widgets.
- `LibraryRepository.load()` returns an immutable `LibrarySnapshot` (books, completions, sessions, pins) that the UI reads; writes invalidate `libraryProvider`.

## Startup (`lib/main.dart`)

1. Register font licences.
2. Open `reading-library.sqlite` in the documents directory with `NativeDatabase.createInBackground`, build `LocalLibraryRepository`, and call `load()` once to fail early.
3. Create `FileDraftStore` (`drafts.json` in the application-support directory) and flush it when the app goes inactive or paused.
4. Fire-and-forget cover cleanup (`CoverStore.collectGarbage`), whose errors are ignored.
5. Create the push service (`FirebasePushService.create()`; never fails, falls back to "unavailable").
6. `runApp` with provider overrides. If steps 2 to 4 throw, a plain "Your library could not be opened" screen with **Try again** is shown and nothing on disk is touched.

`lib/demo.dart` runs the same app on an in-memory sample library. `lib/dev_seed.dart` fills a development device's real library and then calls `main()`. Both are separate entry points and never part of a release.

## Providers (`lib/app/providers.dart`)

| Provider | Meaning |
| --- | --- |
| `repositoryProvider` | must be overridden (local repository, or the demo one) |
| `libraryProvider` | `FutureProvider<LibrarySnapshot>`; invalidate after writes |
| `demoProvider` | true in the demo build (labels the app bar) |
| `draftStoreProvider` | in-memory by default; file-backed in `main.dart` |
| `preferencesProvider` | in-memory by default; file-backed (`preferences.json` in the support directory) in `main.dart`; holds the shelf's sort choice |
| `bookLookupProvider` | `ServerBookLookup` (server first, `OpenLibraryLookup` as fallback); tests override with a fake |
| `sessionStoreProvider` | in-memory by default; `SecureSessionStore` (secure storage) in `main.dart`; holds the friends sign-in tokens |
| `serverApiProvider` | the one `HttpFriendsApi` on the session store, shared so friends calls and library saves use the same sign-in and a single token refresh |
| `friendsApiProvider` | `FriendsApi`, by default `serverApiProvider`; tests override with a fake |
| `pushApiProvider`, `pushServiceProvider` | `PushApi` (by default `serverApiProvider`) and `PushService` (`NoPushService` by default; `main.dart` overrides it with `FirebasePushService`); tests override both with fakes |
| `librarySyncApiProvider` | `LibrarySyncApi`, by default `serverApiProvider`; tests override with a fake server |
| `accountRequiredProvider` | false by default (tests, the demo); `main.dart` overrides it to true, which makes the router demand a signed-in account |
| `signedInProvider` | `FutureProvider<bool>` from `FriendsApi.signedIn()`, answered from the device's session without the network; invalidated by `resetFriendsData` / `resetAccountData` on sign-in, sign-out, deletion and a lost session |
| `syncRepositoryProvider` | the plain local repository the sync engine uses (`main.dart` overrides it); defaults to `repositoryProvider`. Distinct from `repositoryProvider`, which `main.dart` wraps in `SyncingRepository`, so a download is not seen as a change to save again |
| `libraryChangeHookProvider` | the `LibraryChangeHook` shared by `SyncingRepository` and `SyncController` |
| `contactsSourceProvider` | `DeviceContactsSource` (permission and numbers); tests override with a fake |
| `regionProvider` | the device's country code (for reading phone numbers written without a country code); tests override |

`syncEngineProvider` and `syncControllerProvider` live in `lib/features/sync/presentation/sync_controller.dart` (see "Account sync"). The friends screens add their own data providers in `lib/features/friends/presentation/friends_providers.dart` (`accountProvider`, `friendsProvider`, `friendRequestsProvider`, `blockedProvider`, `mySharedShelfProvider`, `friendShelfProvider`), invalidated together (with `signedInProvider`) by `resetFriendsData` on sign-in, sign-out, and account deletion, and an action wrapper `runFriends` that turns failures into messages and a lost session into the sign-in panel.

## Data model

Schema version **4**, defined in `lib/core/storage/database.dart` with Drift. Foreign keys are on. Ids are UUID strings. Writes that touch several tables run in a transaction.

| Table | Columns | Notes |
| --- | --- | --- |
| `books` | id, title, series_name?, series_number?, created_at, updated_at | catalogue entry; the series columns were added in version 2 (a number needs a name and is 1 or more) |
| `authors` | id, name | one author per saved book; orphans are pruned |
| `book_authors` | book_id (cascade), author_id, position | PK (book_id, author_id) |
| `editions` | id, book_id (cascade), page_count?, language?, cover_local_path?, cover_source?, metadata_source ('manual' or 'open_library') | the selected edition. `cover_source` (added in version 3) is where an online cover came from, an Open Library address of the form `https://covers.openlibrary.org/b/id/<n>-L.jpg[?default=false]` only (`isOpenLibraryCoverUrl`; `saveBook` and `restoreData` reject anything else); null for a gallery cover |
| `user_books` | id, book_id (cascade), edition_id, status, rating?, current_page (default 0), added_at, updated_at | the reader's copy; status is `reading`, `want_to_read` (shown as Wishlist), or `finished`. `rating` (added in version 4) is a whole number 1 to 5 or null; it belongs to the reader's copy, so a reread keeps it |
| `reading_records` | id, user_book_id (cascade), finished_value?, finished_precision, source, created_at | completion claims; source is `tracked_in_app` or `entered_past` |
| `reading_sessions` | id, user_book_id (cascade), started_at, start_page?, end_page?, duration_seconds?, created_at | the only source of activity |
| `pins` | id, user_book_id (cascade), text_content, type, page?, progress_percent?, created_at, updated_at | private notes |

Series is a name and a number on the book, not a separate table, so renaming a series means editing each book. Deliberately absent from the plan's model: subtitle, description, ISBNs, publisher, publication year, start dates, custom shelves. (Ratings were absent until version 4, D41.)

### Dates

`PartialDate(precision, value)` stores `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, or null for `unknown`. The constructor rejects a value that does not match its precision, an invalid calendar date, and a non-null value for `unknown`. `addedAt` is never used to infer a date. Rereading keeps earlier records.

### Rules enforced in the repository

- Title and author required; page count above zero; finishing a new book requires a confirmed finish.
- `updatePage` is bounded by the edition's page count. `logSession` validates pages and duration (`validateSession`), rejects future dates, advances progress only forward, and never rewinds it.
- Editing an edition is rejected if it would invalidate current page, existing sessions, or pins.
- `setStatus(finished)` requires a finish, refuses an already-finished book, and writes a record.
- `deleteBook` cascades and prunes orphan authors.
- `setRating(id, rating)`: 1 to 5 or null (`validateRating`, `maxRating`); a number needs at least one reading record (never rated before a finish); null always allowed; it does not touch status, records, sessions, or pins. Editing a book or reading it again leaves the rating. Adding a book as Finished sets it afterwards through `setRating`, so one validation path covers both.
- Pins: non-empty text, a known type, page within the total, percent in 0..100.

## Backup and restore (`lib/core/storage/backup_service.dart`)

Envelope: `{ "format": "reading-library", "version": 1, "data": { "version": 1, books, authors, bookAuthors, editions, userBooks, records, sessions, pins }, "covers": { "<editionId>.cover": "<base64>" } }`.

- Export embeds cover bytes under portable keys instead of device paths, and fails clearly if a cover file is missing.
- Restore checks size (150 MB; covers 20 MB each) and format, rejects keys that are not `[a-zA-Z0-9-]+.cover`, stages cover files under fresh names, then validates every record (values, precisions, relations, pages, pins) and replaces all tables in one transaction. On any failure staged files are deleted and the existing library is untouched.
- Android automatic backup is disabled; the account's saved copy (see "Account sync") and this explicit file are the copies, and both contain private notes. `cover_source` travels in the data, so a restored library can fetch its online covers again.

## Migrations

`schemaVersion` is 4. `onUpgrade` uses Drift's `stepByStep()` from `lib/core/storage/migrations/schema_versions.dart`; the steps are `from1To2` (two nullable columns on `books`, so existing rows keep their data and simply have no series), `from2To3` (one nullable `cover_source` column on `editions`; existing covers have no known source and are not given one), and `from3To4` (one nullable `rating` column on `user_books`; existing books are unrated). An unknown upgrade throws instead of dropping data. Frozen schemas are `drift_schemas/drift_schema_v1.json`, `..._v2.json`, `..._v3.json` and `..._v4.json`, with generated test helpers in `test/generated_migrations/`. `test/migration_test.dart` upgrades the frozen v1 schema to the current one, upgrades the frozen v2 schema, checks the current schema equals the frozen v4 dump, upgrades a seeded v3 library with every book unrated, and checks that a v1 library survives with null series and a v2 library keeps its series and cover path with no cover source. The v1 to v2 upgrade and the v2 to v3 upgrade each ran for real on an emulator whose database was still at the older version (the 51-book seeded library kept every book); the v3 to v4 upgrade ran the same way on 2026-10-08 (a 52-book library and its signed-in account opened normally on the new build). Procedure for the next version is in the root `README.md`.

**Backups across versions:** the backup envelope stays at version 1 because the series, cover source and rating fields are additive and optional (a backup without `rating` restores as unrated; a rating outside 1 to 5, or on a book with no finish, makes the restore refuse and leave the library unchanged). A backup made before series existed restores (the keys are absent and read as null); an invalid series (number below 1, number without a name, blank name) is rejected and the existing library is left untouched.

## Online lookup (`lib/features/book_search`)

`BookLookup` (domain) has `search(query)` and `fetchCover(suggestion)`. `OpenLibraryLookup` (data) uses `dart:io` `HttpClient` with an 8 s connect timeout, 15 s response timeout, size caps (2 MB JSON, 5 MB image), a `ReadingLibrary/0.1` user agent, and no identifiers. Cover bytes are accepted only if they are JPEG or PNG by content. All failures become a friendly `LookupException`; the looser retry for misspellings never raises an error and leaves out a short stop-word list (English, Romanian, a few French, German and Spanish articles), because an any-word query containing "the" makes Open Library return HTTP 500 after about 10 s. Hosts are injectable for tests.

`ServerBookLookup` (data) is what the app uses. It sends `POST {HttpFriendsApi.defaultOrigin}/books/search` with `{"q": text}` (5 s connect, 20 s response, 1 MB cap, no token or identifier); the server runs the same exact-then-any-word logic (`backend.md`, Book search) and returns books with a `cover_id`. The cover and thumbnail URLs are built on the device from that id with `OpenLibraryLookup.coverUrlFor`, so a cover is only ever downloaded from Open Library's cover host, and `fetchCover` is delegated to `OpenLibraryLookup`. Any server failure (unreachable, timeout, non-200 including 429, bad body) falls back to `OpenLibraryLookup.search`, so search works as before when the server is down.

## Shelf rendering (`lib/features/library/presentation/shelf.dart`)

`packShelves(books, width, keepsakes)` returns rows of `BookSlot` and `KeepsakeSlot` no wider than the width, with keepsakes spaced evenly. `SliverShelf` builds rows lazily in a sliver list so a large library stays cheap; its `onOpen` callback (the Library tab pushes `/book/:id`) is awaited, so the tapped book can settle back afterwards. The `/book/:id` route (`app.dart`) uses a `CustomTransitionPage`: when the shelf pushes it with a `BookOpening` as `extra` (the tapped book's id must match the route's), the page plays `bookOpeningTransition` (800 ms, 520 ms back); from anywhere else, or when the platform disables animations (no transition at all), it fades and rises 4% (420 ms, 320 ms back). Slot sizes derive from `bookSeed(title)` (a stable FNV-1a hash) and page count. Details in `design-system.md`.

## Account sync (`lib/features/sync/`)

The library is saved to the account as a whole, using the backup data (`exportData`) without cover files. The phone is the source of truth and never waits for the server.

- **Server side:** `libraries` (one row per account: `revision`, JSONB `payload`, `updated_at`), `GET /me/library/meta`, `GET /me/library`, `PUT /me/library` with `{base_revision, data}`; a save whose `base_revision` is not the stored revision is refused with 409 and writes nothing. Details in `backend.md`.
- **`LibrarySyncApi`** (`sync_models.dart`): `accountId`, `libraryRevision`, `fetchLibrary`, `saveLibrary`; a 409 is `LibraryConflictException`, other failures are `FriendsException` (unreachable, or `signedOut`). `HttpFriendsApi` implements it (responses up to 24 MB for this call, 8 MB otherwise).
- **`SyncEngine`** (`sync_engine.dart`, plain Dart, no Flutter): state lives in `preferences.json` under `sync.userId`, `sync.revision` (the revision this phone last saw) and `sync.dirty` (changes not yet saved). `markDirty()` also bumps an in-memory counter so a change made while a save is in flight keeps the flag. `sync()` decides: no baseline (first time with this account) and the account empty → save; phone empty → download; both have books → `SyncOutcome.conflict` with both counts; baseline equal → save only if dirty; account newer and phone clean → download; account newer and phone dirty → conflict; account behind the baseline (restored from an old copy) → the phone is the source and saves; a 409 during a save → conflict. `resolve(keepPhone)` saves over the account's revision or downloads. `adopt(userId)` clears the baseline when the account differs from last time; `forget()` is for account deletion. A saved library has every edition's `coverLocalPath` set to null (device paths never leave the phone). A download keeps the cover paths this phone already has for the same edition ids, then `restoreData` validates everything in one transaction; a malformed account copy becomes `SyncOutcome.failed` and leaves the phone untouched (type errors from wrong shapes are turned into a `FormatException`). `fetchMissingCovers()` fetches up to 40 editions that have a `cover_source` and no file, through `BookLookup.fetchCoverFromUrl`, which only contacts Open Library's cover host; failures are retried at the next sync, and attaching a cover (`LibraryRepository.attachCover`) is not a change to save.
- **`SyncingRepository`** wraps the local repository in `main.dart` and tells the shared `LibraryChangeHook` after every successful write (`saveBook`, `updatePage`, `setStatus`, `logSession`, `addPin`, `deletePin`, `deleteBook`, `restoreData`); reads, `exportData` and cover attachments are not changes.
- **`SyncController`** (`sync_controller.dart`, a Riverpod `Notifier<SyncState>`): turns a change into `markDirty` and a save 3 s later, runs one sync at a time (a request during a run repeats it), retries after 1 minute when offline, pauses while a conflict waits for the reader, and on `signedOut` invalidates the session so the router returns to `/welcome`. Phases: `off`, `syncing`, `saved`, `waiting`, `conflict`, `problem`. After a download or fetched covers it invalidates `libraryProvider`. Disabled when `accountRequiredProvider` is false or in the demo.
- **App wiring** (`lib/app/app.dart`): `ReadingLibraryApp` is a `ConsumerStatefulWidget` and a lifecycle observer (saves on resume); the router has a `redirect` that sends everything to `/loading` (session not read yet) or `/welcome` (nobody signed in) and `refreshListenable` tied to `signedInProvider`; a listener shows the conflict dialog (`conflict_dialog.dart`) on the root navigator so it appears wherever the reader is. `welcome_screen.dart` is the account panel full screen.

## Friends client (`lib/features/friends/`)

Separate from the library: nothing here reads or writes it except `sharedBooksFrom`, which builds what the reader chose to publish to friends. The account itself (sign-in) is shared with sync.

- `FriendsApi` is the interface; `HttpFriendsApi` implements it against `https://ai.duk-tech.com/books-api` (`HttpFriendsApi.defaultOrigin`; injectable for tests). 8 s connect and 20 s response timeouts, an 8 MB response cap, a `ReadingLibrary/0.1` user agent.
- **Sessions:** the access and refresh tokens live in `SessionStore` (secure storage in production), never in `preferences.json` and never in a backup. A 401 triggers one refresh (shared by concurrent calls, `_refreshing`) and a retry. Only a refusal by the server ends the session; a network failure, timeout, or server error never signs the reader out.
- **Errors:** every failure becomes a `FriendsException` with a message that is safe to show (the server's own `detail` text when it has one, a generic text for 429 or 5xx, the first validation error named by field for 422). `signedOut` marks a lost session.
- `sharedBooksFrom(LibrarySnapshot)` is the only code that decides what leaves the device: `id`, `title`, `author`, `status`, and one finish per completion with its precision. `SharedBook` has no field for notes, pins, sessions, progress, covers, or series, so leaving them out does not depend on remembering to. A finished book with no recorded finish is sent as `unknown`; a wishlist book carries none; titles and authors are clipped to 300 characters.
- **Publishing is explicit:** a button, a confirmation that states what is sent, and a replace of the previous snapshot. There is no background sync; friends see the shelf as of the last publish.
- **Contacts:** `DeviceContactsSource` requests the read permission only after the reader confirms a dialog, reads phone numbers only (no names, emails, or photos), sends at most 3000 numbers in batches of 1000 with the device region, and keeps nothing. People already friends or with a pending request are not offered again.
- A friend's shelf is shown from `friendShelfProvider` and is never merged into `LibrarySnapshot`, so it cannot affect statistics, the Journal, or keepsakes.
- The Settings entry is hidden in the demo build.

## Push notifications (`lib/features/push/`)

Friend requests and acceptances reach a closed app through the server (Firebase Cloud Messaging, sent by `server/app/push.py`; see `backend.md`). The client is small and everything about Firebase sits behind `PushService`, so the rest of the app and every test run without it.

- `PushService` (domain) is the phone's side: `available`, `enable()` (asks permission, returns the token or null), `currentToken()`, `forget()`, and the streams `tokenRefreshed`, `received` (a notification arrived while the app was open) and `opened` (the reader tapped one, including the one that launched the app). `NoPushService` is the default and reports itself unavailable. `FirebasePushService.create()` (called in `main.dart`, never throws, 5 s limit) initialises Firebase only on Android; if `google-services.json` was missing at build time initialisation fails and it returns `NoPushService`. It is deliberately not initialised on iOS: without `GoogleService-Info.plist` the native call would crash the app.
- `PushApi` (domain) is the server side, implemented by `HttpFriendsApi`: `PUT /me/devices` and `POST /me/devices/remove`.
- `PushController` (`pushControllerProvider`) keeps the choice in the preferences key `push` (`on`, `off`, or empty for "not decided"). `enable()` asks permission, registers the token, then stores `on`; a refusal stores `off`; an unreachable server leaves it undecided. `disable()` removes the token from the server (best effort), deletes it from Firebase, stores `off`. `refresh()` (after sign-in and on resume) re-sends the token when the choice is `on`, because tokens rotate and a phone can change owner. `signingOut()` (Sign out, and after a successful account deletion) disables and stores "not decided" so the next account is asked. A notification received while the app is open invalidates `friendRequestsProvider` and `friendsProvider`.
- `app.dart` offers notifications once after sign-in (`offerPushNotifications`, only when push is available and nothing was decided) and opens `/friends` when a notification is tapped. The Friends screen has the switch.
- Android: the manifest requests `POST_NOTIFICATIONS` (asked at the moment the reader turns it on), `MainActivity` creates the notification channel `friends` ("Friend requests"), and the manifest names it as Firebase's default channel and `drawable/ic_stat_notification` (a white open book; a colour icon shows as a plain square) as its default small icon. The message text comes from the server's `notification` block, so Android shows it with no app code while the app is closed.

## Suggestions (`lib/features/recommendations/`)

The rules are plain Dart in `domain/recommendations.dart` and take a `LibrarySnapshot`; they read nothing else and write nothing.

- `libraryRecommendations(library, dismissed:)`: groups books by series (`titleKey` of the series name). For a series with numbered finished books it looks at number `max finished + 1` (skipped when the highest finished volume is rated 1 or 2 stars; quoted in the reason when rated 4 or 5): absent from the library gives `nextInSeries` (no title is known, so the card heading is "Series, book N"); a Wishlist book gives `nextOnWishlist`; anything else (being read) gives nothing. Then Wishlist books whose author the reader has finished (`wishlistByAuthor`), ordered by `counted + loved` for that author. `counted` is finished books not rated 1 or 2 stars (an author with none counted gives no suggestion); `loved` is, among those, books rated 4 or 5, read more than once, or with a pin of type Favorite. Authors compare by surname (`authorKey`, first word). At most 5 per group (`maxPerGroup`).
- `friendRecommendations(library, shelves, dismissed:)`: finished books on friends' shelves, minus any book already in the library in any status (`bookIdentity` = `titleKey|surname`, so case, diacritics, a leading article and "Surname, Given" do not matter). Ordered by number of distinct friends, then author affinity, then title; at most 5.
- A suggestion's `key` (`series:<series key>:<n>`, `wish:<book id>`, `friend:<identity>`) is what "Not interested" remembers. `dismissedRecommendationsProvider` stores the keys as a JSON list (newest last, capped at 500) under the preferences key `dismissedRecommendations`: a device preference like the sort order, so never part of a backup, the account copy, or the server.
- `friendShelvesForSuggestionsProvider` is an `autoDispose` `FutureProvider` that asks `friendsApiProvider` directly (`friends()`, then `friendShelf(id)` for up to 30 friends: the same calls the Friends screens make), keeping only finished books as title and author. It deliberately does not use the cached `friendsProvider`/`friendShelfProvider`, which keep their answer for the whole session: a reader who opened the Reading tab before having a friend, or before the friend published, would otherwise see nothing until the app restarted. A non-empty answer is kept alive for `friendShelvesFreshFor` (1 minute) so tab changes do not ask again; an empty or failed one is dropped at once. It returns an empty list when the build is the demo, nobody is signed in, or any call fails, so the section degrades to library-only suggestions. No new endpoint, field, or request body: the reader sends nothing new, though the server sees these reads more often.
- The section (`RecommendationsSection`) sits at the end of the Reading tab. Cards use a generated cover for every suggestion (friends never share covers; an unseen volume has none) and either open the Wishlist book (`/book/:id`) or open `/add` prefilled. `/add` accepts optional query parameters `title`, `author`, `series` and `number`; they become a `BookPrefill`, which only fills the form's fields. A prefilled form does not use or overwrite the saved new-book draft.

## Drafts (`lib/core/storage/draft_store.dart`)

`DraftStore` (`load`, `save`, `clear`) with `MemoryDraftStore` and `FileDraftStore` (debounced writes, atomic rename, 30-day expiry, damaged file ignored). `DraftBinding` ties one form to one key and clears the draft when all text is blank. Keys: `book:new` and `action:<userBookId>:<page|session|pin>`.

## Platform configuration

- **Android:** `applicationId` `app.readingroom.reading_library` (a placeholder; change with `tool/set_bundle_id.sh`), Kotlin namespace unchanged. `allowBackup=false`. The main manifest requests `INTERNET` (search, the account and library saving, and friends) and `READ_CONTACTS` (only used by "Find friends from contacts"; read-only; checked in the built APK's merged manifest) and `POST_NOTIFICATIONS` (friend notifications, asked for only when the reader turns them on). Nothing else is requested by the app itself; the Firebase libraries add `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `BIND_JOB_SERVICE`, `DUMP` and Google's own C2DM receive/send permission (read in the merged debug manifest of a build with the real Firebase file, 2026-10-09; no Analytics or advertising-id permission). `android/app/google-services.json` is the Firebase project's client configuration: git-ignored, written by CI from the `GOOGLE_SERVICES_JSON` secret, and optional (without it the app builds and cannot receive notifications). Release signing reads `android/key.properties`; without it a release build fails unless `READING_LIBRARY_DEBUG_SIGNING=1` is set for a local, non-uploadable build.
- **iOS:** bundle id `app.readingroom.readingLibrary` (placeholder), `NSPhotoLibraryUsageDescription` and `NSContactsUsageDescription` set, automatic signing with no team committed. No app-level privacy manifest yet.
- **CI** (`.github/workflows/checks.yml`): format check, analyze, tests, `tool/check_docs.sh`, debug APK on Linux; unsigned simulator build on macOS.
- **Release CI** (`.github/workflows/release.yml`): on every push to `main` (unless the head commit says `[skip release]`) and on a `v*` tag, the same checks plus `tool/test_release_scripts.sh`, then a release APK published as a GitHub Release (signed when the `ANDROID_KEYSTORE_*` secrets exist, otherwise debug-signed and marked pre-release). Helpers: `tool/release_version.sh` (a pushed tag must match `pubspec.yaml`), `tool/next_release_version.sh` (the version of an automatic release), `tool/test_release_scripts.sh`, `tool/ci_prepare_signing.sh` (secrets to `android/key.properties`). See `release.md`.

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
| `lib/core/widgets/book_cover.dart` | cover, generated cover, spine, palette, `bookSeed`, optional status seal |
| `lib/core/widgets/book_opening.dart` | `BookOpening` (the tapped book and its on-screen bounds, passed as the route's `extra`) and `bookOpeningTransition`, the cover-grows-then-swings-open page transition |
| `lib/core/widgets/status_badge.dart` | `BookStatusLook` (icon and colours per status) and the round `StatusBadge` seal |
| `lib/core/widgets/rating_stars.dart` | five-star rating control: 48 px stars, tap the chosen star again to clear, each star labelled "N of 5 stars" with its own tap action |
| `lib/core/widgets/common.dart` | eyebrow, empty state, snackbar, discard dialog, form sheet, `screenPadding` (bottom inset for full-screen lists) |
| `lib/features/library/domain/library_title.dart` | `libraryTitle`: the Library tab heading, "<First name>’s Library" or "My Library" |
| `lib/features/library/domain/models.dart` | domain classes, `PartialDate`, validation, `LibraryRepository` interface |
| `lib/features/library/domain/search.dart` | diacritic-insensitive multi-word search and ranking (title, author, series) |
| `lib/features/library/domain/sorting.dart` | title and author sort keys, series grouping, `LibrarySort`, and `librarySortPreference` (the preferences key for the saved sort, also read by the Journal's Share shelf) |
| `lib/features/library/data/local_library_repository.dart` | Drift implementation, export and restore validation |
| `lib/features/library/presentation/library_screen.dart` | Library tab: filters (with status seals), search, empty states; a tapped book opens `/book/:id` |
| `lib/features/library/presentation/shelf.dart` | shelf packing, rows, planks, keepsake note, the tilt-and-open animation of a shelf book |
| `lib/features/library/presentation/keepsakes.dart` | keepsake enum, thresholds, painters |
| `lib/features/library/presentation/book_form.dart` | add and edit form, search entry, drafts |
| `lib/features/book_search/domain/book_lookup.dart` | lookup interface, suggestion, ISBN detection |
| `lib/features/book_search/data/open_library_lookup.dart` | Open Library client (direct fallback, covers) |
| `lib/features/book_search/data/server_book_lookup.dart` | search through the Reading Library server, falling back to Open Library |
| `lib/features/book_search/presentation/book_search_screen.dart` | online search screen |
| `lib/features/reading/presentation/reading_screen.dart` | Reading tab (ends with the suggestions section) |
| `lib/features/recommendations/domain/recommendations.dart` | the suggestion rules in plain Dart: `libraryRecommendations`, `friendRecommendations`, `bookIdentity`, `Recommendation`, `FriendShelf` |
| `lib/features/recommendations/presentation/recommendations_providers.dart` | the dismissed-suggestions notifier (device preference) and the friends' shelves read for suggestions |
| `lib/features/recommendations/presentation/recommendations_section.dart` | "What to read next" section and cards on the Reading tab, and the "Nothing to suggest yet" note when a non-empty library has no suggestion |
| `lib/features/reading/presentation/reading_actions.dart` | page, session, pin, finish sheets with drafts |
| `lib/features/history/presentation/finish_date_field.dart` | finish-date precision picker |
| `lib/features/history/domain/journal_buckets.dart` | groups finishes by month, year-only, year, and undated without inventing precision |
| `lib/features/history/presentation/journal_months.dart` | Journal Months view: year rows, month tiles, cover fans |
| `lib/features/history/presentation/journal_screen.dart` | Journal tab: summary, Months / Days / History views, session calendar |
| `lib/features/book_details/presentation/book_details_screen.dart` | book details, pins, history, remove |
| `lib/features/settings/presentation/settings_screen.dart` | export, restore, account links, Android updates and licences |
| `lib/features/updates/update_service.dart` | installed Android package metadata, bounded HTTPS update manifest fetch, version/application/download validation, browser download channel |
| `lib/features/updates/update_controller.dart` | `updateServiceProvider`, `updateControllerProvider`: foreground checks, six-hour session throttle, retry, dismissal and download state |
| `lib/features/updates/update_widgets.dart` | optional shelf-shell update notice and Android Settings update controls |
| `lib/features/sync/domain/sync_models.dart` | `LibrarySyncApi`, `LibraryRevision`, `RemoteLibrary`, `LibraryConflictException`, `SyncConflict`, `SyncOutcome`, `SyncResult` |
| `lib/features/sync/data/sync_engine.dart` | `SyncEngine`: decides between saving, downloading and a conflict; saves and downloads the whole library; fetches missing online covers |
| `lib/features/sync/data/syncing_repository.dart` | `SyncingRepository` (reports every write) and `LibraryChangeHook` |
| `lib/features/sync/presentation/sync_controller.dart` | `SyncController`, `SyncState`, `SyncPhase`, `syncEngineProvider`, `syncControllerProvider`: when to save, retries, status |
| `lib/features/sync/presentation/conflict_dialog.dart` | "Which library do you want to keep?" |
| `lib/features/sync/presentation/welcome_screen.dart` | the full-screen account page shown while nobody is signed in |
| `lib/features/sharing/presentation/share_app_button.dart` | native app-invitation share button, fixed public Android download message, clipboard and share-error fallback; anchors the chooser to its button |
| `lib/features/sharing/data/share_image.dart` | on-device share images; `yearShelf` takes the `LibrarySort`, lists every book, and scales the canvas down above 8000 px tall |
| `lib/features/push/domain/push_models.dart` | `PushApi` (register and remove a device token), `PushService` (permission, token, incoming and tapped notifications) and `NoPushService` |
| `lib/features/push/data/firebase_push_service.dart` | `FirebasePushService`: Firebase Cloud Messaging on Android; unavailable elsewhere or without `google-services.json` |
| `lib/features/push/presentation/push_controller.dart` | `PushController`, `PushState`, `PushChoice`, `PushResult`, `pushServiceProvider`, `pushApiProvider`: the stored choice, registering the token, signing out |
| `lib/features/push/presentation/push_prompts.dart` | the one-time "Know when a friend writes?" offer and the messages for a blocked or failed turn-on |
| `lib/features/friends/domain/friends_models.dart` | `Person`, `Account`, `SharedBook`, `SharedShelf`, `FriendsException`, the `FriendsApi` interface (including `updateProfile` and `changePassword`), and `sharedBooksFrom` (what is published) |
| `lib/features/friends/domain/account_rules.dart` | plain-Dart checks for the account page: name, username (3 to 30 of `a-z0-9_.`, case ignored) and new password (10 to 128, repeated), mirroring the server |
| `lib/features/friends/presentation/account_screen.dart` | `/account`: edit first name, last name and username (only changed fields are sent), and change the password |
| `lib/features/friends/data/http_friends_api.dart` | `FriendsApi` over HTTPS with `dart:io`: tokens, refresh, error messages; `updateProfile` is `PATCH /me` with only the given fields, `changePassword` is `POST /me/password` and stores the fresh tokens the server returns (it ended every other session) |
| `lib/features/friends/data/contacts_source.dart` | contacts permission and phone numbers (numbers only) |
| `lib/features/friends/presentation/friends_providers.dart` | friends data providers, `resetFriendsData`, `runFriends` |
| `lib/features/friends/presentation/friends_screen.dart` | `/friends`: account, shelf sharing, requests, friends, phone, blocked, sign out, delete account |
| `lib/features/friends/presentation/account_panel.dart` | sign-in and create-account panel |
| `lib/features/friends/presentation/find_friends.dart` | find by username and from contacts |
| `lib/features/friends/presentation/friend_shelf_screen.dart` | `/friends/:id`: a friend's read-only shelf, remove, block |
| `lib/features/friends/presentation/person_row.dart` | a person with their actions |

Other tooling: `tool/flutterw` (finds the Flutter SDK), `tool/set_bundle_id.sh`, `tool/check_docs.sh`, `tool/docs_stop_hook.sh`, `tool/release_version.sh`, `tool/ci_prepare_signing.sh`.

## Android updates outside Google Play

The app checks signed GitHub release metadata after the first frame and on resume, at most once per six hours within a process; a manual Settings check bypasses the throttle. The demo and other platforms do not check. `reading_library/updates` in Android `MainActivity` reads the actual installed version, build number and application ID and opens an HTTPS browser download on request. No new dependency or permission is required. The release manifest must describe the same application ID, a positive higher build number, and an exact APK address in this repository/tag; equal or older builds are never offered. A failed check keeps an already known update. Network reads have a 15-second total timeout and 64 KiB body limit; the app does not download or execute an APK itself. Android verifies the APK signature and asks the reader to install.

`tool/create_update_manifest.py` checks the compiled release manifest against CI version/build values and generates `update.json` only for signed public releases. The workflow publishes a fixed `reading-library.apk` asset and SHA-256 checksum, allowing a permanent latest-download address. Private account and library data are never included in update requests.
