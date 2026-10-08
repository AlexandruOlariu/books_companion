# Features: what the app does today

This is the behavioural specification of the working POC, written from the code. It describes what exists, not what was planned (see `product-plan.md` for the original plan and `decisions.md` for where and why the build departs from it). Exact user-facing strings are quoted where tests or the design depend on them.

**Product in one line:** a private reading journal for Android and iOS. The library is written to the phone first and saved to the reader's account in the background, so the app works offline and a lost or new phone does not lose it (see Account and saving, and `backend.md` for the server). No analytics. An account also lets the reader find friends and share a list of what they have read (see Friends). The reader records what they know and leaves unknown details unknown.

## Honesty rules (they shape every feature)

1. Adding a book is not reading it. Reading history is not reading activity.
2. A remembered finish keeps its precision: `day`, `month`, `year`, or `unknown`. No fake dates are ever stored (a year-only record is `"2019"`, never January 1).
3. Only logged **sessions** create activity: pages logged, minutes, calendar colour. Page updates, corrections, and past finishes never do.
4. Shelf keepsakes are earned by the count of finished books only. Never by streaks, pages, time, or opening the app.
5. Personal notes (pins) are never generated automatically. They are kept on the phone and saved to the reader's own account; friends never see them.

## Wishlist

**Wishlist** is the status for books you want to read but have not started. It was first called "Want to read" and was renamed to Wishlist (see D34); it is the same status (stored as `want_to_read`), and nothing else changed. Wishlist books appear on the shelf like any other book and have their own filter chip; a wishlist book offers **Start reading** on its details page.

## Navigation

Three labelled bottom destinations: **Library**, **Reading**, **Journal**. A settings button (tune icon) sits in the top bar. A floating labelled **Add book** button is on Library. There is no onboarding beyond the account page: until someone is signed in the app opens on it, and nothing else (see Account and saving). The demo build skips it.

Routes: `/library`, `/reading`, `/journal?year=YYYY` (inside the shell); `/add`, `/add?past=true`, and `/add?title=&author=&series=&number=` (any of them, used by suggestions to fill the form), `/book/:id`, `/edit/:id`, `/settings`, `/friends`, `/friends/:id?name=` (full screens). Online search is a pushed screen, not a route.

## Library

Top to bottom: eyebrow, title **My library**, a year selector with a **N books finished** button, status filters, a search field, the count, a **Sort** button and the **List/Shelf** switch, the shelf, and the floating button.

- **Year selector:** `All time` or a completion year. It is shown only when the status filter is All or Finished (unfinished books have no completion year). Selecting a year narrows to books finished in it. The **N books finished** button opens the Journal for that period.
- **Status filters:** All, Reading, Wishlist, Finished. They wrap onto a second line on narrow phones so none is ever off-screen. Choosing Reading or Wishlist clears the year.
- **Search:** see "Library search" below.
- **Shelf / List switch:** the shelf is the signature view. The list (cover thumbnail, title, author, status) is used automatically at large text sizes (system text scale above about 1.44x) and can be chosen with the switch.
- **Selected-book panel:** above the shelf, tapping a spine or cover shows its cover, title, author, and status (or page progress for books being read, and pin count). Tapping the panel opens the book. It grows with its content rather than having a fixed height.
- **Shelf rendering:** see `design-system.md`. Rows of spines on wooden planks; books being read stand face-out with a bookmark ribbon; keepsakes sit among the books.
- **Keepsakes note:** a line under the shelf, e.g. "Keepsakes: 3 of 7. Finish 2 more books for a tea mug." followed by "Earned by books you finish, never by streaks." Shown only when the whole shelf is visible (see Keepsakes).
- **Empty states:** an empty library shows "A shelf of possibilities." with **Add your first book** and **Add books I've already read**. A filtered or searched empty shelf never says "first book" (see below). Actions have bottom clearance so the floating button never covers them.

### Sorting and series

**Sort: Title** is the default. The **Sort** button opens a sheet with three choices, and the choice is remembered between launches (a small device-local file).

- **Title (A-Z):** alphabetical, ignoring case, diacritics, and a leading "The", "A", or "An" ("The Hobbit" sits under H).
- **Author (A-Z):** by the first author's surname (works for "Given Surname", "Surname, Given", and several authors joined by commas), then by title.
- **Recently added:** newest first.
- **Series stay together.** In both alphabetical sorts, books with the same series name sit side by side in number order, at the place of the series name; unnumbered books follow the numbered ones. A selected book shows "Series name, book N" in the panel and on its details page.
- The sort applies to the shelf and the list. A typed search ranks by relevance and uses the sort only to order equally good matches.

