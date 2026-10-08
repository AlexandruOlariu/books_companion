# Testing and verification

## Run

```sh
./tool/flutterw analyze
dart format --output=none --set-exit-if-changed lib test integration_test
./tool/flutterw test                                            # 255 unit and widget tests
./tool/flutterw test integration_test/core_flows_test.dart -d <android-device>
./tool/flutterw build apk --debug
./tool/check_docs.sh                                            # docs cover the code
```

`dart format` is run with the SDK's `dart` (`flutter format` no longer exists). The integration test installs a test build, so it **wipes the app's data on the device**; re-run `lib/dev_seed.dart` afterwards if a seeded library is wanted.

Latest results (2026-10-08): 255 unit and widget tests pass, including nine Android update tests; debug APK compiles with the native update channel. Analyzer and final format checks are clean; release-script checks pass and the changed workflow YAML parses. Server tests (72), the emulator integration test and the release builds were last run on 2026-10-07 and not repeated for these changes (neither touches the server or the integration flow; the integration flow itself was not re-run after the schema change); a debug APK built and ran on the emulator; the release APK and a release APK (debug-signed) build.

## Test inventory

| File | Tests | Covers |
| --- | --- | --- |
| `test/domain_test.dart` | 3 | partial dates keep only what the reader knows; retroactive completions never become activity; sessions need coherent page ranges or a known time |
| `test/repository_test.dart` | 19 | page corrections, batch history and sessions stay independent; full export restores history, notes, and cover bytes on a clean database; malformed restore and foreign-key failure roll back everything; backup rejects path references; delete cascades; editing an edition cannot invalidate positions or pins; the database survives close and reopen at the current version; cover source: kept and exported, only Open Library cover addresses accepted (saving and restoring), covers still to fetch and attaching one, a backup from before cover sources restores; ratings: rate, change and clear, only 1 to 5 and only after a finish, kept across a reread and an edit, history and activity untouched, export and restore round trip, a backup without ratings restores unrated, a bad rating refuses the restore |
| `test/app_updates_test.dart` | 9 | newer build only; reject foreign app/schema/version/download address; six-hour automatic throttle and manual bypass; offline retry preserving a known update; dismissal until a different release; explicit download and browser failure; overlapping checks and safe disposal; notice/Settings download actions; 360 px at 200% text |
| `test/widget_test.dart` | 2 | update a page without creating activity; layouts at 360 px and 200% text |
| `test/library_title_test.dart` | 2 | the Library heading: a first name (trimmed) makes it theirs, no name keeps "My Library" |
| `test/search_test.dart` | 7 | diacritics, word order, ranking, a filter hiding a match (phone-sized screen), search miss, clear button |
| `test/shelf_test.dart` | 10 | keepsake thresholds, row packing (no overflow, order, tap sizes, evenly spread keepsakes), keepsake semantics, hidden under a filter, a status seal on Reading and Wishlist books and none on a finished one, and a tap pulling the book out and then opening its details (and back) |
| `test/lookup_test.dart` | 7 | Open Library parsing, ISBN query, misspelling fallback (stop words left out), failures, real-image check, against a local HTTP server |
| `test/server_lookup_test.dart` | 3 | search through the server: only `{q}` in a POST body, approximate flag, cover URLs built on the device; fallback to Open Library on 502, 429, 404, a bad body, and an unreachable server |
| `test/online_and_draft_widget_test.dart` | 6 | search to filled form, no-cover message, cover preview, offline fallback, book draft restore, pin draft restore and clear |
| `test/journal_buckets_test.dart` | 4 | months hold only remembered months in order; a year-only finish is never in a month; years newest first with undated apart; every finish counted exactly once |
| `test/journal_widget_test.dart` | 4 | All time year rows; a year's month tiles and a month sheet that excludes year-only books; Days explains itself and past finishes do not count; History groups |
| `test/draft_and_cover_test.dart` | 6 | cover garbage collection rules, draft persistence, expiry, damaged file, blank input |
| `test/migration_test.dart` | 6 | the frozen v1 and v2 schemas upgrade to the current one; the current schema equals the frozen v4 dump; a seeded v3 library upgrades with every book unrated; a v1 library survives the upgrade with null series; a v2 library keeps its series and cover path and gets no invented cover source |
| `test/sorting_test.dart` | 10 | title and author keys (articles, diacritics, surname formats), alphabetical and author sort, series grouping and order, unnumbered books, same-named standalone, stable ties, saved-name fallback |
| `test/series_repository_test.dart` | 6 | series saved, loaded, edited, cleared; number rules; search by series; backup round trip; a pre-series backup restores; an invalid series is rejected |
| `test/series_and_sort_widget_test.dart` | 7 | one Finished choice; Add another keeps the series and moves the number on; series quick picks; a number without a series is explained; default title sort with series together; author sort and the saved choice; search ranking with the sort breaking ties |
| `test/preferences_test.dart` | 4 | preferences survive a restart, later writes win, a damaged file is ignored, the memory store |
| `test/friends_models_test.dart` | 7 | what is published: only title, author, status, and finish dates; every date precision kept; a finished book without a finish sent as unknown; wishlist carries none and a re-read keeps earlier ones; titles clipped to the server limit; an empty library publishes nothing |
| `test/http_friends_api_test.dart` | 30 | the real client against a local HTTP server that mimics the API: register and sign-in store the session; an expired token is refreshed once and retried; concurrent calls share one refresh; a refused refresh ends the session; losing the connection or a server error never signs the reader out; error messages (server detail, 429, 422 by field); username lookup; contacts sent in batches of 1000 with the region; the exact shelf fields and date splitting on publish; a shelf parsed back with precision intact; over-limit libraries refused before sending; library: signed-in known on the device, account id, nothing saved is null, revision and library read back, a save sends only `base_revision` and `data`, 409 is a conflict, 413 is explained, an expired token is refreshed and the save retried, losing the connection never signs out |
| `test/friends_widget_test.dart` | 23 | Settings entry (hidden in the demo); the sign-in panel states what is sent; create account, missing fields, wrong password; sharing asks first and sends only books and dates, cancel sends nothing, an empty library, stop sharing; accept a request; find by username sends a request; contacts explained before any permission, refusal explained, existing friends not re-offered; phone number and the findable switch; sign out; delete account needs the password; a friend's shelf shows dates as shared, never touches the reader's own library, nothing-shared state, remove and block; 200% text on a phone-height view. Uses `test/support/fake_friends_api.dart` |
| `test/recommendations_test.dart` | 20 | the suggestion rules: nothing from an empty or unrelated library; next in a series (highest finished number, gaps, Wishlist book, being read, unnumbered); Wishlist by finished authors ranked by amount read, Favorite pin and reread; dismissals; the cap; ratings: 1 or 2 stars cancel a series follow-up and do not count for an author, 4 or 5 stars count as loved and rank higher, the rating is quoted; friends' books skip anything already owned in any status, rank by friends then author, count a friend once, summarise many, ignore blanks, match across title and name variants |
| `test/system_inset_test.dart` | 1 | at 360 x 800 with a 48 px system navigation bar drawn over the app: scrolled to the end, the book page's **Remove from library** sits above the bar (fails without the fix by 10 px) |
| `test/rating_widget_test.dart` | 8 | at 360 x 800: a finished book is rated, changed and cleared on its page; a Wishlist book has no stars; a book being read again keeps and shows its rating; stars are 48 px targets that fit; each star announces itself with a tap action; the add form rates a book added as Finished, leaves it empty, and drops a chosen rating when the choice becomes Wishlist |
| `test/recommendations_widget_test.dart` | 8 | at 360 x 800: no section for an empty library; a short shelf says what makes an idea appear; series card opens the add form prefilled and adds nothing; Not interested hides, undoes, and survives a relaunch; friends' finished books listed without those already owned; a friend added after the tab was first seen shows up on the next visit; a friends outage leaves the rest; the demo never reads friends |
| `test/account_rules_test.dart` | 4 | name needed and limited to 60, username 3 to 30 of letters, digits, `_` and `.` (case and surrounding spaces ignored), new password 10 to 128 with a matching repeat |
| `test/account_screen_test.dart` | 7 | the demo has no account entry; current details shown and Save off until a change; only changed fields are sent; a taken username is explained and a username goes out lower-case; empty name and bad username refused before sending; password change needs the right current password and empties the fields; short or mismatched new passwords refused first. Uses the fake friends API |
| `test/sync_engine_test.dart` | 21 | the sync decisions against an in-memory server with the real revision rule and a real repository: first save (including the private note and session), cover files never sent but their source is, an empty phone downloads, a download keeps local cover files, both sides having books is a conflict with both counts and nothing changed, keeping either side, nothing changed sends nothing, a change is saved on the last revision, a newer account copy is downloaded or becomes a conflict when the phone has unsaved changes, someone saving in between becomes a conflict, an account that lost its library is refilled, a change made while saving stays marked, offline keeps changes waiting, a lost session, no account, an unreadable account copy fails without touching the phone, a different account starts from scratch, covers fetched again after a download (and not counted as a change), a failed fetch is retried |
| `test/syncing_repository_test.dart` | 3 | every write is reported once and reads, exports and cover attachments are not; a failed write is not reported |
| `test/sync_widget_test.dart` | 8 | an account is required: the account page comes first, signing in opens the library and saves what was on the phone, a signed-in reader goes straight in; a change is saved shortly after (a burst is one save), offline changes are saved when the connection returns, the conflict dialog with both counts and both choices; the demo needs no account and saves nothing |
| `integration_test/core_flows_test.dart` | 1 | on an Android emulator: Library, Reading, update page, add pin, Journal history, add a past book with year-only precision; asserts the stored value is `2019` and the session count is unchanged |

