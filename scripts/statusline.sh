#!/usr/bin/env bash
# Status line: the session's context size and the branch, e.g. "ctx 63k · main",
# with "⚠ hand off" past GUARDRAILS_WARN_TOKENS (default 250000), so the user
# sees a session growing expensive, not only the model.
#
# Stands alone: the session status copies this file into the plugin's data
# folder, and settings.json runs that copy, because the plugin's own folder
# moves on every update. So it sources nothing and calls nothing of ours.
j=${GUARDRAILS_JQ:-jq}
command -v "$j" >/dev/null 2>&1 || exit 0
input=$(cat)
# tr: a Windows jq.exe may end each line with \r
n=$("$j" -r '.context_window.total_input_tokens // empty' <<<"$input" 2>/dev/null | tr -d '\r')
d=$("$j" -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null | tr -d '\r')
case "$n" in
  ''|*[!0-9]*) out="ctx –" ;;
  *) out="ctx $((n / 1000))k"
     [ "$n" -ge "${GUARDRAILS_WARN_TOKENS:-250000}" ] && out="$out ⚠ hand off" ;;
esac
b=""
[ -n "$d" ] && b=$(git -C "$d" branch --show-current 2>/dev/null)
[ -n "$b" ] && out="$out · $b"
echo "$out"
exit 0
