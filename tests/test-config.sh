# test-config.sh -- scripts/config.sh and the portable helpers in scripts/lib.sh.

C="$GR_REPO/scripts/config.sh"
. "$GR_REPO/scripts/lib.sh"

# --- the project lookup: a repo is a project when it holds a config
P="$GR_TMP/dir with space/proj"; mkrepo "$P"; mkdir -p "$P/.claude" "$P/sub/deep"
O="$GR_TMP/dir with space/other"; mkrepo "$O"
F="$GR_TMP/foreign"; mkrepo "$F"
printf '%s\n' '# a comment' '' 'partners = ../other' '  memory   =  ~/mem/committed  ' \
  'words = CLAUDE.md 800' 'guard = (make deploy) :: :: :: This deploys.' \
  'guard = second = with equals :: :: :: x' > "$P/.claude/guardrails.conf"
o=$("$C" project "$P/sub/deep");  [ "$o" = "$P" ] && ok || bad "project from a subfolder -- got [$o]"
o=$("$C" project "$F");           [ -z "$o" ] && ok || bad "project foreign is nothing -- got [$o]"
o=$("$C" root "$F");              [ "$o" = "$F" ] && ok || bad "root foreign -- got [$o]"
o=$("$C" root "$GR_TMP");         [ -z "$o" ] && ok || bad "root outside git is nothing -- got [$o]"
exits "config.sh exits 0 knowing nothing" 0 "$C" get "$GR_TMP" memory

# --- values: repeats, comments, ~, relative paths against the root
o=$("$C" get "$P/sub/deep" partners); [ "$o" = "$O" ] && ok || bad "partners resolve against the root -- got [$o]"
o=$("$C" get "$P" memory);            [ "$o" = "$HOME/mem/committed" ] && ok || bad "memory ~ expands, trims -- got [$o]"
o=$("$C" get "$P" words);             [ "$o" = "$P/CLAUDE.md 800" ] && ok || bad "words path resolves -- got [$o]"
o=$("$C" get "$P" guard | wc -l | tr -d ' '); [ "$o" = 2 ] && ok || bad "guard repeats -- got $o lines"
o=$("$C" get "$P" guard | tail -1);  [ "$o" = "second = with equals :: :: :: x" ] && ok || bad "a value keeps its = -- got [$o]"
o=$("$C" repos "$P" | tr '\n' '|');  [ "$o" = "$P|$O|" ] && ok || bad "repos root then partners -- got [$o]"
o=$("$C" repos "$F" | tr '\n' '|');  [ "$o" = "$F|" ] && ok || bad "repos foreign -- got [$o]"

# --- defaults
o=$("$C" get "$P" decisions);          [ "$o" = "$P/docs/DECISIONS.md" ] && ok || bad "decisions default -- got [$o]"
mkdir -p "$P/docs/decisions"; touch "$P/docs/DECISIONS.md"
o=$("$C" get "$P" decisions | tr '\n' '|'); [ "$o" = "$P/docs/DECISIONS.md|$P/docs/decisions|" ] && ok || bad "decisions default, both present -- got [$o]"
rm "$P/docs/DECISIONS.md"
o=$("$C" get "$P" decisions); [ "$o" = "$P/docs/decisions" ] && ok || bad "decisions default, the folder only -- got [$o]"
rm -r "$P/docs/decisions"
o=$("$C" get "$P" backlog);            [ "$o" = "$P/docs/BACKLOG.md" ] && ok || bad "backlog default -- got [$o]"
o=$("$C" get "$P" agent_launch_guard); [ "$o" = off ] && ok || bad "agent_launch_guard default -- got [$o]"
o=$("$C" get "$F" decisions);          [ -z "$o" ] && ok || bad "no defaults outside a project -- got [$o]"

# --- the local file overrides the committed one
printf '%s\n' 'memory = /local/mem' 'decisions = notes/log.md' > "$P/.claude/guardrails.local.conf"
o=$("$C" memory "$P");          [ "$o" = /local/mem ] && ok || bad "local memory wins -- got [$o]"
o=$("$C" get "$P" decisions);   [ "$o" = "$P/notes/log.md" ] && ok || bad "local decisions resolve -- got [$o]"
L="$GR_TMP/localonly"; mkrepo "$L"; mkdir -p "$L/.claude"; echo 'ports = 1 2' > "$L/.claude/guardrails.local.conf"
o=$("$C" project "$L");         [ "$o" = "$L" ] && ok || bad "a local file alone makes a project -- got [$o]"

