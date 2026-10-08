# Privacy policy — Reading Library

*Draft for review. Replace the bracketed items before publishing. This is not
legal advice.*

Last updated: [date]

Reading Library is a private reading journal. It has no ads, no analytics, and
no tracking. **You need an account to use it**: your library is saved to your
account so that a lost, broken, or new phone does not lose it (see "Your
account and your saved library" below). An account also lets you find friends
and share a list of the books you have read (see "Friends and sharing").

## What is on your phone

Your books, covers, reading dates, ratings, progress, sessions, and private notes are
stored on your phone first, and the app works without a connection. Automatic
cloud backup is disabled on Android. Photos you choose as covers stay on your
phone; they are never uploaded.

If you export a backup, the file contains your whole library, including private
notes and cover images. It is saved where you choose, and you are responsible
for storing it safely. Deleting the app deletes the on-device library; backup
files you saved elsewhere remain until you delete them.

## What leaves your device

Only when you tap **Search** in the online book search, the text you typed is
sent to the developer's server (`ai.duk-tech.com`), which passes it to Open
Library (openlibrary.org, operated by the Internet Archive) to find matching
books and sends the results back. No account is needed for this. The server
does not store the search text: it is not written to a database or to logs; recent
searches and their results are kept only in memory, for up to 6 hours, so the
same search is not sent to Open Library again. Your IP address is used to limit
how many searches can be made per hour and is kept for up to a day for that
purpose only. Open Library sees the search coming from the developer's server,
not from you. If the developer's server cannot be reached, the app sends the
search to Open Library directly, which then sees your IP address. When you pick
a result, the app downloads that book's cover image from Open Library directly,
which reveals your IP address to Open Library. Open Library's own privacy
policy applies to that service. The app's online search sends nothing else, and
does not send your library, notes, or any identifier. You can use the app fully
without ever using online search.

## Android version checks

The Android app checks GitHub for a new signed version on opening and returning to the app (at most once per six hours per session), and when you tap Check for updates. GitHub and its download infrastructure receive your IP address and normal HTTPS request metadata. The request sends no account credentials, library, notes, contacts, or device identifier. Download update opens GitHub in your browser only when you tap it; installation needs your confirmation. GitHub's privacy policy applies to these requests. The demo and iOS app do not make these checks.

## Your account and your saved library

When you sign in, the app saves your whole library to your account on the
developer's server, shortly after every change and whenever it can reach the
server. Changes made offline wait on your phone and are saved later.

**What is saved:** every book with its title, author, page count, language,
series, status, and finish dates exactly as you recorded them; your reading
progress and reading sessions; your **ratings** (1 to 5 stars, only if you give them); and your **private notes and pins**. For a cover
that came from Open Library, only its address on Open Library's cover host is
saved, so another phone can download it again; the picture itself is not saved,
and covers you chose from your own photos are not saved at all.

**Who can see it.** Not other readers: friends never see what is in this
section (see "Friends and sharing" for the separate, smaller list you can
publish). The developer can technically read it, because it is stored on the
developer's server as readable data and is **not end-to-end encrypted** (it is
encrypted in transit by HTTPS). Do not keep anything in your notes that you
would not want the person running the server to be able to read.

**Where it is stored and for how long.** On the same server and under the same
terms as the account data below, until you delete your account. **Delete my
account** erases your saved library with it, immediately. It does not affect
the library on your phone, which is saved again if you create a new account.
Two phones on one account: if both have changes, the app asks you which library
to keep; it never merges them, and the one you do not keep is replaced.

## Friends and sharing

Nothing in this section happens unless you use Friends.

**What the developer's server receives and keeps**

- When you create an account: your first and last name, a username, your email
  address, and your password (stored only as a salted one-way hash, never in
  readable form). You can change your name, username and password later from
  the app's account page; the server receives the new values (and, for a
  password change, the current password to check it) and stores them the same way.
- If you tap **Share my shelf** and confirm: for each book, its title, author,
  status (reading, wishlist, finished), and finish dates exactly as you
  recorded them (a remembered year stays a year). Nothing else: no ratings,
  notes, pins, reading sessions, progress, series, or covers. Publishing again replaces the
  earlier copy, and **Stop sharing** deletes it.
- Your friend requests, friends, and blocked people.
- If you add a phone number and switch on "Let people find me by phone": a
  keyed one-way code derived from the number. The number itself is not stored,
  and the server does not check that it is yours.
- Your saved library (above).
- Technical logs of requests (time, address, and the request line, which
  includes a username you search for) kept by the server and its web server for
  operating and securing the service. Request bodies, such as your password,
  your library, your shelf, or contact numbers, are not logged.

**Who can see it.** Another reader sees your name and username (when they
search your exact username, or find you by phone if you allowed it) and, once
you have accepted each other as friends, your published shelf. Nobody sees your
email address or phone number. You can remove a friend or block someone at any
time. There is no public profile and no search by name.

**Contacts.** Only if you tap **Find friends from contacts** and allow the
permission, the app reads the phone numbers in your address book (not names,
emails, or photos) and sends them to the server. The server compares them with
people who chose to be found by phone and replies; it does not store or log the
numbers you sent.

**Where it is stored and for how long.** On a server operated by the developer
([location and host to fill in]), over an encrypted (HTTPS) connection. Account
data, your saved library, and the shared shelf are kept until you delete your
account. **Delete my account** (in Friends) erases your account, saved library,
friend list, blocks, shared shelf, and sign-in sessions from the server
immediately; it does not affect the library on your phone. Backups of the server, if any, are kept for [period].

**Not verified, not recoverable.** Email addresses and phone numbers are not
verified, and there is currently no password reset; a forgotten password means
the account cannot be recovered (you can create a new one).

**Sharing with others.** The developer does not sell data or share it with
advertisers or analytics providers. The account server does not use third-party
services. GitHub receives Android update requests as described above. Open Library (above) receives only your book search text, as
described, normally from the developer's server rather than from your device,
and, when a phone downloads a cover again, the cover address (and that phone's
IP address).

## Sharing the app

Share app opens your device's share chooser with a fixed invitation and public Android download link. You choose the receiving app and recipient. No account information, library, contacts or private notes are included, and opening the chooser does not send a message automatically. Copy download link writes only that public URL to your device clipboard. When a recipient follows the link, GitHub receives the normal download request as described under Android version checks.

## Photos

The app reads an image only when you choose a cover from your photo library, and
copies only that image into the app. It is not uploaded.

## Children

The app does not knowingly collect any personal information from anyone.

## Changes and contact

If this policy changes, the updated version will be published at [URL].
Questions: [contact email].
