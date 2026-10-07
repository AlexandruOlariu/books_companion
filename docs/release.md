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
and requested only the `INTERNET` permission (used for optional Open Library
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
Runner target. The app code itself uses no tracking; it sends only the optional account data
and the online search text (not stored, see `store-privacy.md`), but
confirm the archive's generated privacy report in Xcode before submitting.

## 3a. Automated releases (GitHub Actions)

`.github/workflows/release.yml` builds and publishes the APK so nothing has to be built or uploaded by hand.

1. Make sure `pubspec.yaml` has the version you want (`version: 0.2.0+1`; the part after `+` is ignored by CI).
2. Push a tag that matches it: `git tag v0.2.0 && git push origin v0.2.0`.
3. The workflow runs format check, analyze, all tests, and `tool/check_docs.sh`, then builds a release APK and publishes a GitHub Release with the APK and `SHA256SUMS.txt`. Any failing step stops the release. A tag that does not match `pubspec.yaml` is refused (`tool/release_version.sh`).
4. To build without publishing, run the workflow by hand from the Actions tab; the APK is kept as a workflow artifact for 30 days.

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

**Build number.** Android only accepts an update with a higher `versionCode`, so CI uses the workflow run number as the build number and the tag as the version name, instead of the `+N` in `pubspec.yaml`.

**Where the upload key is.** The key was generated on 2026-10-06 and lives in `~/.config/reading-library-signing/` on the development machine (`upload-keystore.jks` and `passwords.txt`, both mode 600, outside the repository), with copies in the four GitHub secrets. Back that folder up somewhere safe: GitHub secrets cannot be read back, and without the key no update can be signed to replace an installed build. Never commit it or paste its passwords anywhere. Its certificate is `CN=Reading Library, OU=Upload key`.

**Status.** Verified on GitHub on 2026-10-06: a manual run built and signed an APK, then the tag `v0.1.0` published the first release (signed, not a pre-release; the downloaded APK matched `SHA256SUMS.txt` and carried the upload-key certificate; versionCode 2). *Update 2026-10-07:* the repository is **public**, so anyone can download from Releases (and read the code and docs); there is no private distribution through GitHub. To share a build privately, send the file directly. CI shows warnings that should be cleared at some point: Node 20 deprecation for the v4 actions and a deprecated `actions/setup-java@v4` (move to v5). It signs Android only; iOS releases need a Mac and signing (section 3). Only the Android job publishes; the iOS simulator job in `checks.yml` is separate.

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
