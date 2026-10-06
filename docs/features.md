# Features: what the app does today

This is the behavioural specification of the working POC, written from the code. It describes what exists, not what was planned (see `product-plan.md` for the original plan and `decisions.md` for where and why the build departs from it). Exact user-facing strings are quoted where tests or the design depend on them.

**Product in one line:** a private, local-first reading journal for Android and iOS. No account, backend, analytics, or required network. The reader records what they know and leaves unknown details unknown.

## Honesty rules (they shape every feature)

1. Adding a book is not reading it. Reading history is not reading activity.
2. A remembered finish keeps its precision: `day`, `month`, `year`, or `unknown`. No fake dates are ever stored (a year-only record is `"2019"`, never January 1).
3. Only logged **sessions** create activity: pages logged, minutes, calendar colour. Page updates, corrections, and past finishes never do.
4. Shelf keepsakes are earned by the count of finished books only. Never by streaks, pages, time, or opening the app.
5. Personal notes (pins) stay on the device and are never generated automatically.

## Navigation

Three labelled bottom destinations: **Library**, **Reading**, **Journal**. A settings button (tune icon) sits in the top bar. A floating labelled **Add book** button is on Library. There is no sign-in and no onboarding.

Routes: `/library`, `/reading`, `/journal?year=YYYY` (inside the shell); `/add` and `/add?past=true`, `/book/:id`, `/edit/:id`, `/settings` (full screens). Online search is a pushed screen, not a route.

## Library

Top to bottom: eyebrow, title **My library**, a year selector with a **N books finished** button, status filters, a search field, the shelf, and the floating button.

- **Year selector:** `All time` or a completion year. It is shown only when the status filter is All or Finished (unfinished books have no completion year). Selecting a year narrows to books finished in it. The **N books finished** button opens the Journal for that period.
- **Status filters:** All, Reading, Want to read, Finished. They wrap onto a second line on narrow phones so none is ever off-screen. Choosing Reading or Want to read clears the year.
- **Search:** see "Library search" below.
- **Shelf / List switch:** the shelf is the signature view. The list (cover thumbnail, title, author, status) is used automatically at large text sizes (system text scale above about 1.44x) and can be chosen with the switch.
- **Selected-book panel:** above the shelf, tapping a spine or cover shows its cover, title, author, and status (or page progress for books being read, and pin count). Tapping the panel opens the book. It grows with its content rather than having a fixed height.
- **Shelf rendering:** see `design-system.md`. Rows of spines on wooden planks; books being read stand face-out with a bookmark ribbon; keepsakes sit among the books.
- **Keepsakes note:** a line under the shelf, e.g. "Keepsakes: 3 of 7. Finish 2 more books for a tea mug." followed by "Earned by books you finish, never by streaks." Shown only when the whole shelf is visible (see Keepsakes).
- **Empty states:** an empty library shows "A shelf of possibilities." with **Add your first book** and **Add books I've already read**. A filtered or searched empty shelf never says "first book" (see below). Actions have bottom clearance so the floating button never covers them.

### Library search

Searches title and author together, entirely on the device.

- Ignores case, diacritics and punctuation: `calinescu` finds Călinescu, `morometii` finds Moromeții.
- Every typed word must appear, in any order, and may be partial: `mcfadden freida` and `mcf hous` both find *The Housemaid* by Freida McFadden.
- Results are ranked: exact title, title starts with, author starts with, whole-word hits, word-start hits. Ties keep the library's own order. With no query the order is unchanged.
- A clear (x) button appears while text is typed.
- If a status or year filter hides matches, the empty state says so: "Nothing here for "x". N matching books are hidden by the Finished filter." with a button (**Show it** / **Show all N**) that clears the filters.
- If nothing matches anywhere: "No book matches "x"." with an **Add a book** button.
- With filters only (no text): "A little space on this shelf." with **Add a book**.

### Keepsakes

Seven small objects drawn in code (no image assets): Brass bookend (1 finished book), Potted plant (3), Tea mug (5), Candle (8), Globe (12), Hourglass (18), Reading cat (25). The count is the number of books whose status is Finished, including books entered from memory. They are spread evenly through the shelf, never side by side. They show only when no status filter, year filter, or search is active. Tapping one shows "<name>. Earned by finishing N book(s)." and each has a screen-reader label.

