#!/usr/bin/env bash
# config.sh -- read a project's .claude/guardrails.conf for the hooks and tools.
#
#   config.sh project <dir>     the repo root when it holds a config, else nothing
#   config.sh get <dir> <key>   every value of <key>, one a line, local file first
#   config.sh root <dir>        the repo root of <dir>, else nothing
#   config.sh memory <dir>      the memory folder a session started in <dir> uses
#   config.sh repos <dir>       root, then partners -- the repos worth reporting
#
# Reads <root>/.claude/guardrails.local.conf (git-ignored; a linked worktree
# also reads its main checkout's), then <root>/.claude/guardrails.conf, and
# for words and watch_dirs also ~/.claude/guardrails.conf. Lines are
# `key = value`; keys may repeat; # starts a comment line.
#
# Always exits 0, with empty output when it knows nothing, so a hook calling
# it falls back to its generic behaviour instead of failing.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
CR=$'\r'

# The repo root: the nearest folder up from <dir> holding .git, in the same
# form the path was given (git's own answer would be C:/... in Git Bash).
_root() {
  local d
  d=$(gr_abspath "$1")
  while :; do
    [ -e "$d/.git" ] && { printf '%s\n' "$d"; return 0; }
    case "$d" in /|[A-Za-z]:|"") return 0 ;; esac
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
}

# The main checkout of a linked worktree (its .git file points into the
# main repo's .git/worktrees/), else the root itself.
_main() {
  local g
  if [ -f "$1/.git" ]; then
    g=$(head -1 "$1/.git"); g=${g#gitdir: }; g=${g%"$CR"}
    case "$g" in
      */.git/worktrees/*)
        case "$g" in /*|[A-Za-z]:*) ;; *) g="$1/$g" ;; esac
        gr_abspath "${g%/.git/worktrees/*}"
        return 0 ;;
    esac
  fi
  printf '%s\n' "$1"
}

# Config files of root $1, in reading order.
_files() {
  local m
  m=$(_main "$1")
  echo "$1/.claude/guardrails.local.conf"
  [ "$m" != "$1" ] && echo "$m/.claude/guardrails.local.conf"
  echo "$1/.claude/guardrails.conf"
}

_vals() {  # file key
  [ -f "$1" ] || return 0
  local line k v
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$CR"}
    line=${line#"${line%%[![:space:]]*}"}
    case "$line" in ""|"#"*) continue ;; *=*) ;; *) continue ;; esac
    k=${line%%=*}; k=${k%"${k##*[![:space:]]}"}
    [ "$k" = "$2" ] || continue
    v=${line#*=}
    v=${v#"${v%%[![:space:]]*}"}
    v=${v%"${v##*[![:space:]]}"}
    printf '%s\n' "$v"
  done < "$1"
}

_resolve() {  # key value base
  local v=$2
  case "$1" in
    partners|decisions|backlog|worktree_links|memory|watch_dirs)
      case "$v" in "~"*|/*|[A-Za-z]:*) gr_abspath "$v" ;; *) gr_abspath "$3/$v" ;; esac ;;
    words)
      _resolve partners "${v% *}" "$3" | tr -d '\n'; printf ' %s\n' "${v##* }" ;;
    *)
      case "$v" in "~/"*) v="$HOME/${v#??}" ;; esac
      printf '%s\n' "$v" ;;
  esac
}

_get() {  # dir key
  local r f v out=""
  r=$(_root "$1")
  if [ -n "$r" ]; then
    while IFS= read -r f; do
      while IFS= read -r v; do [ -n "$v" ] && out="$out$(_resolve "$2" "$v" "$r")
"; done <<EOF
$(_vals "$f" "$2")
EOF
    done <<EOF
$(_files "$r")
EOF
  fi
  case "$2" in
    words|watch_dirs)
      while IFS= read -r v; do [ -n "$v" ] && out="$out$(_resolve "$2" "$v" "$HOME")
"; done <<EOF
$(_vals "$HOME/.claude/guardrails.conf" "$2")
EOF
      ;;
  esac
  out=$(printf '%s' "$out" | grep -v '^$')
  if [ -z "$out" ] && [ -n "$(_project "$1")" ]; then
    case "$2" in
      decisions)          # the log and the records folder, each when present
                          [ -f "$r/docs/DECISIONS.md" ] && out=$(gr_abspath "$r/docs/DECISIONS.md")
                          [ -d "$r/docs/decisions" ] && out="${out:+$out
}$(gr_abspath "$r/docs/decisions")"
                          [ -n "$out" ] || out=$(gr_abspath "$r/docs/DECISIONS.md") ;;
      backlog)            out=$(gr_abspath "$r/docs/BACKLOG.md") ;;
      agent_launch_guard) out=off ;;
    esac
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

_project() {  # dir
  local r f
  r=$(_root "$1")
  [ -n "$r" ] || return 0
  while IFS= read -r f; do
    [ -f "$f" ] && { printf '%s\n' "$r"; return 0; }
  done <<EOF
$(_files "$r")
EOF
}

# The memory folder: the config's, else the repo's autoMemoryDirectory, else
# Claude Code's own key for the main checkout (shared by its worktrees).
_memory() {  # dir
  local r m="" f k
  m=$(_get "$1" memory | head -1)
  [ -n "$m" ] && { printf '%s\n' "$m"; return 0; }
  r=$(_root "$1")
  if [ -n "$r" ]; then
    for f in "$r/.claude/settings.local.json" "$r/.claude/settings.json" \
             "$(_main "$r")/.claude/settings.local.json" "$(_main "$r")/.claude/settings.json"; do
      [ -f "$f" ] || continue
      m=$(gr_jq -r '.autoMemoryDirectory // empty' "$f" 2>/dev/null) || m=""
      [ -n "$m" ] && { gr_abspath "$m"; return 0; }
    done
    k=$(_main "$r")
  else
    k=$(gr_abspath "$1")
  fi
  # Claude Code keys the folder by the native path (C:\x -> C--x), in its long
  # form as git prints it (not an 8.3 short name).
  case "$k" in /*) command -v cygpath >/dev/null 2>&1 && k=$(cygpath -m -l "$k") ;; esac
  printf '%s\n' "$HOME/.claude/projects/$(printf '%s' "$k" | sed 's/[^A-Za-z0-9]/-/g')/memory"
}

case "${1:-}" in
  project) [ -n "${2:-}" ] && _project "$2" ;;
  get)     [ -n "${2:-}" ] && [ -n "${3:-}" ] && _get "$2" "$3" ;;
  root)    [ -n "${2:-}" ] && _root "$2" ;;
  memory)  [ -n "${2:-}" ] && _memory "$2" ;;
  repos)   if [ -n "${2:-}" ]; then
             r=$(_root "$2")
             [ -n "$r" ] && { echo "$r"; _get "$2" partners; }
           fi ;;
  *) sed -n '2,8p' "$0" >&2 ;;
esac
exit 0
