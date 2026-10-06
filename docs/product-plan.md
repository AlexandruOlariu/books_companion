# Reading Library — Mobile App Plan

## 1. Product summary

A mobile-only reading journal built with Flutter for Android and iOS. The app helps a reader keep a beautiful visual library, record books read in the past without corrupting dates or statistics, track current reading, and remember thoughts attached to pages.

The first release is a **local-first app with no application backend, account system, or cloud dependency**. A user's books, reading history, activity, pins, preferences, and cover files are stored on the device. Online book lookup may be used as an optional metadata source, but every selected result is saved locally and the library remains usable offline.

### Product principles

1. **Adding a book is not the same as reading a book.**
2. **Reading history is not the same as reading activity.**
3. **Never invent dates or activity to fill gaps in a user's memory.**
4. **The visual bookshelf is the home screen and the product's identity.**
5. **Personal notes stay private on the device by default.**
6. **Keep the first release small and avoid infrastructure that is not needed.**

## 2. First-release scope

### Included

- Flutter app for Android and iOS; phone-first layouts.
- On-device SQLite persistence.
- Visual library with `Reading`, `Want to Read`, and `Finished` groupings.
- Add books manually and optionally search online metadata by title, author, or ISBN.
- Save selected books, editions, and cover images locally.
- Record a past finish using exact day, month, year, or unknown precision.
- Batch-friendly history entry so users can add several previously read books in one flow.
- Currently reading status and manual page-progress updates.
- Optional reading sessions with pages and duration.
- Private pins/notes attached to a page and/or percentage of the book.
- Yearly/all-time book and page summaries, activity calendar, and book details.
- Local export/restore file for a user's data.
- Share a finished-book or yearly-shelf image using the device's native share sheet, generated on-device.

### Not included in the first release

- Sign-in, cloud sync, social profiles, friends, comments, public libraries, or shared pins.
- A web app, admin panel, or custom backend.
- Push notifications, subscriptions, ads, or payments.
- ISBN camera scanning (can follow once core book entry feels good).
- Automatic reading detection or fabricated daily activity for retroactive books.

These are product follow-ups, not assumptions that they will never be built. If sync is added later, the app can add a remote repository behind the existing local data layer.

## 3. Main navigation

Use three labeled bottom destinations:

- **Library** — the home screen and visual shelves.
- **Reading** — current books and quick progress updates.
- **Journal** — reading history, monthly calendar, and statistics.

Expose **Add book** as a visible labeled action on Library. Put the local profile and settings behind a recognizable top-bar avatar/settings button. Keep export/restore there. The app does not require an account or onboarding form to reach the library.

Each screen has one visually dominant primary action. Secondary actions remain visible where useful, and less frequent actions go in a labeled menu. Gestures may accelerate an action, but no core feature depends on discovering a gesture.

## 4. Core user flows

### 4.1 Add a book

1. Search by title, author, or ISBN, or choose **Add manually**.
2. Pick the correct edition when results contain multiple editions.
3. Check title, author, page count, language, and cover.
4. Choose one action: `Reading now`, `Want to read`, `Finished`, or `Read in the past`.
5. Save the book and user-specific reading record locally.

If online lookup is unavailable or finds no match, manual entry must remain straightforward. A generated spine using the title, author, and a palette color should keep the shelf attractive when no cover is available. Users may select an image from their device as a cover.

### 4.2 Add books read in the past

Provide a quick-entry mode that stays open after each save:

`Search / choose book → choose when read → Add another`

For each past book, the user chooses the best-known finish date precision:

- **Day:** a specific calendar date.
- **Month:** a year and month, with no invented day.
- **Year:** a year, with no invented month or day.
- **Unknown:** known to have been read, but date not remembered.

The date precision is part of the data model, not just a UI hint. Do not store January 1 as a fake date for a year-only record. A historical record with month or year precision contributes to book-completion counts for that known period, but does not create daily activity, a streak, reading duration, or a reading speed.

The first release should support a simple past-finished record. If the user remembers a full reading interval, optional start date and precision can be recorded too; the finish date remains independently precise.

### 4.3 Track current reading

- Set a book to `Reading`.
- Update the current page quickly.
- Optionally record a session with start page, end page, and duration.
- Mark the book finished and choose the actual finish date precision.

Manual page updates should not automatically be treated as timed sessions. A user can log progress without claiming to know the minutes spent reading.