# --- CRLF gives the same values
R="$GR_TMP/crlf"; mkrepo "$R"; mkdir -p "$R/.claude"
printf 'partners = ../foreign\r\nmemory = ~/m\r\n' > "$R/.claude/guardrails.conf"
o=$("$C" get "$R" partners); [ "$o" = "$F" ] && ok || bad "CRLF partners -- got [$(printf '%s' "$o" | od -c | head -2)]"
o=$("$C" memory "$R");       [ "$o" = "$HOME/m" ] && ok || bad "CRLF memory -- got [$o]"

# --- memory falls back to autoMemoryDirectory, then Claude Code's own key
A="$GR_TMP/auto"; mkrepo "$A"; mkdir -p "$A/.claude"
echo '{"autoMemoryDirectory": "~/shared/memory"}' > "$A/.claude/settings.local.json"
o=$("$C" memory "$A"); [ "$o" = "$HOME/shared/memory" ] && ok || bad "memory from autoMemoryDirectory -- got [$o]"
o=$("$C" memory "$F")
k=$F; command -v cygpath >/dev/null 2>&1 && k=$(cygpath -m -l "$F")   # Windows: the native long path
want="$HOME/.claude/projects/$(printf '%s' "$k" | sed 's/[^A-Za-z0-9]/-/g')/memory"
[ "$o" = "$want" ] && ok || bad "memory default key -- got [$o] want [$want]"

# on Windows the key is built from the long form of the path (git prints the
# long form; cygpath -m alone may give an 8.3 short one, such as LONGFO~1)
SH="$GR_TMP/short cygpath"; mkdir -p "$SH"
printf '#!/bin/sh\nlong=; [ "$2" = -l ] && long=1\nfor a; do :; done\nif [ -n "$long" ]; then printf "C:/Long Folder%%s\\n" "$a"; else printf "C:/LONGFO~1%%s\\n" "$a"; fi\n' > "$SH/cygpath"; chmod +x "$SH/cygpath"
o=$(PATH="$SH:$PATH" "$C" memory "$F")
expect "the memory key uses the long Windows name" "C--Long-Folder-" "$o"

# --- a worktree reads its main checkout's local file and shares its memory key
git -C "$F" worktree add -q "$F/.claude/worktrees/rev" main 2>/dev/null
o=$("$C" memory "$F/.claude/worktrees/rev")
[ "$o" = "$want" ] && ok || bad "worktree shares the main memory key -- got [$o]"
git -C "$P" worktree add -q "$GR_TMP/p-wt" main 2>/dev/null
o=$("$C" memory "$GR_TMP/p-wt"); [ "$o" = /local/mem ] && ok || bad "worktree reads main's local file -- got [$o]"

# --- the user-level file adds words and watch_dirs, nothing else
U="$GR_TMP/home"; mkdir -p "$U/.claude"
printf '%s\n' 'words = ~/.claude/CLAUDE.md 800' 'watch_dirs = ~/tools' 'memory = /not/from/user' > "$U/.claude/guardrails.conf"
o=$(HOME=$U "$C" get "$P" words | tr '\n' '|'); [ "$o" = "$P/CLAUDE.md 800|$U/.claude/CLAUDE.md 800|" ] && ok || bad "user words added -- got [$o]"
o=$(HOME=$U "$C" get "$GR_TMP" watch_dirs);     [ "$o" = "$U/tools" ] && ok || bad "user watch_dirs outside a project -- got [$o]"
o=$(HOME=$U "$C" get "$F" memory);              [ -z "$o" ] && ok || bad "user file gives no memory -- got [$o]"

