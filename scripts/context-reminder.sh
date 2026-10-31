#!/usr/bin/env bash
# UserPromptSubmit: once the session carries more than ~250k tokens, remind
# the model to suggest a handoff or /compact at the next natural break: every
# step re-reads the whole context, so a long session quietly costs most of
# its spend. Never blocks the prompt: on any failure it prints nothing and
# exits 0. The count and threshold: context-tokens.sh.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
gr_jq || exit 0
input=$(cat)
t=$(gr_jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$t" ] || exit 0
read -r n state <<EOF
$("$here/context-tokens.sh" "$t" 2>/dev/null)
EOF
[ "${state:-}" = warn ] || exit 0
msg="Context is ~$((n / 1000))k tokens, re-read on every step. At the next natural break -- not mid-task -- suggest to the user a session handoff or /compact, in one line."
gr_jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}' 2>/dev/null
exit 0
