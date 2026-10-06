# Decision log

Why the POC is the way it is. Newest decisions are appended at the bottom of each section. Each entry says what was decided, why, and what it costs. When a decision is reversed, keep the entry and add a line saying so rather than deleting it.

Dates are 2026-10-06 unless stated (the whole POC was built in one working session).

## Product and data honesty

**D1. Local-first, no backend.** Everything is stored on the device. *Why:* the product is a private journal; infrastructure that is not needed is cost and risk. *Cost:* no sync, no cross-device library; the only copy is the device plus the reader's own backup files. *Amended 2026-10-07 by D35:* a backend now exists for accounts, friends and published shelves; the library itself is still local and the app does not use the server yet.

**D2. A date is a memory, not a timestamp (`PartialDate`).** Finish dates store a precision (`day`, `month`, `year`, `unknown`) together with a value that matches it. *Why:* a remembered year must never become January 1. Past finishes count towards books finished in that period but create no daily activity, streak, duration, or speed.

**D3. Only sessions create activity.** Page updates and corrections change position only. A backdated session cannot rewind progress. *Why:* two page updates say nothing about minutes; celebrating a correction would be dishonest. *Cost:* users who only update pages see 0 pages logged, which is intended.

**D4. Past books store one finish date, not a start date.** The plan left start dates optional. *Why:* start dates were rarely remembered and doubled the date UI. *Cost:* no reading durations from history. Revisit if wanted.

**D5. Rereading keeps every completion.** "Read again" sets the status back to Reading; finishing again adds a record. *Why:* history is a record of what happened.

**D6. Ratings, custom shelves, editing a recorded finish date, and multiple authors per book are not implemented.** Deferred to keep the first release small; the schema has no columns for them.

## Storage and safety

**D7. Drift over SQLite, behind a repository interface.** Screens never touch Drift. *Why:* testable domain rules, and a later remote implementation can slot in. No sync queue exists, deliberately.

**D8. Backup is one JSON file with cover bytes embedded.** Restore validates everything first, stages cover files under fresh names, and replaces the library in one transaction; any failure leaves the existing library unchanged. Restore replaces, never merges. *Why:* a half-restored library is worse than a refused one. *Cost:* large libraries make large files (limit 150 MB).

**D9. Android automatic backup is off.** *Why:* the explicit backup contains private notes; a silent cloud copy would contradict the privacy position.

**D10. Migrations are step-by-step with a frozen fixture.** `stepByStep()`, a v1 schema dump, and a test that fails if the schema drifts without a version bump. A missing step throws; it never drops data. *Why:* the library may be a person's only reading record.

**D11. Drafts live in a small JSON file, not the database.** Written after a short debounce and when the app goes inactive; expire after 30 days; removed on save or discard; excluded from backups; never kept for the finish-date choice. *Why:* they are throwaway, and putting them in SQLite would have forced a schema version for no benefit. Finish dates are excluded so a past date is always freshly confirmed.

**D12. Unreferenced covers are deleted at startup, conservatively.** Only files that no edition references (compared by file name, so a moved container cannot orphan live covers) and that are at least a day old. *Why:* a cover picked in a still-open form must never be removed.

**D13. Known risk, not fixed: cover paths are stored as absolute paths.** If iOS relocates the app container (for example restoring a device backup to a new phone), covers would break until re-resolved against the current documents directory. Not observed here; check on iOS.

## Online search

**D14. Online lookup is optional and user-initiated, via Open Library, using `dart:io`.** Runs only when the reader taps Search; sends only the typed text; saves everything locally; manual entry always works. *Why:* it needs no key, no account, and keeps the app usable offline. Dio was in the plan but is unnecessary for two GET requests.

