# test-undo.sh -- the undo check: a push that would put files back as they were
# before the default branch's recent work. In three places: the push guard
# (Claude's pushes), git's pre-push hook (every push, once installed), and CI.

ASK='"permissionDecision": *"ask"'
WINDOWS=; command -v cygpath >/dev/null 2>&1 && WINDOWS=1
BN="$GR_REPO/bin"
pg() { GR_HOOK=push-guard.sh runhook PreToolUse Bash "$(hookjson cwd="$1" tool_name=Bash tool_input.command="$2")"; }
pasks()   { o=$(pg "$1" "$2"); expect "push guard asks [$2]" "$ASK" "$o"; }
pallows() { o=$(pg "$1" "$2"); [ -z "$o" ] && ok || bad "push guard allows [$2] -- got $o"; }

# --- a remote, and a clone with merged, fresh and deleted branches
U="$GR_TMP/undo dir"; R="$U/remote.git"; P="$U/push repo"; mkdir -p "$U"
git init -q --bare "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
gp() { git -C "$P" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git clone -q "$R" "$P" 2>/dev/null; gp switch -qc main; gp commit -q --allow-empty -m init; gp push -q -u origin main
gp remote set-head origin main >/dev/null 2>&1
gp switch -qc merged; gp commit -q --allow-empty -m "merged work"; gp push -q -u origin merged
gp switch -q main; gp merge -q --no-ff merged -m "Merge PR"; gp push -q origin main
gp switch -q merged; gp commit -q --allow-empty -m "late commit"
gp switch -qc fresh main; gp push -q -u origin fresh; gp commit -q --allow-empty -m "new work"
gp switch -qc gone main; gp commit -q --allow-empty -m "w"; gp push -q -u origin gone; gp push -q origin --delete gone
gp switch -q merged
pasks   "$P" "git push"
pasks   "$P" "git push -q origin merged"
pasks   "$U" "cd \"$P\" && git push origin merged"
pasks   "$U" "git -C \"$P\" push -u origin merged"
pasks   "$P" "git push origin gone"
pallows "$P" "git push origin fresh"
pallows "$P" "git push -q origin main"
pallows "$P" "git push origin --delete merged"
pallows "$P" "echo 'git push origin merged'"
pallows "$P" "git status"
o=$(pg "$P" "git push origin merged"); expect "push guard reason" 'already merged into main' "$o"
o=$(pg "$P" "git push origin gone"); expect "push guard gone reason" 'no longer exists' "$o"

# --- undoing the default branch's work: a branch rebuilt from an older copy of
# the files puts them back as they were, and git sees no conflict
gp switch -q main; printf 'z\n' > "$P/z.txt"; gp add z.txt
old60="$(( $(date +%s) - 5184000 )) +0000"   # 60 days ago, without GNU date
GIT_AUTHOR_DATE="$old60" GIT_COMMITTER_DATE="$old60" gp commit -q -m "an old file"
printf 'y1\n' > "$P/y.txt"; gp add y.txt; gp commit -q -m "base files"; old=$(git -C "$P" rev-parse HEAD)
printf 'x\n' > "$P/x.txt"; printf 'y2\n' > "$P/y.txt"; gp add x.txt y.txt; gp commit -q -m "fix: add x, change y"; gp push -q origin main
gp switch -qc rebuilt main; gp rm -q x.txt; gp checkout -q "$old" -- y.txt; printf 'd\n' > "$P/doc.md"; gp add doc.md; gp commit -q -m "docs, from an old copy"
gp switch -qc dropx main; gp rm -q x.txt; gp commit -q -m "drop x"
gp switch -qc rebased main; printf 'd\n' > "$P/doc2.md"; gp add doc2.md; gp commit -q -m "docs, rebased"
gp switch -qc sameedit main; printf 'y3\n' > "$P/y.txt"; gp commit -q -am "change y again"
gp switch -qc oldfile main; gp rm -q z.txt; gp commit -q -m "remove a file main made long ago"
gp switch -q main
o=$(pg "$P" "git push -u origin rebuilt"); expect "push guard asks before undoing main" "$ASK" "$o"
expect "push guard names the file and what it undoes" 'before \\"fix: add x, change y\\": `x\.txt` \(deleted\)' "$o"
expect "push guard's advice is not a plain rebase" 'git rebase --onto origin/main' "$o"
expect "push guard names the changed file too" 'y\.txt' "$o"
expect "push guard names the git hook it lacks" 'guardrails-install-git-hooks' "$o"
pasks   "$P" "git push -u origin dropx"
pallows "$P" "git push -u origin rebased"
gp switch -qc oldbase "$old"; printf 'n\n' > "$P/new.txt"; gp add new.txt; gp commit -q -m "work from an old base, never rebased"; gp switch -q main
pallows "$P" "git push -u origin oldbase"
pasks   "$P" "git push origin rebuilt:other-name"
gp switch -q dropx; pasks "$P" "git push"; gp push -q -u origin dropx 2>/dev/null
gp commit -q --allow-empty -m "a review fix"; pallows "$P" "git push"; gp switch -q main
pallows "$P" "git push -u origin sameedit"
o=$(pg "$P" "git push -u origin oldfile"); [ -z "$o" ] && ok || bad "push guard allows removing a file older than its window -- got $o"
o=$(GUARDRAILS_UNDO_DAYS=90 pg "$P" "git push -u origin oldfile"); expect "GUARDRAILS_UNDO_DAYS widens the window" "$ASK" "$o"
gp switch -q main; gp rm -q x.txt; gp commit -q -m "drop x on main"; pasks "$P" "git push origin main"; gp reset -q --hard origin/main
# a file name git C-quotes (a double quote, a backslash) is compared by its
# real name: a new edit is not an undo, putting the old copy back still is; a
# name with a tab or a newline is skipped (not on Windows, where such names
# cannot exist)
if [ -z "$WINDOWS" ]; then
  QR="$U/quoted.git"; QP="$U/quoted repo"; git init -q --bare "$QR"; git -C "$QR" symbolic-ref HEAD refs/heads/main
  git clone -q "$QR" "$QP" 2>/dev/null
  qg() { git -C "$QP" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
  TB="$(printf 'tab\tname.txt')"; NL="$(printf 'line\nname.txt')"
  qg switch -qc main; for f in "say \"hi\".txt" "$TB" "$NL"; do printf 'a\n' > "$QP/$f"; done; qg add .; qg commit -qm base; qg push -q -u origin main
  for f in "say \"hi\".txt" "$TB" "$NL"; do printf 'b\n' > "$QP/$f"; done; qg commit -qam "main edits the quoted files"; qg push -q origin main
  qg switch -qc qedit main; for f in "say \"hi\".txt" "$TB" "$NL"; do printf 'c\n' > "$QP/$f"; done; qg commit -qam "a new edit"
  qg switch -qc qback main; qg checkout -q HEAD^ -- "say \"hi\".txt"; qg commit -qm "put the old copy back"
  o=$(bash "$GR_REPO/scripts/undo-check.sh" "$QP" origin qedit "" main 2>&1); st=$?
  # names are read as bytes: macOS's tr stops on one that is not UTF-8 outside
  # the C locale, and the check would go on with its list cut short
  LT="$U/locale tr"; mkdir -p "$LT"; printf '#!/bin/sh\necho "$LC_ALL" >> "%s/seen"\nexec "%s" "$@"\n' "$LT" "$(command -v tr)" > "$LT/tr"; chmod +x "$LT/tr"
  LANG=en_US.UTF-8 LC_ALL= PATH="$LT:$PATH" bash "$GR_REPO/scripts/undo-check.sh" "$QP" origin qedit "" main >/dev/null 2>&1
  [ "$(sort -u "$LT/seen" 2>/dev/null)" = C ] && ok || bad "undo-check runs tr in the C locale -- saw [$(sort -u "$LT/seen" 2>/dev/null)]"
  [ "$st" = 0 ] && [ -z "$o" ] && ok || bad "a new edit of a quoted file name is not an undo -- got $st [$o]"
  o=$(bash "$GR_REPO/scripts/undo-check.sh" "$QP" origin qback "" main 2>&1)
  expect "putting a quoted file name back as it was is an undo" 'say "hi"\.txt' "$o"
  refuse "a quoted file put back is not called deleted" 'deleted' "$o"
fi
# a repo on `master` with no origin/HEAD (made with git init and pushed, never
# cloned; git before 2.48 never sets it on fetch): the check still finds master
MR="$U/master remote.git"; MP="$U/master repo"; git init -q --bare "$MR"; git init -q "$MP"
mg() { git -C "$MP" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
mg symbolic-ref HEAD refs/heads/master; mg commit -q --allow-empty -m init
mg remote add origin "$MR"; mg config remote.origin.followRemoteHEAD never; mg push -q -u origin master
printf 'm\n' > "$MP/m.txt"; mg add m.txt; mg commit -qm "fix: add m"; mg push -q origin master
mg switch -qc mdrop master; mg rm -q m.txt; mg commit -qm "drop m"
mg symbolic-ref -q refs/remotes/origin/HEAD >/dev/null && bad "the master repo has no origin/HEAD (test setup)" || ok
o=$(bash "$GR_REPO/scripts/undo-check.sh" "$MP" origin mdrop 2>&1)
expect "the undo check falls back to master" '`m\.txt` \(deleted\)' "$o"
o=$(pg "$MP" "git push -u origin mdrop"); expect "push guard checks a master repo with no origin/HEAD" 'm\.txt' "$o"
# a push behind a wrapper is read too
pasks   "$P" "FOO=1 git push origin merged"
pasks   "$P" "git -c color.ui=never push origin merged"
pasks   "$P" "timeout 60 git push origin merged </dev/null 2>&1 | tail -1"
pasks   "$P" "git --no-pager push origin merged"
pasks   "$P" "env git push origin merged"
pasks   "$P" "command git push origin merged"
# the 200-file cap: the first 200 changed files are checked, and the reason says so
gp switch -qc many main; gp rm -q x.txt; i=0
while [ $i -lt 205 ]; do printf '%s\n' $i > "$P/z$i.txt"; i=$((i + 1)); done
gp add . >/dev/null; gp commit -q -m "many files"; gp switch -q main
o=$(pg "$P" "git push -u origin many"); expect "the undo check names the cap" 'checked the first 200 of 206 changed files' "$o"
# a check that runs past its time says so instead of hanging the guard
SLOW="$GR_TMP/slow plugin"; mkdir -p "$SLOW"; (cd "$GR_REPO" && tar cf - --exclude .git --exclude .superpowers .) | (cd "$SLOW" && tar xf -)
printf '#!/bin/sh\nsleep 5\n' > "$SLOW/scripts/undo-check.sh"
if timeout --version 2>/dev/null | grep -q coreutils || command -v gtimeout >/dev/null 2>&1; then
  o=$(GR_PLUGIN_SRC="$SLOW" GUARDRAILS_UNDO_SECONDS=1 pg "$P" "git push -u origin rebased")
  expect "a slow undo check says it was not checked in time" 'not checked in time' "$o"
else
  echo "skip: no GNU timeout here, so the guard's time budget is not tested"
fi

# --- git's pre-push hook: runs inside `git push`, so it sees a commit made in the
# same command; installed as a small stub running a copy in the plugin's data folder
D="$GR_TMP/hook data"
gpush() { (cd "$P" && "$@" 2>&1); }
onremote() { git -C "$R" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
o=$(cd "$P" && env -u CLAUDE_PLUGIN_DATA "$BN/guardrails-install-git-hooks" 2>&1); st=$?
[ "$st" -ne 0 ] && ok || bad "installer with no data folder refuses -- got $o"
expect "installer says to pass --data" '\-\-data' "$o"
o=$("$BN/guardrails-install-git-hooks" --data "$D" "$P" 2>&1); expect "installer installs the hook" 'installed' "$o"
[ -f "$D/git-hooks/pre-push" ] && [ -f "$D/git-hooks/undo-check.sh" ] && [ -f "$D/git-hooks/lib.sh" ] && ok || bad "installer copies the check into the data folder"
hp="$P/.git/hooks/pre-push"
[ -f "$hp" ] && [ ! -L "$hp" ] && grep -q 'guardrails-undo-check-stub' "$hp" && ok || bad "installer writes a stub, not a link"
o=$("$BN/guardrails-install-git-hooks" --data "$D" "$P" 2>&1); expect "installer run twice changes nothing" 'already installed' "$o"
NB="$GR_TMP/no bash"; mkdir -p "$NB"
o=$(cd "$P" && env PATH="$NB" /bin/sh "$hp" origin "$R" </dev/null 2>&1); st=$?
[ "$st" = 0 ] && ok || bad "the stub lets the push through when bash is missing -- got $st: $o"
expect "the stub says bash is missing" 'bash not found' "$o"
Q="$U/own hook"; git init -q "$Q"; printf '#!/bin/sh\nexit 0 # own\n' > "$Q/.git/hooks/pre-push"; chmod +x "$Q/.git/hooks/pre-push"
o=$("$BN/guardrails-install-git-hooks" --data "$D" "$Q" 2>&1); st=$?
[ "$st" -ne 0 ] && ok || bad "installer refuses a repo with its own pre-push hook"
expect "installer names the hook it kept" 'already has its own' "$o"
grep -q '# own' "$Q/.git/hooks/pre-push" && ok || bad "installer kept the repo's own hook"
H3="$U/husky"; git init -q "$H3"; git -C "$H3" config core.hooksPath .husky
o=$("$BN/guardrails-install-git-hooks" --data "$D" "$H3" 2>&1); st=$?
[ "$st" -ne 0 ] && [ ! -e "$H3/.husky/pre-push" ] && ok || bad "installer refuses a hooks folder inside the repo -- got $o"
H4="$U/global hooks"; git init -q "$H4"; GH="$GR_TMP/gitconfig-global"; printf '[core]\n\thooksPath = %s\n' "$U/shared hooks" > "$GH"
o=$(GIT_CONFIG_GLOBAL="$GH" "$BN/guardrails-install-git-hooks" --data "$D" "$H4" 2>&1); st=$?
[ "$st" -ne 0 ] && [ ! -e "$U/shared hooks/pre-push" ] && ok || bad "installer refuses a hooks folder every repo shares -- got $o"
expect "installer says the folder is shared" 'every repo' "$o"
o=$("$BN/guardrails-install-git-hooks" --data "$D" "$U/not a repo" 2>&1); st=$?
[ "$st" -ne 0 ] && ok || bad "installer fails on a folder that is not a repo"
gp switch -qc oneliner main; gp rm -q x.txt
o=$(gpush git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "drop x, one line" && gpush git push -q -u origin oneliner); st=$?
[ "$st" -ne 0 ] && ok || bad "pre-push refuses a one-liner commit and push that undoes main -- got $o"
onremote oneliner && bad "a refused push reached the remote" || ok
expect "pre-push names what it undoes" 'before "fix: add x, change y": `x\.txt` \(deleted\)' "$o"
expect "pre-push names the branch" "'oneliner'" "$o"
expect "pre-push names the override" 'GUARDRAILS_ALLOW_UNDO=1' "$o"
o=$(gpush env GUARDRAILS_ALLOW_UNDO=1 git push -q -u origin oneliner); st=$?
[ "$st" -eq 0 ] && onremote oneliner && ok || bad "the override lets a meant undo through -- got $o"
gp commit -q --allow-empty -m "after the override"
o=$(gpush git push -q origin oneliner); [ $? -eq 0 ] && ok || bad "a file already on the remote branch is not refused again -- got $o"
o=$(gpush git push -q -u origin rebased); [ $? -eq 0 ] && ok || bad "pre-push lets an ordinary push through -- got $o"
o=$(gpush git push -q -u origin oldbase); [ $? -eq 0 ] && ok || bad "pre-push lets an old base with no undo through -- got $o"
o=$(gpush git push -q origin sameedit rebuilt); st=$?
[ "$st" -ne 0 ] && ok || bad "pre-push refuses a push of several branches when one undoes main"
expect "pre-push names which branch" "'rebuilt'" "$o"
o=$(gpush git push -q origin --delete dropx); [ $? -eq 0 ] && ok || bad "pre-push lets a branch delete through -- got $o"
gp tag t-rebuilt rebuilt; o=$(gpush git push -q origin t-rebuilt); [ $? -eq 0 ] && ok || bad "pre-push lets a tag through -- got $o"
# the guard leaves the undo check to git where the hook is installed (else it would
# ask, and git refuse after the yes); it asks when a push skips or overrides it
gp switch -q main
pallows "$P" "git push -u origin rebuilt"
pallows "$P" "git push -u origin sameedit"
pasks   "$P" "GUARDRAILS_ALLOW_UNDO=1 git push -u origin rebuilt"
pasks   "$P" "export GUARDRAILS_ALLOW_UNDO=1; git push -u origin sameedit"
pasks   "$P" "GUARDRAILS_UNDO_DAYS=0 git commit -qam x && git push -u origin sameedit"
pasks   "$P" "export GUARDRAILS_UNDO_DAYS=0; git push -u origin sameedit"
pasks   "$P" "git push --no-verify -u origin sameedit"
pasks   "$P" "git -c core.hooksPath=/dev/null push -u origin sameedit"
o=$(pg "$P" "git push --no-verify -u origin sameedit"); expect "push guard says why it asks on --no-verify" 'skips' "$o"
# ...in every spelling git accepts, and wherever in the command it sits
pasks   "$P" "GUARDRAILS_ALLOW_UNDO=1 timeout 60 git push -u origin rebuilt </dev/null 2>&1 | tail -1"
pasks   "$U" "cd \"$P\" && GUARDRAILS_ALLOW_UNDO=1 timeout 60 git push -u origin rebuilt"
pasks   "$P" "timeout 60 env GUARDRAILS_ALLOW_UNDO=1 git push -u origin rebuilt"
pasks   "$P" "(git push --no-verify -u origin sameedit)"
pasks   "$P" "command git push --no-verify -u origin sameedit"
pasks   "$P" "git --no-pager push --no-verify -u origin sameedit"
pasks   "$P" "git push --no-verif -u origin sameedit"
pasks   "$P" "git -c core.hookspath=/dev/null push -u origin sameedit"
pasks   "$P" "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hookspath GIT_CONFIG_VALUE_0=/dev/null git push -u origin sameedit"
pasks   "$U" "cd \"$P\" && git push --no-verify -u origin sameedit"
pasks   "$P" "git push --no-verify --tags origin sameedit"
pasks   "$P" "git push --no-verify origin main"
pasks   "$P" "(git push -u origin sameedit --no-verify)"
pasks   "$P" "git push -u origin sameedit --no-verify;echo"
pasks   "$P" "git push -u origin sameedit \"--no-verify\""
pasks   "$P" "git push -u origin sameedit '--no-verify'"
pasks   "$P" "git push -u origin sameedit --no-verify&& echo ok"
pasks   "$P" "git push -u origin sameedit --no-verify>out"
# a commit message naming --no-verify asks too (a false match costs one ask)
pasks   "$P" "git commit -qm \"Ask on \`--no-verify\`\" && git push -u origin sameedit"
pasks   "$P" "git push -u origin sameedit --no-verify</dev/null"
# ...and the ask shows what the override lets through
o=$(pg "$P" "GUARDRAILS_ALLOW_UNDO=1 git push -u origin rebuilt"); expect "the override's ask names what it undoes" 'What it lets through: .*x\.txt' "$o"
# a mention in a commit message is not a setting
pallows "$P" "git commit -m 'note GUARDRAILS_ALLOW_UNDO docs' && git push origin sameedit"
pallows "$P" "git commit -m 'core.hooksPath explained' && git push origin sameedit"
# the stub without its copy is not installed: the guard checks itself, and git
# lets the push through with a warning rather than refuse every push
mv "$D/git-hooks/pre-push" "$D/pre-push.away"
pasks "$P" "git push -u origin rebuilt"
gp switch -qc nocopy main; gp commit -q --allow-empty -m "pushed while the copy is gone"
o=$(gpush git push -q -u origin nocopy); [ $? -eq 0 ] && onremote nocopy && ok || bad "a missing copy lets the push through -- got $o"
expect "a missing copy warns" 'undo check is missing' "$o"
gp switch -q main; mv "$D/pre-push.away" "$D/git-hooks/pre-push"
# a push by URL is checked against the remote with that URL; one no remote has warns
o=$(gpush git push -q "$R" rebuilt:refs/heads/byurl); st=$?
[ "$st" -ne 0 ] && ok || bad "pre-push refuses an undo pushed by its remote's URL -- got $o"
R2="$U/other.git"; git init -q --bare "$R2"
o=$(gpush git push -q "$R2" rebuilt:refs/heads/byurl); [ $? -eq 0 ] && ok || bad "a push to an unknown URL goes through -- got $o"
expect "a push to an unknown URL warns" 'no remote here has' "$o"
# a remote with no fetched default branch cannot be checked: it warns
gp remote add other "$R2"
o=$(gpush git push -q other rebuilt); [ $? -eq 0 ] && ok || bad "an uncheckable push goes through -- got $o"
expect "an uncheckable push warns" 'could not run' "$o"
# the installer with no repos named: the current repo and its partners, each once
I1r="$U/inst one"; I2r="$U/inst two"; mkrepo "$I1r"; mkrepo "$I2r"; mkdir -p "$I1r/.claude" "$I2r/.claude"
echo 'partners = ../inst two' > "$I1r/.claude/guardrails.conf"; echo 'partners = ../inst one' > "$I2r/.claude/guardrails.conf"
o=$(cd "$I1r" && "$BN/guardrails-install-git-hooks" --data "$D" 2>&1)
[ "$(grep -c 'installed (' <<<"$o")" = 2 ] && [ -f "$I1r/.git/hooks/pre-push" ] && [ -f "$I2r/.git/hooks/pre-push" ] && ok || bad "installer installs the repo and its partners once each -- got $o"
o=$(cd "$U" && "$BN/guardrails-install-git-hooks" --data "$D" 2>&1); st=$?
[ "$st" -ne 0 ] && ok || bad "installer with no repo found fails -- got $o"
# --remove takes out only its own stub
o=$("$BN/guardrails-install-git-hooks" --remove "$I1r" "$Q" 2>&1)
[ ! -e "$I1r/.git/hooks/pre-push" ] && grep -q '# own' "$Q/.git/hooks/pre-push" && ok || bad "--remove takes out only its own stub -- got $o"
# the installer finds the data folder from where Claude Code keeps the plugin
CC="$GR_TMP/cc home/plugins"; PV="$CC/cache/mkt/guardrails/0.1.0"; mkdir -p "$PV"
(cd "$GR_REPO" && tar cf - --exclude .git --exclude .superpowers .) | (cd "$PV" && tar xf -)
o=$(env -u CLAUDE_PLUGIN_DATA "$PV/bin/guardrails-install-git-hooks" "$I2r" 2>&1); st=$?
[ "$st" -ne 0 ] && [ ! -e "$CC/data/guardrails-mkt" ] && ok || bad "installer refuses a guessed data folder that does not exist yet -- got $st: $o"
expect "installer says how to fix a guessed folder" 'start a Claude Code session first, or pass --data' "$o"
mkdir -p "$CC/data/guardrails-mkt"
o=$(env -u CLAUDE_PLUGIN_DATA "$PV/bin/guardrails-install-git-hooks" "$I2r" 2>&1)
[ -f "$CC/data/guardrails-mkt/git-hooks/pre-push" ] && grep -qF "$CC/data/guardrails-mkt/git-hooks/pre-push" "$I2r/.git/hooks/pre-push" \
  && ok || bad "installer derives the data folder from the plugin's path -- got $o"
# a check that breaks lets the push through with a warning, so a bug cannot block every push
cp "$D/git-hooks/undo-check.sh" "$D/undo.away"; printf '#!/bin/sh\nexit 3\n' > "$D/git-hooks/undo-check.sh"
o=$(gpush git push -q -u origin rebuilt); [ $? -eq 0 ] && ok || bad "a broken check lets the push through -- got $o"
expect "a broken check warns" 'check failed' "$o"
cp "$D/undo.away" "$D/git-hooks/undo-check.sh"
# plain Windows: the installer given Windows paths writes a stub that still runs
if [ -n "$WINDOWS" ]; then
  WR="$U/win repo"; git clone -q "$R" "$WR" 2>/dev/null
  o=$("$BN/guardrails-install-git-hooks" --data "$(cygpath -w "$D")" "$(cygpath -w "$WR")" 2>&1)
  expect "installer takes Windows paths" 'installed' "$o"
  git -C "$WR" -c user.name=t -c user.email=t@t switch -qc wdrop origin/main && git -C "$WR" -c user.name=t -c user.email=t@t rm -q x.txt \
    && git -C "$WR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "drop x"
  o=$(cd "$WR" && git push -q -u origin wdrop 2>&1); [ $? -ne 0 ] && ok || bad "the stub runs on plain Windows paths -- got $o"
fi

# --- the session status keeps the copy the stub runs fresh
rm -rf "$GR_TMP/plugin data/git-hooks"
runhook SessionStart startup "$(hookjson cwd="$P" source=startup)" >/dev/null 2>&1
cmp -s "$GR_TMP/plugin data/git-hooks/undo-check.sh" "$GR_REPO/scripts/undo-check.sh" \
  && cmp -s "$GR_TMP/plugin data/git-hooks/pre-push" "$GR_REPO/git-hooks/pre-push" \
  && cmp -s "$GR_TMP/plugin data/git-hooks/lib.sh" "$GR_REPO/scripts/lib.sh" \
  && ok || bad "session status copies the git hook's files into the data folder"

# --- in CI: every pull request, checked out the way actions/checkout does it
# (init, remote add, fetch; no origin/HEAD; HEAD the merge commit), here with
# a `master` default branch
CR="$GR_TMP/ci remote.git"; CW="$GR_TMP/ci work"; git init -q --bare "$CR"; git -C "$CR" symbolic-ref HEAD refs/heads/master
git clone -q "$CR" "$CW" 2>/dev/null
cg() { git -C "$CW" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
cg switch -qc master; printf 'a\n' > "$CW/a.txt"; cg add a.txt; cg commit -qm base; cbase=$(git -C "$CW" rev-parse HEAD)
printf 'fix\n' > "$CW/fix.txt"; printf 'a2\n' > "$CW/a.txt"; cg add fix.txt a.txt; cg commit -qm "fix: add fix.txt"; cg push -q -u origin master
cg switch -qc undo master; cg rm -q fix.txt; cg checkout -q "$cbase" -- a.txt; printf 'd\n' > "$CW/doc.md"; cg add doc.md; cg commit -qm "docs, from an old copy"
cg switch -qc clean master; printf 'd\n' > "$CW/doc2.md"; cg add doc2.md; cg commit -qm "docs"
for b in undo clean; do   # the merge commit GitHub makes for each pull request
  cg switch -q --detach master; cg merge -q --no-ff "$b" -m "Merge $b into master"
  cg push -q origin "HEAD:refs/pull/$b/merge"; cg push -q origin "$b"
done
ci() {  # ci BRANCH [LABEL] [BASE]: the CI check as a pull request of BRANCH sees it
  local w="$GR_TMP/ci checkout $1" e="$GR_TMP/ci event $1.json"
  rm -rf "$w"; git init -q "$w"; git -C "$w" remote add origin "$CR"
  git -C "$w" fetch -q origin '+refs/heads/*:refs/remotes/origin/*' "+refs/pull/$1/merge:refs/remotes/pull/$1/merge"
  git -C "$w" checkout -q --detach "refs/remotes/pull/$1/merge"
  jq -n --arg h "$(git -C "$CW" rev-parse "$1")" --arg b "${3:-master}" --arg l "${2:-}" \
    '{pull_request: {head: {sha: $h}, base: {ref: $b}, labels: (if $l == "" then [] else [{name: $l}] end)}}' > "$e"
  (cd "$w" && GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=${3:-master} GITHUB_EVENT_PATH="$e" bash "$GR_REPO/scripts/undo-check-ci.sh" 2>&1)
}
o=$(ci undo); st=$?
[ "$st" = 1 ] && ok || bad "CI fails a pull request that undoes the base branch -- got $st: $o"
expect "CI prints an error annotation naming the file" '^::error title=Undo check::this push would undo work already on master.*`fix\.txt` \(deleted\)' "$o"
o=$(ci clean); st=$?
[ "$st" = 0 ] && ok || bad "CI passes a clean pull request -- got $st: $o"
refuse "CI prints no error for a clean pull request" '::error' "$o"
o=$(ci undo undo-ok); st=$?
[ "$st" = 0 ] && ok || bad "CI passes an undo labelled undo-ok -- got $st: $o"
expect "CI's notice names what the label let through" '^::notice title=Undo check::.*undo-ok.*fix\.txt' "$o"
o=$(ci undo "" release); st=$?
[ "$st" = 0 ] && ok || bad "CI with a base branch not fetched lets the pull request through -- got $st: $o"
expect "CI says it could not check" '^::notice title=Undo check::.*could not' "$o"
o=$(cd "$CW" && GITHUB_EVENT_NAME=push bash "$GR_REPO/scripts/undo-check-ci.sh" 2>&1); st=$?
[ "$st" = 0 ] && ok || bad "CI on a push event exits 0 -- got $st"
expect "CI on a push event says there is nothing to check" '^::notice title=Undo check::.*not a pull request' "$o"

# --- the workflow a project copies, and the plugin's own CI
WF="$GR_REPO/examples/workflows/undo-check.yml"
o=$(cat "$WF" 2>/dev/null)
expect "the example workflow runs the CI script" 'bash \.guardrails/scripts/undo-check-ci\.sh' "$o"
expect "the example runs on pull requests, labels included" 'types: \[opened, synchronize, reopened, labeled, unlabeled\]' "$o"
expect "the example only reads the repo" 'contents: read' "$o"
expect "the example fetches the whole history" 'fetch-depth: 0' "$o"
want="v$(jq -r .version "$GR_REPO/.claude-plugin/plugin.json" 2>/dev/null)"
o2=$(grep -E '^[[:space:]]+ref:' "$WF" 2>/dev/null | awk '{print $2}')
[ "$o2" = "$want" ] && ok || bad "the example pins the plugin at this version's tag ($want) -- got [$o2]"
for f in "$WF" "$GR_REPO"/.github/workflows/*.yml; do
  o=$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$f" 2>/dev/null | grep -vE 'uses: [^@ ]+@[0-9a-f]{40}( |$)')
  refuse "every action in ${f#"$GR_REPO"/} is pinned by commit" '.' "$o"
  expect "${f#"$GR_REPO"/} only reads the repo" '^permissions:' "$(cat "$f" 2>/dev/null)"
done
expect "the plugin's own CI runs the undo check on pull requests" 'bash scripts/undo-check-ci\.sh' "$(cat "$GR_REPO"/.github/workflows/*.yml)"
o=$(cat "$GR_REPO/.github/workflows/test.yml" 2>/dev/null)
refuse "a label on a pull request does not re-run the test matrix" 'labeled' "$o"
expect "a push runs the test matrix only on main (a pull request runs it for branches)" 'push:[[:space:]]+branches: \[main\]' "$(tr '\n' ' ' <<<"$o")"
expect "the plugin's CI validates as the README does" 'claude plugin validate --strict \.' "$o"
expect "the plugin's undo check re-runs on a label" 'labeled, unlabeled' "$(cat "$GR_REPO/.github/workflows/undo-check.yml" 2>/dev/null)"
refuse "the example names the check as GitHub lists it" 'make "undo check" a required' "$(cat "$WF")"
if command -v ruby >/dev/null 2>&1; then
  for f in "$WF" "$GR_REPO"/.github/workflows/*.yml; do
    exits "${f#"$GR_REPO"/} parses as YAML" 0 ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f"
  done
else
  echo "skip: no ruby here, so the workflows are not parsed as YAML (GitHub's runners have it)"
fi
