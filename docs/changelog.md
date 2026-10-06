# Changelog

What changed, newest first. One entry per working session or meaningful change. Add entries with `update-docs`; do not rewrite history.

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