### Server tests (`server/tests/`, pytest, 72 tests)

Run from `server/` with a Postgres test database (see `backend.md`); the suite builds the schema from the Alembic migrations and truncates between tests. CI runs it in the `server-tests` job. They are separate from the Flutter count above.

| File | Tests | Covers |
| --- | --- | --- |
| `server/tests/test_auth.py` | 8 | registration and validation, unique normalised email and username, login with identical answers for a wrong password and an unknown email, login rate limit, protected routes, refresh rotation and reuse revoking every session, logout |
| `server/tests/test_me.py` | 7 | profile edits, username conflict, the phone stored only as a hash, invalid numbers, discoverability needing a phone, password change signing out other devices, account deletion cascading |
| `server/tests/test_discovery.py` | 9 | exact username lookup only, nothing but id, username and display name exposed, opt-in contact matching, number formats, self and blocked excluded, the daily number budget, oversized lists, contacts not stored |
| `server/tests/test_friends.py` | 10 | request and accept, only the asked person can accept, asking back accepts, duplicates, decline and cancel, removal, blocking, privacy of the lists |
| `server/tests/test_shelf.py` | 9 | publish replaces, only accepted friends read it, unfriending or unpublishing hides it, private fields rejected, date precision rules, finishes versus status, future dates, limits, sign-in required |
| `server/tests/test_books.py` | 10 | book search without an account, result shape, ISBN query, any-word retry without stop words, no retry for one real word, a failed retry is not an error, 502 when Open Library is down and failures not cached, cache by normalised text, input validation, search text never stored, per-address rate limit |
| `server/tests/test_library.py` | 16 | nothing saved yet is 404; sign-in required; a save and read back including private notes; each save moves the revision on; a stale save is 409 and changes nothing; libraries are private to their owner; an unknown table, a malformed or missing table, and wrong version are 422 and do not echo the library; an oversized library is 413; saving is rate limited; deleting the account deletes the library |
| `server/tests/test_migrations.py` | 3 | models equal the migrations, health check, interactive docs off |
| `server/tests/conftest.py` | n/a | fixtures; refuses a test database whose name does not end in `_test` |