## Adding and editing a book (`/add`, `/edit/:id`)

Single form. For new books it starts with a **Search online** button ("Or enter the details yourself below.").

Fields: Title, Author (one text field, one author), Page count (optional), Language (optional), cover (**Choose a cover** from the gallery, a preview of the selected cover, **Use a generated cover**). New books also choose **Add to**: Want to read, Reading now, Finished, or Read in the past, plus **Add another book after saving**.

- **Finished / Read in the past** require the finish-date choice (below); today is never assigned silently.
- **Add another book** keeps the sheet open after saving, clears the fields, and shows e.g. "Dune added to 2019. Ready for another book." The date must be chosen again for each book.
- **Edit** changes title, author, pages, language, and cover. It refuses a page count that would invalidate existing progress, sessions, or pins. It never changes status or history.
- The selected cover is copied into app storage. The cover preview and an explanatory message show whenever a cover is present.
- Validation messages appear inline and the typed input is kept. Dirty forms ask before discarding.
- **Drafts:** unsaved new-book input survives the app being killed (see Drafts).

### Finish date ("When did you finish it?")

Four explicit precisions, no default: **Exact date** (date picker, cannot be in the future), **Month and year**, **Year only**, **I don't remember** ("Saved in All time, without an invented date."). Saving requires a choice; the date picker needs an explicit pick.

## Online book search (optional)

Reached from **Search online** in the add form. Search by title, author, or ISBN (10 or 13 digits, hyphens allowed). It runs only when the reader taps Search or presses the keyboard search key; nothing is sent while typing. The field is pre-filled from the form's title and author.

