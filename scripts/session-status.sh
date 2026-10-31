#!/usr/bin/env bash
# SessionStart (every source, compaction included): live state a session
# should start from rather than recall. For the repo the session started in
# and its partners: branch, uncommitted count, and every local branch not yet
# merged into the default branch (as of the last fetch). Then, as far as the
# config says: dev ports listening, the signed-in Claude account, unsaved
# changes in the folders named by watch_dirs, process fixes awaiting the user
# (pending-improvements.md in the memory folder), instruction files over
# their word budget, and backlog rulings the decision log may have settled.
# Warns first when jq is missing or Claude Code is too old for the guards.
# Also refreshes the copies the status line and git's pre-push hook run from
# in the plugin's data folder, and caches Claude Code's own subcommands.
# Never fails the session: prints what it can and exits 0.
#
#   session-status.sh [dir]   dir defaults to the hook's cwd, else $PWD
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
C="$here/config.sh"
dir=${1:-}
if [ -z "$dir" ] && [ ! -t 0 ]; then
  input=$(cat)
  dir=$(gr_jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || dir=""
fi
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}

gr_jq || echo "guardrails: jq is missing, so every command will be refused until it's installed -- install it in a terminal outside Claude Code (Windows: winget install jqlang.jq; Mac: brew install jq; Linux: your package manager), then start a new session."

