#!/usr/bin/env bash
# PreToolUse (Agent|Task): refuse to launch an agent until its work would
# survive a usage limit -- MEMORY.md written in the last 30 minutes (a "Where
# to resume" note) and the prompt saved in a file the prompt names. Off
# unless the project's config says `agent_launch_guard = on`. Denied rather
# than asked: the reason says what to write, and the retry passes once it is
# written. Quick lookups (Explore and the like) are let through. Prints
# nothing when both are in place.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
gr_need_jq agent-launch-guard
input=$(cat)
prompt=$(gr_jq -r '.tool_input.prompt // empty' <<<"$input" 2>/dev/null) || prompt=""
[ -n "$prompt" ] || exit 0
case "$(gr_jq -r '.tool_input.subagent_type // empty' <<<"$input" 2>/dev/null)" in
  Explore|claude-code-guide|statusline-setup) exit 0 ;;
esac
dir=$(gr_jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || dir=""
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}
[ -n "$("$here/config.sh" project "$dir")" ] || exit 0
[ "$("$here/config.sh" get "$dir" agent_launch_guard | head -1)" = on ] || exit 0
mem=$("$here/config.sh" memory "$dir")
set -f

missing=""
if [ -z "$mem" ] || [ -z "$(find "$mem/MEMORY.md" -mmin -30 2>/dev/null)" ]; then
  missing="write an interim \"Where to resume\" in ${mem:-the memory folder}/MEMORY.md: what this agent does, where its prompt is saved, and what to do if it never returns; "
fi

# saved: a file the prompt names exists. A path may hold spaces, be quoted,
# or be written C:/x, C:\x, /c/x or ~/x, so try every run of words that
# starts like a path and ends in .md or .txt.
saved=
while IFS= read -r line; do
  # shellcheck disable=SC2206
  words=($line)
  i=0
  while [ $i -lt ${#words[@]} ] && [ -z "$saved" ]; do
    case "${words[$i]}" in
      [\"\'\`\(]*) w=${words[$i]#?} ;;
      *) w=${words[$i]} ;;
    esac
    case "$w" in
      "~"*|/*|\\*|[A-Za-z]:/*|[A-Za-z]:\\*)
        j=$i; cand=""
        while [ $j -lt ${#words[@]} ]; do
          cand="$cand${cand:+ }${words[$j]}"
          case "${words[$j]}" in
            *.md*|*.txt*)
              p=$(printf '%s' "$cand" | sed -E 's/^[("'"'"'`]+//; s/(\.(md|txt))[^A-Za-z0-9]*$/\1/')
              [ -f "$(gr_abspath "$p")" ] && { saved=1; break; } ;;
          esac
          j=$((j + 1))
        done ;;
    esac
    i=$((i + 1))
  done
  [ -n "$saved" ] && break
done <<EOF
$prompt
EOF
[ -n "$saved" ] || missing="${missing}save the prompt to a file (beside the plan, or in a scratch folder) and pass a short prompt that names that file; "
[ -n "$missing" ] || exit 0

reason="before launching an agent, so a usage limit cannot lose its work: ${missing}then launch it again."
gr_jq -n --arg r "Agent launch guard: $reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
