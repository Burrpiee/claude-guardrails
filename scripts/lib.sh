# scripts/lib.sh -- portable helpers, sourced by every hook and tool.
# Runs under bash 3.2 (macOS), Git Bash (Windows) and GNU/Linux: nothing
# here may assume GNU coreutils. Never exits, except gr_need_jq.

# gr_jq [ARGS...]: with no arguments, succeeds when jq can run; with
# arguments, runs it and returns jq's status. A Windows jq.exe may end each
# line with \r, which would stick to every value read, so it is dropped (tr,
# not sed: BSD sed reads \r as a plain r). GUARDRAILS_JQ names another jq
# (tests point it at a missing file to stand for "not installed").
gr_jq() {
  local j=${GUARDRAILS_JQ:-jq}
  command -v "$j" >/dev/null 2>&1 || return 1
  [ $# -eq 0 ] && return 0
  "$j" "$@" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

# gr_need_jq GUARD: a guard without jq refuses rather than lets through.
gr_need_jq() {
  gr_jq && return 0
  echo "guardrails: $1 needs jq -- install it in a terminal outside Claude Code (Windows: winget install jqlang.jq; Mac: brew install jq; Linux: your package manager), then start a new session." >&2
  exit 2
}

# gr_python: prints the command that runs Python 3.7 or later (the first with
# sys.stdout.reconfigure, which the tools' UTF-8 output needs), else fails.
# GUARDRAILS_PYTHON when set (no other is tried); otherwise the first of
# python3, python and py that runs as one. Each is run, not just found:
# on Windows, python3 is often the Microsoft Store's placeholder, which only
# says "Python was not found", and python.org's installer gives python and
# py, not python3.
gr_python() {
  local c
  for c in ${GUARDRAILS_PYTHON:+"$GUARDRAILS_PYTHON"} python3 python py; do
    command -v "$c" >/dev/null 2>&1 \
      && "$c" -c 'import sys; sys.exit(not (3, 7) <= sys.version_info < (4,))' < /dev/null > /dev/null 2>&1 \
      && { printf '%s\n' "$c"; return 0; }
    [ -n "${GUARDRAILS_PYTHON:-}" ] && return 1
  done
  return 1
}

# gr_no_python TOOL: says, on stderr, that TOOL found no Python 3.7+ and why.
gr_no_python() {
  if [ -n "${GUARDRAILS_PYTHON:-}" ]; then
    echo "guardrails: $1 needs python3: GUARDRAILS_PYTHON ($GUARDRAILS_PYTHON) does not run as Python 3.7 or later" >&2
  else
    echo "guardrails: $1 needs python3 (none of python3, python or py runs as Python 3.7 or later; install one, or set GUARDRAILS_PYTHON to it)" >&2
  fi
}

# gr_abspath PATH: absolute, with ~ expanded, \ turned into /, . and ..
# folded, no trailing /. C:/x and /c/x count as absolute. The path need
# not exist.
gr_abspath() {
  local p=$1 out="" seg rest drive=""
  case "$p" in
    "~") p=$HOME ;;
    "~/"*|"~\\"*) p="$HOME/${p#??}" ;;
  esac
  p=${p//\\//}
  case "$p" in
    [A-Za-z]:) p="$p/" ;;
  esac
  case "$p" in
    /*) ;;
    [A-Za-z]:/*) drive=${p%%/*}; p=${p#??} ;;
    *) p="$PWD/$p" ;;
  esac
  rest=$p
  while [ -n "$rest" ]; do
    seg=${rest%%/*}
    if [ "$seg" = "$rest" ]; then rest=""; else rest=${rest#*/}; fi
    case "$seg" in
      ""|.) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s\n' "$drive${out:-/}"
}

# gr_mtime FILE: modification time in epoch seconds (GNU, then BSD stat).
gr_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# gr_iso_to_epoch ISO: 2026-10-25T00:00:00[.fff]Z as UTC epoch seconds,
# whatever TZ says; empty when it cannot be read.
gr_iso_to_epoch() {
  local s=${1%Z}
  s=${s%%.*}
  case "$s" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  date -u -d "${s}Z" +%s 2>/dev/null \
    || date -j -u -f %Y-%m-%dT%H:%M:%S "$s" +%s 2>/dev/null \
    || true
}

# gr_timeout SECS CMD...: GNU timeout when that is what `timeout` is
# (Windows also has an unrelated timeout.exe), else gtimeout, else no limit.
gr_timeout() {
  if timeout --version 2>/dev/null | grep -q coreutils; then
    timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$@"
  else
    shift
    "$@"
  fi
}

# gr_listening PORT...: the ports given that something listens on, one a
# line (ss, then lsof, then netstat).
gr_listening() {
  local out p
  out=$(ss -ltn 2>/dev/null) || out=""
  [ -n "$out" ] || out=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null) || out=""
  [ -n "$out" ] || out=$(netstat -an 2>/dev/null | grep -i listen) || out=""
  for p in "$@"; do
    printf '%s\n' "$out" | grep -qE "[:.]$p([^0-9]|\$)" && echo "$p"
  done
  return 0
}