### 4.4 Add a pin

A pin can include:

- Type: `Thought`, `Favorite`, `Quote`, `Question`, or `Idea`.
- User-entered text.
- Page number, percentage, or both.
- Created timestamp.

Pins are private local notes in this release. Do not show quotes from book metadata or create notes automatically.

### 4.5 Share

Generate share images on the device, using locally stored cover art and book details. Start with a finished-book card and yearly shelf image. Sharing uses the Android/iOS share sheet; no server upload is required. The user explicitly chooses when to share.

## 5. UI direction — a personal reading room in your pocket

### 5.1 Required product qualities

The interface must be distinctive, immediately understandable, and visually attractive. Treat this as a first-release requirement. Its identity comes from physical-looking miniature books, a quiet editorial layout, and interactions that feel like handling a personal collection.

The proposed visual direction is warm paper, dark ink, generous spacing, fine shelf lines, and restrained tactile depth. The covers provide most of the color. This is a concrete starting direction to validate with a visual prototype, not a user-approved final mockup.

### 5.2 The signature Library screen

Top to bottom:

1. A short title such as **My library**, with an unobtrusive settings/profile button.
2. A visible year selector: **All time / 2026 / 2025 / ...**. A picker supports older years without endless horizontal scrolling.
3. A compact status filter: **All / Reading / Finished / Want to read**.
4. The bookshelf, occupying most of the screen.
5. A visible **Add book** action within easy thumb reach.
6. The three-item bottom navigation.

A small summary below the year selector can read **18 books finished**; tapping it opens the corresponding Journal period. Specify that the year filter refers to completion year: books with unknown completion dates remain available in All time. Reading and Want to read views use All time and hide the completion-year filter, since unfinished books have no completion year.

Render shelves as vertically scrolling rows with subtle supporting lines and soft contact shadows. Mix recognizable front covers with spines: a selected book reveals its cover and readable title in a reserved preview area. Keep stable shelf positions as focus changes. Do not rearrange all books on every tap.

The current book can carry a slim bookmark ribbon indicating progress, accompanied by a readable page/progress label in its preview. Pin counts may appear when a book is selected; avoid decorating every spine with badges.

Offer an explicit **Shelf / List** view switch. The list shows cover thumbnails, titles, authors, and status and shares the same filters and selection. It is useful for large libraries, precise lookup, and larger text settings.

### 5.3 Miniature book treatment

- Preserve real cover artwork with an aspect-preserving fit; never crop away the title to fill a generic card.
- Suggest depth with a spine edge, a narrow page block, and a contact shadow.
- Derive a restrained spine palette from the cover, but keep app controls on stable theme colors.
- Use bounded width variation based on page count; never make a short book an untappable sliver.
- Generate an attractive typographic cover/spine when artwork is missing. Show the title and author, with deliberate color choices and a small decorative rule.
- Generated spines approximate the book; do not claim they reproduce the actual physical spine.
- Use Flutter painting, clipping, and transforms. Cache thumbnails and avoid continuous animation.
- On tap, lift the book slightly and reveal its detail view through a short shared-cover transition.

### 5.4 Reading screen — the daily action

Give each current book a clear cover, title, and progress. With several current books, use a vertical list with one expanded book; do not hide them in a swipe-only carousel.

Primary action: **Update page**. Open a compact sheet with the numeric keypad, current page prefilled, the total page count when known, and **Save**. A numeric field is the primary control; a slider is optional because exact page numbers matter.

Secondary actions: **Add pin**, **Log session**, and **Finish book**. Optional time/duration fields are collapsed until requested. After saving, confirm the result and offer Undo where the action can be safely reversed. Invalid values get an inline explanation without clearing typed input.

A progress correction must be distinguishable from reading activity. Never celebrate a page correction as pages read today.

### 5.5 Book details — one clear hierarchy

Show the cover, title, author, status, and the main next action first. Place **Pins**, **History**, and **Details** in clearly labeled sections below. Let the user edit edition/page count/cover from Details. Keep destructive actions away from the main reading action.

Pins use a restrained paper-note treatment with a visible page marker and type label. Text remains easy to scan. Type is optional in the composer, defaulting to Thought. Do not require selecting a category before writing.

### 5.6 History entry — dates without friction

Use the prompt **When did you finish it?** with four explicit choices:

- **Exact date** — date picker.
- **Month and year** — month/year picker.
- **Year only** — year picker.
- **I don't remember** — no date input.

