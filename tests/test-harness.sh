# test-harness.sh -- the helpers every other test leans on.

# hookjson nests dotted keys and takes raw JSON after :=
o=$(hookjson cwd=/x tool_name=Bash 'tool_input.command=git push && ls' 'context_window.total_input_tokens:=260000')
expect "hookjson nests"  '"tool_input":\{"command":"git push && ls"\}' "$o"
expect "hookjson raw"    '"total_input_tokens":260000' "$o"
expect "hookjson string" '"tool_name":"Bash"' "$o"
# ...and the paths as Claude Code sends them: in Windows form on Windows
want=/x; command -v cygpath >/dev/null 2>&1 && want=$(cygpath -w /x)
[ "$(jq -r .cwd <<<"$o")" = "$want" ] && ok || bad "hookjson cwd -- wanted $want, got $(jq -r .cwd <<<"$o")"
o=$(hookjson transcript_path=/x workspace.current_dir=/x)
[ "$(jq -r .transcript_path <<<"$o")" = "$want" ] && ok || bad "hookjson transcript_path -- wanted $want, got $(jq -r .transcript_path <<<"$o")"
[ "$(jq -r .workspace.current_dir <<<"$o")" = "$want" ] && ok || bad "hookjson workspace.current_dir -- wanted $want, got $(jq -r .workspace.current_dir <<<"$o")"

# mkrepo, under a folder with a space
R="$GR_TMP/a repo"
mkrepo "$R"
o=$(git -C "$R" branch --format='%(refname:short)' | sort | tr '\n' ' ')
expect "mkrepo branches" '^feature main $' "$o"
o=$(git -C "$R" rev-parse --abbrev-ref HEAD); expect "mkrepo on feature" '^feature$' "$o"

# exits reports the real code
exits "exits sees 3" 3 sh -c 'exit 3'

# the stub claude stands in for the real one
exits "stub claude exits 99" 99 claude --version
o=$(claude -p hi 2>&1); expect "stub claude says so" 'TEST CALLED REAL claude' "$o"

# runhook: matcher as an anchored regex, shell form, root path with a space
FX="$GR_TMP/fixture"; mkdir -p "$FX/hooks" "$FX/scripts"
printf '%s\n' '#!/bin/sh' 'echo "root=$CLAUDE_PLUGIN_ROOT"; echo "in=$(cat)"; exit 3' > "$FX/scripts/echo.sh"
printf '%s\n' '#!/bin/sh' 'echo second; exit 0' > "$FX/scripts/second.sh"
chmod +x "$FX/scripts/echo.sh" "$FX/scripts/second.sh"
cat > "$FX/hooks/hooks.json" <<'EOF'
{"hooks": {
  "PreToolUse": [
    {"matcher": "Bash|PowerShell", "hooks": [
      {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/echo.sh"},
      {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/second.sh"}]}],
  "SessionStart": [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/second.sh"}]}]
}}
EOF
o=$(GR_PLUGIN_SRC=$FX runhook PreToolUse PowerShell '{"a":1}'); rc=$?
expect "runhook root has a space" 'root=.*plugin root/' "$o"
expect "runhook passes stdin"     'in=\{"a":1\}' "$o"
expect "runhook runs every match" '^second$' "$o"
[ "$rc" = 3 ] && ok || bad "runhook returns the first non-zero code -- got $rc"
o=$(GR_PLUGIN_SRC=$FX GR_HOOK=second.sh runhook PreToolUse Bash '{}'); rc=$?
refuse "GR_HOOK filters" 'root=' "$o"; [ "$rc" = 0 ] && ok || bad "GR_HOOK filtered rc -- got $rc"
o=$(GR_PLUGIN_SRC=$FX runhook PreToolUse BashOutput '{}')
refuse "matcher is anchored" '.' "$o"
o=$(GR_PLUGIN_SRC=$FX runhook SessionStart startup '{}')
expect "no matcher matches all" '^second$' "$o"
