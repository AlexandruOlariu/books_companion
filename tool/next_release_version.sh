#!/usr/bin/env bash
# Prints the version for the next automatic release (a push to main), without
# the leading "v".
#
# It is the version in pubspec.yaml when that is newer than every release tag
# (the owner bumped it on purpose), otherwise the newest tag with its patch
# number raised by one. Only plain vX.Y.Z tags count. For tests, RELEASE_TAGS
# (one tag per line) replaces the tags read from git.
#
#   tool/next_release_version.sh
set -euo pipefail
cd "$(dirname "$0")/.."
pubspec=$(./tool/release_version.sh)
tags=${RELEASE_TAGS-$(git tag -l 'v*')}
latest=$(printf '%s\n' "$tags" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -1 || true)
if [ -z "$latest" ]; then
  echo "$pubspec"
  exit 0
fi
newest=$(printf '%s\n%s\n' "$pubspec" "$latest" | sort -V | tail -1)
if [ "$newest" = "$pubspec" ] && [ "$pubspec" != "$latest" ]; then
  echo "$pubspec"
else
  IFS=. read -r major minor patch <<<"$latest"
  echo "$major.$minor.$((patch + 1))"
fi
