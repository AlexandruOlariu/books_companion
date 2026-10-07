# Reading Library: project notes for Claude

A private, local-first reading journal for Android and iOS (Flutter). The owner writes in Romanian; reply in the language the user writes in. Docs and code comments are in English.

## Docs first, docs last

- **Start** by reading `docs/README.md`, then the doc for the area you will touch (`features.md`, `architecture.md`, `design-system.md`, `decisions.md`).
- **Before finishing any task that changed code, tests, or config**, run the `update-docs` skill (`.claude/skills/update-docs/SKILL.md`). Docs must always describe the current code, because the POC may be rebuilt from them.
- `tool/check_docs.sh` verifies the docs cover the code (also run in CI). A Stop hook (`tool/docs_stop_hook.sh`, configured in `.claude/settings.json`) will ask you to fix docs if it fails. Do not bypass it; fix the docs.

## Rules the product depends on

- Never invent dates or activity. A finish date keeps its precision (`day`, `month`, `year`, `unknown`). Only logged sessions create reading activity. Keepsakes are earned only by finished-book count. See `docs/features.md`.
- Personal notes are written to the device first and saved to the reader's own account on the server (D38); friends never see them. A new network call, permission, or place data is sent is a privacy change: tell the user and update `docs/privacy-policy.md` and `docs/store-privacy.md`.
- Never put secrets in the repo. `android/key.properties` and keystores are git-ignored; do not read them or print passwords. If a user pastes a password in chat, do not use it unless the task truly needs it, and suggest changing it.

## Working conventions

- Run Flutter through `./tool/flutterw` (it finds the SDK). Format with `dart format`, not `flutter format`.
- Before calling work done: `./tool/flutterw analyze`, `./tool/flutterw test`, and format check (`dart format --output=none --set-exit-if-changed lib test integration_test`). See `docs/testing.md`.
- Test layout at phone size (360 x 800 logical), not the default test surface.
- Screens call `LibraryRepository`, never Drift directly. Put rules in plain Dart so they can be unit-tested.
- Check changes in the running app on the emulator (`Pixel_9_Pro`), not only in tests. The integration test wipes app data; reseed with `lib/dev_seed.dart`.
- Schema changes need a version bump, a schema dump, a migration step, and a test (`docs/architecture.md`, Migrations).
- Release builds: `docs/release.md`. The app identifier is still a placeholder.
- Releases: `v<version>` tag, matching `pubspec.yaml`, triggers `.github/workflows/release.yml` (see `docs/release.md`). Never commit built artifacts (APK, AAB). `dist/` is git-ignored; GitHub warns above 50 MB.
