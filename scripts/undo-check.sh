#!/usr/bin/env bash
# undo-check.sh <repo> <remote> <commit> [<remote-commit>] [<base-branch>] --
# would pushing <commit> undo the default branch's recent work? Prints why,
# or nothing. <remote-commit> is what the destination branch holds now (empty
# for a new branch). <base-branch> is the branch to compare with (default:
# the remote's default branch, else main, else master). Exits 0 when it checked (finding
# or not), 2 when it could not (no fetched base branch, the commit unknown, no
# common history, git older than 2.37), anything else when it broke. Expects
# the remote fetched.
# Called by the push guard, by git's pre-push hook (git-hooks/pre-push), which
# sees a commit made in the same command as its push, and by the CI check
# (undo-check-ci.sh).
#
# A branch rebuilt from an older copy of the files puts them back as they were
# before something merged since, and git sees no conflict: a fix merged an
# hour ago is quietly deleted. Names a file the push changes that is now
# exactly as it was before a recent base-branch commit to it -- a deleted file
# the base branch added counts. Only exact matches, so an ordinary edit of the
# same file never matches; a file already on the remote branch as it is now
# was asked about at its first push. GUARDRAILS_UNDO_DAYS (default 14) is how
# far back a base-branch change still counts. The first 200 changed files are
# checked. The base's recent history is read once and every file version
# looked up in one batch, so a large push stays within a guard's time limit.
repo=$1; remote=$2; head=$3; pushed=${4:-}; def=${5:-}
export LC_ALL=C   # names are bytes: macOS's tr stops on one that is not UTF-8
g() { git -C "$repo" "$@" 2>/dev/null; }
# --since-as-filter came in git 2.37.
v=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
[ -n "$v" ] && { [ "${v%%.*}" -gt 2 ] || { [ "${v%%.*}" -eq 2 ] && [ "${v#*.}" -ge 37 ]; }; } || exit 2
if [ -z "$def" ]; then
  def=$(g symbolic-ref --short "refs/remotes/$remote/HEAD"); def=${def#"$remote"/}
  if [ -z "$def" ]; then
    for c in main master; do
      g rev-parse -q --verify "refs/remotes/$remote/$c" >/dev/null && { def=$c; break; }
    done
  fi
  def=${def:-main}
fi
base="refs/remotes/$remote/$def"
g rev-parse -q --verify "$base" >/dev/null || exit 2
head=$(g rev-parse -q --verify "$head^{commit}") || exit 2
# A remote commit this repo never fetched cannot be compared, so it counts as none.
[ -n "$pushed" ] && { pushed=$(g rev-parse -q --verify "$pushed^{commit}") || pushed=""; }
days=${GUARDRAILS_UNDO_DAYS:-14}
case "$days" in ''|*[!0-9]*) days=14 ;; esac
mb=$(g merge-base "$head" "$base") || exit 2

tmp=$(mktemp -d "${TMPDIR:-/tmp}/undo-check.XXXXXX") || exit 3
trap 'rm -rf "$tmp"' EXIT
# The files the push changes (names with a newline or a tab are not checked), and the
# base's recent first-parent commits with the files each touched, newest first.
# -z: unquoted names (git C-quotes a `"`, `\` or tab even with quotePath off).
g diff -z --name-only -M "$mb" "$head" > "$tmp/changed0" || exit 3
g log -z --first-parent --since-as-filter="$days.days" \
  --format='commit %H' --name-only "$mb" > "$tmp/log0" || exit 3
# A newline inside a changed name becomes a tab, so the name is skipped whole.
tr '\n\0' '\t\n' < "$tmp/changed0" > "$tmp/changed"; tr '\0' '\n' < "$tmp/log0" > "$tmp/log"
# Every version to look up: the file as pushed, as on the remote branch, and as
# it was before each recent commit to it (at most 50 a file).
awk -v head="$head" -v pushed="$pushed" -v lf="$tmp/log" -v tf="$tmp/total" '
  FILENAME == lf { if (/^commit /) c = substr($0, 8); else if ($0 != "" && n[$0] < 50) { n[$0]++; cs[$0] = cs[$0] " " c } next }
  $0 == "" || index($0, "\t") { next }
  ++total > 200 { next }
  { print "H\t" $0 "\t" head ":" $0
    if (pushed != "") print "P\t" $0 "\t" pushed ":" $0
    k = split(cs[$0], a, " ")
    for (i = 1; i <= k; i++) print "C\t" $0 "\t" a[i] "^1:" $0 "\t" a[i] }
  END { print total + 0 > tf }
' "$tmp/log" "$tmp/changed" > "$tmp/q" || exit 3
total=$(cat "$tmp/total")
cut -f3 "$tmp/q" | g cat-file --batch-check='%(objectname)' > "$tmp/ids" || exit 3
# For each file, the first (newest) commit whose parent held exactly what the
# push holds; the groups come out in the order their commits are first met.
found=$(paste "$tmp/q" "$tmp/ids" | awk -F'\t' '
  { id = $NF; if (id ~ / missing$/) id = "" }
  $1 == "H" { now[$2] = id; done[$2] = 0; next }
  $1 == "P" { if (id == now[$2]) done[$2] = 1; next }
  $1 == "C" && !done[$2] && id == now[$2] {
    done[$2] = 1
    name = "`" $2 "`" (id == "" ? " (deleted)" : "")
    if (!($4 in g)) { order[++n] = $4; g[$4] = name } else g[$4] = g[$4] ", " name }
  END { for (i = 1; i <= n; i++) print order[i] "\t" g[order[i]] }
') || exit 3
[ -n "$found" ] || exit 0
list=""; n=0
while IFS="$(printf '\t')" read -r c files; do
  n=$((n + 1))
  [ "$n" -le 3 ] && list="${list:+$list; }before \"$(g log -1 --format=%s "$c")\": $files"
done <<EOF
$found
EOF
[ "$n" -gt 3 ] && list="$list; and files from $((n - 3)) more commits"
[ "$total" -gt 200 ] && list="$list (checked the first 200 of $total changed files)"
echo "this push would undo work already on $def, putting files back as they were $list. A branch rebuilt from an older copy of the files reverts what merged since, with no conflict, and a rebase only replays the revert. If that is not meant, rebuild it from $remote/$def with only the branch's own changes (git rebase --onto $remote/$def <its original base>), then check that git diff --stat $remote/$def...HEAD lists only intended files"
