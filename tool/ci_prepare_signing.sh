#!/usr/bin/env bash
# CI only. Turns repository secrets into android/key.properties so the release
# build is signed with the project's own upload key.
#
# Expects ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
# ANDROID_KEY_PASSWORD. Prints "signed=true" or "signed=false" (for
# $GITHUB_OUTPUT). With no keystore secret it signs nothing and says so; the
# workflow then falls back to a debug-signed, pre-release APK.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "signed=false"
  exit 0
fi
for v in ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "$v is required when ANDROID_KEYSTORE_BASE64 is set" >&2; exit 1; }
done
keystore="${RUNNER_TEMP:-$(mktemp -d)}/upload-keystore.jks"
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$keystore"
chmod 600 "$keystore"
umask 077
cat > android/key.properties <<PROPS
storeFile=$keystore
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
keyPassword=$ANDROID_KEY_PASSWORD
PROPS
echo "signed=true"
