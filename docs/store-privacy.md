# Store privacy answers (to confirm before submitting)

These are the answers that match how the app behaves today. Both stores define
"collected" by their own wording; re-read the question text when you fill the
form and check any answer you are unsure of.

## Facts

- No account, analytics, advertising, crash reporting, or third-party SDKs that
  transmit data.
- All library data is stored on the device and is not sent to the developer.
- The only network requests are user-initiated: search text to openlibrary.org
  when the reader taps Search, and the chosen cover image download.

## Google Play — Data safety

- Collects or shares data with the developer: **No**.
- The search text goes to a third-party service the reader chose to query, with
  no identifier attached. Decide whether to declare it (for example as in-app
  search history, "not collected by developer, shared with Open Library") or
  rely on Play's exemption for user-initiated transfers. Declaring it is the
  conservative choice.
- Data encrypted in transit: **Yes** (HTTPS). Deletion request: not applicable
  (no developer-held data).

## Apple — App Privacy

- Tracking: **No**. No tracking domains.
- Data collected: **Data Not Collected** is expected, because nothing reaches
  the developer. The Open Library search text is the one item to weigh against
  Apple's definition of collection; if in doubt, declare "Search History,
  not linked to identity, not used for tracking".
- Photos: access is only through the system picker when choosing a cover.
