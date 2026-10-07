#!/usr/bin/env bash
# Checks tool/next_release_version.sh against made-up tag lists. Run by CI.
set -euo pipefail
cd "$(dirname "$0")/.."
pubspec=$(./tool/release_version.sh)
fail=0
expect() { # name expected tags...
  local name=$1 want=$2; shift 2
  local got
  got=$(RELEASE_TAGS=$(printf '%s\n' "$@") ./tool/next_release_version.sh)
  if [ "$got" != "$want" ]; then echo "FAIL $name: wanted $want, got $got"; fail=1; else echo "ok   $name"; fi
}
expect "no tags uses pubspec" "$pubspec"
expect "patch goes up from the newest tag" "1.2.4" v1.2.3 v1.2.2 v0.9.9
expect "numeric, not alphabetic, order" "1.10.1" v1.9.0 v1.10.0
expect "pre-release tags are ignored" "1.2.4" v1.2.3 v1.2.4-build.7 v9.9.9-rc1
expect "a tag that is not a version is ignored" "1.2.4" v1.2.3 vnext
# A pubspec newer than every tag wins; this needs a pubspec we control.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tool"; cp tool/release_version.sh tool/next_release_version.sh "$tmp/tool/"
printf 'version: 3.0.0+1\n' > "$tmp/pubspec.yaml"
got=$(cd "$tmp" && RELEASE_TAGS=$'v1.2.3\nv2.9.9' ./tool/next_release_version.sh)
if [ "$got" != "3.0.0" ]; then echo "FAIL newer pubspec wins: got $got"; fail=1; else echo "ok   newer pubspec wins"; fi
printf 'version: 1.2.3+1\n' > "$tmp/pubspec.yaml"
got=$(cd "$tmp" && RELEASE_TAGS=$'v1.2.3' ./tool/next_release_version.sh)
if [ "$got" != "1.2.4" ]; then echo "FAIL pubspec equal to the newest tag: got $got"; fail=1; else echo "ok   pubspec equal to the newest tag"; fi
exit $fail
