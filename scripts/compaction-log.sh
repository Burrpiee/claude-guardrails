#!/usr/bin/env bash
# compaction-log.sh <dir> <text> -- append one dated line to compaction-log.md
# in the memory folder of the project at <dir>, so "did it compact, when, and
# why" is read from a file, not guessed. Called by the PreCompact hooks;
# writes the header on first use; quiet and exit 0 on anything unexpected.
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-}; text=${2:-}
[ -n "$dir" ] && [ -n "$text" ] || exit 0
mem=$("$here/config.sh" memory "$dir" 2>/dev/null)
[ -n "$mem" ] && mkdir -p "$mem" 2>/dev/null || exit 0
log="$mem/compaction-log.md"
if [ ! -e "$log" ]; then
  printf '%s\n' '---' 'name: compaction-log' \
    'description: "One line each time Claude Code began compacting a session (UTC time, trigger, size, session) and each one a hook skipped; read it to answer when and why a session compacted instead of guessing."' \
    'metadata:' '  type: reference' '---' '' '# Compactions, one line each' '' \
    'Appended by the guardrails plugin from its PreCompact hooks. Not a memory: never prune or edit it.' '' \
    > "$log" 2>/dev/null || exit 0
fi
echo "- $(date -u +%Y-%m-%dT%H:%MZ)  $text" >> "$log" 2>/dev/null
exit 0
