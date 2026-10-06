#!/usr/bin/env bash
# Sets the app's permanent identifier for Android and iOS in one step.
# Usage: tool/set_bundle_id.sh com.yourname.readinglibrary
set -euo pipefail
id="${1:-}"
# Lowercase letters and digits in dot-separated parts: valid on both platforms
# (iOS forbids underscores; Android forbids a leading digit in a part).
if [[ ! "$id" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]; then
  echo "Usage: $0 <reverse.domain.id>   e.g. com.example.readinglibrary" >&2
  echo "Use lowercase letters and digits only, with at least two dot-separated parts." >&2
  exit 1
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
gradle="$root/android/app/build.gradle.kts"
pbx="$root/ios/Runner.xcodeproj/project.pbxproj"
# Only applicationId changes on Android. The Kotlin namespace is a code package
# and deliberately stays as it is.
sed -i -E "s/^( *applicationId = )\"[^\"]*\"/\1\"$id\"/" "$gradle"
sed -i -E "s/(PRODUCT_BUNDLE_IDENTIFIER = )[A-Za-z0-9._-]+\.RunnerTests;/\1$id.RunnerTests;/" "$pbx"
sed -i -E "/RunnerTests;/! s/(PRODUCT_BUNDLE_IDENTIFIER = )[A-Za-z0-9._-]+;/\1$id;/" "$pbx"
grep -n 'applicationId' "$gradle"
grep -n 'PRODUCT_BUNDLE_IDENTIFIER' "$pbx" | sort -u -k3
