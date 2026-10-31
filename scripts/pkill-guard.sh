#!/usr/bin/env bash
# PreToolUse (Bash|PowerShell): refuse `pkill -f` (or --full), with the safe
# way in the reason. The agent's shell runs the command line as its own
# arguments, so `pkill -f <pattern>` matches -- and kills -- that shell too
# (exit 144). Denied rather than asked: the command never works safely here,
# and the reason says what to run instead. Prints nothing for every other
# command.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
gr_need_jq pkill-guard
input=$(cat)
cmd=$(gr_jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0

# `pkill` with an -f flag (alone or bundled, e.g. -9f) where it would RUN: at
# the start, or after &&, ||, ;, |, ( or a newline.
printf '%s\n' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*(sudo[[:space:]]+)?pkill[^;&|]*[[:space:]]-[a-zA-Z0-9]*f' \
  || printf '%s\n' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*(sudo[[:space:]]+)?pkill[[:space:]]+--full' \
  || exit 0

reason='pkill -f matches the shell running this command (its command line holds the pattern) and kills it (exit 144). Find the PID first, excluding this shell: ps ax | grep "[p]attern" -- the [p] stops grep matching itself -- then kill <pid> in a separate command.'
gr_jq -n --arg r "pkill guard: $reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
