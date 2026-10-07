# Store privacy answers (to confirm before submitting)

These are the answers that match how the app behaves today. Both stores define
"collected" by their own wording; re-read the question text when you fill the
form and check any answer you are unsure of.

## Facts

- No analytics, advertising, crash reporting, or third-party SDKs that transmit
  data. An account is **optional** (Friends); the app is fully usable without it.
- The library, notes, pins, sessions, and covers stay on the device. Without an
  account, the only thing sent to the developer is the online search text,
  which is not stored (see below).
- Network requests are all user-initiated: search text to the developer's
  server (`https://ai.duk-tech.com/books-api/books/search`, no account, which
  queries openlibrary.org; directly to openlibrary.org if the server cannot be
  reached) when the reader taps Search, the chosen cover download from
  openlibrary.org, and, only after the reader creates an account in Friends,
  the account requests to the same server.
- With an account, the server receives: first and last name, username, email,
  a password hash, friend requests and friends, and, only when the reader taps
  Share my shelf, each book's title, author, status, and finish dates. If the
  reader adds a phone number, a keyed hash of it. Contact phone numbers are
  sent for matching when the reader taps Find friends from contacts and are not
  stored.
- Permissions: `INTERNET`; `READ_CONTACTS` on Android and
  `NSContactsUsageDescription` on iOS, requested only when the reader taps
  Find friends from contacts. Read-only; phone numbers only.
- In-app account deletion exists (Friends > Delete my account) and erases all
  server-side data for the account immediately.

## Google Play — Data safety

- Collects or shares data with the developer: **Yes, only if the reader creates
  a Friends account.** Declare, as collected and linked to the user, optional,
  for app functionality: **Name**, **Email address**, **User IDs** (username),
  **Other user-generated content** (the published list of books and dates), and
  **Phone number** (hashed; only if added). Not shared with third parties, not
  used for advertising or analytics.
- **Contacts:** the phone numbers of contacts are sent to the server for
  matching only and are not stored. Declare "Contacts" as accessed; weigh
  whether Play's wording of "collected" covers data processed transiently and
  not retained (declaring it as collected, ephemeral processing, not stored, is
  the conservative choice).
- **Account deletion:** Play requires both an in-app path (present) and a web
  page where an account can be deleted. **There is no web deletion page yet**; it
  must be added (it can be a simple page explaining how to delete in the app and
  how to ask the developer to delete an account) before submitting.
- The search text now reaches the developer's server (processed in real time,
  not stored, cached in memory up to 6 hours, never linked to an account) and is
  passed to Open Library. Declare it as **App activity > In-app search
  history**, collected, processed ephemerally, not shared for advertising,
  required for the search feature (optional to use). The IP address is used
  only for rate limiting and kept up to a day.
- Data encrypted in transit: **Yes** (HTTPS). Deletion request: in-app deletion
  (Friends > Delete my account) plus a web page (see above).

## Apple — App Privacy

- Tracking: **No**. No tracking domains.
- Data collected (only with a Friends account), linked to the user, for App
  Functionality, not used for tracking: **Contact Info** (name, email address,
  phone number if added), **Identifiers** (username), **User Content** (the
  published list of books and dates). The contact phone numbers sent for
  matching are processed in real time and not stored; Apple does not count data
  that is not retained as collected, but re-read the definition when filling
  the form and declare it if in doubt. The online search text reaches the
  developer's server (not stored, in-memory cache up to 6 hours, no account
  needed): declare "Search History, not linked to identity, not used for
  tracking, App Functionality".
- **Account deletion** (App Store guideline 5.1.1(v)): in-app deletion is
  present (Friends > Delete my account).
- `NSContactsUsageDescription` is set; the permission is requested only when the
  reader taps Find friends from contacts.
- Photos: access is only through the system picker when choosing a cover.
