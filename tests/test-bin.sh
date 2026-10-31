# test-bin.sh -- the on-demand commands in bin/.

BN="$GR_REPO/bin"
# stub_claude DIR REPLY: a `claude` that logs its arguments to DIR/args and prints REPLY.
stub_claude() {
  mkdir -p "$1"; printf '%s\n' "$2" > "$1/reply"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/args"\ncat "%s/reply"\n' "$1" "$1" > "$1/claude"
  chmod +x "$1/claude"
}

# --- owed-check: flags an open "ruling owed" the decision log cites, nothing else
OW="$GR_TMP/owed proj"; mkrepo "$OW"; mkdir -p "$OW/docs" "$OW/.claude"; touch "$OW/.claude/guardrails.conf"
printf '%s\n' '# Backlog' '## L. Exports' '20. **Ruling owed:** free plan exports?' \
  '21. Build the export.' '22. ~~**[ruling owed]**~~ RULED, DECISIONS 3.1' '## P. Projects' \
  '7. **Ruling owed:** board column order.' '9ab. Stashed, ruling owed before any build.' > "$OW/docs/BACKLOG.md"
printf '%s\n' '# Decisions' '### 14.3 Weekly digest -- 2026-10-04' 'Ruled: digest email (BACKLOG L.20).' \
  '### 3.1 Old -- 2026-09-01' 'See BACKLOG L.22 and BACKLOG L.21.' '### 8.9 Importer' 'The flag 9ab(b).' > "$OW/docs/DECISIONS.md"
