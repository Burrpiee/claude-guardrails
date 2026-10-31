#!/usr/bin/env bash
# PreCompact: before a long session is summarised, save the live state the
# summary might lose -- time, the project's (and its partners') branches and
# unmerged work, dev ports -- to that project's memory folder. Overwritten
# each compaction; compaction-log.md beside it gains one line each time.
# Quiet and exit 0 on any failure.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
input=""; [ ! -t 0 ] && input=$(cat)
field() { gr_jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
dir=$(field .cwd)
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}
mem=$("$here/config.sh" memory "$dir")
[ -n "$mem" ] && mkdir -p "$mem" 2>/dev/null || exit 0
{
  echo "---"
  echo "name: precompact-snapshot"
  echo "description: \"Live git state and time saved automatically just before the last context compaction; read after a compaction to check what the summary may have lost.\""
  echo "metadata:"
  echo "  type: reference"
  echo "---"
  echo
  echo "# State just before the last compaction ($(date -u +%Y-%m-%dT%H:%MZ))"
  echo
  echo "Written by the guardrails plugin's precompact-snapshot.sh; not a memory, just a snapshot."
  echo
  echo '```'
  "$here/session-status.sh" "$dir" </dev/null
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    echo "--- $(basename "$r") last 3 commits on $(git -C "$r" branch --show-current 2>/dev/null)"
    git -C "$r" log --oneline -3 2>/dev/null
  done <<EOF
$("$here/config.sh" repos "$dir")
EOF
  echo '```'
} > "$mem/precompact-snapshot.md" 2>/dev/null

sid=$(field .session_id); sid=${sid:-?}; t=$(field .transcript_path); trigger=$(field .trigger)
n=""; [ -n "$t" ] && read -r n _ <<EOF
$("$here/context-tokens.sh" "$t" 2>/dev/null)
EOF
size="size unknown"; [ -n "$n" ] && size="~$((n / 1000))k tokens"
"$here/compaction-log.sh" "$dir" "${trigger:-?}  $size  session $(printf '%s' "$sid" | cut -c1-8)  requested"
exit 0
