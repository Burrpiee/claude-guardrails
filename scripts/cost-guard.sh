#!/usr/bin/env bash
# PreToolUse (Bash|PowerShell): ask the user before a command their project
# names as costly or deploying. Each project lists its own in
# .claude/guardrails.conf:
#
#   guard = <runs> :: <requires> :: <forbids> :: <reason>
#
# <runs> is a regex that must match where the command RUNS (at the start or
# after &&, ||, ;, | or a newline -- not inside echo "..." or a grep
# pattern); every <requires> part (split on " && ") must match somewhere;
# <forbids> must not. A session gets its project's guards and its partners'.
# Prints nothing -- and so leaves the normal permission flow -- otherwise.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
gr_need_jq cost-guard
input=$(cat)
cmd=$(gr_jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0
dir=$(gr_jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || dir=""
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}

has()  { printf '%s\n' "$cmd" | grep -qE -- "$1"; }
S='(^|[;&|]|&&|\|\|)[[:space:]]*'
runs() { printf '%s\n' "$cmd" | grep -qE -- "${S}$1"; }
trim() { local v=$1; v=${v#"${v%%[![:space:]]*}"}; printf '%s' "${v%"${v##*[![:space:]]}"}"; }

# check LINE: succeeds (setting reason) when the guard on LINE fires.
check() {
  local rest=$1 run req forbid r
  run=$(trim "${rest%%::*}");  rest=${rest#*::}
  req=$(trim "${rest%%::*}");  rest=${rest#*::}
  forbid=$(trim "${rest%%::*}"); rest=${rest#*::}
  [ -n "$run" ] && runs "$run" || return 1
  while [ -n "$req" ]; do
    r=$(trim "${req%% && *}")
    case "$req" in *" && "*) req=${req#* && } ;; *) req="" ;; esac
    [ -z "$r" ] || has "$r" || return 1
  done
  [ -n "$forbid" ] && has "$forbid" && return 1
  reason=$(trim "$rest")
}

reason=""
while IFS= read -r repo; do
  [ -n "$repo" ] && [ -n "$("$here/config.sh" project "$repo")" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] && check "$line" && break 2
  done <<EOF
$("$here/config.sh" get "$repo" guard)
EOF
done <<EOF
$("$here/config.sh" repos "$dir")
EOF

[ -n "$reason" ] || exit 0
gr_jq -n --arg r "Cost guard: $reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
exit 0
