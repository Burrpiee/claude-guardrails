#!/usr/bin/env bash
# PreCompact: skip a compaction that would be wasted, because a session
# handoff already saved what matters.
#
#   precompact-handoff.sh mark            the session-handoff skill's last step:
#                                         marks this session ($CLAUDE_CODE_SESSION_ID)
#   precompact-handoff.sh after-handoff   wired: exit 2 skips any compaction but
#                                         /compact while the mark is newer than
#                                         the user's last message, below ~900k
#
# Once a handoff has run the user will /clear, so compacting the idle session
# only spends. It matches every trigger but "manual": Claude Code's "auto"
# trigger covers both the window filling and an idle compaction. Each skip is
# logged in compaction-log.md.
#
#   precompact-handoff.sh gate   synchronous: exit 2 skips the compaction
#   precompact-handoff.sh wake   asyncRewake: exit 2 wakes the model with stderr
#
# Not wired in this version (a setting to switch it on comes later): skip
# Claude Code's own compaction of a session left idle and wake the model to
# run the handoff instead, while the prompt cache is warm. A handoff is many
# requests, each re-reading the session; a compaction is one. The gate
# skips once per session, and only below ~900k tokens: near the window's end
# the compaction is the context filling, and skipping it would fail the
# request.
#
# State lives in $GUARDRAILS_STATE, else the plugin's data folder. On
# anything unexpected every mode exits 0, so compaction runs as before.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
mode=${1:-}
max=${GUARDRAILS_HANDOFF_MAX_TOKENS:-900000}
state=${GUARDRAILS_STATE:-${CLAUDE_PLUGIN_DATA:+$CLAUDE_PLUGIN_DATA/state}}
[ -n "$state" ] || exit 0
if [ "$mode" = mark ]; then
  sid=${CLAUDE_CODE_SESSION_ID:-}
  [ -n "$sid" ] || { echo "No CLAUDE_CODE_SESSION_ID; handoff not marked." >&2; exit 0; }
  mkdir -p "$state" 2>/dev/null && touch "$state/$sid.handoff-done" && echo "Handoff marked for session $(printf '%s' "$sid" | cut -c1-8)."
  find "$state" -type f -mtime +7 -exec rm -f {} + 2>/dev/null
  exit 0
fi
gr_jq || exit 0
input=$(cat)
field() { gr_jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
trigger=$(field .trigger); sid=$(field .session_id); t=$(field .transcript_path)
pid=$(field .prompt_id); pid=${pid:-none}
tokens() { local n _; read -r n _ <<EOF
$("$here/context-tokens.sh" "$1" 2>/dev/null)
EOF
  printf '%s' "$n"; }

if [ "$mode" = after-handoff ]; then
  mark="$state/$sid.handoff-done"
  [ "$trigger" != manual ] && [ -n "$sid" ] && [ -n "$t" ] && [ -e "$mark" ] || exit 0
  n=$(tokens "$t")
  [ -n "$n" ] && [ "$n" -lt "$max" ] || exit 0
  said=$(gr_iso_to_epoch "$("$here/last-user-time.sh" "$t")")
  marked=$(gr_mtime "$mark")
  [ -n "$said" ] && [ -n "$marked" ] && [ "$marked" -gt "$said" ] || exit 0
  dir=$(field .cwd)
  "$here/compaction-log.sh" "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" \
    "${trigger:-?}  ~$((n / 1000))k tokens  session $(printf '%s' "$sid" | cut -c1-8)  skipped: the handoff was the last thing done" 2>/dev/null
  echo "Skipped by the guardrails plugin: the session handoff already ran and nothing was said since, so /clear starts fresh." >&2
  exit 2
fi

[ "$trigger" = auto ] && [ -n "$sid" ] || exit 0
mkdir -p "$state" 2>/dev/null || exit 0
decision="$state/$sid.$pid.decision"

if [ "$mode" = gate ]; then
  find "$state" -type f -mtime +7 -exec rm -f {} + 2>/dev/null
  n=""; [ -n "$t" ] && n=$(tokens "$t")
  if [ -e "$state/$sid.handed-off" ] || [ -z "$n" ] || [ "$n" -ge "$max" ]; then
    echo allow > "$decision"; exit 0
  fi
  touch "$state/$sid.handed-off"
  echo "wake $n" > "$decision"
  echo "Skipped by the guardrails plugin: the session handoff runs instead." >&2
  exit 2
fi

if [ "$mode" = wake ]; then
  i=0
  while [ $i -lt "${GUARDRAILS_HANDOFF_WAIT:-20}" ]; do
    [ -e "$decision" ] && break
    sleep 0.5
    i=$((i + 1))
  done
  [ -e "$decision" ] && read -r verdict n < "$decision" || exit 0
  [ "$verdict" = wake ] || exit 0
  echo "Claude Code was about to compact this idle session (~$((n / 1000))k tokens) before its prompt cache expired, and the guardrails plugin skipped it, because a summary loses quoted rulings and review findings. Run the session-handoff skill now, while the cache is warm. Start no other task. Then stop, leaving the user one line: the handoff ran while they were away, so /clear and say carry on." >&2
  exit 2
fi
exit 0
