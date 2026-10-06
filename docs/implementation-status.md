# Implementation status

The source plan is preserved in `product-plan.md`. This implementation establishes a usable local-first app across milestones 0–4. Store release readiness is a separate remaining milestone. This file holds the data-integrity guarantees, the checks that have been run, and what remains before release; for behaviour see `features.md`, for structure `architecture.md`, and for history `changelog.md`.

## Data integrity

- SQLite uses foreign keys and transactional writes. Restore parses and validates records before transactionally replacing rows. Duplicate IDs or missing references roll back the replacement.
- Backup JSON embeds cover bytes under portable keys. Restore rejects external/path-traversal keys and stages fresh files, preserving existing data on failure.
- Past finishes contribute only to completion counts. Year-only, month-only, and unknown values stay at their original precision.
- Manual progress updates and corrections never generate sessions, time, calendar intensity, or streaks.
- Backdated sessions cannot rewind current progress. Edition edits cannot make existing pages or pins invalid.
- Inputs and notes survive validation errors, backgrounding, and process death: unsaved new-book, session and pin input is written to a small device-local `drafts.json` (flushed when the app goes inactive, expired after 30 days) and offered back with a visible **Start fresh** option. Finish dates are never drafted, so a past date always has to be confirmed again. Drafts are not part of backups.
- Unreferenced cover files are deleted at startup, but only when no edition references their file name and they are at least a day old, so a cover picked in an unsaved form is never removed.
- Online search (Open Library) is optional and user-initiated; chosen metadata, including the cover, is saved locally with `metadataSource = open_library`. Page counts are medians across editions and language is prefilled only when unambiguous; the reader confirms both in the form. Many titles have no cover there (see `decisions.md` D17, D19).
- Shelf keepsakes are earned only by the number of finished books, never by streaks, pages, or time; they do not create or imply reading activity.

## Verification

See the final verification notes below for execution results. Tests cover partial-date validation, history/activity separation, session validation, progress correction, cascade removal, atomic restore failures, backup cover portability, database reopen, and large-text layouts.

## Remaining before release

- Run the generated iOS project on macOS/Xcode and test iOS image import, file export/restore, sharing, back navigation, and accessibility. Linux cannot compile an iOS application.
- Profile a 500-book library on a chosen midrange physical Android device. Emulator timings do not establish physical-device performance.
- Have a new reader try adding a past book, updating a page, and finding a pin without coaching. The visual direction has implementation checks, not user usability validation.
- Exercise TalkBack/VoiceOver, reduced motion, maximum platform text settings, and interrupted background/process lifecycle behavior on real devices.
- Choose the permanent bundle identifier (`tool/set_bundle_id.sh`), create the Android upload key and iOS signing team, publish the privacy policy, and complete store listings. See `release.md`, `privacy-policy.md`, and `store-privacy.md`.
- Final icon review and store-size screenshots from a seeded build.
- Cover paths are stored as absolute paths. If iOS relocates the app container (for example restoring a device backup to a new device), covers would need re-resolving against the current documents directory; this has not been observed here and needs checking on iOS.
- Open product question: Google Books as a cover fallback (`decisions.md` D19), and whether keepsakes count only in-app finishes (D23).
- Custom shelves, ratings, editable history, and more advanced statistics are follow-ups. No cloud service or sync queue is present.

## Executed checks — 6 October 2026

- Flutter 3.47.6 / Dart 3.13.5; resolved, pinned dependencies.
- Android debug APK builds successfully (minimum Android API 24; target API 36).
- 12 domain, repository, and widget tests pass, including 360px phone layouts at 200% text size.
- Android emulator integration test passes: Library → Reading → update page → add pin → Journal history → add a past book with year-only precision. Confirms history has the exact `2019` value and the session count stays unchanged.
- The integration test exposed and drove fixes for confirmation snackbars obscuring subsequent actions. Long-title generated covers and a large-text Journal control overflow were also corrected.
- iOS project targets iOS 15.0; compilation and native flows remain unverified locally because this host is Linux. The macOS CI job is configured but has not been run here.
- Screenshots under `docs/screenshots` were first captured from the demo entry point; Library, Reading, and Journal were re-captured on 2026-10-06 from a seeded development library (`lib/dev_seed.dart`), so they show sample data, not a real reader's library.
- Android native image sharing was exercised: a locally generated shelf PNG appeared in the system share sheet. No recipient was chosen and no image was sent.
- Final analyzer run reports no issues. Generated screenshots include Library, Reading, Journal, and the native share preview.

## Executed checks — follow-up pass (6 October 2026)

- 29 tests pass, adding: schema-v1 fixture and data-preserving upgrade test (`drift_schemas/`, `test/migration_test.dart`), cover garbage collection, draft persistence across a new store instance, Open Library parsing/errors/cover validation against a local HTTP server, and widget flows for online search, offline fallback, and draft restore.
- Schema migrations now use Drift's step-by-step helper. A schema change without a new version, dump, and step fails `migration_test.dart`; a missing step throws and never deletes data. To add version 2: bump `schemaVersion`, `dart run drift_dev schema dump lib/core/storage/database.dart drift_schemas/`, regenerate steps and test helpers (commands in README), and add a `from1To2` step.
- Android release build: fails with a clear message without `android/key.properties`; with a throwaway key the APK is signed by that key; the manifest requests only `INTERNET`. The unreachable-network path was exercised with fakes and a closed local server, not a real Open Library request.
- `tool/set_bundle_id.sh` was checked on a copy of the project files: only the identifiers changed.

## Executed checks — shelf, search, and docs pass (6 October 2026)

- 49 unit and widget tests pass (was 29), adding diacritic-insensitive search and ranking, filter-hidden and no-match empty states, shelf packing, keepsake thresholds and semantics, cover preview and no-cover messages, and the any-word search fallback. The emulator integration test passes against the redesigned Library screen.
- Real Open Library responses were checked for field names, accent and word-order tolerance, lack of typo tolerance, and missing covers for Romanian titles.
- Shelf, search results, the no-cover case, and the Reading and Journal tabs were reviewed on the emulator with a 40+ book seeded library. A release APK (debug-signed) was built and installed there.
- Phone-size testing (360 x 800 logical) found and fixed three layout defects (see `design-system.md`).

## Executed checks — Journal pass (6 October 2026)

- 57 unit and widget tests pass, run eight times in a row (one earlier flaky test was fixed). New tests cover month, year, and undated grouping and the Months, Days, and History views.
- The new Journal was reviewed on the emulator with a seeded library: All time year rows, a year's month tiles, the year-only tile, the Date unknown sheet, and the Days view with no sessions. Not yet checked on a real phone or at maximum text size.