An exact-date picker may open on today, but saving requires selecting/confirming that precision. Do not automatically assign today when adding a past book.

After saving, show the cover and a short confirmation such as **Dune added to 2019**, followed by **Add another book**. Keep the previous precision/year available as a visible suggestion, and require confirmation for each new book. Avoid silently applying a batch date.

### 5.7 Journal — a visual reading memory

Use an editorial heading for the selected year and a short summary with explicit labels such as **Books finished** and **Pages logged**. Allow switching between a monthly calendar and a history list.

Completed books appear with cover thumbnails in the history list. Exact-day completions can have a separately labeled marker in the calendar, but must never contribute to reading-activity intensity. Month-only records appear in a monthly section; year-only records appear in **Month unknown** within the year; undated records appear in an all-time **Date unknown** section.

Keep the calendar comfortable to read on a phone: display one month with a legend and tappable day cells. Show daily details in a sheet. Place advanced statistics below the first screenful so the calendar and books remain prominent.

### 5.8 Starting design tokens

These are proposed theme values to test together in a prototype. Validate contrast for actual text/control combinations during implementation.

| Token | Starting value / rule |
| --- | --- |
| Paper background | `#F7F3EB` |
| Surface | `#FFFCF6` |
| Primary ink | `#242B28` |
| Secondary ink | `#5E655F` |
| Primary accent | Deep forest `#28564B` |
| Decorative accent | Muted terracotta `#B66750`; use sparingly |
| Typography | One expressive serif for large editorial headings; one highly readable sans serif for controls and body text |
| Font delivery | Bundle licensed font assets for reliable offline rendering |
| Body text | Start at 16 logical pixels and honor system text scaling |
| Spacing | Base scale of 4, 8, 12, 16, 24, and 32 logical pixels |
| Controls | Moderate corner radii; consistent dimensions across features |
| Tap targets | Product minimum of 48 x 48 logical pixels; no overlapping hit areas |
| Shadows | Soft, localized to books and temporary floating surfaces |

Use centralized theme tokens and shared controls. Cover colors must not change navigation colors or reduce label contrast. Start with one polished light theme; a dark theme can follow with separately validated colors.

### 5.9 Motion and feedback

Use animation to explain changes:

- Selecting a book: subtle lift and cover transition, approximately 180–240 ms.
- Saving progress: a brief bookmark/progress change, approximately 150–220 ms.
- Finishing a book: a short placement animation on the Finished shelf, approximately 300–450 ms, followed by a calm confirmation.
- Switching years: a short content transition that preserves scroll behavior sensibly.

These durations are design targets, not performance guarantees. Save data independently of animation completion; input must remain responsive. Respect reduced-motion preferences with immediate state changes or simple fades. Haptic feedback is optional and limited to meaningful confirmations. No background animation loop is needed.

### 5.10 Empty states and first use

Open directly to an attractive empty shelf with **Add your first book** and a secondary **Add books I've already read** action. Explain the app through those actions. Do not request a name, account, permissions, or preferences before the user can begin.

Request image access only when choosing a cover. If online search fails, preserve the search text and expose manual entry. After saving the first book, the shelf should already look like the intended product.

### 5.11 Usability and performance checks

- Core actions have visible text labels and work without gesture discovery.
- A current book's page update is reachable from Reading with one action to open the input sheet.
- Keyboard appearance does not hide the save button or active input.
- At large system text sizes, allow content to reflow; the list presentation remains fully usable.
- Screen readers receive a book's title, author, status, and available actions. Decorative page edges and shadows are excluded from semantics.
- Support platform back navigation and safe areas consistently.
- Draft notes and in-progress input survive incidental sheet/background interruptions where feasible; dismissing nonempty input must not silently lose it.
- Profile scrolling with 500 saved books on a selected midrange Android device in profile mode. Lazy-build rows and size images to their display use. Target smooth scrolling at the device's supported refresh rate and investigate measured frame overruns.
- Check an empty shelf, one book, missing covers, long titles, large text, unknown page counts, and a large collection.

### 5.12 Design validation before broad implementation

Build a Flutter visual prototype of three representative screens first: Library with mixed book covers/spines, Reading with the page-update sheet, and Journal with a month and partial-date history. Use representative sample data isolated from real user records.

