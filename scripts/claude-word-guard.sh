#!/usr/bin/env bash
# PreToolUse (Bash|PowerShell): refuse `claude <word>` unless the word is a
# real subcommand or a flag, with the session list in the reason. A word
# claude does not know runs as a paid one-off prompt: `claude ps`, typed to
# list sessions, starts a model call instead. Denied rather than asked: the
# reason names what to run instead. A quoted prompt (`claude "..."`) is
# refused too; a deliberate one is `claude -p "..."`. Prints nothing for
# every other command. `--list` prints the subcommands it knows by itself
# (the tests compare them with `claude --help`).
#
# Known gaps: `bash -c "..."`, xargs and a flag before the word (`claude
# --verbose ps`) are not caught; a subcommand a Claude Code update removes
# stays allowed; PowerShell here-strings are scanned as commands.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# From `claude --help`, 2.1.312; aliases listed as their own words. The
# session status adds the installed version's own words to
# ${CLAUDE_PLUGIN_DATA}/claude-subcommands, so a newer Claude Code's
# subcommand is not refused.
subs="agents attach auth auto-mode doctor gateway import install logs mcp plugin
plugins purge respawn rm setup-token stop kill ultrareview update upgrade"
[ "${1:-}" = "--list" ] && { printf '%s\n' $subs; exit 0; }

gr_need_jq claude-word-guard
input=$(cat)
cmd=$(gr_jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0
known=$(printf '%s\n' $subs)
cache="${CLAUDE_PLUGIN_DATA:-}/claude-subcommands"
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "$cache" ] && known="$known
$(sed 1d "$cache")"

# What is only text, not a command, goes before the scan (a grep pattern, a
# heredoc's body and a commit message would be refused): a backslash-newline
# is joined, heredoc bodies are dropped, and single-quoted strings are
# emptied. Double-quoted text is still scanned, since `"$(claude ps)"` runs;
# so `echo "a && claude ps"` is refused, a known over-refusal.
cmd=${cmd//$'\\\n'/ }
cmd=$(awk -v q="'" '
  skip { t = $0; if (strip) sub(/^\t+/, "", t); if (t == delim) skip = 0; next }
  { print; line = $0
    while (match(line, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
      op = substr(line, RSTART, RLENGTH); pre = RSTART > 1 ? substr(line, RSTART - 1, 1) : ""
      line = substr(line, RSTART + RLENGTH)
      if (pre == "<" || substr(op, 3, 1) == "<") continue   # a here-string, <<<
      strip = substr(op, 3, 1) == "-"
      delim = op; sub(/^<<-?[ \t]*/, "", delim); gsub("[\"" q "]", "", delim)
      skip = 1; break
    } }' <<<"$cmd")
cmd=$(awk -v q="'" 'BEGIN { RS = "\001" } {
  out = ""; s = 0; d = 0; n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (s) { if (c == q) s = 0; continue }
    if (c == "\\") { out = out c substr($0, i + 1, 1); i++; continue }
    if (c == q && !d) { s = 1; out = out q q; continue }
    if (c == "\"") d = !d
    out = out c
  }
  printf "%s", out }' <<<"$cmd")

# `claude` where it would RUN: at the start, or after &&, ||, ;, |, (, {, a
# backtick or a newline, after any of the usual prefixes (VAR=value, env, sudo,
# command, exec, nohup, time, timeout [-opts] N, if/then/do/while/until/!) and
# with or without a path. Its first argument is the next word, quotes
# included.
sep='(^|[;&|({`])[[:space:]]*'
pfx='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|env|command|exec|nohup|time|if|then|do|else|elif|while|until|!|timeout([[:space:]]+-[^[:space:]]+)*([[:space:]]+[A-Z]+)?[[:space:]]+[0-9.]+[smhd]?)[[:space:]]+)*'
bin='([^[:space:];&|(){}`]*/)?claude[[:space:]]+[^[:space:];&|)`]+'
bad=""
while read -r arg; do
  [ -z "$arg" ] && continue
  case "$arg" in -*) continue ;; esac
  printf '%s\n' "$known" | grep -qxF -- "$arg" && continue
  bad=$arg; break
done < <(printf '%s\n' "$cmd" | grep -oE "$sep$pfx$bin" | sed -E 's/^.*claude[[:space:]]+//')
[ -z "$bad" ] && exit 0

reason="'$bad' is not a claude subcommand, so claude would run it as a paid one-off prompt. To list sessions: claude agents --json --all (or, in a main session, the ListAgents tool). Real subcommands: claude --help. A deliberate one-off prompt is claude -p \"...\"."
gr_jq -n --arg r "claude word guard: $reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
