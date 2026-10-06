# Testing and verification

## Run

```sh
./tool/flutterw analyze
dart format --output=none --set-exit-if-changed lib test integration_test
./tool/flutterw test                                            # 57 unit and widget tests
./tool/flutterw test integration_test/core_flows_test.dart -d <android-device>
./tool/flutterw build apk --debug
./tool/check_docs.sh                                            # docs cover the code
```

`dart format` is run with the SDK's `dart` (`flutter format` no longer exists). The integration test installs a test build, so it **wipes the app's data on the device**; re-run `lib/dev_seed.dart` afterwards if a seeded library is wanted.

Latest results (2026-10-06): analyzer clean; format clean; 57 unit and widget tests pass (the suite was run eight times in a row without a flaky failure); the emulator integration test passes; the debug APK and a release APK (debug-signed) build.

## Test inventory

| File | Tests | Covers |
| --- | --- | --- |
| `test/domain_test.dart` | 3 | partial dates keep only what the reader knows; retroactive completions never become activity; sessions need coherent page ranges or a known time |
| `test/repository_test.dart` | 7 | page corrections, batch history and sessions stay independent; full export restores history, notes, and cover bytes on a clean database; malformed restore and foreign-key failure roll back everything; backup rejects path references; delete cascades; editing an edition cannot invalidate positions or pins; the database survives close and reopen at v1 |
| `test/widget_test.dart` | 2 | update a page without creating activity; layouts at 360 px and 200% text |
| `test/search_test.dart` | 7 | diacritics, word order, ranking, a filter hiding a match (phone-sized screen), search miss, clear button |
| `test/shelf_test.dart` | 9 | keepsake thresholds, row packing (no overflow, order, tap sizes, evenly spread keepsakes), keepsake semantics, hidden under a filter |
| `test/lookup_test.dart` | 7 | Open Library parsing, ISBN query, misspelling fallback, failures, real-image check, against a local HTTP server |
| `test/online_and_draft_widget_test.dart` | 6 | search to filled form, no-cover message, cover preview, offline fallback, book draft restore, pin draft restore and clear |
| `test/journal_buckets_test.dart` | 4 | months hold only remembered months in order; a year-only finish is never in a month; years newest first with undated apart; every finish counted exactly once |
| `test/journal_widget_test.dart` | 4 | All time year rows; a year's month tiles and a month sheet that excludes year-only books; Days explains itself and past finishes do not count; History groups |
| `test/draft_and_cover_test.dart` | 6 | cover garbage collection rules, draft persistence, expiry, damaged file, blank input |
| `test/migration_test.dart` | 2 | schema equals the frozen v1 dump; a v1 library survives upgrade |
| `integration_test/core_flows_test.dart` | 1 | on an Android emulator: Library, Reading, update page, add pin, Journal history, add a past book with year-only precision; asserts the stored value is `2019` and the session count is unchanged |

## Conventions that avoid false failures

- Layout tests set `tester.view.physicalSize = Size(1080, 2400)` and `devicePixelRatio = 3` (360 x 800 logical) and scroll with `tester.drag`, because the default surface is wider and shorter than a phone.
- `Eyebrow` upper-cases its text; match `'1 BOOK ON THE SHELF'`, not `'1 book...'`.
- Books saved in the same millisecond are ordered by random UUID, so which book is first (and shown in the selected-book panel) varies per run. Never tap a status by plain text such as `find.text('Want to read')`; tap the chip (`find.widgetWithText(ChoiceChip, ...)`). This caused one flaky test.
- Generated covers contain the title as text, so `find.text(title)` can match covers as well as list rows; scope searches with `find.descendant` or count rows.
- Lazy lists (`ListView`, slivers) do not build off-screen children; scroll with `dragUntilVisible` and `ensureVisible` before asserting or tapping.
- Demo books get new random ids per `createDemoRepository()`; reuse one repository across a simulated restart when a test keys on a book id.
- The Android emulator's current system image shows a stylus-handwriting tutorial the first time a text field is focused; dismiss it (Cancel) when driving the UI by hand.

## Verified in this environment

Android emulator (Pixel 9 Pro image, Android 16): the integration flow; online search with real Open Library results and cover download and save; shelf rendering with a seeded library of 40+ books; release APK signing with a throwaway key; the manifest requests only `INTERNET`. Real Open Library responses were checked once for field names.

## Not verified (needs hardware or a Mac)

- Any native iOS flow (image import, file export and restore, sharing, back navigation, accessibility) and any run on an iOS simulator or device. Only the unsigned simulator *build* has been seen to pass, in CI (see below).
- Performance with 500 books on a midrange physical Android device (profile mode). Emulator timings do not count.
- Usability: a new reader adding a past book, updating a page, and finding a pin without coaching.
- TalkBack and VoiceOver, reduced motion, maximum platform text sizes, and background and process lifecycle on real devices.
- The Google Play and App Store submission flows.
- A real-phone run of the release APK. (A friend installed an earlier build, reported it functional, and reported the missing-cover behaviour that led to D17.)

## CI results

On 2026-10-06 both jobs of `.github/workflows/checks.yml` passed on GitHub Actions for commit `2f53858`: `analyze-and-test` (format, analyze, `flutter test`, `tool/check_docs.sh`, debug APK; 10 minutes) and `ios-build` (`flutter build ios --simulator --debug` on macOS; the UI showed 1 minute, which is short for an iOS build, so confirm in the job log that it really compiled). This also shows the docs check and the format check pass on a fresh checkout. The release workflow (`release.yml`) also passed: a manual run, then the `v0.1.0` tag, which published the first release.