Evaluate two things independently: whether the shelf has a recognizable visual identity, and whether a new user can add a past book, update a page, and find a pin without being coached. Refine the same direction based on the result before applying it across the app.

Do not treat a static mockup as proof that scrolling, accessibility, keyboard handling, or actual Flutter rendering works. Verify those in the running prototype.

## 6. Data model

Keep catalog information separate from the current user's copy and reading history. This avoids making global book metadata carry user-specific state and leaves room for sync later.

### Book

- `id` (local UUID)
- `title`
- `subtitle` (optional)
- `description` (optional)
- `createdAt`, `updatedAt`

### Author

- `id`
- `name`

### BookAuthor

- `bookId`
- `authorId`
- `position` (for author ordering)

### Edition

- `id`
- `bookId`
- `isbn10` (optional)
- `isbn13` (optional)
- `publisher` (optional)
- `language` (optional)
- `pageCount` (optional)
- `publicationYear` (optional)
- `coverLocalPath` (optional)
- `coverSourceUrl` (optional provenance only)
- `metadataSource` (for example `manual` or `open_library`)

### UserBook

A locally owned entry connecting the reader to a selected edition.

- `id`
- `bookId`
- `editionId` (optional)
- `status`: `reading`, `want_to_read`, or `finished`
- `rating` (optional; can be enabled in the first release or deferred)
- `currentPage` (optional)
- `addedAt`
- `updatedAt`

### ReadingRecord

Represents a completion/history claim, independently of when the app entry was created.

- `id`
- `userBookId`
- `startedValue` (optional normalized date/month/year value)
- `startedPrecision`: `day`, `month`, `year`, or `unknown`
- `finishedValue` (optional normalized date/month/year value)
- `finishedPrecision`: `day`, `month`, `year`, or `unknown`
- `source`: `tracked_in_app` or `entered_past`
- `createdAt`

For `unknown`, the corresponding value is null. Validate that a day-precision value has a day, month-precision has a month, and year-precision has only a year. Do not infer a date from `addedAt`.

### ReadingSession

Represents measured reading activity, not a retroactive completion.

- `id`
- `userBookId`
- `startedAt`
- `endedAt` (optional if session is incomplete)
- `startPage` (optional)
- `endPage` (optional)
- `durationSeconds` (optional)
- `createdAt`

### Pin

- `id`
- `userBookId`
- `page` (optional)
- `progressPercent` (optional)
- `type`
- `text`
- `createdAt`
- `updatedAt`

### LocalShelf (optional for first release)

- `id`
- `name`
- `sortOrder`

### LocalShelfBook (optional for first release)

- `shelfId`
- `userBookId`
- `sortOrder`

Use stable UUIDs even while data is local. They make later backup restore, import/export, and potential sync easier.

## 7. Statistics and calendar rules

Show two clearly distinct kinds of information.

### Reading history

Can include retroactively entered completions where the date is known:

- Books finished in a selected year.
- Pages in completed books, only when the selected edition has a page count.
- Monthly completion counts only where month precision is known.

A year-only finish appears in that year's total, but should not be assigned to a month. An unknown finish date can count in an all-time total, but not in a dated year/month.

### Reading activity

Comes only from actual logged sessions or explicit daily activity entries, if introduced later:

- Pages logged.
- Reading time.
- Activity calendar intensity.
- Reading speed and streaks, only when their inputs are sufficiently complete.

Do not turn the difference between two page updates into a session duration. Do not treat retroactively finished books as pages read on their entry date. Clearly label any statistic that is based on incomplete data.

The calendar shows real activity dates from sessions. Tapping a day lists sessions and pages for that day. Historical completions with only month/year precision may be shown in a separate history list or summary, never as an invented calendar dot.

## 8. Technical architecture

### App stack

- **Flutter / Dart**
- **Riverpod** for state management and dependency injection.
- **go_router** for navigation.
- **Drift + SQLite** for local relational persistence and schema migrations.
- **Freezed + json_serializable** for immutable data models where they reduce boilerplate.
- **Dio** only for optional online book metadata lookup.
- **cached_network_image** for transient remote covers if needed; copy chosen covers to app-owned local storage for durable offline access.
- **path_provider** for app document/cache directories.
- **image_picker** or platform picker for selecting a local cover.
- Native share integration for generated images.

Package versions should be selected and pinned when implementation begins, after checking current Flutter compatibility.

### Feature-based folder structure