### Release scripts

`tool/test_release_scripts.sh` (7 checks, run by both workflows) covers `tool/next_release_version.sh`: no tags uses `pubspec.yaml`, the patch goes up from the newest tag, versions compare numerically (`1.10.0` after `1.9.0`), pre-release and non-version tags are ignored, a newer `pubspec.yaml` wins, and one equal to the newest tag is raised by one. The workflow itself has not been run on GitHub since it was changed.

## Conventions that avoid false failures

- Layout tests set `tester.view.physicalSize = Size(1080, 2400)` and `devicePixelRatio = 3` (360 x 800 logical) and scroll with `tester.drag`, because the default surface is wider and shorter than a phone.
- `Eyebrow` upper-cases its text; match `'1 BOOK ON THE SHELF'`, not `'1 book...'`.
- Books saved in the same millisecond are ordered by random UUID, so which book is first varies per run. Never tap a status by plain text such as `find.text('Wishlist')`; tap the chip (`find.widgetWithText(ChoiceChip, ...)`). This caused one flaky test.
- Generated covers contain the title as text, so `find.text(title)` can match covers as well as list rows; scope searches with `find.descendant` or count rows.
- To read the order of a list in a test, give it a tall screen (for example 4800 physical px high) and read `BookListTile.book` in order; a short screen builds only the first few rows.
- Lazy lists (`ListView`, slivers) do not build off-screen children; scroll with `dragUntilVisible` and `ensureVisible` before asserting or tapping.
- Demo books get new random ids per `createDemoRepository()`; reuse one repository across a simulated restart when a test keys on a book id.
- The Android emulator's current system image shows a stylus-handwriting tutorial the first time a text field is focused; dismiss it (Cancel) when driving the UI by hand.