o=$("$BN/guardrails-owed-check" "$OW")
expect "owed cited"      'BACKLOG L\.20 <- DECISIONS 14\.3 Weekly digest' "$o"
expect "owed bare id"    'BACKLOG P\.9ab <- DECISIONS 8\.9' "$o"
expect "owed count"      '3 backlog item\(s\) still say.*mention is not a ruling' "$o"
expect "owed shows line" '"Ruled: digest email \(BACKLOG L\.20\)\."' "$o"
refuse "owed struck"     'L\.22' "$o"
refuse "owed not owed"   'L\.21' "$o"
refuse "owed uncited"    'P\.7 ' "$o"
o=$("$BN/guardrails-owed-check" "$OW/docs"); expect "owed from a subfolder" 'BACKLOG L\.20' "$o"
# on Windows, Python cannot open a Git Bash path (/c/...): each path goes through cygpath -m
CYG="$GR_TMP/cygpath stub"; mkdir -p "$CYG"
RC=$(command -v cygpath)   # on Windows the stub records, then asks the real one
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\nif [ -n "%s" ]; then exec "%s" "$@"; fi\nfor a; do :; done\nprintf "%%s\\n" "$a"\n' "$CYG" "$RC" "$RC" > "$CYG/cygpath"; chmod +x "$CYG/cygpath"
o=$(PATH="$CYG:$PATH" "$BN/guardrails-owed-check" "$OW"); expect "owed-check with cygpath still reads" 'BACKLOG L\.20' "$o"
c=$(cat "$CYG/calls" 2>/dev/null)
expect "owed-check converts the backlog path" "^-m $OW/docs/BACKLOG\.md\$" "$c"
expect "owed-check converts the log path" "^-m $OW/docs/DECISIONS\.md\$" "$c"
NC="$GR_TMP/owed noconf"; mkrepo "$NC"; cp -R "$OW/docs" "$NC/docs"
o=$("$BN/guardrails-owed-check" "$NC"); [ -z "$o" ] && ok || bad "owed-check silent with no config -- got $o"
OL="$GR_TMP/owed log"; mkrepo "$OL"; mkdir -p "$OL/notes" "$OL/docs" "$OL/.claude"
cp "$OW/docs/DECISIONS.md" "$OL/notes/log.md"; cp "$OW/docs/BACKLOG.md" "$OL/docs/BACKLOG.md"
echo 'decisions = notes/log.md' > "$OL/.claude/guardrails.conf"
o=$("$BN/guardrails-owed-check" "$OL"); expect "owed-check reads decisions = notes/log.md" 'BACKLOG L\.20 <- DECISIONS 14\.3' "$o"
rm "$OL/docs/BACKLOG.md"; o=$("$BN/guardrails-owed-check" "$OL"); [ -z "$o" ] && ok || bad "owed-check silent with no backlog -- got $o"
o=$(runhook SessionStart startup "$(hookjson cwd="$OW")"); expect "session status runs owed-check" '^owed-check: ' "$o"
# a folder of decision records: each cites as its "# " title; README.md,
# index.md and an *-index.md other than a numbered record are not records
OR="$GR_TMP/owed records"; mkrepo "$OR"; mkdir -p "$OR/docs/decision records" "$OR/.claude"
cp "$OW/docs/BACKLOG.md" "$OR/docs/BACKLOG.md"
printf '%s\n' '# 0003 Weekly digest by email' 'Date: 2026-10-04.' 'Ruled: digest email (BACKLOG L.20).' > "$OR/docs/decision records/0003-digest.md"
printf '%s\n' '# 0031 Board search index' 'Both on the BACKLOG (P.7, L.21).' > "$OR/docs/decision records/0031-search-index.md"
printf '%s\n' '# Records' 'BACKLOG L.20 is listed here.' > "$OR/docs/decision records/README.md"
printf '%s\n' '# Archive index' 'BACKLOG L.20 is listed here.' > "$OR/docs/decision records/archive-index.md"
echo 'decisions = docs/decision records' > "$OR/.claude/guardrails.conf"
o=$("$BN/guardrails-owed-check" "$OR")
expect "owed-check reads a records folder, cites the title" 'BACKLOG L\.20 <- 0003 Weekly digest by email: "Ruled: digest email' "$o"
expect "owed-check counts a bare id in a record" 'BACKLOG P\.7 <- 0031 Board search index: "Both on the BACKLOG \(P\.7, L\.21\)\."' "$o"
refuse "owed-check skips README and index files" 'Records|Archive index' "$o"
printf '%s\n' 'decisions = docs/decision records' 'decisions = notes/log.md' > "$OR/.claude/guardrails.conf"
mkdir -p "$OR/notes"; printf '%s\n' '# Log' '### 8.9 Importer' 'The flag 9ab(b).' > "$OR/notes/log.md"
o=$("$BN/guardrails-owed-check" "$OR")
expect "owed-check reads a file and a folder: the folder" 'BACKLOG L\.20 <- 0003 Weekly' "$o"
expect "owed-check reads a file and a folder: the file" 'BACKLOG P\.9ab <- DECISIONS 8\.9' "$o"
# a records folder is converted once, not once a record (a cygpath start each)
: > "$CYG/calls"; PATH="$CYG:$PATH" "$BN/guardrails-owed-check" "$OR" >/dev/null
[ "$(grep -c 'decision records' "$CYG/calls")" = 1 ] && ok || bad "owed-check converts a records folder once -- got: $(cat "$CYG/calls")"
OD="$GR_TMP/owed defaults"; mkrepo "$OD"; mkdir -p "$OD/docs/decisions" "$OD/.claude"; touch "$OD/.claude/guardrails.conf"
cp "$OW/docs/BACKLOG.md" "$OW/docs/DECISIONS.md" "$OD/docs/"; cp "$OR/docs/decision records/0031-search-index.md" "$OD/docs/decisions/"
o=$("$BN/guardrails-owed-check" "$OD")
expect "owed-check defaults: the log" 'BACKLOG L\.20 <- DECISIONS 14\.3' "$o"
expect "owed-check defaults: the records folder" 'BACKLOG P\.7 <- 0031 Board' "$o"
refuse "owed-check: a bare id in the log is still not a citation" 'P\.7 <- DECISIONS' "$o"
# the session status runs it with GUARDRAILS_PYTHON when python3 is not on PATH.
# Only a PATH folder holding python is swapped for links to its other files:
# Git Bash's ln -s copies, and a copied Git Bash program or Chocolatey shim
# (jq on the Windows runner) may not run from another folder.
py3=$(type -P python3); NOPY=""; i=0
while IFS= read -r d; do
  [ -d "$d" ] || continue
  if ls "$d" | grep -q '^python'; then
    i=$((i + 1)); farm="$GR_TMP/no python/$i"; mkdir -p "$farm"
    for f in "$d"/*; do
      b=${f##*/}; case "$b" in python*) continue ;; esac
      [ -d "$f" ] || ln -s "$f" "$farm/$b" 2>/dev/null
    done
    d=$farm
  fi
  NOPY=${NOPY:+$NOPY:}$d
