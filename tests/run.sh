#!/usr/bin/env bash
# tests/run.sh [tests/test-x.sh ...] -- runs every tests/test-*.sh (or the
# files named), prints one line per failure and a total, exits 1 on any
# failure. Spends nothing: a stub `claude` that exits 99 is first on PATH.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
trap 'rm -rf "$GR_TMP"' EXIT

if [ -n "${GUARDRAILS_EXPECT_BASH:-}" ]; then
  if [ "${BASH_VERSINFO[0]}" = "$GUARDRAILS_EXPECT_BASH" ]; then ok
  else bad "bash version -- wanted $GUARDRAILS_EXPECT_BASH.x, running $BASH_VERSION"; fi
fi

if [ $# -eq 0 ]; then set -- "$here"/test-*.sh; fi
for t in "$@"; do . "$t"; done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
