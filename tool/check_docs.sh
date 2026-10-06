#!/usr/bin/env bash
# Checks that docs/ still describe the code.
#
#   tool/check_docs.sh [--quiet] [--strict-stale]
#
# Exit 1 when the docs miss something the code now has (a source file, table,
# route, provider, dependency, keepsake, or test file), point at something that
# no longer exists, or state a wrong test count. Files changed since the last
# docs sync (docs/.docs-synced) are only a warning, unless --strict-stale.
set -uo pipefail
cd "$(dirname "$0")/.."
quiet=0; strict=0
for a in "$@"; do
  case "$a" in
    --quiet) quiet=1 ;;
    --strict-stale) strict=1 ;;
  esac
done
arch=docs/architecture.md features=docs/features.md testing=docs/testing.md
design=docs/design-system.md
fail=0
miss() { echo "DOCS: $1" >&2; fail=1; }
has() { grep -qF -- "$1" "$2"; }

# Every source file is in the architecture file map, and nothing listed is gone.
while read -r f; do
  has "\`$f\`" "$arch" || miss "$f is missing from the file map in $arch"
done < <(find lib -name '*.dart' | sort)
while read -r f; do
  [ -e "$f" ] || miss "$arch lists $f, which no longer exists"
done < <(grep -oE 'lib/[A-Za-z0-9_/.]+\.dart' "$arch" | sort -u)

# Every Drift table is described.
while read -r c; do
  snake=$(echo "$c" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr 'A-Z' 'a-z')
  has "\`$snake\`" "$arch" || miss "table $snake is not described in $arch"
done < <(grep -oP 'class \K\w+(?= extends Table)' lib/core/storage/database.dart)

# Every route is described.
while read -r r; do
  has "$r" "$features" || miss "route $r is not described in $features"
done < <(grep -oP "path: '\K/[^']+" lib/app/app.dart | sort -u)

# Every provider is described.
while read -r p; do
  has "\`$p\`" "$arch" || miss "provider $p is not described in $arch"
done < <(grep -oP 'final \K\w+Provider' lib/app/providers.dart)

# Every direct dependency is described.
while read -r d; do
  has "$d" "$arch" || miss "dependency $d is not described in $arch"
done < <(grep -E '^  [a-z_0-9]+: [0-9^]' pubspec.yaml | sed -E 's/^  ([a-z_0-9]+):.*/\1/')

# Every keepsake is described in both places that name them.
while read -r k; do
  has "$k" "$features" || miss "keepsake '$k' is not described in $features"
  has "$k" "$design" || miss "keepsake '$k' is not described in $design"
done < <(grep -oP "^\s+\w+\('\K[^']+(?=', \d+, Size)" lib/features/library/presentation/keepsakes.dart)

# Every test file is described, and the stated test count is right.
while read -r t; do
  has "\`$t\`" "$testing" || miss "$t is not described in $testing"
done < <(find test integration_test -name '*_test.dart' | sort)
count=$(grep -hE '^\s+(test|testWidgets)\(' test/*_test.dart | wc -l | tr -d ' ')
claimed=$(grep -oE '[0-9]+ unit and widget tests' "$testing" | head -1 | grep -oE '^[0-9]+')
[ "$claimed" = "$count" ] ||
  miss "$testing says ${claimed:-no} unit and widget tests; the code has $count"

# Links between docs resolve.
for doc in docs/*.md; do
  while read -r l; do
    [ -e "docs/$l" ] || miss "$doc links to $l, which does not exist"
  done < <(grep -oP '\]\(\K[^)#:]+\.md' "$doc" | sort -u)
done

# Staleness is a warning: source files newer than the last sync marker.
if [ -e docs/.docs-synced ]; then
  newer=$(find lib test integration_test tool pubspec.yaml \
    android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts \
    ios/Runner/Info.plist -type f -newer docs/.docs-synced \
    ! -name '*.g.dart' ! -path 'test/generated_migrations/*' 2>/dev/null | sort)
  if [ -n "$newer" ]; then
    echo "DOCS WARNING: $(echo "$newer" | wc -l | tr -d ' ') source file(s) changed since the last docs sync:" >&2
    echo "$newer" | head -10 | sed 's/^/  /' >&2
    echo "  Run /update-docs, then touch docs/.docs-synced." >&2
    [ "$strict" = 1 ] && fail=1
  fi
fi

if [ "$fail" = 0 ] && [ "$quiet" = 0 ]; then echo "docs: ok"; fi
exit "$fail"