done <<EOF
$(printf '%s\n' "$PATH" | tr ':' '\n')
EOF
PATH="$NOPY" command -v python3 >/dev/null && bad "the no-python PATH still finds python3: $(PATH="$NOPY" command -v python3)" || ok
o=$(PATH="$NOPY" GUARDRAILS_PYTHON="$py3" runhook SessionStart startup "$(hookjson cwd="$OW")" 2>"$GR_TMP/nopy err")
expect "session status honours GUARDRAILS_PYTHON" '^owed-check: ' "$o"
printf '%s\n' "$o" | grep -q '^owed-check: ' ||
  echo "  its stderr: $(cat "$GR_TMP/nopy err"); found: $(PATH="$NOPY" type -P sh jq | tr '\n' ' ')"

# --- each python3 tool says so and stops when python3 is missing, before any claude call
NP="$GR_TMP/nopython"; stub_claude "$NP" '{}'
for tool in guardrails-owed-check guardrails-handoff-check guardrails-instructions-check guardrails-session-messages; do
  a1=$OW; a2=""
  case "$tool" in
    guardrails-instructions-check) a1="$GR_REPO/examples/instruction-questions.md"; a2=$OW ;;
    guardrails-session-messages)   a1="$GR_TMP/none.jsonl" ;;
  esac
  o=$(PATH="$NP:$PATH" GUARDRAILS_PYTHON=/nonexistent "$BN/$tool" "$a1" ${a2:+"$a2"} 2>&1); rc=$?
  expect "$tool without python3" "^guardrails: $tool needs python3" "$o"
  [ "$rc" = 1 ] && ok || bad "$tool without python3 exits 1 -- got $rc"
done
[ -e "$NP/args" ] && bad "a python3 tool called claude without python3: $(cat "$NP/args")" || ok
# on Windows, python3 is often the Microsoft Store's placeholder, which only
# says "Python was not found": each tool runs python3, python and py in turn
# and takes the first that is Python 3
store() { printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store." >&2\nexit 9009\n' > "$1"; chmod +x "$1"; }
SA="$GR_TMP/store python3"; mkdir -p "$SA"; store "$SA/python3"
printf '#!/bin/sh\necho used >> "%s/used"\nexec "%s" "$@"\n' "$SA" "$py3" > "$SA/python"; chmod +x "$SA/python"
o=$(PATH="$SA:$PATH" GUARDRAILS_PYTHON= "$BN/guardrails-owed-check" "$OW" 2>&1)
expect "owed-check falls back to python past the Store's python3" 'BACKLOG L\.20 <- DECISIONS 14\.3' "$o"
[ -s "$SA/used" ] && ok || bad "owed-check ran the python that works"
SJ="$GR_TMP/store.jsonl"; printf '%s\n' '{"type":"user","timestamp":"2026-10-08T01:01:00Z","message":{"role":"user","content":"carry on"}}' > "$SJ"
o=$(PATH="$SA:$PATH" GUARDRAILS_PYTHON= "$BN/guardrails-session-messages" "$SJ" 2>&1)
expect "session-messages falls back to python past the Store's python3" 'turn +carry on$' "$o"
o=$(PATH="$SA:$PATH" GUARDRAILS_PYTHON= runhook SessionStart startup "$(hookjson cwd="$OW")")
expect "session status falls back to python past the Store's python3" '^owed-check: ' "$o"
SN="$GR_TMP/store only"; mkdir -p "$SN"; for b in python3 python py; do store "$SN/$b"; done; stub_claude "$SN" '{}'
for tool in guardrails-owed-check guardrails-handoff-check guardrails-instructions-check guardrails-session-messages; do
  a1=$OW; a2=""
  case "$tool" in
    guardrails-instructions-check) a1="$GR_REPO/examples/instruction-questions.md"; a2=$OW ;;
    guardrails-session-messages)   a1=$SJ ;;
  esac
  o=$(PATH="$SN:$PATH" GUARDRAILS_PYTHON= "$BN/$tool" "$a1" ${a2:+"$a2"} 2>&1); rc=$?
  expect "$tool with only the Store's placeholders" "^guardrails: $tool needs python3 \\(none of python3, python or py runs" "$o"
  [ "$rc" = 1 ] && ok || bad "$tool with only the Store's placeholders exits 1 -- got $rc"
