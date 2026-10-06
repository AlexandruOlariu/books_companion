#!/usr/bin/env bash
# Prints the app version name from pubspec.yaml ("0.1.0" for "0.1.0+1").
# With a tag argument it also checks the tag agrees ("v0.1.0"), so a release
# can never ship under a version number that differs from the app's own.
#
#   tool/release_version.sh [vX.Y.Z]
set -euo pipefail
cd "$(dirname "$0")/.."
name=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml | head -1)
[ -n "$name" ] || { echo "No version in pubspec.yaml" >&2; exit 1; }
if [ -n "${1:-}" ] && [ "${1#v}" != "$name" ]; then
  echo "Tag $1 does not match pubspec.yaml version $name. Update pubspec.yaml or retag." >&2
  exit 1
fi
echo "$name"
