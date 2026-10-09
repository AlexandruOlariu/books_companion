# Release checklist

Work that needs a Mac, a physical device, or an account of yours is listed
separately in `implementation-status.md`. This file covers what is prepared in
the repository and what you must still do by hand.

## 1. Choose the permanent app identifier (once)

The current identifier, `app.readingroom.reading_library`, is a placeholder. An
identifier cannot be changed after the first store upload.

```sh
tool/set_bundle_id.sh com.yourname.readinglibrary
```

Use a domain or name you control. The script sets Android `applicationId` and
the iOS bundle identifier (including the test target) to the same value. It
leaves the Kotlin `namespace` alone: that is a code package, not the store
identity.

## 2. Android signing

1. Create an upload key once and keep it, with its passwords, somewhere backed
   up. Losing it blocks updates unless Play App Signing key reset is available.

   ```sh
   keytool -genkeypair -v -keystore ~/upload-keystore.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and fill
   it in. It and `*.jks` are git-ignored.
3. Build:

   ```sh
   flutter build appbundle --release
   ```

A release build **fails** without `android/key.properties`. For a local smoke
test only, `READING_LIBRARY_DEBUG_SIGNING=1 flutter build apk --release` signs
with the debug key; Google Play rejects those builds.

Verified here: a release APK built with a throwaway key is signed by that key
and requested only the `INTERNET` permission (used for Open Library
search). That check predates the friends feature: the debug build now also
requests `READ_CONTACTS` (checked in its merged manifest); a release build has
not been re-inspected since.

Before the first release that includes Friends: update the store listings per
`store-privacy.md` (data safety and app privacy answers change), publish the
privacy policy with the friends section filled in, add the web account-deletion
page Google Play requires, and make sure the server is running and backed up
(`backend.md`). The server address is `HttpFriendsApi.defaultOrigin`.

## 3. iOS signing (on a Mac)

Open `ios/Runner.xcworkspace`, select your team under Runner > Signing &
Capabilities, then `flutter build ipa --release`. Signing style is Automatic and
no team is committed.

Not yet done (needs Xcode): an app-level `PrivacyInfo.xcprivacy` added to the
Runner target. The app code itself uses no tracking; it sends only the account data and the saved library
and the online search text (not stored, see `store-privacy.md`), but
confirm the archive's generated privacy report in Xcode before submitting.

## 3a. Automated releases (GitHub Actions)

`.github/workflows/release.yml` builds and publishes the APK so nothing has to be built or uploaded by hand.

**Every push to `main` makes a new release (D39).**

1. Push to `main`. The workflow runs format check, analyze, all tests, `tool/check_docs.sh` and `tool/test_release_scripts.sh`, then builds a release APK and publishes a GitHub Release with the APK and `SHA256SUMS.txt`. Any failing step stops the release.
2. The version is chosen by `tool/next_release_version.sh`: the newest plain `vX.Y.Z` tag with its patch number raised by one (`v0.1.1` becomes `v0.1.2`), or the `pubspec.yaml` version when that is newer than every tag (set `version: 0.2.0+1` and push to release `v0.2.0`; the part after `+` is ignored). The tag is created on the tested commit when the release is published.
3. To push without releasing, put `[skip release]` in the head commit's message. Only the head commit of the push is looked at.
4. A pushed tag (`git tag v0.2.0 && git push origin v0.2.0`) still releases under exactly that name, and is refused if it does not match `pubspec.yaml` (`tool/release_version.sh`). Use it for a hand-picked version number.
5. To build without publishing, run the workflow by hand from the Actions tab; the APK is kept as a workflow artifact for 30 days.

Several pushes in quick succession are queued one at a time; GitHub drops a queued run when a newer one arrives behind it, so a burst may release only its last commit. The workflow's own token creates the tag, which by GitHub's rule does not start a second run. Every release is public and carries the whole app, so docs-only pushes also publish one: use `[skip release]` for those.

**Signing.** With the four repository secrets below the APK is signed with your upload key and published as a normal release, and later releases update earlier ones. Without them CI signs with a throwaway debug key and marks the release **pre-release** with a warning: it installs for testing but cannot update a build signed by another key. Each CI run would otherwise produce a different debug key, so set the secrets before sharing builds widely.

```sh
# one time: create the key (keep the .jks and passwords backed up outside git)
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
# store it as repository secrets (needs the GitHub CLI, logged in)
base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS          # upload
gh secret set ANDROID_KEY_PASSWORD
```

**Build number.** Android only accepts an update with a higher `versionCode`, so CI uses the workflow run number as the build number and the release version as the version name, instead of the `+N` in `pubspec.yaml`. On Android, Settings and licences read the installed package version through the native update channel, so they follow the release version.

**Where the upload key is.** The key was generated on 2026-10-06 and lives in `~/.config/reading-library-signing/` on the development machine (`upload-keystore.jks` and `passwords.txt`, both mode 600, outside the repository), with copies in the four GitHub secrets. Back that folder up somewhere safe: GitHub secrets cannot be read back, and without the key no update can be signed to replace an installed build. Never commit it or paste its passwords anywhere. Its certificate is `CN=Reading Library, OU=Upload key`.

**Status.** Verified on GitHub on 2026-10-06: a manual run built and signed an APK, then the tag `v0.1.0` published the first release (signed, not a pre-release; the downloaded APK matched `SHA256SUMS.txt` and carried the upload-key certificate; versionCode 2). *Update 2026-10-07:* the repository is **public**, so anyone can download from Releases (and read the code and docs); there is no private distribution through GitHub. To share a build privately, send the file directly. CI shows warnings that should be cleared at some point: Node 20 deprecation for the v4 actions and a deprecated `actions/setup-java@v4` (move to v5). It signs Android only; iOS releases need a Mac and signing (section 3). Only the Android job publishes; the iOS simulator job in `checks.yml` is separate.

## 3a-2. Friend notifications (Firebase)

Notifications need a Firebase project that only the owner can create (D47). Without it everything still builds; the app just says it cannot send notifications and the server sends nothing.

1. In the Firebase console create a project. **Do not enable Google Analytics.** Add an Android app whose package name is the application ID (`app.readingroom.reading_library` while it is a placeholder; if the ID is changed later, add the new app and replace the file). Download `google-services.json`.
2. Put that file at `android/app/google-services.json` (git-ignored) for local builds, and give CI the same text: `gh secret set GOOGLE_SERVICES_JSON < android/app/google-services.json`. The release workflow writes it before building. The file holds identifiers rather than passwords, but it is per-owner configuration, so it stays out of the repository.
3. Project settings > Service accounts > Generate new private key. **This one is a secret.** Save it as `server/secrets/fcm.json` (mode 644 so the container user can read it; the folder is git-ignored), set `FCM_CREDENTIALS_FILE=/srv/secrets/fcm.json` in `server/.env`, then `docker compose up -d --build`. The new migration (`0003`) runs on start.
4. Build and install a release APK, sign in on two phones, turn notifications on for one, and send it a friend request from the other.
5. Changing the application ID or signing key does not break existing tokens, but the Firebase Android app must match the package name.

For iOS later: add an iOS app in Firebase, upload an APNs key from the Apple developer account, add `GoogleService-Info.plist` to the Runner target, enable the Push Notifications capability, and let `FirebasePushService.create()` initialise on iOS (today it returns "unavailable" there on purpose, because initialising without the plist crashes).

## 3b. Sharing a build without committing it

Built APKs and bundles are ignored by git (`dist/`, `*.apk`, `*.aab`); an APK is about 60 MB and GitHub warns above 50 MB. To share one, attach it to a GitHub Release (`gh release create v0.1.0 dist/reading-library-0.1.0.apk`) or send the file directly. A debug-signed APK installs for testing but cannot update a build signed with a different key.

## 4. Version

`pubspec.yaml` `version: 0.1.0+1` is `name+buildNumber`. Increase the build
number for every upload.

## 5. Store listings

- Privacy policy: publish `privacy-policy.md` (after filling in the contact
  line) at a public URL; both stores require one.
- Data safety / App Privacy answers: see `store-privacy.md`.
- Screenshots: `docs/screenshots` are emulator captures of the demo entry point.
  Produce store-sized shots from a seeded build on target devices.
- Icon: `assets/branding/reading-room-icon.png`; review at store sizes.

## 6. Before pressing submit

- `flutter analyze && flutter test`
- Install the signed build on a real device, add a book, back up, restore on a
  second install, and confirm covers survive.
- Complete the real-device checks in `implementation-status.md`.

## Android downloads and updates without Google Play

New releases use the fixed APK filename `reading-library.apk`. Share this permanent link after publishing the first release with that asset:

https://github.com/AlexandruOlariu/books_companion/releases/latest/download/reading-library.apk

The signed release pipeline also publishes `update.json` (schema 1: version, buildNumber, applicationId, downloadUrl), generated from the compiled Android manifest. Unsigned test releases stay pre-releases and do not contain update metadata; manually dispatched artifact-only builds do not contain it either. Older published releases have versioned APK filenames and no update metadata. Until the first new signed release is published, checking may report unavailable metadata. The workflow and live download links must be exercised after publishing; local checks are not evidence of a successful GitHub run.

Install the first update-enabled release manually. Later versions offer a browser download from inside the app. Android still requires the reader to open the APK, allow installation from their browser/file app if asked, and confirm Update. Keep the application ID, signing key, and increasing build number to preserve an in-place update and its library. Verify on a phone that an older signed APK updates with its books intact. Automatic checks contact GitHub; see `privacy-policy.md`.

**Share app (2026-10-08):** the main toolbar and Settings share the permanent latest-APK URL above with Android install/update instructions. Settings can also copy that URL. Its live download returned HTTP 200 for v0.1.8 during this work; it follows future signed releases automatically. This is an app invitation, not a private library export or an automatic friend request.
