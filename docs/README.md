# Reading Library: documentation

A private, local-first reading journal for Android and iOS, built with Flutter. This folder describes the working POC completely enough to maintain it or rebuild it. Read in this order.

| Doc | Read it for |
| --- | --- |
| [features.md](features.md) | what the app does, screen by screen, with the rules behind it |
| [architecture.md](architecture.md) | stack, layers, data model, backup format, migrations, platform config, **file map** |
| [design-system.md](design-system.md) | colours, type, components, the bookshelf, keepsakes, layout lessons |
| [decisions.md](decisions.md) | why things are the way they are; open questions |
| [testing.md](testing.md) | how to run tests, what each covers, what is and is not verified |
| [backend.md](backend.md) | the Python/Postgres server for accounts, friends and shared shelves (the app's optional Friends feature uses it) |
| [rebuild-guide.md](rebuild-guide.md) | order of work, traps, things to do differently, commands |
| [changelog.md](changelog.md) | what changed and when |
| [implementation-status.md](implementation-status.md) | data-integrity guarantees, checks run, what remains before release |
| [release.md](release.md) | signing, bundle id, store submission checklist |
| [privacy-policy.md](privacy-policy.md), [store-privacy.md](store-privacy.md) | draft privacy policy and store declarations |
| [product-plan.md](product-plan.md) | the original product plan (frozen source; see decisions.md for departures) |
| `screenshots/` | emulator captures of the current build |

## Keeping these docs current

The docs are part of the work, not an afterthought. Four things keep them in sync:

1. **`.claude/skills/update-docs`**: the skill Claude runs after any change. It says which doc each kind of change belongs in. Invoke it with `/update-docs`, or it triggers itself after changes.
2. **`CLAUDE.md`** (project root): tells every session to read these docs first and to run the skill before finishing.
3. **`tool/check_docs.sh`**: checks that the docs still cover the code (every `lib/` file in the file map, every table, route, keepsake, and test file mentioned). It also warns when source files changed since the last sync. Runs in CI.
4. **`tool/docs_stop_hook.sh`** (wired in `.claude/settings.json`): when Claude finishes a turn and the structural check fails, it is told to update the docs before stopping.

The marker file `docs/.docs-synced` records the last sync; the skill refreshes it.

## Rules for editing docs

- Describe what the code does, verified against the code, never what was intended. If unsure, read the file.
- Record the reason for a decision in `decisions.md`, in the same change as the decision.
- Keep `features.md` free of implementation detail and `architecture.md` free of UI copy, so each fact lives in one place.
- Do not delete history: reverse a decision by appending to its entry; add a changelog line for every change.