done
[ -e "$SN/args" ] && bad "a python3 tool called claude with no working python: $(cat "$SN/args")" || ok
# GUARDRAILS_PYTHON is run too, still wins (no fallback), and is named when it fails
SG="$GR_TMP/store set"; mkdir -p "$SG"; store "$SG/placeholder"; stub_claude "$SG" '{}'
for tool in guardrails-owed-check guardrails-handoff-check guardrails-instructions-check guardrails-session-messages; do
  a1=$OW; a2=""
  case "$tool" in
    guardrails-instructions-check) a1="$GR_REPO/examples/instruction-questions.md"; a2=$OW ;;
    guardrails-session-messages)   a1=$SJ ;;
  esac
  o=$(PATH="$SG:$PATH" GUARDRAILS_PYTHON="$SG/placeholder" "$BN/$tool" "$a1" ${a2:+"$a2"} 2>&1); rc=$?
  expect "$tool names a GUARDRAILS_PYTHON that is not Python 3" "^guardrails: $tool needs python3: GUARDRAILS_PYTHON \\($SG/placeholder\\) does not run as Python 3" "$o"
  [ "$rc" = 1 ] && ok || bad "$tool with a broken GUARDRAILS_PYTHON exits 1 -- got $rc"
done
[ -e "$SG/args" ] && bad "a python3 tool called claude with a broken GUARDRAILS_PYTHON: $(cat "$SG/args")" || ok
# Python 3.7 or later (the UTF-8 output needs it): a 3.6 python3 is passed over
P36="$GR_TMP/python 3.6"; mkdir -p "$P36/site"; echo 'import sys; sys.version_info = (3, 6, 9, "final", 0)' > "$P36/site/sitecustomize.py"
printf '#!/bin/sh\nPYTHONPATH="%s" exec "%s" "$@"\n' "$P36/site" "$py3" > "$P36/python3"; chmod +x "$P36/python3"
cp "$SA/python" "$P36/python"; rm -f "$SA/used"
o=$(PATH="$P36:$PATH" GUARDRAILS_PYTHON= "$BN/guardrails-owed-check" "$OW" 2>&1)
expect "owed-check passes over a Python 3.6" 'BACKLOG L\.20 <- DECISIONS 14\.3' "$o"
[ -s "$SA/used" ] && ok || bad "owed-check ran the python that is 3.7 or later"
o=$(GUARDRAILS_PYTHON="$P36/python3" "$BN/guardrails-owed-check" "$OW" 2>&1)
expect "owed-check names a GUARDRAILS_PYTHON older than 3.7" 'GUARDRAILS_PYTHON \(.*\) does not run as Python 3\.7 or later' "$o"
# Python starts only where there is something to check
PL="$GR_TMP/python log"; mkdir -p "$PL"; printf '#!/bin/sh\necho run >> "%s/runs"\nexec "%s" "$@"\n' "$PL" "$py3" > "$PL/python3"; chmod +x "$PL/python3"
NB="$GR_TMP/owed nobacklog"; mkrepo "$NB"; mkdir -p "$NB/.claude"; touch "$NB/.claude/guardrails.conf"
PATH="$PL:$PATH" GUARDRAILS_PYTHON= runhook SessionStart startup "$(hookjson cwd="$NB")" >/dev/null
[ ! -e "$PL/runs" ] && ok || bad "session status started Python with no backlog to check: $(wc -l < "$PL/runs") run(s)"
PATH="$PL:$PATH" GUARDRAILS_PYTHON= runhook SessionStart startup "$(hookjson cwd="$OW")" >/dev/null
[ "$(wc -l < "$PL/runs" | tr -d ' ')" = 2 ] && ok || bad "session status probes once, then runs the check -- $(wc -l < "$PL/runs" 2>/dev/null) run(s)"
# session start where only python is installed (python.org, no python3 at all)
PO="$GR_TMP/python only"; mkdir -p "$PO"; printf '#!/bin/sh\nexec "%s" "$@"\n' "$py3" > "$PO/python"; chmod +x "$PO/python"
o=$(PATH="$PO:$NOPY" GUARDRAILS_PYTHON= runhook SessionStart startup "$(hookjson cwd="$OW")")
expect "session status runs owed-check where only python is installed" '^owed-check: ' "$o"

