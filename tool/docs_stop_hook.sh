#!/usr/bin/env bash
# Claude Code Stop hook. If the docs no longer cover the code, tell Claude to
# update them before it stops. Exit 2 feeds stderr back to Claude. It never
# blocks twice in a row (stop_hook_active), so it cannot loop.
input=$(cat)
if echo "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
out=$("$root/tool/check_docs.sh" --quiet 2>&1)
if [ $? -ne 0 ]; then
  {
    echo "The docs in docs/ no longer match the code. Run the update-docs skill (.claude/skills/update-docs/SKILL.md) and fix these before finishing:"
    echo "$out"
  } >&2
  exit 2
fi
exit 0
