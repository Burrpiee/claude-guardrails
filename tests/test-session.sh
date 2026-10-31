# test-session.sh -- session status, context size, status line, compaction.

SC="$GR_REPO/scripts"
reply() { printf '{"type":"assistant","isSidechain":%s,"message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":5}}}\n' "$1" "$2" "$3" "$4"; }
small="$GR_TMP/small.jsonl"; big="$GR_TMP/big.jsonl"; side="$GR_TMP/side.jsonl"; junk="$GR_TMP/junk.jsonl"
{ echo '{"type":"user","message":{"content":"hi"}}'; reply false 2 1000 60000; } > "$small"
{ reply false 2 1000 60000; reply false 2 1000 299000; echo '{"type":"user"}'; } > "$big"   # 300k: the last reply wins
{ reply false 2 1000 60000; reply true 2 1000 400000; } > "$side"                            # a helper agent's reply is not ours
{ reply false 2 1000 299000; reply false 0 0 0; echo 'not json {'; } > "$junk"              # zero-usage and broken lines skipped
# the last reply sits before a long tail of other lines, so the first read window starts mid-line
long="$GR_TMP/long.jsonl"; { reply false 2 1000 299000; i=0; while [ $i -lt 40 ]; do echo '{"type":"user","message":{"content":"a fairly long line of chat to push the reply out of the window"}}'; i=$((i + 1)); done; } > "$long"

# --- context-tokens.sh
o=$("$SC/context-tokens.sh" "$small"); [ "$o" = "61002 ok" ] && ok || bad "context-tokens small -- got [$o]"
o=$("$SC/context-tokens.sh" "$big");   [ "$o" = "300002 warn" ] && ok || bad "context-tokens big -- got [$o]"
o=$("$SC/context-tokens.sh" "$side");  [ "$o" = "61002 ok" ] && ok || bad "context-tokens skips sidechain -- got [$o]"
o=$("$SC/context-tokens.sh" "$junk");  [ "$o" = "300002 warn" ] && ok || bad "context-tokens skips zero and junk -- got [$o]"
o=$(GUARDRAILS_WARN_TOKENS=50000 "$SC/context-tokens.sh" "$small"); [ "$o" = "61002 warn" ] && ok || bad "context-tokens threshold env -- got [$o]"
# a compaction: the reply before it measured the context it replaced
boundary='{"type":"system","subtype":"compact_boundary","isSidechain":false}'
comp="$GR_TMP/comp.jsonl"; { reply false 2 1000 364000; echo "$boundary"; echo '{"type":"user"}'; } > "$comp"
after="$GR_TMP/after.jsonl"; { reply false 2 1000 364000; echo "$boundary"; reply false 2 1000 123000; } > "$after"
o=$("$SC/context-tokens.sh" "$comp");  [ -z "$o" ] && ok || bad "context-tokens stops at a compaction -- got [$o]"
o=$("$SC/context-tokens.sh" "$after"); [ "$o" = "124002 ok" ] && ok || bad "context-tokens counts the reply after a compaction -- got [$o]"
o=$(GUARDRAILS_TAIL_BYTES=100 "$SC/context-tokens.sh" "$comp"); [ -z "$o" ] && ok || bad "context-tokens stops widening at a compaction -- got [$o]"
o=$("$SC/context-tokens.sh" "$GR_TMP/missing.jsonl"); [ -z "$o" ] && ok || bad "context-tokens missing file -- got [$o]"
o=$(GUARDRAILS_TAIL_BYTES=300 "$SC/context-tokens.sh" "$long"); [ "$o" = "300002 warn" ] && ok || bad "context-tokens widens its window -- got [$o]"
o=$(GUARDRAILS_JQ=/nonexistent "$SC/context-tokens.sh" "$small"); [ -z "$o" ] && ok || bad "context-tokens without jq is silent -- got [$o]"