# --- handoff-check: one headless call from the repo, its answer and cost printed
HC="$GR_TMP/handoff"; stub_claude "$HC" '{"result":"1. Built the plugin.","num_turns":3,"usage":{"input_tokens":10,"cache_read_input_tokens":5},"total_cost_usd":0.12,"modelUsage":{"claude-sonnet-x":{}}}'
o=$(cd "$OW/docs" && PATH="$HC:$PATH" "$BN/guardrails-handoff-check" 2>&1); rc=$?
[ "$rc" = 0 ] && ok || bad "handoff-check exits 0 -- got $rc: $o"
expect "handoff-check prints the answer" '^1\. Built the plugin\.$' "$o"
expect "handoff-check prints the cost"   '3 turns, 15 input tokens, \$0\.120 nominal' "$o"
a=$(cat "$HC/args" 2>/dev/null)
expect "handoff-check asks about the user" 'waiting on the user' "$a"
refuse "handoff-check says no operator"    'operator' "$a"
expect "handoff-check uses sonnet, read-only" 'Read,Grep,Glob' "$a"
HE="$GR_TMP/handoff err"; stub_claude "$HE" '{"is_error":true,"result":"usage limit reached"}'; printf 'exit 1\n' >> "$HE/claude"
o=$(cd "$OW/docs" && PATH="$HE:$PATH" "$BN/guardrails-handoff-check" 2>&1)
expect "handoff-check prints the reply when claude fails" 'usage limit reached' "$o"
o=$(cd "$OW/docs" && PATH="$HE:$PATH" "$BN/guardrails-handoff-check" >/dev/null 2>&1); rc=$?
[ "$rc" = 1 ] && ok || bad "handoff-check exits 1 when claude fails -- got $rc"
o=$(cd "$OW/docs" && PATH="$HE:$PATH" "$BN/guardrails-handoff-check" 2>&1); refuse "a failed call prints no stats line" 'None turns' "$o"

# --- instructions-check: one call a question, DRY lists, empty partner list is fine
IC="$GR_TMP/instr"; stub_claude "$IC" '{"result":"It says so in README.md.","total_cost_usd":0.01}'
Q="$GR_TMP/questions.md"
printf '%s\n' '| # | Question | Expected |' '|---|---|---|' '| A01 | First? | one |' '| A02 | Second? | two |' > "$Q"
o=$(DRY=1 "$BN/guardrails-instructions-check" "$Q" "$OW"); [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 2 ] && ok || bad "instructions-check DRY lists 2 -- got $o"
o=$(PATH="$IC:$PATH" "$BN/guardrails-instructions-check" "$Q" "$OW" A02 2>&1); rc=$?
[ "$rc" = 0 ] && ok || bad "instructions-check with no partners exits 0 -- got $rc: $o"
expect "instructions-check asks the chosen id" '^=== A02: Second\?' "$o"
refuse "instructions-check skips the others"   '=== A01' "$o"
expect "instructions-check totals the cost"    'TOTAL nominal: \$0\.01$' "$o"
o=$(DRY=1 "$BN/guardrails-instructions-check" "$GR_REPO/examples/instruction-questions.md" "$OW")
[ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 3 ] && ok || bad "the example questions file parses to 3 -- got $o"

