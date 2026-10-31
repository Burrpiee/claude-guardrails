# test-guards.sh -- the four PreToolUse guards, run through hooks.json the
# way Claude Code runs them.

ASK='"permissionDecision": *"ask"'
DENY='"permissionDecision": *"deny"'
WINDOWS=; command -v cygpath >/dev/null 2>&1 && WINDOWS=1

# gd GUARD TOOL CWD COMMAND: one guard's answer to a shell command.
gd() { GR_HOOK="$1" runhook PreToolUse "$2" "$(hookjson cwd="$3" tool_name="$2" tool_input.command="$4")"; }
# ga CWD PROMPT [TYPE]: the agent-launch guard's answer.
ga() { GR_HOOK=agent-launch-guard.sh runhook PreToolUse Agent \
  "$(hookjson cwd="$1" tool_name=Agent tool_input.prompt="$2" tool_input.subagent_type="${3:-code-reviewer}")"; }

exits "hooks.json parses" 0 jq -e . "$GR_REPO/hooks/hooks.json"
o=$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.onFailure != "block" or .timeout != 15)] | length' "$GR_REPO/hooks/hooks.json" 2>/dev/null)
[ "$o" = 0 ] && ok || bad "every guard blocks on failure, timeout 15 -- got [$o] that do not"
o=$(jq -r '.hooks.PreToolUse[].matcher' "$GR_REPO/hooks/hooks.json" 2>/dev/null | tr '\n' ' ')
[ "$o" = "Bash|PowerShell Agent|Task " ] && ok || bad "guard matchers -- got [$o]"
o=$(jq -r '.hooks[][].hooks[].command' "$GR_REPO/hooks/hooks.json" 2>/dev/null | grep -v '^"${CLAUDE_PLUGIN_ROOT}"/scripts/[a-z-]*\.sh')
refuse "hook commands are shell form, path quoted" '.' "$o"

# --- every guard: no jq refuses with the install line; every allow path is silent and exits 0
G="$GR_TMP/guards"; mkrepo "$G"; mkdir -p "$G/.claude"
for gs in cost-guard push-guard pkill-guard claude-word-guard; do
  o=$(GUARDRAILS_JQ=/nonexistent gd "$gs.sh" Bash "$G" ls 2>&1); rc=$?
  [ "$rc" = 2 ] && ok || bad "$gs without jq exits 2 -- got $rc"
  expect "$gs without jq says how to install it" "^guardrails: $gs needs jq -- install it in a terminal outside Claude Code \(Windows: winget install jqlang\.jq" "$o"
  for input in "$(hookjson cwd="$G" tool_name=Bash tool_input.command=ls)" 'garbage{' '{}'; do
    o=$(GR_HOOK=$gs.sh runhook PreToolUse Bash "$input" 2>&1); rc=$?
    [ "$rc" = 0 ] && [ -z "$o" ] && ok || bad "$gs allows [$input] silently -- rc $rc, got [$o]"
  done