**D15. Treat catalogue data as suggestions to confirm.** Page counts are medians across editions and the screen says so. Language is prefilled only when a work lists exactly one (a work's list covers every edition, e.g. *Dune* lists 13). The source is stored as `open_library`.

**D16. Cover images are accepted only if the bytes are JPEG or PNG.** An error page or a placeholder served with an image type is never stored. Failures are silent to the catalogue code but explained to the reader.

**D17. Say plainly when there is no cover.** Many titles, especially Romanian ones (e.g. *Enigma Otiliei*, *Cel mai iubit dintre pământeni*), have no cover in Open Library. Results show "no cover" before choosing, the form says so after, and the cover preview appears whenever a cover exists. *Why:* a reader reported "it does not fetch the cover" and the app had given no hint that none existed.

**D18. Misspelled queries fall back to an any-word search, clearly labelled.** Open Library handles diacritics and word order but has no typo tolerance ("freida mcfaden housemaid" returns nothing). Only for two or more words of 3+ letters, never for ISBNs or single words, and a failed retry is never an error.

**D19. OPEN: Google Books as a cover and metadata fallback.** Would fix missing Romanian covers. Not built because it sends the typed text and IP address to a second third-party and requires updating `privacy-policy.md` and `store-privacy.md`. Needs an explicit product decision.

## Library UX

**D20. Library search is local, diacritic-insensitive, order-free, ranked, and honest about filters.** A reader searched "freida" with the Finished filter on and saw 0 results with "Add your first book". Search now ignores diacritics and word order, ranks exact and leading matches first, and when a status or year filter hides matches the empty state says how many and offers to clear the filter. A search miss never suggests adding a first book.

**D21. Status filters wrap instead of scrolling.** On a 360 px phone the fourth filter was off-screen. Wrapping beats horizontal scroll for four short chips.

**D22. The shelf is a bookcase, not a grid of cards.** Rows of spines on planks, face-out covers for books being read, varied sizes and colours. *Why:* the plan calls the shelf the product's identity; three equal cards per row did not read as a shelf. Spines are never narrower than 48 px (the tap-target minimum), which makes them chunkier than real spines.

**D23. Keepsakes are earned only by finished-book count.** Seven objects at 1, 3, 5, 8, 12, 18, 25 books, with a line saying "never by streaks". *Why:* rewards must not pressure the reader or invent activity (honesty rule 4). Past finishes count because they are books actually finished. If only in-app finishes should count, change the count in one place (`finishedCount` in `library_screen.dart`). Keepsakes hide while a filter or search narrows the shelf. Placement is automatic (evenly spread); user placement is a possible follow-up.

## Release and tooling

**D24. A release build fails without a signing key.** `android/key.properties` is required; `READING_LIBRARY_DEBUG_SIGNING=1` allows a local non-uploadable build. *Why:* silently shipping debug-signed builds is a trap. The `INTERNET` permission is in the main manifest because online search needs it in release builds.

**D25. Bundle identifiers are placeholders with a script to set them.** `tool/set_bundle_id.sh` changes the Android `applicationId` and the iOS identifier together and leaves the Kotlin namespace (a code package) alone. The identifier cannot be changed after the first store upload.

**D26. Development-only entry points are separate.** `lib/demo.dart` (in-memory) and `lib/dev_seed.dart` (a device's real library, with real covers) never run in release builds; `lib/main.dart` never seeds anything.

**D27. Tests run at phone size.** The default 800 x 600 test surface hid real layout bugs (see `design-system.md`). Widget tests that care about layout set a 360 x 800 logical surface and scroll like a reader.

**D28. Documentation is part of the work and is kept current mechanically.** `docs/` describes the POC so it can be rebuilt. A project skill (`update-docs`), a `CLAUDE.md` rule, `tool/check_docs.sh`, and a stop hook keep it in sync. See `README.md` in this folder.

**D29. The Journal's main view shows finished books by month, not a session calendar.** A reader found the calendar unintuitive: the library is mostly past finishes, which by design never colour a day, so the grid was empty with one ring and a legend that did not explain why. The Journal now defaults to **Months** (one row per year for All time; twelve month tiles for a year, with covers), a separate wide tile for books remembered only as a year (never placed in a month), and a **Date unknown** row. The session calendar is kept as **Days**, with an explanation, an empty-state message, a dot instead of a ring for exact-day finishes, and clearer legend text. **History** is unchanged. *Why:* the question people ask is "what did I read, and when", which finished books answer; activity answers a different question and should say so. *Cost:* three views instead of two; the calendar is no longer the first thing seen.

**D30. APKs are published by CI as GitHub Releases, never committed.** A first push carried a 60 MB APK (GitHub warns above 50 MB), so `dist/`, `*.apk`, and `*.aab` are git-ignored and a tag-triggered workflow builds and publishes. It runs the full checks first, refuses a tag that disagrees with `pubspec.yaml`, and takes the build number from the run number so updates are always accepted. Signing uses repository secrets when present; otherwise it publishes a debug-signed **pre-release** with a warning, because CI would otherwise mint a different debug key every run and early testers could not update in place. *Cost:* secrets must be set up once and the key backed up by hand; the repository being private limits who can download. Android only; iOS needs a Mac and Apple signing. Verified end to end on 2026-10-06 (manual run, then `v0.1.0`). The signing key is generated on the development machine (`~/.config/reading-library-signing/`) and mirrored into repository secrets.

**D31. One "Finished" choice when adding a book; "Read in the past" removed.** The two options led to the same screen and the same date choice; the only difference was an internal flag that changed a Journal label. A reader found it confusing. Now a book added directly as Finished is always recorded as a remembered finish (`entered_past`); a finish from the Reading tab is `tracked_in_app`. Existing records are unchanged, and an old saved draft that said "past" is read as Finished. *Cost:* a book added as Finished today is labelled "Remembered" even if it was finished yesterday; it was not tracked in the app, so that is accurate.

**D32. Series are a name and a number on the book (schema version 2).** Optional, free text, entered in the add and edit form, with quick-pick chips for existing series and a next-number suggestion; "Add another" keeps the series and moves the number on. *Why:* the reader wanted a series shelved together; Open Library search results do not give reliable series data, so manual entry is the source of truth. *Cost:* no automatic detection, no separate series records (renaming means editing each book), whole-number positions only (no 2.5). This was the first real migration (`from1To2`, additive nullable columns), chosen so existing data is never touched. The backup format stays at version 1 because the change is additive.

**D33. The shelf is sorted, by Title by default, with series kept together.** Title ignores case, diacritics, and a leading English article; Author files by the first author's surname (a heuristic: last word, or the part before a comma; compound surnames such as "Garcia Marquez" file under the last word). A series sits at the position of its name, in number order. The choice is remembered in a small preferences file rather than the database or backups (it is a device preference, not library data). Search results rank by relevance and use the sort only to break ties. Recently added remains available. *Cost:* the author heuristic can misfile unusual names; a per-book sort name would fix it if it matters.

**D34. "Want to read" is now called "Wishlist".** A pure rename of the label: same status, same behaviour, stored value still `want_to_read`, so no migration and old backups restore unchanged. *Why:* the owner's word for it. A separate wishlist for books not yet owned was offered and declined, so nothing here models ownership: a Wishlist book still sits on the shelf. If a distinction between "own it, will read" and "want to buy" is wanted later, it needs a new status and a schema change. The frozen `product-plan.md` still says "Want to read".


## Backend and friends

**D35. A small backend for accounts, friends and published shelves; it supersedes the "no backend" part of D1 for the social features only (2026-10-07).** The owner chose a server over device-to-device sharing: NFC cannot move data between two phones any more (Android Beam was removed in Android 10, and iOS apps can only read and write tags), and a hosted service also gives phone search and contact matching, which sharing cannot. Stack: Python (FastAPI) and PostgreSQL in Docker on the owner's host, behind the existing nginx at `https://ai.duk-tech.com/books-api/`; classic email and password login, no Google or Facebook. See `backend.md`. *What stays true:* the library, notes, pins and sessions remain on the device; the server only ever receives what a reader explicitly publishes (titles, authors, status, finish dates with their precision), and rejects any other field. A friend's shelf never feeds the reader's own statistics or keepsakes. *Choices inside it:* discovery is exact username or exact phone only (no prefix search, so the user base cannot be listed); phone numbers are stored only as an HMAC with a server-side pepper and finding someone by phone is opt-in; contact sync sends raw numbers over HTTPS and the server keeps none (hashing on the phone would be reversible because numbers are guessable); friendship needs acceptance, and a block hides both people from each other. *Cost:* the app is no longer purely local once a client uses this (privacy policy and store declarations must change then, and are not changed yet because no client exists); there is now infrastructure to run and back up (including the pepper); phone numbers and emails are unverified for lack of an SMS provider and a mailer, so there is no password reset yet. The app must keep working fully without an account.