## Verified in this environment

Android emulator (Pixel 9 Pro image, Android 16): the integration flow; online search with real Open Library results and cover download and save; shelf rendering with a seeded library of 40+ books; release APK signing with a throwaway key; the manifest requested only `INTERNET` at the time. Real Open Library responses were checked once for field names.

Account and library saving (2026-10-07), on the emulator against the real server (this machine behind `https://ai.duk-tech.com/books-api/`, with a throwaway account deleted afterwards): the v2 to v3 database upgrade kept all 51 books; with nobody signed in the app opened on the account page; creating an account opened the library and the server held exactly the 51 books (revision 1); after clearing the app's data and signing in again the conflict dialog appeared with both counts, "Use my account" downloaded the 51 books, and the one edition that had a cover source got its cover file again (70 KB, created seconds after the download) while the others, which never had a source, show generated covers; adding a book in the app reached the server within seconds (revision 2, 52 books); Settings showed "Saved to your account at <time>". Not exercised: a second real phone, real offline use with a waiting change on a device, a real library of several MB (only that a 6 MB body passes nginx's new 22 MB limit, answered 401 without a token), iOS.

Friends (2026-10-07), on the same emulator against the real server at `https://ai.duk-tech.com/books-api/`: create account, share a 51-book shelf, and delete the account, all from the UI. The server's database afterwards held exactly the allowed book fields (`id`, `title`, `author`, `status`, `finishes`) with year-precision finishes carrying no month or day, and zero users, shelves, and tokens after deletion. A scripted run of the real client (two accounts, request, accept, publish, read, a stranger seeing nothing) also passed against the public URL. The contacts permission and a real match were **not** exercised (no contacts on the emulator and no second device). Server tests are listed under "Server tests".

## Not verified (needs hardware or a Mac)

- Any native iOS flow (image import, file export and restore, sharing, back navigation, accessibility) and any run on an iOS simulator or device. Only the unsigned simulator *build* has been seen to pass, in CI (see below).
- Performance with 500 books on a midrange physical Android device (profile mode). Emulator timings do not count.
- Usability: a new reader adding a past book, updating a page, and finding a pin without coaching.
- TalkBack and VoiceOver, reduced motion, maximum platform text sizes, and background and process lifecycle on real devices.
- The Google Play and App Store submission flows.
- A real-phone run of the release APK. (A friend installed an earlier build, reported it functional, and reported the missing-cover behaviour that led to D17.)

## CI results

On 2026-10-06 both jobs of `.github/workflows/checks.yml` passed on GitHub Actions for commit `2f53858`: `analyze-and-test` (format, analyze, `flutter test`, `tool/check_docs.sh`, debug APK; 10 minutes) and `ios-build` (`flutter build ios --simulator --debug` on macOS; the UI showed 1 minute, which is short for an iOS build, so confirm in the job log that it really compiled). This also shows the docs check and the format check pass on a fresh checkout. The release workflow (`release.yml`) also passed: a manual run, then the `v0.1.0` tag, which published the first release.

## Direct Android update validation (2026-10-08)

255 unit/widget tests pass; the Android debug APK compiles. A local release APK smoke build (debug signing allowed) also compiles, and update metadata generation passes against its actual merged manifest; synthetic checks reject a mismatched build and a prerelease version. The emulator preview uses a fake update provider and no real account or library; the actual native installed-version channel was also exercised (0.1.1, build 1). It demonstrates the notice, dismissal and Settings UI, not a published update. Still to verify: the first signed GitHub workflow run with the fixed asset/manifest, live metadata fetch, browser APK download and a same-key update on a real phone preserving books. No live release was published during this work.