# --- session-messages: every user message in order, mid-turn ones and answers included
J="$GR_TMP/msgs.jsonl"
cat > "$J" <<'EOF_J'
{"type":"user","isMeta":true,"timestamp":"2026-10-08T01:00:00Z","message":{"role":"user","content":"<local-command-caveat>x</local-command-caveat>"}}
{"type":"user","timestamp":"2026-10-08T01:00:01Z","message":{"role":"user","content":"<command-name>/clear</command-name>\n<command-args></command-args>"}}
{"type":"user","timestamp":"2026-10-08T01:01:00Z","message":{"role":"user","content":"carry on"}}
{"type":"assistant","timestamp":"2026-10-08T01:01:05Z","message":{"role":"assistant","content":[{"type":"text","text":"menu"}]}}
{"type":"user","timestamp":"2026-10-08T01:02:00Z","toolUseResult":{"stdout":"x"},"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
{"type":"attachment","timestamp":"2026-10-08T01:03:00Z","attachment":{"type":"queued_command","prompt":"also this","origin":{"kind":"human"},"timestamp":"2026-10-08T01:03:00Z"}}
{"type":"attachment","timestamp":"2026-10-08T01:03:30Z","attachment":{"type":"queued_command","prompt":"<task-notification>done</task-notification>","origin":{"kind":"task-notification"}}}
{"type":"user","timestamp":"2026-10-08T01:04:00Z","toolUseResult":{"questions":[],"answers":{"Which?":"Option 2"},"annotations":{"Which?":{"notes":"but bigger"}}},"message":{"role":"user","content":[{"type":"tool_result","content":"answered"}]}}
{"type":"user","isSidechain":true,"timestamp":"2026-10-08T01:05:00Z","message":{"role":"user","content":"a subagent's prompt"}}
{"type":"user","timestamp":"2026-10-08T01:06:00Z","message":{"role":"user","content":[{"type":"text","text":"look"},{"type":"image","source":{}}]}}
{"type":"user","timestamp":"2026-10-08T01:07:00Z","message":{"role":"user","content":"<task-notification>agent done</task-notification>"}}
garbage
{"type":"user","timestamp":"2026-10-08T01:08:00Z","message":{"role":"user","content":"<bash-input>git status</bash-input>"}}
{"type":"user","timestamp":"2026-10-08T01:09:00Z","message":{"role":"user","content":"line one\nline two<system-reminder>hidden</system-reminder>"}}
EOF_J
want='2026-10-08 01:00  command   /clear
2026-10-08 01:01  turn      carry on
2026-10-08 01:03  mid-turn  also this
2026-10-08 01:04  answer    Which? -> Option 2 (note: but bigger)
2026-10-08 01:06  turn      look [image]
2026-10-08 01:08  shell     ! git status
2026-10-08 01:09  turn      line one
                            line two'
o=$("$BN/guardrails-session-messages" "$J"); [ "$o" = "$want" ] && ok || bad "session-messages -- got: $o"
o=$("$BN/guardrails-session-messages" "$J" --last); [ "$o" = "2026-10-08T01:09:00Z" ] && ok || bad "session-messages --last -- got $o"
o=$(HOME="$GR_TMP/nohome" "$BN/guardrails-session-messages" no-such-session 2>&1; echo "rc=$?")
expect "session-messages unknown id" '^no transcript' "$o"; expect "session-messages unknown id exits 1" 'rc=1$' "$o"
# a backlog or log not in UTF-8 (old Notepad's "café") must not silence the check
L1="$GR_TMP/owed latin1"; mkrepo "$L1"; mkdir -p "$L1/docs" "$L1/.claude"; touch "$L1/.claude/guardrails.conf"
printf '# Backlog\n## L. Caf\351\n20. **Ruling owed:** free plan exports?\n' > "$L1/docs/BACKLOG.md"
printf '# Decisions\n### 14.3 Caf\351 digest\nRuled: digest (BACKLOG L.20).\n' > "$L1/docs/DECISIONS.md"
o=$("$BN/guardrails-owed-check" "$L1" 2>&1); expect "owed-check reads files that are not UTF-8" 'BACKLOG L\.20 <- DECISIONS 14\.3' "$o"
# on Windows, Python prints to a pipe in the code page (cp1252), which has no
# "→": each tool prints UTF-8 instead of crashing on it
U="$GR_TMP/owed utf8"; mkrepo "$U"; mkdir -p "$U/docs" "$U/.claude"; touch "$U/.claude/guardrails.conf"
printf '%s\n' '# Backlog' '## L. Exports' '20. **Ruling owed:** free plan exports?' > "$U/docs/BACKLOG.md"
printf '%s\n' '# Decisions' '### 14.3 Weekly digest → email' 'Ruled: digest (BACKLOG L.20).' > "$U/docs/DECISIONS.md"
o=$(PYTHONIOENCODING=cp1252 "$BN/guardrails-owed-check" "$U" 2>&1)
expect "owed-check prints a non-ASCII heading under cp1252" 'BACKLOG L\.20 <- DECISIONS 14\.3 Weekly digest → email' "$o"
printf '%s\n' '{"type":"user","timestamp":"2026-10-08T01:01:00Z","message":{"role":"user","content":"ship it → now"}}' > "$GR_TMP/utf8.jsonl"
o=$(PYTHONIOENCODING=cp1252 "$BN/guardrails-session-messages" "$GR_TMP/utf8.jsonl" 2>&1)
expect "session-messages prints a non-ASCII message under cp1252" 'turn +ship it → now$' "$o"
UH="$GR_TMP/handoff utf8"; stub_claude "$UH" '{"result":"1. Built → shipped.","num_turns":1,"total_cost_usd":0.1}'
o=$(cd "$OW/docs" && PATH="$UH:$PATH" PYTHONIOENCODING=cp1252 "$BN/guardrails-handoff-check" 2>&1)
expect "handoff-check prints a non-ASCII answer under cp1252" '^1\. Built → shipped\.$' "$o"
UI="$GR_TMP/instr utf8"; stub_claude "$UI" '{"result":"See README → Setup.","total_cost_usd":0.01}'
o=$(PATH="$UI:$PATH" PYTHONIOENCODING=cp1252 "$BN/guardrails-instructions-check" "$Q" "$OW" A02 2>&1)
expect "instructions-check prints a non-ASCII answer under cp1252" '^See README → Setup\.$' "$o"
expect "instructions-check totals after a non-ASCII answer" 'TOTAL nominal: \$0\.01$' "$o"
# the running total keeps no CR (Windows Python ends a line \r\n)
UP="$GR_TMP/crlf python"; mkdir -p "$UP"; printf '#!/bin/sh\n"%s" "$@" | sed "s/\\$/$(printf "\\r")/"\n' "$py3" > "$UP/python3"; chmod +x "$UP/python3"
o=$(PATH="$UI:$PATH" GUARDRAILS_PYTHON="$UP/python3" "$BN/guardrails-instructions-check" "$Q" "$OW" A02 2>&1)
[ "$(printf '%s\n' "$o" | tail -1 | tr -cd '\r' | wc -c | tr -d ' ')" = 0 ] && ok || bad "instructions-check's total keeps no CR -- $(printf '%s\n' "$o" | tail -1 | od -c | head -2)"
# ...and, like owed-check, hands Python the native path where cygpath exists
: > "$CYG/calls"; PATH="$CYG:$PATH" "$BN/guardrails-session-messages" "$J" >/dev/null
expect "session-messages converts the transcript path" "^-m $J\$" "$(cat "$CYG/calls")"

# --- review-worktree: links and smoke from the config, local file first; a copy is refused
RW="$GR_TMP/rw repo"; mkrepo "$RW"; mkdir -p "$RW/.claude"; echo secret > "$RW/.env"
o=$(cd "$RW" && REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" HEAD r1 2>&1)
expect "worktree bare built" "worktree: $GR_TMP/wt/r1" "$o"; expect "worktree bare no smoke" 'none configured' "$o"
o=$(REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$RW" --remove r1 2>&1)
expect "worktree removed" 'removed' "$o"; [ -e "$GR_TMP/wt/r1" ] && bad "worktree dir left behind" || ok
printf '%s\n' 'worktree_links = .env' 'smoke = echo committed smoke' > "$RW/.claude/guardrails.conf"
printf '%s\n' 'smoke = echo 3 passed' > "$RW/.claude/guardrails.local.conf"
# (on Windows, links need what the tool tells users to set)
o=$(MSYS=winsymlinks:nativestrict REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$RW" HEAD r2 2>&1); rc=$?
[ "$rc" = 0 ] && ok || bad "worktree with config exits 0 -- got $rc: $o"
[ -L "$GR_TMP/wt/r2/.env" ] && ok || bad "worktree links .env as a link"
expect "worktree smoke local first" '^smoke 1 \(ok\): 3 passed$' "$o"
expect "worktree smoke committed too" '^smoke 2 \(ok\): committed smoke$' "$o"
REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$RW" --remove r2 >/dev/null 2>&1
CPY="$GR_TMP/copying-ln"; mkdir -p "$CPY"; printf '#!/bin/sh\nshift\ncp -R "$1" "$2"\n' > "$CPY/ln"; chmod +x "$CPY/ln"
o=$(PATH="$CPY:$PATH" REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$RW" HEAD r3 2>&1); rc=$?
[ "$rc" = 1 ] && ok || bad "worktree refuses a copied link -- got $rc"
expect "worktree names the Windows fix" 'MSYS=winsymlinks:nativestrict.*Developer Mode' "$o"
echo 'worktree_links = missing.txt' >> "$RW/.claude/guardrails.local.conf"
o=$(REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$RW" HEAD r4 2>&1); rc=$?
[ "$rc" = 1 ] && ok || bad "worktree stops on a missing link source -- got $rc"
expect "worktree names the missing source" 'missing in main checkout: missing\.txt' "$o"

# --- review-worktree: .worktreeinclude (Claude Code's list) copies files that match AND git ignores
WI="$GR_TMP/wi repo"; mkrepo "$WI"
printf '%s\n' '.env.local' 'secret dir/' > "$WI/.gitignore"
printf '%s\n' '# copied into worktrees' '.env.local' 'secret dir/' 'loose.txt' '.gitignore' > "$WI/.worktreeinclude"
git -C "$WI" add .gitignore .worktreeinclude && git -C "$WI" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm ignores
echo local > "$WI/.env.local"; mkdir -p "$WI/secret dir"; echo s > "$WI/secret dir/a b.txt"; echo l > "$WI/loose.txt"
o=$(REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$WI" HEAD w1 2>&1); rc=$?
[ "$rc" = 0 ] && ok || bad "worktree with .worktreeinclude exits 0 -- got $rc: $o"
[ -f "$GR_TMP/wt/w1/.env.local" ] && [ ! -L "$GR_TMP/wt/w1/.env.local" ] && [ "$(cat "$GR_TMP/wt/w1/.env.local" 2>/dev/null)" = local ] \
  && ok || bad "worktree copies an ignored file .worktreeinclude names, as a copy"
[ "$(cat "$GR_TMP/wt/w1/secret dir/a b.txt" 2>/dev/null)" = s ] && ok || bad "worktree copies an ignored folder's files, spaces in names"
[ -e "$GR_TMP/wt/w1/loose.txt" ] && bad "worktree copied a file git does not ignore" || ok
expect "worktree says what it copied" 'copied from the main checkout: 2 file' "$o"
REVIEW_WT_BASE="$GR_TMP/wt" "$BN/guardrails-review-worktree" --repo "$WI" --remove w1 >/dev/null 2>&1