# --- context reminder (UserPromptSubmit)
cr() { runhook UserPromptSubmit '' "$(hookjson transcript_path="$1" cwd=/tmp)"; }
o=$(cr "$small"); [ -z "$o" ] && ok || bad "context reminder quiet below -- got $o"
o=$(cr "$big");   expect "context reminder above" '"additionalContext": "Context is ~300k tokens' "$o"
expect "context reminder event" '"hookEventName": "UserPromptSubmit"' "$o"
expect "context reminder says the user" 'suggest to the user a session handoff or /compact' "$o"
o=$(GUARDRAILS_TAIL_BYTES=300 cr "$long"); expect "context reminder past the first window" 'Context is ~300k' "$o"
o=$(cr "$GR_TMP/missing.jsonl"); rc=$?; [ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "context reminder missing transcript -- rc $rc, got $o"
o=$(runhook UserPromptSubmit '' 'garbage{'); rc=$?; [ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "context reminder bad input -- rc $rc, got $o"
o=$(GUARDRAILS_JQ=/nonexistent cr "$big"); rc=$?; [ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "context reminder without jq -- rc $rc, got $o"

# --- the status line (stands alone: run from an empty folder)
SL="$GR_TMP/sl only"; mkdir -p "$SL"; cp "$SC/statusline.sh" "$SL/"
B="$GR_TMP/sl repo"; mkrepo "$B"
sl() { printf '%s' "$1" | "$SL/statusline.sh"; }
o=$(sl "$(hookjson workspace.current_dir="$B" context_window.total_input_tokens:=260000)")
[ "$o" = "ctx 260k ⚠ hand off · feature" ] && ok || bad "statusline over -- got [$o]"
o=$(sl "$(hookjson workspace.current_dir="$B" context_window.total_input_tokens:=61000)")
[ "$o" = "ctx 61k · feature" ] && ok || bad "statusline under -- got [$o]"
o=$(PATH="$GR_CRJQ:$PATH" sl "$(hookjson workspace.current_dir="$B" context_window.total_input_tokens:=260000)")
[ "$o" = "ctx 260k ⚠ hand off · feature" ] && ok || bad "statusline with a jq that ends lines in CR -- got [$o]"
o=$(sl "$(hookjson cwd=/nonexistent)"); [ "$o" = "ctx –" ] && ok || bad "statusline nothing known -- got [$o]"
o=$(GUARDRAILS_WARN_TOKENS=50000 sl "$(hookjson context_window.total_input_tokens:=61000)"); [ "$o" = "ctx 61k ⚠ hand off" ] && ok || bad "statusline threshold env -- got [$o]"
o=$(sl 'garbage{'; echo "rc=$?"); expect "statusline bad input exits 0" 'rc=0$' "$o"

# --- session status (SessionStart)
H2="$GR_TMP/home2"; mkdir -p "$H2/.claude"
SP="$GR_TMP/status proj"; mkrepo "$SP"; mkdir -p "$SP/.claude"; SM="$GR_TMP/status mem"; mkdir -p "$SM"
printf 'x %.0s' $(seq 50) > "$SP/CLAUDE.md"
printf '%s\n' "memory = $SM" 'ports = 5173 5001' 'words = CLAUDE.md 40' 'words = CLAUDE.md 60' 'words = none.md 1' > "$SP/.claude/guardrails.conf"
printf '%s\n' '# Pending' '- 2026-10-01: a fix awaiting the user' > "$SM/pending-improvements.md"
TW="$H2/tools"; mkrepo "$TW"; echo dirty > "$TW/f"; echo 'watch_dirs = ~/tools' > "$H2/.claude/guardrails.conf"
ST="$GR_TMP/stubs-status"; mkdir -p "$ST"
printf '#!/bin/sh\necho "State Recv-Q Send-Q Local Peer"\necho "LISTEN 0 511 0.0.0.0:5173 0.0.0.0:*"\n' > "$ST/ss"
cat > "$ST/claude" <<'EOF'
#!/bin/sh
case "$*" in
  --version) echo "${STUB_VERSION:-2.1.310} (Claude Code)" ;;
  "auth status --json") echo '{"loggedIn":true,"email":"a@b.c","subscriptionType":"pro"}' ;;
  *) echo "TEST CALLED REAL claude" >&2; exit 99 ;;
