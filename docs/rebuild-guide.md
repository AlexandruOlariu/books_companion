# If you rebuild the POC

Everything needed to recreate this app, in the order that worked, with the traps that cost time. The goal is that a fresh project plus these docs reproduces the POC, or a better one.

## What to treat as the product (keep these even if the code is rewritten)

1. The honesty rules in `features.md`: date precision, activity only from sessions, keepsakes only from finished-book count.
2. The data model and validation rules in `architecture.md`, and the backup and restore guarantees (atomic, validated, never merge, never lose the existing library on failure).
3. The tests. Domain, repository, backup, and migration tests encode the rules and port directly to any implementation.
4. The decision log. Several decisions came from a real reader's confusion (D17, D20, D21); do not relearn them.

What is just implementation: the Riverpod and go_router wiring, Drift specifics, and the painter code.

## Order of work that worked

1. **Skeleton and theme.** Flutter project, `RoomColors`, fonts (DM Sans, Literata) bundled with licences, `roomTheme()`, three-tab shell. Confirm Android and (on a Mac) iOS build.
2. **Domain first.** `PartialDate`, validation functions, `LibraryRepository` interface, `LibrarySnapshot`. Write `domain_test.dart` now.
3. **Storage.** Drift tables, `LocalLibraryRepository`, transactions, cascade deletes. Write `repository_test.dart`. Dump schema v1 immediately (`drift_schemas/`) and set up `stepByStep()` so migrations are never an afterthought.
4. **Library and shelf.** Add/edit form with covers, generated covers and spines, the shelf, the list view, filters, search.
5. **Reading flows.** Page sheet with Undo, sessions, pins, finish with date precision, book details.
6. **Journal.** Period summaries, calendar from sessions only, history groups.
7. **Backup, restore, share images.**
8. **Optional online lookup** and drafts, once the core is stable.
9. **Keepsakes and shelf polish.**
10. **Release prep** (`release.md`).

Verify each screen in a running emulator, not only in widget tests.

## Traps and how they were solved

- **Test at phone size.** Default test surface is 800 x 600; real phones are about 360 x 800 logical. Chips pushed off-screen, a fixed-height panel overflowing, and hidden buttons all appeared only at phone size.
- **Hash for colours.** A character-sum hash made colours cluster; use FNV-1a and different bit slices for different decisions (`bookSeed`).
- **Stable hash vs `String.hashCode`.** `hashCode` is not guaranteed stable across Dart versions; never use it for visual identity that must persist.
- **Date pickers.** Never default "today" for a past book; require an explicit precision and an explicit pick.
- **Snackbars cover Save.** Dismiss the current snackbar before opening a sheet (an integration test exposed this).
- **Restore must stage files first,** validate everything, then replace in one transaction, deleting staged files on failure.
- **Drift `Value(null)`** writes NULL to a non-null column on update; use `Value.absent()` to keep a column unchanged.
- **Open Library is accent-tolerant but not typo-tolerant;** many titles have no cover. Do not promise covers.
- **Android release needs `INTERNET`** in the main manifest; only the debug manifest has it by default.
- **`flutter format` is gone;** use `dart format`.
- **The first text-field focus on the newest emulator image shows a stylus tutorial;** dismiss it.
- **The integration test wipes app data;** reseed afterwards.
- **Keepsake and shelf positions** are recomputed from the packing function each layout, so adding a book moves later items. That is accepted; if user-placed items are wanted, they need stored positions.

## Things to do differently next time

- Store cover paths relative to the documents directory (D13), or resolve them at read time.
- Consider relative-width spines narrower than 48 px with a padded hit area, if the 48 px minimum makes spines too chunky.
- Add a real iOS privacy manifest. The macOS CI job is what first showed the iOS simulator build compiling (2026-10-06); run it from the start of a rebuild.
- Decide the Google Books question (D19) before launch if Romanian covers matter.
- Make the shelf's first row visible without scrolling on short phones (shrink the selection panel or move it).
- Decide whether keepsakes should count only in-app finishes (D23).

## Reference commands

```sh
flutter pub get
dart run build_runner build
dart run drift_dev schema dump lib/core/storage/database.dart drift_schemas/
dart run drift_dev schema steps drift_schemas/ lib/core/storage/migrations/schema_versions.dart
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
flutter run                                  # real library
flutter run -t lib/demo.dart                 # in-memory sample
flutter run -t lib/dev_seed.dart -d <device> # seed a development device
READING_LIBRARY_DEBUG_SIGNING=1 flutter build apk --release   # local, non-uploadable
```

SDK location on this machine: `tool/flutterw` finds Flutter at `~/.local/share/books-toolchain/flutter`. Android SDK: `~/Android/Sdk` (includes `cmdline-tools/latest`, so `sdkmanager` works). Emulator AVD: `Pixel_9_Pro`.
