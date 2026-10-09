# Store privacy answers (to confirm before submitting)

These are the answers that match how the app behaves today. Both stores define
"collected" by their own wording; re-read the question text when you fill the
form and check any answer you are unsure of.

## Facts

- No analytics, advertising, or crash reporting. One third-party SDK transmits
  data: Firebase Cloud Messaging (Google), used only for friend notifications the
  reader turned on (Android; not initialised on iOS yet). It sends Google a
  push token and a Firebase installation id; the messages carry no names or
  book data. Analytics is not included. An account is **required**: the app opens on the sign-in page, because
  the library is saved to the account (decision D38). The demo build is the
  only part that works without one.
- The library, notes, pins, and sessions are stored on the device and saved to
  the reader's account on the developer's server in the background (readable by
  the developer, not end-to-end encrypted). Cover images chosen from the photo
  library never leave the device; for online covers only the Open Library
  address is saved.
- Network requests: search text to the developer's server
  (`https://ai.duk-tech.com/books-api/books/search`, no account, which
  queries openlibrary.org; directly to openlibrary.org if the server cannot be
  reached) when the reader taps Search, cover downloads from openlibrary.org
  (when a cover is chosen, and again on a phone that has a saved library but not
  the file), and the account and library requests to the same server
  (sign-in, saving the library after changes and when the app returns to the
  foreground, friends).
- The server receives: first and last name, username, email, a password hash,
  **the whole library (books, finish dates, ratings, reading sessions, private
  notes and pins, series, page counts, language, cover addresses)**, friend requests and
  friends, and, only when the reader taps Share my shelf, each book's title,
  author, status, and finish dates (the part friends see). If the
  reader adds a phone number, a keyed hash of it. Contact phone numbers are
  sent for matching when the reader taps Find friends from contacts and are not
  stored.
- Push: the reader's device push token is stored on the server for the account
  until notifications are turned off, the reader signs out, or the account is
  deleted.
- Permissions: `INTERNET`; `POST_NOTIFICATIONS` (Android 13+, requested when the
  reader turns friend notifications on); `READ_CONTACTS` on Android and
  `NSContactsUsageDescription` on iOS, requested only when the reader taps
  Find friends from contacts. Read-only; phone numbers only.
- In-app account deletion exists (Friends > Delete my account) and erases all
  server-side data for the account immediately.

## Android release updates

The Android app automatically fetches a public GitHub release manifest on opening/resume (six-hour in-process throttle) and on a manual check. GitHub and its CDN receive the IP address and transport metadata, never an account token, library, notes, contacts or device identifier. Tapping Download update opens an HTTPS GitHub APK address in the browser. There is no new permission or analytics SDK. Reassess this external download feature before distributing through Google Play: this workflow is for the direct-APK channel, and a Play distribution should use its permitted update mechanism instead.

## Google Play — Data safety

- Collects or shares data with the developer: **Yes, for every user (an account
  is required).** Declare, as collected and linked to the user, required for app
  functionality: **Name**, **Email address**, **User IDs** (username),
  **Other user-generated content** (the library: books, reading dates, ratings,
  sessions, and private notes), **App activity** (reading sessions, if the form counts
  them separately), and, optional, **Phone number** (hashed; only if added).
  Not shared with third parties, not used for advertising or analytics. Say
  that data is **not** end-to-end encrypted.
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
- Data encrypted in transit: **Yes** (HTTPS). Data is not encrypted end to end.
  Deletion request: in-app deletion (Friends > Delete my account, which also
  erases the saved library) plus a web page (see above).

**Friend notifications:** declare **Device or other IDs** (the push token and Firebase installation id), collected, linked to the user, required for the optional notification feature, not used for advertising or analytics; shared with Google as a service provider (Firebase Cloud Messaging). Re-read the stores' wording on service providers. The merged manifest of a build with the real Firebase file adds only network-state, wake-lock, job-service, dump and Google's push receive/send permissions (no Analytics). Check Firebase's own data disclosure before submitting.

## Apple — App Privacy

- Tracking: **No**. No tracking domains.
- Data collected (every user, since an account is required), linked to the
  user, for App Functionality, not used for tracking: **Contact Info** (name,
  email address, phone number if added), **Identifiers** (username), **User
  Content** (the whole library including private notes, and the published list
  of books and dates), **Usage Data > Product Interaction** (reading sessions,
  if counted). The contact phone numbers sent for
  matching are processed in real time and not stored; Apple does not count data
  that is not retained as collected, but re-read the definition when filling
  the form and declare it if in doubt. The online search text reaches the
  developer's server (not stored, in-memory cache up to 6 hours, no account
  needed): declare "Search History, not linked to identity, not used for
  tracking, App Functionality".
- **Account deletion** (App Store guideline 5.1.1(v)): in-app deletion is
  present (Friends > Delete my account). It erases the saved library too.
  Because sign-in is now required to use the app, Apple's sign-in rules apply:
  the app offers its own email and password sign-in only (no third-party login),
  so Sign in with Apple is not required.
- `NSContactsUsageDescription` is set; the permission is requested only when the
  reader taps Find friends from contacts.
- Photos: access is only through the system picker when choosing a cover.

**App invitations:** Share app hands a fixed public Android download invitation to the native chooser only on a tap; the reader chooses the destination/recipient. Copy download link puts only the public URL on the clipboard. No library, token, username or contacts are read for this action; no new permission, dependency or network call is added.
