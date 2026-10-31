#!/usr/bin/env bash
# last-user-time.sh <transcript.jsonl> -- the ISO time of the user's last
# message in a session: an ordinary turn, one typed while a turn ran (stored
# as a queued_command attachment), an answer to a question (stored as a tool
# result), or a slash or `!` command. Skips helper-agent (sidechain) and meta
# lines, task notifications, command output and tool output. Prints nothing
# when there is none or jq is missing.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
[ -f "${1:-}" ] && gr_jq || exit 0
gr_jq -Rnr '
  def clean: gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "") | gsub("^\\s+|\\s+$"; "");
  def from_turn($ts):
    if test("^<(local-command-stdout|local-command-caveat|task-notification|bash-stdout|bash-stderr)>") then empty
    elif test("<command-name>") then
      {ts: $ts, text: ((capture("<command-name>(?<n>[\\s\\S]*?)</command-name>").n)
                       + " " + ((capture("<command-args>(?<a>[\\s\\S]*?)</command-args>").a) // ""))}
    elif test("<bash-input>") then {ts: $ts, text: ("! " + capture("<bash-input>(?<b>[\\s\\S]*?)</bash-input>").b)}
    else {ts: $ts, text: .} end;
  def events:
    fromjson? | objects | select((.isSidechain | not) and (.isMeta | not)) | .timestamp as $ts
    | if .type == "attachment" then
        (.attachment | objects | select(.type == "queued_command")) as $a
        | ($a.origin | objects | .kind) as $o
        | select($o == "human" or $a.humanTurn == true or ($o == null and $a.commandMode == "prompt"))
        | {ts: ($a.timestamp // $ts), text: ($a.prompt // "" | tostring)}
      elif .type != "user" then empty
      elif (.toolUseResult | type) == "object" and ((.toolUseResult.answers | type) == "object") then
        .toolUseResult.answers | to_entries[] | {ts: $ts, text: "\(.key) -> \(.value)"}
      elif .toolUseResult != null then empty
      else
        ((.message | objects | .content) // null) as $c
        | if ($c | type) == "string" then $c | from_turn($ts)
          elif ($c | type) == "array" then
            [$c[] | objects | if .type == "text" then (.text // "" | clean) elif .type == "image" then "[image]" else empty end
             | select(. != "")]
            | select(length > 0) | join(" ") | from_turn($ts)
          else empty end
      end;
  reduce (inputs | events | .text |= clean | select(.text != "")) as $e ({last: null, ts: null};
    if $e.text == .last then . else {last: $e.text, ts: $e.ts} end)
  | .ts // empty' "$1" 2>/dev/null
exit 0