### Library search

Searches title, author, and series together, entirely on the device.

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

Fields: Title, Author (one text field, one author), **Series** and **Book number in the series** (both optional), Page count (optional), Language (optional), cover (**Choose a cover** from the gallery, a preview of the selected cover, **Use a generated cover**). New books also choose **Add to**: Wishlist, Reading now, or Finished, plus **Add another book after saving**.

- **Finished** requires the finish-date choice (below); today is never assigned silently. There is deliberately one Finished choice: remembering a book from long ago and finishing one yesterday are the same flow (choose a day, a month, a year, or "I don't remember"). Entering a book as Finished is recorded as a remembered finish (shown as "Remembered" in the Journal); finishing a book from the Reading tab is recorded as tracked. **Add books I've already read** opens this form with Finished preselected.
- **Series:** a free-text name and a whole number (1 or more). A number needs a name. Under the name field, quick-pick chips list up to five existing series; choosing one fills the name and suggests the next number. Editing can change or clear the series.
- **Add another book** keeps the sheet open after saving, clears the fields, and shows e.g. "Dune added to 2019. Ready for another book." The series name is kept and the number moves on by one, so a whole series can be entered in a row. The date must be chosen again for each book.
- **Edit** changes title, author, pages, language, and cover. It refuses a page count that would invalidate existing progress, sessions, or pins. It never changes status or history.
- The selected cover is copied into app storage. The cover preview and an explanatory message show whenever a cover is present.
- Validation messages appear inline and the typed input is kept. Dirty forms ask before discarding.
- **Drafts:** unsaved new-book input survives the app being killed (see Drafts). A form opened from a suggestion starts from the suggestion and neither reads nor replaces that draft.

### Finish date ("When did you finish it?")

Four explicit precisions, no default: **Exact date** (date picker, cannot be in the future), **Month and year**, **Year only**, **I don't remember** ("Saved in All time, without an invented date."). Saving requires a choice; the date picker needs an explicit pick.

## Online book search (optional)

Reached from **Search online** in the add form. Search by title, author, or ISBN (10 or 13 digits, hyphens allowed). It runs only when the reader taps Search or presses the keyboard search key; nothing is sent while typing. The field is pre-filled from the form's title and author.

