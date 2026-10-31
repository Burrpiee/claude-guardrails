# test-word.sh -- the claude word guard: `claude <word>` runs only for a real
# subcommand or a flag; any other word would run as a paid one-off prompt.

DENY='"permissionDecision": *"deny"'
cw() { GR_HOOK=claude-word-guard.sh runhook PreToolUse "${2:-Bash}" "$(hookjson cwd=/tmp tool_name="${2:-Bash}" tool_input.command="$1")"; }
for c in 'claude ps' 'cd /x && claude ps' 'claude "list my sessions"' "claude 'ps'" 'true; claude sessions --all' \
         '(claude status)' 'ls | claude list' 'x=$(claude ps)' 'echo hi |& claude ps' \
         'timeout 30 claude ps' 'FOO=1 claude ps' 'env A=b claude ps' 'sudo claude ps' 'nohup claude ps &' \
         'command claude ps' 'exec claude ps' '~/.local/bin/claude ps' '/usr/bin/claude ps' 'echo `claude ps`' \
         '{ claude ps; }' 'if claude ps; then :; fi' 'timeout -s KILL 5m claude ps' "echo 'a'; claude ps"; do
  expect "claude word denies: $c" "$DENY" "$(cw "$c")"
done
expect "claude word denies in PowerShell too" "$DENY" "$(cw 'claude ps' PowerShell)"
o=$(cw 'claude ps'); expect "claude word names the session list" 'claude agents --json --all' "$o"; expect "claude word names ListAgents" 'ListAgents' "$o"
expect "claude word says why" "'ps' is not a claude subcommand, so claude would run it as a paid one-off prompt" "$o"
heredoc_commit=$'git commit -F- <<\'EOF\'\nGuard\n\nclaude ps was run twice\nEOF'
heredoc_py=$'python3 - <<PY\nimport shutil\nclaude = shutil.which("x")\nPY\necho done'
heredoc_tab=$'cat <<-X >notes.md\n\t| claude ps | paid |\n\tX'
continued=$'claude \\\n  agents --json --all'
for c in 'claude' 'claude --version' 'claude -p "hi"' 'claude agents --json --all' 'claude mcp list' 'cd /x && claude doctor' \
         'claude plugins list' 'echo "claude ps"' 'grep -n claude CLAUDE.md' 'git log --grep claude' 'myclaude ps' \
         "grep -n 'pkill\\|claude ps' notes.md" "rg -n 'pkill -f|claude ps' docs" "git commit -m 'fix; claude ps note'" \
         "$heredoc_commit" "$heredoc_py" "$heredoc_tab" "$continued" 'timeout 30 claude --version' 'FOO=1 claude doctor'; do
  o=$(cw "$c"); [ -z "$o" ] && ok || bad "claude word allows: $c -- got $o"
done
# after a heredoc ends, a real call is checked again
o=$(cw $'cat <<EOF\nclaude ps\nEOF\nclaude ps'); expect "claude word checks past a heredoc" "$DENY" "$o"

# a newer Claude Code's own words: the session status caches them from the
# installed `claude --help`, and the guard allows them too
WD="$GR_TMP/plugin data"; rm -f "$WD/claude-subcommands"
expect "a word no list holds is denied" "$DENY" "$(cw 'claude newthing --x')"
WS="$GR_TMP/word stubs"; mkdir -p "$WS"
cat > "$WS/claude" <<'EOS'
#!/bin/sh
case "$*" in
  --version) echo "2.9.1 (Claude Code)" ;;
  --help) printf 'Usage: claude [options] [command] [prompt]\n\nOptions:\n  -p, --print  Print\n\nCommands:\n'
          for w in agents auth doctor install mcp newthing plugin\|plugins setup-token update\|upgrade logs stop; do printf '  %s [options]  Does a thing\n' "$w"; done ;;
  *) echo "TEST CALLED REAL claude" >&2; exit 99 ;;
esac
EOS
chmod +x "$WS/claude"
PATH="$WS:$PATH" runhook SessionStart startup "$(hookjson cwd=/tmp source=startup)" >/dev/null 2>&1
expect "session status caches the installed claude's subcommands" '^newthing$' "$(cat "$WD/claude-subcommands" 2>/dev/null)"
expect "the cache names the version it was read from" '^version 2\.9\.1$' "$(head -1 "$WD/claude-subcommands" 2>/dev/null)"
o=$(cw 'claude newthing --x'); [ -z "$o" ] && ok || bad "claude word allows a word the installed claude lists -- got $o"
expect "the cache does not let any word through" "$DENY" "$(cw 'claude ps')"
# a help whose layout changed (under 10 words) leaves the cache as it was
printf '#!/bin/sh\ncase "$*" in --version) echo "2.9.2 (Claude Code)" ;; --help) echo "Commands:"; echo "  one  x" ;; *) exit 99 ;; esac\n' > "$WS/claude"
PATH="$WS:$PATH" runhook SessionStart startup "$(hookjson cwd=/tmp source=startup)" >/dev/null 2>&1
expect "a help read as under 10 words keeps the cache" '^newthing$' "$(cat "$WD/claude-subcommands" 2>/dev/null)"
rm -f "$WD/claude-subcommands"

# the guard's own list against the real `claude --help` (the CI validate job
# sets GUARDRAILS_REAL_CLAUDE; `--help` is local and free)
if [ -n "${GUARDRAILS_REAL_CLAUDE:-}" ] && [ -x "$GUARDRAILS_REAL_CLAUDE" ]; then
  known=" $("$GR_REPO/scripts/claude-word-guard.sh" --list | tr '\n' ' ') "
  helpwords=$("$GUARDRAILS_REAL_CLAUDE" --help 2>/dev/null | sed -n '/^Commands:/,$p' | grep -oE '^  [a-z][a-z-]*(\|[a-z][a-z-]*)*' | tr -d ' ' | tr '|' '\n')
  [ "$(printf '%s\n' "$helpwords" | grep -c .)" -ge 10 ] && ok || bad "claude word guard: read under 10 subcommands from claude --help -- has its layout changed?"
  while read -r w; do
    [ -z "$w" ] && continue
    case "$known" in *" $w "*) ok ;; *) bad "claude word guard lacks the subcommand '$w' (claude --help)" ;; esac
  done <<EOF2
$helpwords
EOF2
else
  echo "skip: the word list is compared with the real claude --help only where GUARDRAILS_REAL_CLAUDE names it (the CI validate job)"
fi
