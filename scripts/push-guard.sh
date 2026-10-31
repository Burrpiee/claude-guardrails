#!/usr/bin/env bash
# PreToolUse (Bash|PowerShell): ask the user before `git push`
# - sends commits to a branch whose work already merged into the default
#   branch, or whose remote branch was deleted (usually after its pull request
#   merged) -- those commits would never reach the default branch;
# - would undo the default branch's recent work (undo-check.sh), to any
#   branch, the default one included;
# - skips or overrides git's pre-push hook, which makes the undo check inside
#   `git push` where it is installed (guardrails-install-git-hooks).
# Where that hook is installed the guard leaves the undo check to git, which
# also sees a commit made in the same command; elsewhere it checks the branch
# as it is before the command runs. Works in any repo, config or not. Prints
# nothing -- and so leaves the normal permission flow -- otherwise.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
gr_need_jq push-guard
input=$(cat)
cmd=$(gr_jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || cmd=""
[ -n "$cmd" ] || exit 0
dir=$(gr_jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || dir=""
dir=$(gr_abspath "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}")
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
set -f

# Asks with every reason given, joined; prints nothing when there is none.
finish() {
  local r="" x
  for x in "$@"; do [ -n "$x" ] && r="${r:+$r Also: }$x"; done
  [ -n "$r" ] && gr_jq -n --arg r "Push guard: $r" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

# Skipping or overriding git's pre-push hook is the user's yes to give, so it
# is decided from the whole command, before anything below can give up on
# reading it, ignoring case where git does: --no-verify in any shortened
# spelling git accepts, core.hooksPath set on the command line, in git config
# or through GIT_CONFIG_*, or a GUARDRAILS_ALLOW_UNDO / GUARDRAILS_UNDO_DAYS
# setting (plain or exported). --no-verify asks wherever it appears in a
# command that pushes, a commit message naming it included; the settings ask
# only when set, not when a message names them. A false match costs one ask.
bypass=""
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])push([^[:alnum:]_-]|$)'; then
  if printf '%s\n' "$cmd" | grep -qE -- '(^|[^[:alnum:]_-])--no-v[a-z]*([^[:alnum:]_-]|$)'; then
    bypass="--no-verify skips git's hooks, so the undo check in the pre-push hook (where installed) does not run. Push without it unless the user wants the check skipped."
  elif printf '%s\n' "$cmd" | grep -qiE 'core\.hookspath[[:space:]]*=|config[[:space:]]+(-[^[:space:]]+[[:space:]]+)*core\.hookspath|GIT_CONFIG_(COUNT|PARAMETERS|GLOBAL|SYSTEM)'; then
    bypass="this command changes where git looks for its hooks (core.hooksPath or GIT_CONFIG_*), which skips the undo check in the pre-push hook (where installed)."
  elif printf '%s\n' "$cmd" | grep -qE 'GUARDRAILS_(ALLOW_UNDO|UNDO_DAYS)='; then
    bypass="this command sets GUARDRAILS_ALLOW_UNDO or GUARDRAILS_UNDO_DAYS, which lets a push that undoes the default branch's work through, or changes the check. It is the user's yes to give."
  fi
fi

# One shell word: "quoted", 'quoted', or bare.
ARG="(\"[^\"]*\"|'[^']*'|[^[:space:];&|]+)"
# The push segment: `[VAR=x] [timeout 60 | env | command ...] git [-C dir]
# [-c k=v] [--no-pager] push ...` where it would RUN (at the start or after
# &&, ||, ;, |, ( or a newline), not inside echo "..." or a grep pattern.
WRAP="([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*|env|command|exec|nice|time|timeout|[0-9.]+[smhd]?|-[^[:space:];&|]+)"
seg=$(printf '%s\n' "$cmd" | grep -oE "(^|[;&|(])[[:space:]]*($WRAP[[:space:]]+)*git([[:space:]]+(-C[[:space:]]+$ARG|-c[[:space:]]+[^[:space:];&|]+|--[a-z-]+(=[^[:space:];&|]+)?))*[[:space:]]+push([[:space:]]+[^;&|]*)?" | head -1)
[ -n "$seg" ] || finish "$bypass"

unquote() { local p=$1; case "$p" in \"*\"|\'*\') p=${p#?}; p=${p%?} ;; esac; printf '%s' "$p"; }
place() {  # a path as written, relative to the hook's cwd
  local p
  p=$(unquote "$1")
  case "$p" in "~"*|/*|[A-Za-z]:*) gr_abspath "$p" ;; *) gr_abspath "$dir/$p" ;; esac
}

# Which repo: `git -C <dir>`, else the last cd / Set-Location before the push, else cwd.
c=$(printf '%s\n' "$seg" | grep -oE -- "-C[[:space:]]+$ARG" | head -1)
if [ -n "$c" ]; then
  c=${c#-C}; c=${c#"${c%%[![:space:]]*}"}
  repo=$(place "$c")
else
  before=${cmd%%"$seg"*}
  d=$(printf '%s\n' "$before" | grep -oiE "(^|[;&|])[[:space:]]*(cd|set-location|pushd)([[:space:]]+-(literal)?path)?[[:space:]]+$ARG" | tail -1)
  if [ -n "$d" ]; then
    d=$(printf '%s\n' "$d" | grep -oE "$ARG" | tail -1)
    repo=$(place "$d")
  else
    repo=$dir
  fi
fi
g() { git -C "$repo" "$@" 2>/dev/null; }
g rev-parse --git-dir >/dev/null || finish "$bypass"

# Positional args after the first ` push`: [remote [refspec...]]. Options are skipped.
args=${seg#*[[:space:]]push}
# A delete (`--delete`, `:branch`) or a tag push is never the case this guards.
printf '%s\n' "$args" | grep -qE -- '(^|[[:space:]])(--delete|-d|--tags)([[:space:]]|$)' && finish "$bypass"
remote=""; ref=""; n=0
for a in $args; do
  case "$a" in -*|"<"*|">"*|*">"*) continue ;; esac
  n=$((n + 1))
  [ "$n" = 1 ] && remote=$(unquote "$a")
  [ "$n" = 2 ] && ref=$(unquote "$a")
done
branch=$(g branch --show-current)
remote=${remote:-$(g config "branch.$branch.remote")}
remote=${remote:-origin}
if [ -z "$ref" ] || [ "$ref" = "HEAD" ]; then ref=$branch; fi
case "$ref" in :*) finish "$bypass" ;; esac
ref=${ref#+}
# `src:dst`: the commit pushed is the source side, the branch named the destination.
src=${ref%%:*}; ref=${ref##*:}; ref=${ref#refs/heads/}
[ -n "$ref" ] || finish "$bypass"
head=$(g rev-parse -q --verify "refs/heads/${src#refs/heads/}^{commit}" || g rev-parse -q --verify "$src^{commit}")

# Fresh state: a pull request merged on the server is invisible until fetched.
gr_timeout 8 git -C "$repo" fetch -q "$remote" >/dev/null 2>&1 </dev/null
# The default branch: the remote's HEAD, else main, else master (git before
# 2.48 sets the remote's HEAD only on clone).
def=$(g symbolic-ref --short "refs/remotes/$remote/HEAD"); def=${def#"$remote"/}
if [ -z "$def" ]; then
  for c in main master; do
    g rev-parse -q --verify "refs/remotes/$remote/$c" >/dev/null && { def=$c; break; }
  done
fi
def=${def:-main}
rb="refs/remotes/$remote/$ref"; base="refs/remotes/$remote/$def"
g rev-parse -q --verify "$base" >/dev/null || finish "$bypass"

reason=""
if [ "$ref" = "$def" ]; then
  :
elif g rev-parse -q --verify "$rb" >/dev/null; then
  tip=$(g rev-parse "$rb")
  # Merged = the remote branch's tip is inside the default branch, but not on
  # its first-parent line (a branch merely created at a main commit and
  # pushed before any work is on that line, and is not "merged").
  if g merge-base --is-ancestor "$tip" "$base" && ! g rev-list --first-parent "$base" | grep -qx "$tip"; then
    reason="'$ref' was already merged into $def, so commits pushed to it will not reach $def. Start a new branch from $remote/$def (or cherry-pick onto one) instead of pushing here."
  fi
elif [ -n "$(g config "branch.$ref.merge")" ]; then
  reason="'$ref' tracks a remote branch that no longer exists on $remote (usually deleted after its PR merged). Pushing re-creates it and its commits will not reach $def. Check that, then start a new branch from $remote/$def."
fi

# Installed = the repo's pre-push is the installer's stub, or a hook of the
# repo's own that calls the copy, and the copy it runs exists (a stub without
# its copy lets every push through unchecked).
hp="$(g rev-parse --path-format=absolute --git-path hooks)/pre-push"
hooked=""
if grep -q guardrails-undo-check-stub "$hp" 2>/dev/null; then
  copy=$(sed -n "s/^copy='\(.*\)'\$/\1/p" "$hp" | head -1)
  [ -n "$copy" ] && [ -f "$copy" ] && hooked=1
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "$CLAUDE_PLUGIN_DATA/git-hooks/pre-push" ] \
     && grep -qF "$CLAUDE_PLUGIN_DATA/git-hooks/pre-push" "$hp" 2>/dev/null; then
  hooked=1
fi
# With the override set, the undo is checked too, so the user sees what the
# yes lets through. The check gets what is left of the guard's 15 s (at most
# GUARDRAILS_UNDO_SECONDS, default 10); exit 2 means it could not run.
late=""
if [ -n "$head" ] && { [ -n "$bypass" ] || { [ -z "$reason" ] && [ -z "$hooked" ]; }; }; then
  budget=${GUARDRAILS_UNDO_SECONDS:-10}
  case "$budget" in ''|*[!0-9]*) budget=10 ;; esac
  left=$((13 - SECONDS)); [ "$left" -lt "$budget" ] && budget=$left
  if [ "$budget" -lt 1 ]; then
    undo=""; st=124
  else
    undo=$(gr_timeout "$budget" bash "$here/undo-check.sh" "$repo" "$remote" "$head" "$(g rev-parse -q --verify "$rb")" </dev/null); st=$?
  fi
  [ "$st" = 0 ] || undo=""
  [ "$st" = 124 ] && late="the undo check was not checked in time (it gets ${budget}s here), so this push is not checked for undoing $def's recent work; say yes to push unchecked. guardrails-install-git-hooks makes the check inside git push instead, with no time limit."
  fix=""
  [ -z "$hooked" ] && fix=" To have git make this check inside every push, from a terminal or an IDE too, run: guardrails-install-git-hooks --data \"${CLAUDE_PLUGIN_DATA:-<the plugin data folder>}\"."
  if [ -n "$undo" ] && [ -n "$bypass" ]; then
    bypass="$bypass What it lets through: $undo."
  elif [ -n "$undo" ]; then
    reason="$undo; if a revert is meant, say yes.$fix"
  fi
fi

finish "$reason" "$bypass" "$late"
