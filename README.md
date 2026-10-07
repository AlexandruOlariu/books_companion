# Reading Library

A Flutter reading journal for Android and iOS. A warm-paper bookshelf, private page pins, and an honest distinction between remembered reading history and logged activity. Opens on an account page, then to your library: it is saved to your account in the background (and works offline), with no analytics. A small server in `server/` (see `docs/backend.md`) keeps accounts and saved libraries, and powers the optional Friends feature.

## Run

Use **Flutter 3.47.6 / Dart 3.13.5**, Android 7.0+ (API 24), or iOS 15.0+. Direct dependencies are pinned in `pubspec.yaml`, with transitive versions in `pubspec.lock`.

```sh
flutter pub get
flutter run                     # Real, persistent library
flutter run -t lib/demo.dart    # Isolated in-memory visual prototype
```

In this workspace, `./tool/flutterw` also locates the installed SDK if Flutter is not on PATH. Example: `./tool/flutterw run -d emulator-5554`.

`flutter run -t lib/dev_seed.dart` fills a development device's real library with ~45 sample books (covers from Open Library when online) to judge the shelf at a realistic size. It is a separate entry point and never part of a release.

The sample library is created only by `lib/demo.dart`, `lib/dev_seed.dart`, and the tests. The release entry point (`lib/main.dart`) never seeds anything. Demo changes disappear when that process closes; `dev_seed` data persists on the device until the app is uninstalled.

## Implemented

- A bookcase-style shelf: rows of spines on wooden planks (books being read stand face-out with a bookmark), plus a list view, title/author search, status and completion-year filters.
- Manual catalog entry, edition editing, local cover import, generated typographic covers and spines.
- Reading progress with Undo; corrections never create activity.
- Finished and historical books with exact-day, month, year, or unknown dates; batch entry requires a new explicit date choice for each book.
- Sessions with independently optional page ranges and duration; calendar intensity comes only from sessions.
- Private pins with type, text, page, and/or percentage; book details and reading history.
- Journal period summaries, monthly calendar with day details, partial-date history groups.
- Versioned JSON backup including cover bytes; atomic replacement restore with relation and value validation.
- Shelf keepsakes (bookend, plant, mug, candle, globe, hourglass, cat) earned only by the number of books finished, never by streaks, pages, or time.
- Optional Open Library search with local cover download; offline or failed lookups fall back to manual entry.
- Unsaved forms, session notes, and pins are recovered after the app is killed.
- Locally generated finished-book and yearly-shelf PNGs through the native share sheet.
- Bundled OFL-licensed DM Sans and Literata fonts; adaptive list presentation for large text; protected dismissal of dirty forms.

## Structure

`lib/app` owns routing and Riverpod dependency injection. `lib/core/storage` owns Drift, managed cover files, and portable backups. Feature presentation calls `LibraryRepository`, never Drift directly. `LocalLibraryRepository` maps relational catalog, edition, ownership, completion, session, and pin tables to immutable domain snapshots.

`PartialDate` stores `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, or null alongside its precision. It never pads remembered years or months with invented days. `UserBook.currentPage` records position; `ReadingSession` records activity. Rereading keeps earlier completions.

The database is schema version 3. Future upgrades must add an explicit non-destructive migration and an old-schema fixture test. Unknown upgrade paths fail instead of deleting a library. Cover imports are copied to the app documents directory. Android automatic cloud backup is disabled; the explicit local backup contains private notes and should be stored accordingly.

## Validation

```sh
flutter analyze
flutter test
flutter test integration_test/core_flows_test.dart -d <android-device>
flutter build apk --debug
# On a Mac with Xcode:
flutter build ios --simulator --debug
```

Generated Drift source is checked in. Regenerate after schema changes:

```sh
dart run build_runner build
dart run drift_dev schema dump lib/core/storage/database.dart drift_schemas/
dart run drift_dev schema steps drift_schemas/ lib/core/storage/migrations/schema_versions.dart
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

Then add the matching step and a data-preserving case in `test/migration_test.dart`. Release: see `docs/release.md`.

Full documentation is in `docs/` (start with `docs/README.md`): features, architecture, design system, decisions, testing, a rebuild guide, and a changelog. See `docs/implementation-status.md` for tested behavior and remaining release checks. CI includes unit/widget tests, Android compilation, and an unsigned iOS simulator build.

## First-release decisions

Manual entry always works. Optional Open Library search (title, author, or ISBN) fills the form on request and saves everything locally. Ratings, custom shelves, and optional remembered start dates are deferred. The current app stores the independently precise finish date. The yearly share card displays up to 24 distinct covers and labels a larger collection as a selection. Backup restore replaces the current library after an explicit confirmation; it does not merge libraries.

This is a working development build, not a store-ready release. iOS compilation/native flows, physical-device performance, screen-reader exploration, interrupted-process drafts, release signing, and store packaging require the checks described in the status document.
