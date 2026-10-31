# tests/lib.sh -- sourced by tests/run.sh. Assertions, fixtures, and a stub
# `claude` first on PATH so no test can reach the real one and spend.
# bash 3.2 (macOS's /bin/bash): no mapfile, no associative arrays, no ${x,,}.

GR_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GR_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gr-test.XXXXXX")
# As the scripts see it: no doubled slash (macOS's TMPDIR ends in /) and no
# symlink (macOS's /var is /private/var), so expected paths match printed ones.
GR_TMP=$(cd "$GR_TMP" && pwd -P)
pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

# expect NAME REGEX TEXT: TEXT matches REGEX (extended).
expect() { if printf '%s\n' "$3" | grep -qE -- "$2"; then ok; else bad "$1 -- wanted /$2/ in: $(printf '%s' "$3" | head -c 300)"; fi; }
# refuse NAME REGEX TEXT: TEXT does not match REGEX.
refuse() { if printf '%s\n' "$3" | grep -qE -- "$2"; then bad "$1 -- did not want /$2/ in: $(printf '%s' "$3" | head -c 300)"; else ok; fi; }

# exits NAME CODE CMD...: CMD exits with CODE (its output is discarded).
exits() {
  local name=$1 want=$2 rc
  shift 2
  "$@" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$want" ]; then ok; else bad "$name -- wanted exit $want, got $rc"; fi
}

# mkrepo DIR: a git repo with one commit on main and one more on feature
# (left checked out). DIR may contain a space.
mkrepo() {
  local g="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
  mkdir -p "$1"
  git init -q "$1"
  git -C "$1" symbolic-ref HEAD refs/heads/main
  $g -C "$1" commit -q --allow-empty -m init
  git -C "$1" checkout -q -b feature
  $g -C "$1" commit -q --allow-empty -m "feature work"
}

# jq: the tests' own reads drop a trailing \r, as gr_jq does, so they read a
# Windows jq.exe's output the way the scripts do.
jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }

# hookjson KEY=VALUE... : the JSON Claude Code sends a hook. Dotted keys
# nest (tool_input.command=ls); KEY:=JSON sets a raw value (n:=260000).
# MSYS2_ARG_CONV_EXCL: these are values, not files, and Git Bash would
# rewrite one such as cwd=/x as a Windows path (X:/) before jq.exe sees it.
# On Windows Claude Code sends cwd, transcript_path and the status line's
# workspace.current_dir in Windows form (C:\x\y), so the tests do too.
hookjson() {
  local a args=()
  for a; do
    case "$a" in
      cwd=/*|transcript_path=/*|workspace.current_dir=/*)
        command -v cygpath >/dev/null 2>&1 && a="${a%%=*}=$(cygpath -w "${a#*=}")" ;;
    esac
    args+=("$a")
  done
  MSYS2_ARG_CONV_EXCL='*' jq -cn 'reduce $ARGS.positional[] as $a ({};
    ($a | index("=")) as $i | $a[:$i] as $k
    | if ($k | endswith(":")) then setpath($k[:-1] | split("."); $a[$i + 1:] | fromjson)
      else setpath($k | split("."); $a[$i + 1:]) end)' --args ${args[@]+"${args[@]}"}
}

# runhook EVENT MATCHER STDIN: run every hooks.json command of EVENT whose
# matcher matches MATCHER (a tool name or source; no matcher matches all)
# the way Claude Code does: the command string through `sh -c`, with
# CLAUDE_PLUGIN_ROOT a copy of the plugin under a folder with a space.
# GR_HOOK=<text> keeps only commands containing <text>; GR_PLUGIN_SRC
# replaces the repo as the source. Prints stdout; returns the first
# non-zero exit code, else 0.
runhook() {
  local src=${GR_PLUGIN_SRC:-$GR_REPO} root cmd rc=0 r
  root="$GR_TMP/plugin root/$(printf '%s' "$src" | cksum | cut -d' ' -f1)"
  if [ ! -d "$root" ]; then
    mkdir -p "$root"
    (cd "$src" && tar cf - --exclude .git --exclude .superpowers .) | (cd "$root" && tar xf -)
  fi
  mkdir -p "$GR_TMP/plugin data"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in *"${GR_HOOK:-}"*) ;; *) continue ;; esac
    printf '%s' "$3" | CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PLUGIN_DATA="$GR_TMP/plugin data" sh -c "$cmd"
    r=$?
    [ "$rc" -ne 0 ] || rc=$r
  done <<EOF
$(jq -r --arg e "$1" --arg m "$2" '
  .hooks[$e][]? | (.matcher // "") as $mt | select($mt == "" or ($m | test("^(" + $mt + ")$")))
  | .hooks[] | .command' "$root/hooks/hooks.json" 2>/dev/null)
EOF
  return "$rc"
}

# scrub PATH...: lines naming a home folder or an email address, for the
# public-repo check (project names: tests/test-scrub.sh's private list). Prints file:line:text for each.
scrub() {
  grep -rnIE -- '/home/[a-z]|/Users/[A-Za-z]|[A-Za-z]:\\Users\\|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$@" 2>/dev/null
}

# The stub `claude`: any test that reaches it without installing its own fails.
mkdir -p "$GR_TMP/stub-bin"
printf '#!/bin/sh\necho "TEST CALLED REAL claude" >&2\nexit 99\n' > "$GR_TMP/stub-bin/claude"
chmod +x "$GR_TMP/stub-bin/claude"
PATH="$GR_TMP/stub-bin:$PATH"
export PATH

# GR_CRJQ: a folder holding a `jq` that ends every output line with \r, as a
# Windows jq.exe may; put it first on PATH to test a script against that.
GR_CRJQ="$GR_TMP/crlf-jq"
mkdir -p "$GR_CRJQ"
printf '#!/bin/sh\n"%s" "$@" | awk '"'"'{ printf "%%s\\r\\n", $0 }'"'"'\n' "$(type -P jq)" > "$GR_CRJQ/jq"
chmod +x "$GR_CRJQ/jq"