```text
lib/
  app/
    bootstrap/
    routing/
    theme/
  core/
    database/
      app_database.dart
      tables/
      migrations/
    errors/
    files/
    utils/
  shared/
    models/
    widgets/
  features/
    library/
      data/
      domain/
      presentation/
    book_search/
      data/
      domain/
      presentation/
    book_details/
      data/
      domain/
      presentation/
    reading/
      data/
      domain/
      presentation/
    history/
      data/
      domain/
      presentation/
    pins/
      data/
      domain/
      presentation/
    statistics/
      data/
      domain/
      presentation/
    sharing/
      data/
      domain/
      presentation/
    settings/
      data/
      domain/
      presentation/
```

Use repositories as boundaries between features and Drift. Avoid creating a use-case class for every one-line database operation. Keep widgets focused on presentation and put date precision, statistics, and validation rules in testable domain functions.

### Local storage and cover files

- SQLite stores structured records and file paths, not large image blobs.
- Copy imported cover files into an app-managed documents directory; do not rely on temporary picker paths.
- Use the cache directory only for regenerable remote cache.
- Database migrations must preserve user data across app updates.
- Add export/restore before relying on this app as the only record of a long reading history.

### Repository boundary for future sync

Screens and business logic should call repository interfaces, not Drift directly. The first implementation has local repositories only. If online sync becomes a goal, add a remote data source and a sync policy later; do not add a dormant backend or sync queue now.

## 9. Suggested implementation milestones

### Milestone 0 — App foundation and visual prototype

- Establish theme tokens and reusable book, button, sheet, and navigation components.
- Prototype Library, Reading, and Journal using the design specification in section 5.
- Validate the three core flows and refine the shelf before expanding implementation.
- Create Flutter Android/iOS project.
- Set up theme, navigation, Riverpod, Drift, migration strategy, and empty feature shells.
- Confirm the app builds on both platforms.

### Milestone 1 — Local catalog and library

- Add/edit/remove a book and edition.
- Manual author/title/page-count entry.
- Local cover selection and generated spine fallback.
- Library shelves, sorting, filtering, and book detail.

### Milestone 2 — Reading and history

- `Reading`, `Want to Read`, and `Finished` states.
- Progress update.
- Past-book entry with day/month/year/unknown precision.
- Batch history-entry flow.
- Reading sessions with optional pages and duration.

### Milestone 3 — Stats and calendar

- All-time and year completion summaries.
- Monthly summaries only when month is known.
- Activity totals and calendar from logged sessions only.
- Explicit empty, partial-data, and no-page-count states.

### Milestone 4 — Pins, export, and sharing

- Private notes/pins.
- JSON export and validated restore/import.
- On-device finished-book and yearly-shelf images.
- Test native share flow on Android and iOS.

### Milestone 5 — Polish and release readiness

- Accessibility labels and large-text support.
- Empty states, error handling, and offline behavior.
- Verify database upgrade and restore paths.
- App icon, store screenshots, and release builds.

## 10. Acceptance criteria for the first usable release

- The library opens and works without an internet connection.
- A user can add and edit a book manually, including a local cover.
- A user can add a previously read book with year-only precision without creating a false date or calendar activity.
- Adding multiple past books does not change today's activity totals.
- Only actual logged sessions contribute to reading time and daily activity.
- A user can update a current page and finish a book.
- Books remain associated with their edition's page count and cover.
- The app can export user data and restore it on a clean install without losing cover files.
- Shelf layout remains usable with a large library and on smaller phone screens.
- The visual implementation follows section 5: distinctive miniature books, three clear navigation destinations, and labeled primary actions.
- Core flows work with large text, screen-reader navigation, reduced motion, and no gesture discovery.
- Library and Reading interactions are verified in a running Flutter prototype before visual patterns are rolled out across all features.

## 11. Decisions to confirm during implementation

These choices do not block starting the app skeleton, but should be settled before their feature is implemented:

- Whether ratings belong in the first release or the pins/sharing milestone.
- Whether past-book entry stores just a finish date or optional start and finish dates.
- Whether initial online search uses Open Library or starts with manual entry and adds search later.
- Whether custom shelves are needed in the first release.
- Minimum Android/iOS versions based on the devices targeted for testing.

## 12. Guiding rule

> **The app records what the reader knows, and leaves unknown details unknown.**

This keeps the bookshelf honest, the calendar meaningful, and the statistics trustworthy.