- Source: Open Library (`openlibrary.org`). Only the typed text is sent. The screen says so.
- Results show thumbnail, title, author, first-publication year, page count, and **no cover** when there is none. A note says page counts are typical across editions.
- **Fallback for misspellings:** if nothing matches every word and at least two words of three or more letters were typed, a looser any-word search runs and the screen says "No exact match. These are the closest results...". Never for ISBNs or single words.
- Choosing a result downloads its cover into app storage (validated by image content, 5 MB limit), fills the form, and records the edition source as `open_library`. Language is prefilled only when the work lists exactly one language (a work's list covers all editions).
- After choosing, the form says whether the cover was found: "Filled from Open Library. Check the details against your edition.", "...which has no cover for this book. Choose one from your photos, or keep the generated cover.", or "...but the cover could not be downloaded...".
- Failure (offline, timeout, bad response): "Could not reach Open Library. Check your connection, or add the book manually." The typed text is kept and **Add manually instead** returns to the form.
- Open Library has no cover for many titles, especially Romanian ones; this is the main known limitation.

## Reading tab

An editorial heading ("In good company.") and one card per book with status Reading: cover, title, author, page progress (`N of M pages` with a bar, or `Page N` when the total is unknown).

- **Update page** (primary): a sheet with a numeric field prefilled with the current page and the total when known. Saving shows "Position saved. Reading activity is unchanged." with **Undo**. A correction never counts as pages read.
- **Add pin**, **Log session**, **Finish book**, **Book details** are shown for the expanded card (the first by default; others show **More reading actions**).
- With nothing being read: "Your next chapter awaits." with **Add a book**.

### Sessions

**Log a session:** a date (not in the future), optional starting and ending page, and optional minutes (behind **Add reading duration**). Rules: start and end come together, end is not before start, pages stay within the total, duration must be positive, and at least pages or a duration is required. A session ending past the current page advances progress; a backdated session never rewinds it. Pages and minutes are never derived from page updates.

### Pins

A private note with type (Thought, Favorite, Quote, Question, Idea; default Thought), text, and optional page and/or percentage (0 to 100). Shown on the book as a paper note with a type and page marker; deletable with confirmation.

### Finishing

**Finish book** opens the finish-date choice, then records a reading record (`tracked_in_app`) and sets the status to Finished. A finished book offers **Read again**, which sets it back to Reading and keeps all earlier completions; finishing again adds another record.

## Book details (`/book/:id`)

Cover, title, author, status chip, and the main action (Update page / Start reading / Read again), then **Finish book** or **Share book** (finished books). Sections: **Pins** (with **Add pin**), **History** (finishes: "Entered from memory" or "Finished in your reading journal", then sessions with pages and minutes), **Details** (pages, language, **Edit edition and cover**), and a separated destructive **Remove from library** (confirmation; deletes the book, history, sessions, and pins).

## Journal tab

- Heading "Reading journal", a year selector (All time or a year), and **Share shelf** (when there are finished books).
- Summary: **Books finished** and **Pages logged** (pages logged come from sessions only).
- Three views, switched with **Months / Days / History** (Months is the default):
  - **Months** is the main picture: the books you finished, grouped by when you remember finishing them.
    - **All time** shows one row per year (newest first) with the year, the number of books, and a small fan of covers. Tapping a year opens it month by month. Books with no date at all sit in a **Date unknown** row that opens a list.
    - **A single year** shows twelve month tiles (Jan to Dec) with a count and covers. Months with no books are faint and not tappable; tapping a month opens a sheet listing its books. A book is placed in a month only when its month is remembered (exact day or month and year); within a month, books with a known day come first in day order.
    - Books remembered **only as a year** are never put in a month: they appear in a separate wide tile "Sometime in <year>" ("Remembered as a year only. The month is unknown.").
  - **Days** is the reading-activity calendar. It explains itself ("The days you logged a reading session...") and, with no sessions, says the calendar is empty and that books finished in the past do not count as reading days. One month with previous/next, tappable days (a sheet lists that day's sessions and any finishes). A day is coloured only when a session was logged; a small dot marks a day you finished a book (a dot, never colour, because finishing is not reading time). The legend reads "A day you read" and "You finished a book that day". On narrow phones the grid scrolls horizontally to keep 48 px cells.
  - **History** is the detailed list: finished books grouped by period (month and exact-day records under their month, year-only under "<year> · Month unknown", unknown under "Date unknown"), each marked "Remembered" (entered from memory) or "Finished".
- **A little perspective** (every view): minutes logged (sessions with a duration only) and pages in completed editions (separate from pages logged, noting books without a page count).

## Sharing

On-device images only, through the native share sheet; nothing is uploaded and the reader chooses when. **Share book** (finished books): a 600 x 800 card with the cover, title, and author. **Share shelf** (Journal): a yearly grid of up to 24 covers (labelled as a selection when there are more). The share sheet is anchored to the button (needed on iPad).

## Settings ("Your reading room")

- States the privacy position: stored on the device, no account, no cloud, no tracking.
- **Export library:** saves a JSON backup including cover bytes and private pins to a location the reader picks.
- **Restore a backup:** validates the file, asks "Replace this library?" showing the book count, then replaces the library atomically. A failed restore leaves the existing library unchanged. It replaces; it does not merge.
- Version and open-source licences (DM Sans and Literata are listed).

## Drafts (recovery after the app is killed)

Unsaved input in the add-book form (new books only), the session sheet, the pin sheet, and the page sheet is written to a small device-local file shortly after typing and when the app goes inactive. On reopening, the form shows "Restored your unsaved draft." (the add form also offers **Start fresh**). A draft is removed on save or discard, expires after 30 days, is never part of a backup, and is never kept for finishing a book (the date must be confirmed afresh).

## Cover files

Imported or downloaded covers live in the app documents directory (`covers/`). At startup, files not referenced by any edition and older than a day are deleted (compared by file name). A cover picked in a still-unsaved form is therefore safe.

## Accessibility and input

Every tap target is at least 48 x 48. Books, spines, and keepsakes expose labels to screen readers; decorative shadows and page edges are excluded. Layouts reflow at large text. Dirty-form dismissal asks first. Animations (a short lift when a book is selected) are disabled by the platform reduced-motion setting.

## Not implemented

Sign-in, cloud sync, social features, a web app or backend, notifications, payments, ISBN camera scanning, ratings, custom shelves, remembered start dates, editing a recorded finish date, multiple authors per book, dark theme, and process-death recovery beyond the drafts above. See `implementation-status.md` for what is unverified on real devices.