# --- gr_abspath
o=$(gr_abspath 'C:\Users\Jane Doe\x'); [ "$o" = 'C:/Users/Jane Doe/x' ] && ok || bad "abspath backslashes -- got [$o]"
o=$(gr_abspath 'C:/x');                [ "$o" = 'C:/x' ] && ok || bad "abspath drive letter -- got [$o]"
o=$(gr_abspath '/c/x');                [ "$o" = '/c/x' ] && ok || bad "abspath msys -- got [$o]"
o=$(cd "$GR_TMP" && gr_abspath rel/x); [ "$o" = "$(cd "$GR_TMP" && pwd)/rel/x" ] && ok || bad "abspath relative -- got [$o]"
o=$(gr_abspath '~/a/../b/./c');        [ "$o" = "$HOME/b/c" ] && ok || bad "abspath ~ and dots -- got [$o]"
o=$(gr_abspath '/a b/c/');             [ "$o" = '/a b/c' ] && ok || bad "abspath spaces, trailing slash -- got [$o]"

# --- time
o=$(TZ=Asia/Tokyo gr_iso_to_epoch 2026-10-25T00:00:00.123Z); [ "$o" = 1792886400 ] && ok || bad "iso with fraction -- got [$o]"
o=$(TZ=Asia/Tokyo gr_iso_to_epoch 2026-10-25T00:00:00Z);     [ "$o" = 1792886400 ] && ok || bad "iso without fraction -- got [$o]"
o=$(gr_iso_to_epoch garbage); [ -z "$o" ] && ok || bad "iso garbage is empty -- got [$o]"
touch "$GR_TMP/stamp"; o=$(gr_mtime "$GR_TMP/stamp"); n=$(date +%s)
[ -n "$o" ] && [ $((n - o)) -lt 60 ] && [ $((o - n)) -lt 60 ] && ok || bad "gr_mtime -- got [$o] now $n"

# --- jq
exits "gr_jq missing" 1 env GUARDRAILS_JQ=/nonexistent bash -c ". '$GR_REPO/scripts/lib.sh'; gr_jq"
exits "gr_jq present" 0 bash -c ". '$GR_REPO/scripts/lib.sh'; gr_jq"
o=$(gr_jq -r .a <<<'{"a":"x"}'); [ "$o" = x ] && ok || bad "gr_jq runs jq -- got [$o]"
o=$(GUARDRAILS_JQ=/nonexistent bash -c ". '$GR_REPO/scripts/lib.sh'; gr_need_jq cost-guard; echo after" 2>&1); rc=$?
[ "$rc" = 2 ] && ok || bad "gr_need_jq exits 2 -- got $rc"
expect "gr_need_jq names the guard and the fix" '^guardrails: cost-guard needs jq -- install it in a terminal outside Claude Code \(Windows: winget install jqlang\.jq; Mac: brew install jq; Linux: your package manager\), then start a new session\.$' "$o"
o=$(GUARDRAILS_JQ=/nonexistent "$C" memory "$A")
expect "memory without jq falls back to the key" "projects/.*-auto/memory$" "$o"

# --- gr_timeout and gr_listening, with stubs for the tools they pick between
o=$(gr_timeout 5 echo hi); [ "$o" = hi ] && ok || bad "gr_timeout runs the command -- got [$o]"
S="$GR_TMP/stubs-ss"; mkdir -p "$S"
printf '#!/bin/sh\necho "State Recv-Q Send-Q Local Peer"\necho "LISTEN 0 511 0.0.0.0:5173 0.0.0.0:*"\necho "LISTEN 0 511 [::]:80001 [::]:*"\n' > "$S/ss"
chmod +x "$S/ss"
o=$(PATH="$S:$PATH" gr_listening 5173 5001 8000 | tr '\n' ' '); [ "$o" = "5173 " ] && ok || bad "gr_listening via ss -- got [$o]"
S2="$GR_TMP/stubs-lsof"; mkdir -p "$S2"
printf '#!/bin/sh\nexit 1\n' > "$S2/ss"
printf '#!/bin/sh\necho "node 1 u 20u IPv4 0t0 TCP *:5001 (LISTEN)"\n' > "$S2/lsof"
chmod +x "$S2/ss" "$S2/lsof"
o=$(PATH="$S2:$PATH" gr_listening 5173 5001 | tr '\n' ' '); [ "$o" = "5001 " ] && ok || bad "gr_listening via lsof -- got [$o]"
