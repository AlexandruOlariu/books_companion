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
and requests only the `INTERNET` permission (used for optional Open Library
search).

## 3. iOS signing (on a Mac)

Open `ios/Runner.xcworkspace`, select your team under Runner > Signing &
Capabilities, then `flutter build ipa --release`. Signing style is Automatic and
no team is committed.

Not yet done (needs Xcode): an app-level `PrivacyInfo.xcprivacy` added to the
Runner target. The app code itself uses no tracking and collects nothing, but
confirm the archive's generated privacy report in Xcode before submitting.

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