esac
EOF
chmod +x "$ST/ss" "$ST/claude"
ss_() { PATH="$ST:$PATH" HOME=$H2 runhook SessionStart startup "$(hookjson cwd="$1" source="${2:-startup}")"; }
o=$(ss_ "$SP"); rc=$?
[ "$rc" = 0 ] && ok || bad "session status exits 0 -- got $rc"
expect "status branch line"     '^status proj: feature \(2 uncommitted\)$' "$o"
expect "status unmerged line"   '^  unmerged: feature @ [0-9a-f]+ .*feature work' "$o"
expect "status ports"           '^dev servers listening: 5173 $' "$o"
expect "status account"         '^claude account: a@b\.c \(pro\)$' "$o"
expect "status watch_dirs"      "^agent setup: $H2/tools has 1 uncommitted change\(s\)" "$o"
expect "status pending fixes"   '^pending process fixes awaiting the user' "$o"
expect "status pending line"    '^- 2026-10-01: a fix awaiting the user$' "$o"
expect "status words over"      'instruction size: .*CLAUDE\.md is 50 words, over its 40 budget' "$o"
refuse "status words under"     'over its 60 budget' "$o"
refuse "status words missing"   'none\.md' "$o"
refuse "status no version warning on a new Claude Code" '2\.1\.295' "$o"
refuse "status no jq warning with jq" 'jq is missing' "$o"
o2=$(ss_ "$SP" compact); [ "$o2" = "$o" ] && ok || bad "status after a compaction is the same report"
o=$(STUB_VERSION=2.1.200 ss_ "$SP"); expect "status warns on an old Claude Code" 'Claude Code 2\.1\.200 is older than 2\.1\.295' "$o"
o=$(STUB_VERSION=2.2.0 ss_ "$SP");   refuse "status compares versions by number" '2\.1\.295' "$o"
# the status line copy, refreshed when missing or different
D="$GR_TMP/plugin data"
cmp -s "$D/statusline.sh" "$SC/statusline.sh" && ok || bad "status copies the status line into the plugin data folder"
echo stale > "$D/statusline.sh"; ss_ "$SP" >/dev/null
cmp -s "$D/statusline.sh" "$SC/statusline.sh" && ok || bad "status refreshes a stale status line copy"
# a repo with no config: branch lines yes, project lines no
FS="$GR_TMP/plain"; mkrepo "$FS"
o=$(ss_ "$FS")
expect "status plain repo branch" '^plain: feature' "$o"
refuse "status plain repo has no project lines" 'dev servers|pending process|instruction size|owed-check|Read-back' "$o"
o=$(ss_ "$GR_TMP"); refuse "status outside a repo" 'uncommitted\)' "$o"
# without jq: says so first, then what it can
o=$(cd "$SP" && GUARDRAILS_JQ=/nonexistent CLAUDE_PROJECT_DIR="$SP" ss_ "$SP"); rc=$?
first=$(printf '%s\n' "$o" | head -1)
[ "$first" = "guardrails: jq is missing, so every command will be refused until it's installed -- install it in a terminal outside Claude Code (Windows: winget install jqlang.jq; Mac: brew install jq; Linux: your package manager), then start a new session." ] && ok || bad "status without jq, first line -- got [$first]"
expect "status without jq still reports the branch" '^status proj: feature' "$o"
[ "$rc" = 0 ] && ok || bad "status without jq exits 0 -- got $rc"

# the effort level: the session's own when Claude Code passes it, else the
# per-model level the settings files give (local, project, user), labelled so
EP="$GR_TMP/level proj"; mkrepo "$EP"; mkdir -p "$EP/.claude" "$GR_TMP/home3/.claude"
ef() ( unset CLAUDE_EFFORT CLAUDE_CODE_EFFORT_LEVEL; [ -z "${2:-}" ] || export "$2"
  PATH="$ST:$PATH" HOME="$GR_TMP/home3" runhook SessionStart startup "$(hookjson cwd="$EP" source=startup ${1:+"model=$1"})" | grep '^effort' )
