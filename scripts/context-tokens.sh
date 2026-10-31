#!/usr/bin/env bash
# context-tokens.sh <transcript.jsonl> -- how many tokens this session carries.
#
# Prints "<tokens> ok" or "<tokens> warn" (warn from GUARDRAILS_WARN_TOKENS,
# default 250000), or nothing when the transcript is missing, holds no usable
# reply, or jq is missing. The count is the last main-chain reply's input +
# cache-creation + cache-read tokens: what every next step re-reads. A helper
# agent's (sidechain) replies and zero-usage synthetic ones are skipped.
# Reads from the end, widening the window until a reply is found: a long
# session's transcript runs to tens of MB. A compaction stops the search: a
# reply before it measured the context the compaction replaced, so nothing is
# printed until the first reply after it.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
t=${1:-}
[ -f "$t" ] && gr_jq || exit 0
warn=${GUARDRAILS_WARN_TOKENS:-250000}
size=$(wc -c < "$t" | tr -d ' ')
window=${GUARDRAILS_TAIL_BYTES:-1048576}
while :; do
  n=$(tail -c "$window" "$t" | gr_jq -Rrn '
    [inputs | fromjson? | objects | select(.isSidechain | not)
     | if .type == "system" and .subtype == "compact_boundary" then "compacted"
       elif .type == "assistant" then
         (.message | objects | .usage | objects) as $u
         | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))
         | select(. > 0)
       else empty end] | last // empty' 2>/dev/null)
  [ "$n" = compacted ] && exit 0
  if [ -n "$n" ]; then
    if [ "$n" -ge "$warn" ]; then echo "$n warn"; else echo "$n ok"; fi
    exit 0
  fi
  [ "$window" -lt "$size" ] || exit 0
  window=$((window * 4))
done
