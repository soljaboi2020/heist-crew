#!/usr/bin/env bash
# Syntax-check every Luau file (no Studio needed). Uses luau-compile from ~/.claude/bin.
cd "$(dirname "$0")/.." || exit 1
LC="${LUAU_COMPILE:-$HOME/.claude/bin/luau-compile}"
fail=0
for f in $(find src -name '*.lua'); do
  out=$("$LC" --null "$f" 2>&1) || { echo "FAIL $f"; echo "$out"; fail=1; }
done
python3 "$(dirname "$0")/check_materials.py" || fail=1
[ $fail = 0 ] && echo "all Luau files parse OK + materials valid"
exit $fail