o=$(ef "" CLAUDE_EFFORT=xhigh); [ "$o" = "effort: xhigh" ] && ok || bad "status effort from the session -- got [$o]"
o=$(ef "" CLAUDE_CODE_EFFORT_LEVEL=low); [ "$o" = "effort: low (as configured; an /effort change this session is not seen)" ] && ok || bad "status effort from CLAUDE_CODE_EFFORT_LEVEL -- got [$o]"
printf '%s' '{"effortLevel":"max","modelSettings":{"claude-opus-5-5":{"effortLevel":"low"},"claude-sonnet-5-5":{"effortLevel":"low"}}}' > "$GR_TMP/home3/.claude/settings.json"
o=$(ef "claude-opus-5-5[1m]"); expect "status effort per model, user file" '^effort: low \(as configured' "$o"
o=$(ef "claude-sonnet-5-5-20260901"); expect "status effort per model, date suffix stripped" '^effort: low \(as configured' "$o"
printf '%s' '{"modelSettings":{"claude-opus-5-5":{"effortLevel":"high"}}}' > "$EP/.claude/settings.json"
o=$(ef "claude-opus-5-5"); expect "status effort, the project file over the user's" '^effort: high \(as configured' "$o"
printf '%s' '{"modelSettings":{"claude-opus-5-5":{"effortLevel":"medium"}}}' > "$EP/.claude/settings.local.json"
o=$(ef "claude-opus-5-5"); expect "status effort, the local file over the project's" '^effort: medium \(as configured' "$o"
o=$(ef "claude-haiku-5-5"); [ -z "$o" ] && ok || bad "status effort: a top-level level is not trusted, nothing shown -- got [$o]"
o=$(ef ""); [ -z "$o" ] && ok || bad "status effort: no model, nothing shown -- got [$o]"

# --- compaction: snapshot + log, written to the project's memory folder
pc() { runhook PreCompact "${1:-auto}" "$(hookjson cwd="$SP" trigger="${1:-auto}" session_id=abcdef123456 transcript_path="$small")"; }
GR_HOOK=precompact-snapshot.sh pc >/dev/null
o=$(cat "$SM/precompact-snapshot.md" 2>/dev/null)
expect "snapshot file" '^status proj: feature' "$o"
expect "snapshot commits" '^--- status proj last 3 commits on feature' "$o"
o=$(cat "$SM/compaction-log.md" 2>/dev/null)
expect "compaction log header" '^name: compaction-log' "$o"
expect "compaction log line" '^- 20[0-9-]+T[0-9:]+Z  auto  ~61k tokens  session abcdef12  requested$' "$o"
"$SC/compaction-log.sh" "$SP" "second line"
[ "$(grep -c '^name: compaction-log' "$SM/compaction-log.md")" = 1 ] && ok || bad "compaction log header written twice"
expect "compaction log appends" '  second line$' "$(cat "$SM/compaction-log.md")"