done
o=$(GUARDRAILS_JQ=/nonexistent ga "$G" "inline" 2>&1); rc=$?
[ "$rc" = 2 ] && ok || bad "agent-launch-guard without jq exits 2 -- got $rc"
expect "agent-launch-guard without jq says so" '^guardrails: agent-launch-guard needs jq' "$o"
o=$(GR_HOOK=agent-launch-guard.sh runhook PreToolUse Agent 'garbage{' 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$o" ] && ok || bad "agent-launch-guard allows garbage silently -- rc $rc, got [$o]"

# --- cost guard: asks where the command RUNS, only in its project and its partners'
CP="$GR_TMP/cost proj"; mkrepo "$CP"; mkdir -p "$CP/.claude"
printf '%s\n' 'guard = (make deploy) :: :: :: This deploys.' \
  'guard = tool run[^|;&]*spend :: (^|[[:space:]])--all([[:space:]]|$) :: --dry-run :: Spends the lot (~$50).' \
  'guard = tool run[^|;&]*sync :: --source && --limit :: --dry-run :: N records FROM X ($12.50 once).' > "$CP/.claude/guardrails.conf"
PA="$GR_TMP/partner"; mkrepo "$PA"; mkdir -p "$PA/.claude"; echo 'partners = ../cost proj' > "$PA/.claude/guardrails.conf"
FO="$GR_TMP/foreign"; [ -d "$FO" ] || mkrepo "$FO"
asks()   { o=$(gd cost-guard.sh "${3:-Bash}" "$1" "$2"); expect "cost guard asks [$2] in $(basename "$1")" "$ASK" "$o"; }
allows() { o=$(gd cost-guard.sh Bash "$1" "$2"); rc=$?; [ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "cost guard allows [$2] in $(basename "$1") -- rc $rc, got $o"; }
asks   "$CP" "make deploy"
asks   "$CP/.claude" "cd /x && make deploy"
asks   "$CP" "ls; make deploy"
asks   "$CP" "make deploy" PowerShell
asks   "$PA" "make deploy"                       # a partner's guard applies too
allows "$CP" "echo 'make deploy'"
allows "$CP" "grep -n 'make deploy' README.md"
allows "$CP" "make build"
allows "$FO" "make deploy"
asks   "$CP" "tool run spend --all"
allows "$CP" "tool run spend --all-report"
allows "$CP" "tool run spend --all --dry-run"
asks   "$CP" "tool run sync --source t --limit 40"
allows "$CP" "tool run sync --source t"
allows "$CP" "tool run sync --source t --limit 40 --dry-run"
o=$(PATH="$GR_CRJQ:$PATH" gd cost-guard.sh Bash "$CP" "make deploy"); expect "cost guard asks with a jq that ends lines in CR" "$ASK" "$o"
o=$(PATH="$GR_CRJQ:$PATH" jq -r .a <<<'{"a":"x"}'); [ "$o" = x ] && ok || bad "the tests' own jq reads strip a CR -- got [$o]"
o=$(gd cost-guard.sh Bash "$CP" "make deploy");          expect "cost guard reason" 'Cost guard: This deploys\.' "$o"
o=$(gd cost-guard.sh Bash "$CP" "tool run sync --source t --limit 4"); expect "cost guard reason keeps \$" '\$12\.50' "$o"

# --- push guard: asks before pushing to a branch already merged into main
R="$GR_TMP/remote.git"; PD="$GR_TMP/push dir"; P="$PD/repo"; mkdir -p "$PD"
git init -q --bare "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
gp() { git -C "$P" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git clone -q "$R" "$P" 2>/dev/null; gp checkout -q -b main 2>/dev/null; gp commit -q --allow-empty -m init; gp push -q -u origin main 2>/dev/null
gp remote set-head origin main >/dev/null 2>&1
gp checkout -q -b merged; gp commit -q --allow-empty -m "merged work"; gp push -q -u origin merged 2>/dev/null
gp checkout -q main; gp merge -q --no-ff merged -m "Merge PR"; gp push -q origin main 2>/dev/null
gp checkout -q merged; gp commit -q --allow-empty -m "late commit"
gp checkout -q -b fresh main; gp push -q -u origin fresh 2>/dev/null; gp commit -q --allow-empty -m "new work"
gp checkout -q -b gone main; gp commit -q --allow-empty -m w; gp push -q -u origin gone 2>/dev/null; gp push -q origin --delete gone 2>/dev/null
gp checkout -q merged
pasks()   { o=$(gd push-guard.sh "${3:-Bash}" "$1" "$2"); expect "push guard asks [$2]" "$ASK" "$o"; }
pallows() { o=$(gd push-guard.sh Bash "$1" "$2"); rc=$?; [ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "push guard allows [$2] -- rc $rc, got $o"; }
pasks   "$P" "git push"
pasks   "$P" "git push -q origin merged"
pasks   "$GR_TMP" "cd \"$P\" && git push origin merged"
pasks   "$GR_TMP" "git -C \"$P\" push -u origin merged"
pasks   "$GR_TMP" "git -C '$P' push origin merged"
pasks   "$PD" "cd repo && git push origin merged"
pasks   "$GR_TMP" "Set-Location \"$P\"; git push origin merged" PowerShell
pasks   "$GR_TMP" "Set-Location -Path '$P'; git push" PowerShell
pasks   "$P" "git push origin gone"
pallows "$P" "git push origin fresh"
pallows "$P" "git push -q origin main"
pallows "$P" "git push origin --delete merged"
pallows "$P" "echo 'git push origin merged'"
pallows "$P" "git status"
pallows "$GR_TMP" "cd \"$P\" && git status && git push origin fresh"
if [ -n "$WINDOWS" ]; then pasks "$(cygpath -w "$P")" "git push origin merged"; fi
o=$(gd push-guard.sh Bash "$P" "git push origin merged"); expect "push guard reason" 'already merged into main' "$o"
o=$(gd push-guard.sh Bash "$P" "git push origin gone");   expect "push guard gone reason" 'no longer exists' "$o"

# --- pkill guard: denies pkill -f where it runs, nothing else
for c in 'pkill -f "vite preview"' 'cd /x && pkill -f node' 'sleep 1; pkill -9f gunicorn' \
         'sudo pkill --full vite' '(pkill -f a) || true' 'pkill -u me -f vite'; do
  o=$(gd pkill-guard.sh Bash /tmp "$c"); expect "pkill denies: $c" "$DENY" "$o"
done
o=$(gd pkill-guard.sh Bash /tmp 'pkill -f x'); expect "pkill advice is portable" 'ps ax \| grep \\"\[p\]attern\\"' "$o"
for c in 'pkill vite' 'echo "pkill -f is a trap"' 'grep -n "pkill -f" CLAUDE.md' \
         'ps ax | grep "[v]ite"' 'kill 1234' 'pgrep -f vite'; do
  o=$(gd pkill-guard.sh Bash /tmp "$c"); [ -z "$o" ] && ok || bad "pkill allows: $c -- got $o"
done

# --- agent launch guard: off unless the project says on; then a fresh MEMORY.md and a saved prompt
AP="$GR_TMP/agent proj"; mkrepo "$AP"; mkdir -p "$AP/.claude"; AM="$GR_TMP/agent mem"; mkdir -p "$AM"
echo "memory = $AM" > "$AP/.claude/guardrails.conf"
o=$(ga "$AP" "review it all inline"); [ -z "$o" ] && ok || bad "agent guard off by default -- got $o"
printf '%s\n' "memory = $AM" 'agent_launch_guard = on' > "$AP/.claude/guardrails.conf"
o=$(ga "$AP" "review it all inline")
expect "agent guard denies with no note" "$DENY" "$o"
expect "agent guard names MEMORY.md" "$AM/MEMORY\.md" "$o"; expect "agent guard wants the prompt saved" 'save the prompt' "$o"
echo note > "$AM/MEMORY.md"
mkdir -p "$GR_TMP/a b"; echo saved > "$GR_TMP/a b/p.md"; echo saved > "$GR_TMP/prompt.md"
o=$(ga "$AP" "review it all inline"); refuse "agent guard takes a fresh note" 'MEMORY\.md' "$o"; expect "agent guard still wants the prompt" 'save the prompt' "$o"
o=$(ga "$AP" "Your instructions are in $GR_TMP/prompt.md -- read it first."); [ -z "$o" ] && ok || bad "agent guard allows a saved prompt -- got $o"
o=$(ga "$AP" "Read \"$GR_TMP/a b/p.md\" first."); [ -z "$o" ] && ok || bad "agent guard allows a quoted spaced path -- got $o"
o=$(ga "$AP" "Read $GR_TMP/a b/p.md, then go."); [ -z "$o" ] && ok || bad "agent guard allows an unquoted spaced path -- got $o"
o=$(ga "$AP" "Instructions: $GR_TMP/missing.md"); expect "agent guard: the named file must exist" 'save the prompt' "$o"
if [ -n "$WINDOWS" ]; then
  mkdir -p "$GR_TMP/Jane Doe"; echo s > "$GR_TMP/Jane Doe/p.md"
  o=$(ga "$AP" "Read $(cygpath -m "$GR_TMP/Jane Doe/p.md")"); [ -z "$o" ] && ok || bad "agent guard allows C:/... with a space -- got $o"
  o=$(ga "$AP" "Read $(cygpath -w "$GR_TMP/prompt.md")");      [ -z "$o" ] && ok || bad "agent guard allows C:\\... -- got $o"
else
  # Off Windows, C:/x is a relative path: build it under the guard's cwd.
  DR="$GR_TMP/drive"; mkdir -p "$DR/C:/Users/Jane Doe" "$DR/C:/x"
  echo s > "$DR/C:/Users/Jane Doe/p.md"; echo s > "$DR/C:/x/p.md"
  o=$(cd "$DR" && ga "$AP" "Read C:/Users/Jane Doe/p.md first"); [ -z "$o" ] && ok || bad "agent guard allows C:/... with a space -- got $o"
  o=$(cd "$DR" && ga "$AP" 'Read C:\x\p.md first');              [ -z "$o" ] && ok || bad "agent guard allows C:\\x\\p.md -- got $o"
fi
touch -t 202001010000 "$AM/MEMORY.md"
o=$(ga "$AP" "Your instructions are in $GR_TMP/prompt.md"); expect "agent guard refuses a stale note" 'MEMORY\.md' "$o"
o=$(ga "$AP" "find the config files" Explore); [ -z "$o" ] && ok || bad "agent guard lets Explore through -- got $o"
o=$(ga "$FO" "inline"); [ -z "$o" ] && ok || bad "agent guard stays out of projects without a config -- got $o"
