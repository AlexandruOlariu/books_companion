---
name: update-docs
description: Keep docs/ in sync with the Reading Library code. Use after implementing or changing anything (a feature, UI or shelf change, data model, search, dependency, platform or release config, tests, a product decision), before finishing any task that touched the code, whenever the user mentions docs, documentation, the changelog, or rebuilding the POC, and whenever tool/check_docs.sh or the stop hook reports docs problems.
---

# Update the docs

`docs/` describes the working POC completely enough that it can be maintained or rebuilt from it. Your job is to make it true again after a change. Docs describe what the code **does**, so read the code; never document from memory or from what was intended.

## Steps

1. **See what is out of date.** Run `tool/check_docs.sh`. Lines starting `DOCS:` are structural gaps that must be fixed. A `DOCS WARNING` lists source files changed since the last sync (`docs/.docs-synced`); read each of those files and decide what it changes. Also use the conversation: what did you or the user just change?
2. **Find the right doc for each change** with the table below. Update every doc a change touches; each fact lives in exactly one place, and other docs link to it.
3. **Write the update.** Follow the rules below.
4. **Tests.** If tests were added, removed, or changed: run `./tool/flutterw test`, then update the count line in `docs/testing.md` ("N unit and widget tests", which the checker compares with the code), the inventory table, and "Latest results".
5. **Screenshots.** If the UI changed visibly, recapture the affected ones (see below) and make sure `docs/*.md` still describe what they show.
6. **Changelog and decisions.** Add a dated entry at the top of `docs/changelog.md` (use `date +%F`). If you made, changed, or reversed a decision, add or append to a `D<n>` entry in `docs/decisions.md` with the reason and the cost; use the next unused number and never delete an entry.
7. **Verify.** Run `tool/check_docs.sh` until it prints `docs: ok`. Then `touch docs/.docs-synced`. Do not touch the marker if you did not actually review the changes.
8. **Report** to the user in one or two lines: which docs changed. Do not paste the docs.

## What goes where

| You changed | Update |
| --- | --- |
| A screen, flow, rule, message, or limit the reader sees | `features.md` (and `design-system.md` if it is visual) |
| A Dart file added, renamed, or removed | the file map in `architecture.md` (every `lib/` file must be listed) |
| Tables, columns, validation, the repository interface, backup format, startup, providers, routes, platform config, dependencies | `architecture.md` (data model, providers, platform config, stack table) |
| Schema version | `architecture.md` (Migrations), root `README.md` commands if they changed, a `decisions.md` entry |
| Colours, type, components, shelf or keepsake rendering | `design-system.md` |
| A choice with a reason, a trade-off, or a reversal | `decisions.md` |
| Tests, how to run them, what is verified or not | `testing.md`; also `implementation-status.md` for checks run and what remains |
| Signing, bundle id, permissions, privacy-relevant behaviour (what is sent where) | `release.md`, `privacy-policy.md`, `store-privacy.md` |
| A trap you hit that a rebuild would hit again | `rebuild-guide.md` |
| A new top-level doc | add it to the table in `docs/README.md` |
| Anything | one dated line in `changelog.md` |

Privacy-relevant changes (a new network call, a new permission, new data stored or shared) must also update the privacy policy and store declarations, and be called out to the user.

## Rules

- Quote user-facing strings exactly when tests or the design depend on them.
- Keep `features.md` free of implementation detail and `architecture.md` free of UI copy.
- State what is **not** verified honestly (`testing.md`, `implementation-status.md`); do not turn "built" into "verified on a device".
- When behaviour contradicts an older doc line, fix the old line; do not leave both.
- `product-plan.md` is frozen source material. Do not edit it; record departures in `decisions.md`.
- Docs are in English. Reply to the user in the language they write in.

## Recapturing screenshots

The emulator is `Pixel_9_Pro`; the SDK is `~/Android/Sdk`. Start it if needed, install the app, seed a realistic library (`./tool/flutterw run -d emulator-5554 -t lib/dev_seed.dart --no-resident`, wait for the covers to download), then:

```sh
adb exec-out screencap -p > docs/screenshots/<descriptive-name>.png
```

Navigate with `adb shell input tap/swipe` (the screen is 1280 x 2856). Keep file names descriptive (`library.png`, `reading.png`, `journal.png`, `search-online-results.png`, ...) and replace rather than accumulate. Screenshots show sample data from `dev_seed`, not a real reader's library; say so if you add a note.