- Source: Open Library (`openlibrary.org`), searched through the Reading Library server, which needs no account; if the server cannot be reached, the app asks Open Library directly. Only the typed text is sent. The screen says so: "Searches Open Library through the Reading Library server. Only your search text is sent, and only when you search." Covers always come straight from Open Library.
- Results show thumbnail, title, author, first-publication year, page count, and **no cover** when there is none. A note says page counts are typical across editions.
- **Fallback for misspellings:** if nothing matches every word and at least two words of three or more letters were typed (common words such as "the", "and", "din", "pentru" do not count), a looser any-word search runs and the screen says "No exact match. These are the closest results...". Never for ISBNs or single words.
- Choosing a result downloads its cover into app storage (validated by image content, 5 MB limit), fills the form, and records the edition source as `open_library`. Language is prefilled only when the work lists exactly one language (a work's list covers all editions).
- After choosing, the form says whether the cover was found: "Filled from Open Library. Check the details against your edition.", "...which has no cover for this book. Choose one from your photos, or keep the generated cover.", or "...but the cover could not be downloaded...".
- Failure (offline, timeout, bad response): "Could not reach Open Library. Check your connection, or add the book manually." The typed text is kept and **Add manually instead** returns to the form.
- Open Library has no cover for many titles, especially Romanian ones; this is the main known limitation.

## Reading tab

An editorial heading ("In good company.") and one card per book with status Reading: cover, title, author, page progress (`N of M pages` with a bar, or `Page N` when the total is unknown).

- **Update page** (primary): a sheet with a numeric field prefilled with the current page and the total when known. Saving shows "Position saved. Reading activity is unchanged." with **Undo**. A correction never counts as pages read.
- **Add pin**, **Log session**, **Finish book**, **Book details** are shown for the expanded card (the first by default; others show **More reading actions**).
- With nothing being read: "Your next chapter awaits." with **Add a book**.

### What to read next

At the end of the Reading tab, a section "What to read next" appears when there is something to suggest, and is absent otherwise. Suggestions never change the library: the only things they do are open a book already on the Wishlist, or open the add form with some fields filled in (the reader checks and saves it, or leaves). Each card says why it is shown, never has a cover from a friend, and has **Not interested** (hides it for good on this phone, with **Undo**). There are no ratings, so "liked" is never guessed from finishing alone.

- **Continue a series:** for a series where numbered books are finished, the book after the highest finished number. If it is on the Wishlist: "You finished book 1 of S. It is on your Wishlist." with **Open book**. If it is not in the library: "S, book N", "You finished 2 books of S, up to book 2. Book 3 is not on your shelf." with **Add to Wishlist**, which opens the add form with the author, series, and number filled and the title empty (the title of a book not yet seen is not known). Nothing is offered if the next book is already being read. The length of a series is unknown, so the last volume of a finished series is offered too; **Not interested** removes it.
- **From your Wishlist:** Wishlist books by an author the reader has finished: "On your Wishlist. You finished 2 books by X." Authors read more, or one the reader read again or pinned as a Favorite (added to the reason), come first.
- **Your friends finished:** books friends finished that the reader does not have in any status: "Finished by Ana and Bob." (more than two: "Ana, Bob and 2 more"), adding "You finished N books by X." when that is true. **Add to Wishlist** opens the add form with title and author filled. Friends' shelves are read-only here: they never add books, dates, activity, or keepsakes. If the reader has no friends, is offline, or the server fails, this group is simply absent. Not shown in the demo.
- At most five suggestions per group.

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

On-device images only, through the native share sheet; nothing is uploaded and the reader chooses when. **Share book** (finished books): a 600 x 800 card with the cover, title, and author. **Share shelf** (Journal): a yearly grid of every finished book's cover, in the order chosen in the Library (Title, Author, or Recent; the saved choice), four per row. A very large shelf is drawn smaller rather than cut short. The share sheet is anchored to the button (needed on iPad).

## Account and saving (`/welcome`, `/loading`)

An account is required (decision D38). Screenshots (sample library from `dev_seed`, a throwaway account): `screenshots/friends-sign-in.png` (the account page), `account-conflict.png`, `settings-saved.png`. With nobody signed in, every route redirects to `/welcome`: the sign-in and create-account panel, headed "Your reading room, kept safe." (`/loading` is a spinner shown for the moment it takes to read the device's session). The panel says what is saved: name, username and email, and the whole library (books, finish dates, reading sessions, private notes and pins), kept on the developer's server and **not end-to-end encrypted**; covers found online are fetched again from Open Library, photos the reader chose stay on the phone; friends only see what the reader publishes. Whether someone is signed in is known on the device, so the app opens offline once a session exists.

**What is saved, and when.** The library is written to the phone first, always. Shortly after a change (about 3 seconds after the last one, so a burst is one save), when the app returns to the foreground, and after signing in, the whole library is saved to the account. Offline, changes wait on the phone and are retried every minute and on return to the app; nothing is lost and nothing blocks. Settings shows "Saving to your account…", "Saved to your account at <date and time>.", "Waiting for a connection. Your changes are safe on this phone and will be saved when it is back.", or a problem, with **Save now**.

**Two libraries.** The library is never merged (that would mean guessing dates and activity). The first time a phone meets an account:
- the account has nothing: the phone's library is saved as the first copy;
- the phone has no books: the account's library is downloaded;
- both have books: a dialog, "Which library do you want to keep?", says "This phone has N books. Your account has M books, saved <date>." and that the other is replaced and cannot be brought back. **Keep this phone** replaces the account's copy; **Use my account** replaces the phone's. Nothing changes until the reader chooses, and saving pauses meanwhile.

The same dialog appears if the account's copy changed (another phone) while this phone has unsaved changes. If the phone has none, the newer copy is simply downloaded.

**Covers.** Only where an online cover came from (an Open Library address) is saved, never the picture. On a phone that has the book but not the file, the cover is fetched again after a download. A cover chosen from the gallery, and covers added before this feature existed, are not recoverable on another phone: the generated cover is shown there.

**Signing out** returns to the account page and leaves the library on the phone. Signing in as the same account continues where it left off; as a different account it is the "first time" case above. **Deleting the account** erases the saved library from the server too; the library on the phone stays and is saved again if the reader makes a new account.

## Friends (`/friends`, `/friends/:id`)

Reached from Settings ("Read with friends" > **Friends and sharing**). Nothing is shared with friends until the reader acts. Screenshots: `screenshots/friends-sign-in.png`, `friends-signed-in.png`, `friends-share-dialog.png` (sample library; the account shown was a throwaway test account, deleted afterwards).

**Signed out:** the same account panel as `/welcome` (it can only be seen briefly, since the app requires an account). **Sign in** or **Create account** (first name, last name, username, email, password). Usernames are 3 to 30 of letters, digits, `_`, `.`; passwords at least 10 characters. The panel warns there is no password reset. Errors are shown in words ("Wrong email or password.", "That username is already taken.").

**Signed in:** the name, `@username` and email, then:

1. **Your shelf for friends.** "Not shared" until the reader taps **Share my shelf**, which asks "Share N books with your friends?" and says exactly what they will see, that a year stays a year, and that notes, pins, sessions, and covers are never shared with friends. After that it shows the count and last published time, **Update shared shelf** (a manual re-publish), and **Stop sharing**. Friends see the shelf as of the last publish.
2. **Friend requests:** incoming (**Accept**, **Decline**) and outgoing (**Cancel request**). Nobody becomes a friend without accepting.
3. **Friends:** tap one to open their shelf.
4. **Add a friend:** an exact username and **Find** ("No one has that username." when none; there is no partial search), then **Send friend request**; or **Find friends from contacts**, which first explains that only phone numbers are sent and not kept, then asks for the system permission. A refusal is explained and nothing is sent. Matches already friends or requested are not offered.
5. **Be found by phone:** optional. Add a number, then switch on "Let people find me by phone" (off until switched on). The text says the server stores only a scrambled code of the number and does not verify that it is the reader's.
6. **Blocked** (only when someone is blocked): **Unblock**.
7. **Your account:** **Sign out**, and **Delete my account** (asks for the password, says it erases the account, friends, and shared shelf from the server and does not affect the library on the phone, which is saved again if the reader makes a new account).

**A friend's shelf** (`/friends/:id`): read-only, grouped Reading now, Finished (most recent finish first, unknown last), Wishlist; each book shows its title, author, and finish dates exactly as shared ("Finished: March 2024", "Finished: 2019", "Finished: Date unknown"). A note says it is a snapshot and not part of the reader's own journal or keepsakes: it never adds books, dates, or activity to the reader's library. The menu has **Remove friend** and **Block**, each confirmed. A friend who has not shared shows "Nothing shared yet".

## Settings ("Your reading room")

- States the privacy position: kept on the phone and saved to the account, no tracking, with the saving status and **Save now** (hidden in the demo, which says nothing is saved or sent).
- **Export library:** saves a JSON backup including cover bytes and private pins to a location the reader picks.
- **Restore a backup:** validates the file, asks "Replace this library?" showing the book count, then replaces the library atomically. A failed restore leaves the existing library unchanged. It replaces; it does not merge.
- **Friends and sharing** (hidden in the demo): opens Friends, described below.
- Version and open-source licences (DM Sans and Literata are listed).

## Drafts (recovery after the app is killed)

Unsaved input in the add-book form (new books only), the session sheet, the pin sheet, and the page sheet is written to a small device-local file shortly after typing and when the app goes inactive. On reopening, the form shows "Restored your unsaved draft." (the add form also offers **Start fresh**). A draft is removed on save or discard, expires after 30 days, is never part of a backup, and is never kept for finishing a book (the date must be confirmed afresh).

## Cover files

Imported or downloaded covers live in the app documents directory (`covers/`). At startup, files not referenced by any edition and older than a day are deleted (compared by file name). A cover picked in a still-unsaved form is therefore safe.

## Accessibility and input

Every tap target is at least 48 x 48. Books, spines, and keepsakes expose labels to screen readers; decorative shadows and page edges are excluded. Layouts reflow at large text. Dirty-form dismissal asks first. Animations (a short lift when a book is selected) are disabled by the platform reduced-motion setting.

## Not implemented

Password reset, email or phone verification, changing the password or profile from the app, friend notifications, automatic or background sharing, cloud sync of the library, a web app, notifications, payments, ISBN camera scanning, ratings, custom shelves, remembered start dates, editing a recorded finish date, multiple authors per book, dark theme, and process-death recovery beyond the drafts above. See `implementation-status.md` for what is unverified on real devices.