# --- last-user-time.sh: the time of the user's last message
J="$GR_TMP/session.jsonl"
cat > "$J" <<'EOF_J'
{"type":"user","isMeta":true,"timestamp":"2026-10-08T01:00:00Z","message":{"role":"user","content":"<local-command-caveat>x</local-command-caveat>"}}
{"type":"user","timestamp":"2026-10-08T01:01:00Z","message":{"role":"user","content":"carry on"}}
{"type":"assistant","timestamp":"2026-10-08T01:01:05Z","message":{"role":"assistant","content":[{"type":"text","text":"menu"}]}}
{"type":"user","timestamp":"2026-10-08T01:02:00Z","toolUseResult":{"stdout":"x"},"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
{"type":"attachment","timestamp":"2026-10-08T01:03:00Z","attachment":{"type":"queued_command","prompt":"also this","origin":{"kind":"human"},"timestamp":"2026-10-08T01:03:00Z"}}
{"type":"user","timestamp":"2026-10-08T01:04:00Z","toolUseResult":{"questions":[],"answers":{"Which?":"Option 2"}},"message":{"role":"user","content":[{"type":"tool_result","content":"answered"}]}}
{"type":"user","timestamp":"2026-10-08T01:09:00.500Z","message":{"role":"user","content":"line one<system-reminder>hidden</system-reminder>"}}
{"type":"user","isSidechain":true,"timestamp":"2026-10-08T01:10:00Z","message":{"role":"user","content":"a subagent's prompt"}}
{"type":"user","timestamp":"2026-10-08T01:11:00Z","message":{"role":"user","content":"<task-notification>agent done</task-notification>"}}
{"type":"attachment","timestamp":"2026-10-08T01:12:00Z","attachment":{"type":"queued_command","prompt":"<task-notification>done</task-notification>","origin":{"kind":"task-notification"}}}
{"type":"user","timestamp":"2026-10-08T01:13:00Z","message":{"role":"user","content":"<system-reminder>only a reminder</system-reminder>"}}
garbage
EOF_J
o=$("$SC/last-user-time.sh" "$J"); [ "$o" = "2026-10-08T01:09:00.500Z" ] && ok || bad "last-user-time -- got [$o]"
J2="$GR_TMP/session2.jsonl"; { cat "$J"; echo '{"type":"user","timestamp":"2026-10-08T01:20:00Z","message":{"role":"user","content":"<bash-input>git status</bash-input>"}}'; } > "$J2"
o=$("$SC/last-user-time.sh" "$J2"); [ "$o" = "2026-10-08T01:20:00Z" ] && ok || bad "last-user-time counts a ! command -- got [$o]"
J3="$GR_TMP/session3.jsonl"; { cat "$J"; echo '{"type":"user","timestamp":"2026-10-08T01:21:00Z","message":{"role":"user","content":[{"type":"text","text":"look"},{"type":"image","source":{}}]}}'; } > "$J3"
o=$("$SC/last-user-time.sh" "$J3"); [ "$o" = "2026-10-08T01:21:00Z" ] && ok || bad "last-user-time counts an image turn -- got [$o]"
J4="$GR_TMP/session4.jsonl"; { cat "$J"; echo '{"type":"user","timestamp":"2026-10-08T01:22:00Z","message":{"role":"user","content":"<command-name>/clear</command-name>\n<command-args></command-args>"}}'; } > "$J4"
o=$("$SC/last-user-time.sh" "$J4"); [ "$o" = "2026-10-08T01:22:00Z" ] && ok || bad "last-user-time counts a slash command -- got [$o]"
J5="$GR_TMP/session5.jsonl"; { cat "$J"; echo '{"type":"user","timestamp":"2026-10-08T01:23:00Z","message":{"role":"user","content":"<command-name>/help</command-name>"}}'; } > "$J5"
o=$("$SC/last-user-time.sh" "$J5"); [ "$o" = "2026-10-08T01:23:00Z" ] && ok || bad "last-user-time counts a command with no args tag -- got [$o]"
o=$("$SC/last-user-time.sh" "$GR_TMP/missing.jsonl"); [ -z "$o" ] && ok || bad "last-user-time missing file -- got [$o]"

# --- after handoff: an automatic compaction is skipped while a finished handoff is the last thing done
export GUARDRAILS_STATE="$GR_TMP/after"
said="$GR_TMP/said.jsonl"; { cat "$J"; reply false 2 1000 60000; } > "$said"          # last user message 01:09:00.500Z
full="$GR_TMP/full.jsonl"; { cat "$J"; reply false 2 1000 949000; } > "$full"
ah() { GR_HOOK=after-handoff runhook PreCompact "$1" "$(hookjson trigger="$1" session_id="$2" transcript_path="$3" cwd="$SP")" 2>&1; echo "rc=$?"; }
o=$(CLAUDE_CODE_SESSION_ID='' "$SC/precompact-handoff.sh" mark </dev/null 2>&1; echo "rc=$?"); expect "mark with no session exits 0" 'rc=0$' "$o"
o=$(CLAUDE_CODE_SESSION_ID=h1 "$SC/precompact-handoff.sh" mark </dev/null 2>&1)
[ -e "$GUARDRAILS_STATE/h1.handoff-done" ] && ok || bad "mark writes the marker -- got $o"
o=$(unset GUARDRAILS_STATE; CLAUDE_PLUGIN_DATA="$GR_TMP/pdata" CLAUDE_CODE_SESSION_ID=h9 "$SC/precompact-handoff.sh" mark </dev/null 2>&1)
[ -e "$GR_TMP/pdata/state/h9.handoff-done" ] && ok || bad "mark defaults to the plugin data folder -- got $o"
o=$(ah auto h1 "$said"); expect "after-handoff skips" 'handoff already ran' "$o"; expect "after-handoff exits 2" 'rc=2$' "$o"
expect "after-handoff logs the skip" '  auto  ~61k tokens  session h1  skipped' "$(cat "$SM/compaction-log.md")"
o=$(ah idle h1 "$said"); expect "after-handoff skips whatever the trigger is called" 'rc=2$' "$o"
o=$(ah manual h1 "$said"); [ "$o" = "rc=0" ] && ok || bad "after-handoff lets /compact run -- got $o"
o=$(ah auto h2 "$said"); [ "$o" = "rc=0" ] && ok || bad "after-handoff runs with no handoff -- got $o"
o=$(ah auto h1 "$full"); [ "$o" = "rc=0" ] && ok || bad "after-handoff lets a full window compact -- got $o"
o=$(ah auto h1 "$J"); [ "$o" = "rc=0" ] && ok || bad "after-handoff lets an unknown size compact -- got $o"
# the mark one minute older than the user's last message (01:09:00.500Z), read in Tokyo time
TZ=UTC touch -t 202610080108.00 "$GUARDRAILS_STATE/h1.handoff-done"
o=$(TZ=Asia/Tokyo ah auto h1 "$said"); [ "$o" = "rc=0" ] && ok || bad "after-handoff runs once the user wrote since (UTC, fraction) -- got $o"
o=$(runhook PreCompact auto 'garbage{' 2>&1; echo "rc=$?"); expect "precompact hooks take bad input" 'rc=0$' "$o"
unset GUARDRAILS_STATE

# --- the unwired gate/wake pair: an idle auto compaction is skipped once per session
export GUARDRAILS_STATE="$GR_TMP/handoff" GUARDRAILS_HANDOFF_WAIT=1
huge="$GR_TMP/huge.jsonl"; reply false 2 1000 949000 > "$huge"
pg() { hookjson trigger="$2" session_id="$3" prompt_id=p1 transcript_path="$4" | "$SC/precompact-handoff.sh" "$1" 2>&1; echo "rc=$?"; }
o=$(pg gate manual s1 "$small"); [ "$o" = "rc=0" ] && ok || bad "handoff gate lets /compact run -- got $o"
o=$(pg gate auto s1 "$small"); expect "handoff gate skips idle compaction" 'session handoff runs instead' "$o"; expect "handoff gate exits 2" 'rc=2$' "$o"
o=$(pg wake auto s1 "$small"); expect "handoff wake names the skill" 'Run the session-handoff skill now' "$o"; expect "handoff wake says the size" '~61k tokens' "$o"
o=$(pg gate auto s1 "$small"); [ "$o" = "rc=0" ] && ok || bad "handoff gate lets a second compaction run -- got $o"
o=$(pg gate auto s2 "$huge"); [ "$o" = "rc=0" ] && ok || bad "handoff gate lets a full window compact -- got $o"
o=$(pg wake auto s4 "$small"); [ "$o" = "rc=0" ] && ok || bad "handoff wake quiet with no gate decision -- got $o"
unset GUARDRAILS_STATE GUARDRAILS_HANDOFF_WAIT
o=$(jq -r '.hooks.PreCompact[].hooks[].command' "$GR_REPO/hooks/hooks.json" 2>/dev/null)
refuse "gate and wake ship unwired" ' (gate|wake)$' "$o"