# Before 2.1.295 a hook's onFailure is ignored, so a guard that crashes lets
# the command through.
v=$(gr_timeout 5 claude --version 2>/dev/null | head -1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
if [ -n "$v" ]; then
  IFS=. read -r a b c <<EOF
$v
EOF
  if [ "$a" -lt 2 ] || { [ "$a" -eq 2 ] && { [ "$b" -lt 1 ] || { [ "$b" -eq 1 ] && [ "$c" -lt 295 ]; }; }; }; then
    echo "guardrails: Claude Code $v is older than 2.1.295, the first version where a guard that fails refuses the command instead of letting it through -- update it (claude update)."
  fi
fi

# The installed Claude Code's own subcommands, for the claude word guard,
# read again when the version changes (`--help` is local: no model call). A
# help read as under 10 words has changed its layout: the cache is kept.
if [ -n "$v" ] && [ -n "${CLAUDE_PLUGIN_DATA:-}" ] \
   && [ "$(head -1 "$CLAUDE_PLUGIN_DATA/claude-subcommands" 2>/dev/null)" != "version $v" ]; then
  words=$(gr_timeout 5 claude --help 2>/dev/null | sed -n '/^Commands:/,$p' \
    | grep -oE '^  [a-z][a-z-]*(\|[a-z][a-z-]*)*' | tr -d ' ' | tr '|' '\n')
  if [ "$(printf '%s\n' "$words" | grep -c .)" -ge 10 ]; then
    mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null
    printf 'version %s\n%s\n' "$v" "$words" > "$CLAUDE_PLUGIN_DATA/claude-subcommands" 2>/dev/null
  fi
fi

# The status line and git's pre-push hook (guardrails-install-git-hooks) run
# from copies here, since the plugin's folder moves on update.
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA/git-hooks" 2>/dev/null
  for f in scripts/statusline.sh:statusline.sh git-hooks/pre-push:git-hooks/pre-push \
           scripts/undo-check.sh:git-hooks/undo-check.sh scripts/lib.sh:git-hooks/lib.sh; do
    cmp -s "$here/../${f%%:*}" "$CLAUDE_PLUGIN_DATA/${f#*:}" \
      || cp "$here/../${f%%:*}" "$CLAUDE_PLUGIN_DATA/${f#*:}" 2>/dev/null
  done
fi

while IFS= read -r r; do
  [ -n "$r" ] && [ -d "$r" ] || continue
  b=$(git -C "$r" branch --show-current 2>/dev/null)
  d=$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  main=$(git -C "$r" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$main" ]; then
    for c in origin/main origin/master main master; do
      git -C "$r" rev-parse -q --verify "$c" >/dev/null 2>&1 && { main=$c; break; }
    done
  fi
  echo "$(basename "$r"): ${b:-?} ($d uncommitted)"
  [ -n "$main" ] && git -C "$r" branch --no-merged "$main" \
    --format='  unmerged: %(refname:short) @ %(objectname:short) %(upstream:track) %(contents:subject)' \
    2>/dev/null | cut -c1-140 | head -8
done <<EOF
$("$C" repos "$dir")
EOF

project=$("$C" project "$dir")
if [ -n "$project" ]; then
  want=$("$C" get "$dir" ports | tr ' ' '\n' | grep -E '^[0-9]+$')
  if [ -n "$want" ]; then
    # shellcheck disable=SC2086
    listening=$(gr_listening $want | tr '\n' ' ')
    echo "dev servers listening: ${listening:-none}"
  fi
fi

# Which account the CLI spends against; `auth status` is local, no model call.
a=$(gr_timeout 5 claude auth status --json 2>/dev/null \
  | gr_jq -r 'select(.loggedIn == true) | "\(.email // "?") (\(.subscriptionType // .authMethod // "?"))"' 2>/dev/null)
[ -n "$a" ] && echo "claude account: $a"

# The effort level the session runs at. Claude Code gives CLAUDE_EFFORT to the
# shells it starts, but not (so far) to this hook; without it, the level the
# settings files give this model (local, then project, then user), which an
# /effort change made in the session does not reach. A top-level effortLevel
# is not used, since newer models ignore it: nothing is shown when unsure.
e=${CLAUDE_EFFORT:-}; how=
if [ -z "$e" ]; then
  how=" (as configured; an /effort change this session is not seen)"
  e=${CLAUDE_CODE_EFFORT_LEVEL:-}
fi
if [ -z "$e" ]; then
  m=$(gr_jq -r '.model | if type == "object" then .id else . end // empty' <<<"${input:-}" 2>/dev/null)
  m=${m%\[*\]}
  base=$(printf '%s' "$m" | sed -E 's/-[0-9]{8}$//')
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=$dir
  [ -n "$m" ] && for f in "$top/.claude/settings.local.json" "$top/.claude/settings.json" \
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -f "$f" ] || continue
    e=$(gr_jq -r --arg m "$m" --arg b "$base" \
      '(.modelSettings // {}) | (.[$m] // .[$b] // {}) | .effortLevel // empty' "$f" 2>/dev/null)
    [ -n "$e" ] && break
  done
fi
[ -n "$e" ] && echo "effort: $e$how"

while IFS= read -r t; do
  [ -n "$t" ] || continue
  n=$(git -C "$t" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && echo "agent setup: $t has $n uncommitted change(s) -- commit them (git is its only undo)"
done <<EOF
$("$C" get "$dir" watch_dirs)
EOF

p="$("$C" memory "$dir")/pending-improvements.md"
if [ -f "$p" ] && grep -q '^- ' "$p"; then
  echo "pending process fixes awaiting the user (memory/pending-improvements.md):"
  grep '^- ' "$p" | cut -c1-160 | head -8
fi

# Instruction files that load every session, against their word budgets
# (`words = <file> <max>`). Silent while each is under.
while IFS= read -r line; do
  f=${line% *}; max=${line##* }
  [ -f "$f" ] && [ -n "$max" ] || continue
  n=$(wc -w < "$f" | tr -d ' ')
  show=$f; [ "${f#"$HOME"/}" != "$f" ] && show="~/${f#"$HOME"/}"
  [ "$n" -gt "$max" ] && echo "instruction size: $show is $n words, over its $max budget -- prune it, or raise the budget on purpose (.claude/guardrails.conf)"
done <<EOF
$("$C" get "$dir" words)
EOF

if [ -n "$project" ]; then
  owed="$here/../bin/guardrails-owed-check"
  [ -x "$owed" ] && "$owed" "$dir" 2>/dev/null
  echo "Read-back before acting: check each status where it lives (git, the decision log, the backlog)."
fi
exit 0
