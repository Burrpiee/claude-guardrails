# test-setup.sh -- guardrails-write-block, the setup skill and its blocks.

WB="$GR_REPO/bin/guardrails-write-block"
SU="$GR_REPO/skills/setup"
W="$GR_TMP/blocks"; mkdir -p "$W"
sum() { cksum < "$1" | cut -d' ' -f1-2; }
printf '%s\n' '<!-- guardrails:demo v1 -->' '## Demo' 'Line one.' > "$W/demo1.md"
printf '%s\n' '<!-- guardrails:demo v1 -->' '## Demo' 'Line one, changed.' > "$W/demo2.md"
printf '%s\n' '<!-- guardrails:demo v2 -->' '## Demo' 'Line one, changed.' > "$W/demo3.md"

# a new file gets the block
T="$GR_TMP/new dir/CLAUDE.md"; mkdir -p "$GR_TMP/new dir"
o=$("$WB" "$W/demo1.md" "$T"); [ "$o" = added ] && ok || bad "write-block new file -- got [$o]"
[ "$(cat "$T" 2>/dev/null)" = "$(printf '%s\n' '<!-- guardrails:demo v1 -->' '## Demo' 'Line one.' '<!-- /guardrails:demo -->')" ] && ok || bad "write-block wraps the block -- got [$(cat "$T" 2>/dev/null)]"
# the same block again changes nothing
s1=$(sum "$T"); o=$("$WB" "$W/demo1.md" "$T"); [ "$o" = unchanged ] && ok || bad "write-block same block -- got [$o]"
[ "$(sum "$T")" = "$s1" ] && ok || bad "write-block unchanged leaves the file byte-identical"

# around existing text: appended after one blank line, then replaced in place
T2="$GR_TMP/existing.md"; printf '%s\n' '# My project' '' 'Some rules.' > "$T2"
o=$("$WB" "$W/demo1.md" "$T2"); [ "$o" = added ] && ok || bad "write-block appends -- got [$o]"
[ "$(sed -n 3,5p "$T2")" = "$(printf '%s\n' 'Some rules.' '' '<!-- guardrails:demo v1 -->')" ] && ok || bad "write-block appends after one blank line -- got [$(cat "$T2")]"
printf '%s\n' '' '## After' 'Kept.' >> "$T2"
o=$("$WB" "$W/demo2.md" "$T2"); [ "$o" = updated ] && ok || bad "write-block changed text -- got [$o]"
[ "$(grep -c '^<!-- guardrails:demo ' "$T2")" = 1 ] && ok || bad "write-block keeps one marker"
expect "write-block has the new text" '^Line one, changed\.$' "$(cat "$T2")"
refuse "write-block drops the old text" '^Line one\.$' "$(cat "$T2")"
[ "$(head -3 "$T2")" = "$(printf '%s\n' '# My project' '' 'Some rules.')" ] && ok || bad "write-block keeps the text before"
[ "$(tail -3 "$T2")" = "$(printf '%s\n' '' '## After' 'Kept.')" ] && ok || bad "write-block keeps the text after -- got [$(tail -3 "$T2")]"
o=$("$WB" "$W/demo3.md" "$T2"); [ "$o" = updated ] && ok || bad "write-block version-only change -- got [$o]"
expect "write-block writes the new version" '^<!-- guardrails:demo v2 -->$' "$(cat "$T2")"
[ "$(grep -c '^<!-- guardrails:demo ' "$T2")" = 1 ] && ok || bad "write-block keeps one marker after a version change"

# a CRLF file stays CRLF
T3="$GR_TMP/crlf.md"; printf '# Win\r\n\r\nRules.\r\n' > "$T3"
"$WB" "$W/demo1.md" "$T3" >/dev/null; "$WB" "$W/demo2.md" "$T3" >/dev/null
n_lines=$(wc -l < "$T3" | tr -d ' '); n_crlf=$(tr -cd '\r' < "$T3" | wc -c | tr -d ' ')
[ "$n_lines" = "$n_crlf" ] && ok || bad "write-block keeps CRLF -- $n_crlf of $n_lines lines: $(od -c "$T3" | head -12)"
# ...even where grep drops a line's CR before matching (as a Windows grep may)
NG="$GR_TMP/crstrip grep"; mkdir -p "$NG"; RG=$(command -v grep)
printf '#!/bin/sh\nfor f; do :; done\nif [ -f "$f" ] && [ $# -gt 1 ]; then n=$#; i=0; for a; do i=$((i+1)); [ $i -lt $n ] && set -- "$@" "$a"; done; shift $n; tr -d "\\r" < "$f" | "%s" "$@"; else exec "%s" "$@"; fi\n' "$RG" "$RG" > "$NG/grep"; chmod +x "$NG/grep"
T4="$GR_TMP/crlf2.md"; printf '# Win\r\n\r\nRules.\r\n' > "$T4"
PATH="$NG:$PATH" "$WB" "$W/demo1.md" "$T4" >/dev/null
n_lines=$(wc -l < "$T4" | tr -d ' '); n_crlf=$(tr -cd '\r' < "$T4" | wc -c | tr -d ' ')
[ "$n_lines" = "$n_crlf" ] && ok || bad "write-block keeps CRLF where grep drops the CR -- $n_crlf of $n_lines lines"
# ...and where awk drops it on reading a line (as Git Bash's awk does): the
# lines outside the block keep theirs when the block is updated
NA="$GR_TMP/crstrip awk"; mkdir -p "$NA"; RA=$(command -v awk)
printf '#!/bin/sh\nfor f; do :; done\nif [ -f "$f" ] && [ $# -gt 1 ]; then n=$#; i=0; for a; do i=$((i+1)); [ $i -lt $n ] && set -- "$@" "$a"; done; shift $n; tr -d "\\r" < "$f" | "%s" "$@" -; else tr -d "\\r" | "%s" "$@"; fi\n' "$RA" "$RA" > "$NA/awk"; chmod +x "$NA/awk"
T5="$GR_TMP/crlf3.md"; printf '# Win\r\n\r\nRules.\r\n' > "$T5"
PATH="$NA:$PATH" "$WB" "$W/demo1.md" "$T5" >/dev/null; PATH="$NA:$PATH" "$WB" "$W/demo2.md" "$T5" >/dev/null
n_lines=$(wc -l < "$T5" | tr -d ' '); n_crlf=$(tr -cd '\r' < "$T5" | wc -c | tr -d ' ')
[ "$n_lines" = "$n_crlf" ] && ok || bad "write-block keeps CRLF where awk drops the CR -- $n_crlf of $n_lines lines"
o=$("$WB" "$W/demo2.md" "$T3"); [ "$o" = unchanged ] && ok || bad "write-block unchanged on CRLF -- got [$o]"
# ...and when the block is removed again
PATH="$NA:$PATH" "$WB" --remove demo "$T5" >/dev/null
n_lines=$(wc -l < "$T5" | tr -d ' '); n_crlf=$(tr -cd '\r' < "$T5" | wc -c | tr -d ' ')
[ "$n_lines" = "$n_crlf" ] && ok || bad "write-block --remove keeps CRLF where awk drops the CR -- $n_crlf of $n_lines lines"
# a mostly-LF file with one pasted CRLF line is not a CRLF file: the text
# outside the block stays byte-identical, through an update and a removal
T7="$GR_TMP/mixed.md"; printf '# Mixed\n\nPasted.\r\nRules.\n' > "$T7"; cp "$T7" "$T7.orig"
"$WB" "$W/demo1.md" "$T7" >/dev/null; "$WB" "$W/demo2.md" "$T7" >/dev/null
[ "$(head -4 "$T7" | od -c)" = "$(od -c < "$T7.orig")" ] && ok || bad "write-block leaves a mixed file's other lines alone -- $(head -4 "$T7" | od -c | head -4)"
[ "$(tr -cd '\r' < "$T7" | wc -c | tr -d ' ')" = 1 ] && ok || bad "write-block writes an LF block into a mostly-LF file -- $(tr -cd '\r' < "$T7" | wc -c) CRs"
"$WB" --remove demo "$T7" >/dev/null
[ "$(od -c < "$T7")" = "$(od -c < "$T7.orig")" ] && ok || bad "write-block --remove gives a mixed file back byte-identical -- $(od -c < "$T7" | head -4)"
# ...also where awk drops every CR it reads (Git Bash): awk never sees one
T8="$GR_TMP/mixed2.md"; cp "$T7.orig" "$T8"
PATH="$NA:$PATH" "$WB" "$W/demo1.md" "$T8" >/dev/null; PATH="$NA:$PATH" "$WB" "$W/demo2.md" "$T8" >/dev/null
[ "$(head -4 "$T8" | od -c)" = "$(od -c < "$T7.orig")" ] && ok || bad "write-block leaves a mixed file's other lines alone where awk drops the CR -- $(head -4 "$T8" | od -c | head -4)"
PATH="$NA:$PATH" "$WB" --remove demo "$T8" >/dev/null
[ "$(od -c < "$T8")" = "$(od -c < "$T7.orig")" ] && ok || bad "write-block --remove gives a mixed file back where awk drops the CR -- $(od -c < "$T8" | head -4)"
# a file holding \001 (CR's stand-in while awk runs) is refused, untouched,
# when awk would rewrite it (an update or a removal); an append never does
T9="$GR_TMP/soh.md"; printf '# A\001B\n' > "$T9"; cp "$T7" "$T9.2"; "$WB" "$W/demo1.md" "$T9.2" >/dev/null; printf 'x\001\n' >> "$T9.2"
o=$("$WB" "$W/demo2.md" "$T9" 2>&1); [ "$o" = added ] && ok || bad "write-block appends to a file holding \\001 -- got [$o]"
[ "$(head -1 "$T9" | od -c)" = "$(printf '# A\001B\n' | od -c)" ] && ok || bad "write-block's append keeps a \\001 byte -- $(head -1 "$T9" | od -c)"
s1=$(sum "$T9.2"); o=$("$WB" "$W/demo2.md" "$T9.2" 2>&1); rc=$?
expect "write-block refuses to update a file holding \\001, naming the line" '^guardrails-write-block: line 10 of .* holds a Ctrl-A control character \(byte 0x01\)' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T9.2")" = "$s1" ] && ok || bad "write-block refusal exits 1, file untouched -- rc $rc"
o=$("$WB" "$W/demo1.md" "$T9.2" 2>&1); [ "$o" = unchanged ] && ok || bad "write-block leaves a file holding \\001 alone when the block is the same -- got [$o]"
s1=$(sum "$T9.2"); o=$("$WB" --remove demo "$T9.2" 2>&1); rc=$?
expect "write-block --remove refuses a file holding \\001" 'holds a Ctrl-A control character' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T9.2")" = "$s1" ] && ok || bad "write-block --remove refusal exits 1, file untouched -- rc $rc"
# ...found even in a file grep would call binary (a NUL byte)
T12="$GR_TMP/nul.md"; cp "$T7" "$T12"; "$WB" "$W/demo1.md" "$T12" >/dev/null; printf 'x\001y\n\000z\n' >> "$T12"
s1=$(sum "$T12"); o=$("$WB" "$W/demo2.md" "$T12" 2>&1); rc=$?
expect "write-block finds \\001 in a file holding a NUL" 'holds a Ctrl-A control character' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T12")" = "$s1" ] && ok || bad "write-block refusal with a NUL exits 1, file untouched -- rc $rc"
# a close marker gone wrong: both update and --remove refuse, or --remove would
# take everything below it with the block
T13="$GR_TMP/noclose.md"
printf '%s\n' '# Mine' '' '<!-- guardrails:demo v1 -->' 'Line.' '<!-- /guardrails:demo --> ' '' '## My own rules' 'Keep this.' > "$T13"
s1=$(sum "$T13"); o=$("$WB" --remove demo "$T13" 2>&1); rc=$?
expect "write-block --remove refuses a block that never closes" 'opens a demo block but never closes it' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T13")" = "$s1" ] && ok || bad "write-block --remove exits 1, file untouched, on a block that never closes -- rc $rc, $(wc -l < "$T13") lines"
# ...and a later block's close does not count: an open marker inside a block
# means it never closed, or everything between would go. The long case keeps
# text well past a pipe's buffer after that marker, so a check that stops
# reading early (and dies of SIGPIPE under pipefail) is caught too.
T19="$GR_TMP/twoopens.md"; op='<!-- guardrails:demo v1 -->'; cl='<!-- /guardrails:demo -->'
for c in damaged fenced long crlf; do
  case $c in
    damaged) want='3 10'; printf '%s\n' '# Mine' '' "$op" 'Line.' "$cl " '' '## My own rules' 'Keep this.' '' "$op" 'Line.' "$cl" '' '## Tail' > "$T19" ;;
    fenced) want='3 7'; printf '%s\n' '# Mine' '```' "$op" '```' 'Keep this.' '' "$op" 'Line.' "$cl" > "$T19" ;;
    long) want='2 4'; { printf '%s\n' '# Mine' "$op" "$cl " "$op"; i=0; while [ $i -lt 400 ]; do printf '%0512d\n' $i; i=$((i + 1)); done; printf '%s\n' "$cl"; } > "$T19" ;;
    crlf) want='2 6'; printf '%s\r\n' '# Mine' "$op" 'Line.' "$cl " 'Keep this.' "$op" 'Line.' "$cl" '## Tail' > "$T19" ;;
  esac
  s1=$(sum "$T19"); o=$("$WB" --remove demo "$T19" 2>&1); rc=$?
  expect "write-block --remove refuses an open marker inside a block ($c)" "opens a demo block but never closes it \\(open markers on lines: $want\\)" "$o"
  [ "$rc" = 1 ] && [ "$(sum "$T19")" = "$s1" ] && ok || bad "write-block --remove exits 1, file untouched, on an open marker inside a block ($c) -- rc $rc"
  o=$("$WB" "$W/demo2.md" "$T19" 2>&1); rc=$?
  expect "write-block refuses to update past an open marker inside a block ($c)" "opens a demo block but never closes it \\(open markers on lines: $want\\)" "$o"
  [ "$rc" = 1 ] && [ "$(sum "$T19")" = "$s1" ] && ok || bad "write-block's update exits 1, file untouched, on an open marker inside a block ($c) -- rc $rc"
done
# --remove says so when it cannot read the file; a missing file is simply absent
o=$("$WB" --remove demo "$GR_TMP" 2>&1); rc=$?
expect "write-block --remove says when it cannot read the target" 'could not read' "$o"
[ "$rc" = 1 ] && ok || bad "write-block --remove on an unreadable target exits 1 -- rc $rc"
o=$("$WB" --remove demo "$GR_TMP/no such file" 2>&1); [ "$o" = absent ] && ok || bad "write-block --remove on a missing file -- got [$o]"
# a failed write says so (a file locked on Windows), leaves the file and no tmp
T14="$GR_TMP/locked/CLAUDE.md"; mkdir -p "$GR_TMP/locked"; "$WB" "$W/demo1.md" "$T14" >/dev/null
NM="$GR_TMP/failing mv"; mkdir -p "$NM"; printf '#!/bin/sh\necho "mv: Permission denied" >&2\nexit 1\n' > "$NM/mv"; chmod +x "$NM/mv"
s1=$(sum "$T14"); o=$(PATH="$NM:$PATH" "$WB" "$W/demo2.md" "$T14" 2>&1); rc=$?
expect "write-block says when it cannot rewrite the file" 'could not rewrite .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T14")" = "$s1" ] && ok || bad "write-block stops, file untouched, when the write fails -- rc $rc"
o=$(PATH="$NM:$PATH" "$WB" --remove demo "$T14" 2>&1); rc=$?
expect "write-block --remove says when it cannot rewrite the file" 'could not rewrite .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T14")" = "$s1" ] && ok || bad "write-block --remove stops, file untouched, when the write fails -- rc $rc"
"$WB" "$W/demo2.md" "$T14" >/dev/null
[ "$(ls -A "$GR_TMP/locked")" = CLAUDE.md ] && ok || bad "write-block leaves no temp file -- $(ls -A "$GR_TMP/locked")"
# the block's temp file unreadable when awk comes to it: the block is not lost
NK="$GR_TMP/block-losing awk"; mkdir -p "$NK"; printf '#!/bin/sh\n[ -n "${GR_BLOCK:-}" ] && rm -f "$GR_BLOCK"\nexec "%s" "$@"\n' "$RA" > "$NK/awk"; chmod +x "$NK/awk"
s1=$(sum "$T14"); o=$(PATH="$NK:$PATH" "$WB" "$W/demo3.md" "$T14" 2>&1); rc=$?
expect "write-block says when it loses the block's temp file" 'could not rewrite .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T14")" = "$s1" ] && [ "$(ls -A "$GR_TMP/locked")" = CLAUDE.md ] && ok || bad "write-block stops, file untouched, no temp file, when the block's temp file is gone -- rc $rc, $(ls -A "$GR_TMP/locked")"
# a large file with the block near the top (the read goes to the end)
T15="$GR_TMP/large.md"; "$WB" "$W/demo1.md" "$T15" >/dev/null; i=0; while [ $i -lt 400 ]; do printf '%0512d\n' $i; i=$((i + 1)); done >> "$T15"
o=$("$WB" "$W/demo2.md" "$T15" 2>&1); [ "$o" = updated ] && ok || bad "write-block updates a large file -- got [$o]"
# a target path with a backslash escape awk would read (\n), and a non-ASCII one
T16="$GR_TMP/back\new/CLAUDE.md"; mkdir -p "${T16%/*}"; "$WB" "$W/demo1.md" "$T16" >/dev/null
o=$("$WB" "$W/demo2.md" "$T16" 2>&1); [ "$o" = updated ] && expect "write-block keeps the block when the path holds a backslash" '^Line one, changed\.$' "$(cat "$T16")" || bad "write-block with a backslash in the path -- got [$o]"
T17="$GR_TMP/café proj/CLAUDE.md"; mkdir -p "${T17%/*}"
o=$("$WB" "$W/demo1.md" "$T17"; "$WB" "$W/demo2.md" "$T17"; "$WB" --remove demo "$T17")
[ "$(printf '%s\n' "$o" | tr '\n' ' ')" = 'added updated removed ' ] && ok || bad "write-block with a non-ASCII path -- got [$o]"
# a pasted line full of CRs (a progress bar) does not make an LF file CRLF
T18="$GR_TMP/bar.md"; printf '# Rules\n\n%s\n' "$(printf '10%%\r20%%\r30%%\r40%%\r50%%\r60%%\r70%%\r80%%\r')" > "$T18"; "$WB" "$W/demo1.md" "$T18" >/dev/null
c1=$(tr -cd '\r' < "$T18" | wc -c | tr -d ' '); "$WB" "$W/demo2.md" "$T18" >/dev/null
c2=$(tr -cd '\r' < "$T18" | wc -c | tr -d ' ')
[ "$c2" = "$c1" ] && [ "$(head -2 "$T18" | od -c)" = "$(printf '# Rules\n\n' | od -c)" ] && ok || bad "write-block leaves an LF file with stray CRs LF -- $c1 CRs, then $c2"
# a target that is a symlink (a CLAUDE.md kept in a dotfiles repo): the link
# survives and the real file changes. A relative link counts from its own
# folder, not the working directory, and may point at another link.
lnk() { MSYS=winsymlinks:nativestrict ln -s "$1" "$2"; }   # Git Bash's ln -s copies without it
L="$GR_TMP/links"; mkdir -p "$L/dot" "$L/sub"; R="$L/dot/real.md"; printf '%s\n' '# Mine' > "$R"
lnk ../dot/real.md "$L/sub/rel.md"; lnk "$R" "$L/abs.md"; lnk sub/rel.md "$L/chain.md"
for c in "sub rel.md" ". abs.md" ". chain.md"; do
  d=${c% *}; n=${c#* }; printf '%s\n' '# Mine' > "$R"; "$WB" "$W/demo1.md" "$R" >/dev/null
  o=$(cd "$L/$d" && "$WB" "$W/demo2.md" "$n"); [ "$o" = updated ] && [ -L "$L/$d/$n" ] && ok || bad "write-block keeps the link $n through an update -- got [$o]"
  expect "write-block updates the file behind $n" '^Line one, changed\.$' "$(cat "$R")"
  o=$(cd "$L/$d" && "$WB" --remove demo "$n"); [ "$o" = removed ] && [ -L "$L/$d/$n" ] && ok || bad "write-block keeps the link $n through a removal -- got [$o]"
  [ "$(cat "$R")" = '# Mine' ] && ok || bad "write-block removes the block from the file behind $n -- got [$(cat "$R")]"
done
# the real file is swapped, not written into: a swap that fails leaves the link
# and the file as they were, and a cp that fails part way no temp file either
"$WB" "$W/demo1.md" "$R" >/dev/null; s1=$(sum "$R")
o=$(PATH="$NM:$PATH" "$WB" "$W/demo2.md" "$L/abs.md" 2>&1); rc=$?
expect "write-block says when it cannot swap the file behind a link" 'could not rewrite .*nothing changed' "$o"
[ "$rc" = 1 ] && [ -L "$L/abs.md" ] && [ "$(sum "$R")" = "$s1" ] && [ "$(ls -A "$L/dot")" = real.md ] && ok || bad "write-block stops, link and file untouched, no temp file, when the swap fails -- rc $rc, $(ls -A "$L/dot")"
NC="$GR_TMP/failing cp"; mkdir -p "$NC"; printf '#!/bin/sh\nprintf x > "$3"\necho "cp: No space left on device" >&2\nexit 1\n' > "$NC/cp"; chmod +x "$NC/cp"
o=$(PATH="$NC:$PATH" "$WB" "$W/demo2.md" "$L/abs.md" 2>&1); rc=$?
expect "write-block says when it cannot start the swap" 'could not rewrite .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$R")" = "$s1" ] && [ "$(ls -A "$L/dot")" = real.md ] && ok || bad "write-block leaves no temp file when cp fails -- rc $rc, $(ls -A "$L/dot")"
# the temp file sits beside the real file, so a read-only folder holding only
# the link is no bar (skipped where chmod does not stop this user: root)
mkdir -p "$L/ro"; lnk ../dot/real.md "$L/ro/link.md"; chmod 555 "$L/ro"
if [ -w "$L/ro" ]; then echo "skip: a read-only folder does not stop this user, so the temp file's place is not tested"
else o=$("$WB" "$W/demo2.md" "$L/ro/link.md" 2>&1); [ "$o" = updated ] && ok || bad "write-block puts its temp file beside the real file -- got [$o]"; fi
chmod 755 "$L/ro"
# the swap keeps permissions: a file only its owner may read stays that way
P="$GR_TMP/perms.md"; "$WB" "$W/demo1.md" "$P" >/dev/null; chmod 600 "$P"; want=$(ls -l "$P" | cut -c1-10)
"$WB" "$W/demo2.md" "$P" >/dev/null; got=$(ls -l "$P" | cut -c1-10)
[ "$got" = "$want" ] && ok || bad "write-block keeps a file's permissions through an update -- $want became $got"
"$WB" --remove demo "$P" >/dev/null; got=$(ls -l "$P" | cut -c1-10)
[ "$got" = "$want" ] && ok || bad "write-block keeps a file's permissions through a removal -- $want became $got"
# a read-only file is the user's choice: an update and a removal refuse it, as
# an append does; a block already right is left alone (skipped for root)
RO="$GR_TMP/rofile"; mkdir -p "$RO"; "$WB" "$W/demo1.md" "$RO/c.md" >/dev/null; chmod 444 "$RO/c.md"
if [ -w "$RO/c.md" ]; then echo "skip: a read-only file does not stop this user, so its refusal is not tested"
else
  s1=$(sum "$RO/c.md"); o=$("$WB" "$W/demo2.md" "$RO/c.md" 2>&1); rc=$?
  expect "write-block refuses to update a read-only file" 'could not rewrite .*c\.md: it is read-only; nothing changed' "$o"
  [ "$rc" = 1 ] && [ "$(sum "$RO/c.md")" = "$s1" ] && ok || bad "write-block's update refusal exits 1, file untouched -- rc $rc"
  o=$("$WB" --remove demo "$RO/c.md" 2>&1); rc=$?
  expect "write-block refuses to remove from a read-only file" 'could not rewrite .*c\.md: it is read-only; nothing changed' "$o"
  [ "$rc" = 1 ] && [ "$(sum "$RO/c.md")" = "$s1" ] && ok || bad "write-block's removal refusal exits 1, file untouched -- rc $rc"
  o=$("$WB" "$W/demo1.md" "$RO/c.md" 2>&1); [ "$o" = unchanged ] && ok || bad "write-block leaves a read-only file alone when the block is the same -- got [$o]"
  [ "$(ls -A "$RO")" = c.md ] && ok || bad "write-block leaves no temp file beside a read-only file -- $(ls -A "$RO")"
  lnk c.md "$RO/link.md"; o=$("$WB" "$W/demo2.md" "$RO/link.md" 2>&1)
  expect "write-block names the read-only file behind a link" 'could not rewrite .*/c\.md: it is read-only' "$o"
  # the block's own temp file cannot be written (a full disk): the block stays
  NB="$GR_TMP/blocked cp"; mkdir -p "$NB"; printf '#!/bin/sh\n: > "$3.block"; chmod 444 "$3.block"\nexec "%s" "$@"\n' "$(command -v cp)" > "$NB/cp"; chmod +x "$NB/cp"
  B="$GR_TMP/blockfail"; mkdir -p "$B"; "$WB" "$W/demo1.md" "$B/c.md" >/dev/null; s1=$(sum "$B/c.md")
  o=$(PATH="$NB:$PATH" "$WB" "$W/demo2.md" "$B/c.md" 2>&1); rc=$?
  expect "write-block says when it cannot write the block's temp file" 'could not rewrite .*nothing changed' "$o"
  [ "$rc" = 1 ] && [ "$(sum "$B/c.md")" = "$s1" ] && [ "$(ls -A "$B")" = c.md ] && ok || bad "write-block stops, file untouched, no temp file, when the block's temp file cannot be written -- rc $rc, $(ls -A "$B")"
fi
chmod 644 "$RO/c.md"
# a link to nothing yet: the file appears behind it; a link loop stops with an
# error, not a hang (skipped on Windows, which cannot link to nothing)
if lnk "$L/dot/later.md" "$L/broken.md" 2>/dev/null; then
  o=$("$WB" "$W/demo1.md" "$L/broken.md"); [ "$o" = added ] && [ -L "$L/broken.md" ] && [ -f "$L/dot/later.md" ] && ok || bad "write-block adds behind a link to nothing -- got [$o]"
  lnk "$L/b.md" "$L/a.md"; lnk "$L/a.md" "$L/b.md"
  exits "write-block stops on a link loop" 1 "$WB" "$W/demo1.md" "$L/a.md"
else echo "skip: this system cannot link to a file that is not there"; fi
# a name ending in a newline is a name: the file beside it without one is left
# alone, and neither a link's target nor its folder loses the newline
N="$GR_TMP/newline"; mkdir -p "$N"; nl=$'\n'; "$WB" "$W/demo1.md" "$N/both.md$nl" >/dev/null; printf '%s\n' 'Sibling.' > "$N/both.md"
o=$("$WB" "$W/demo2.md" "$N/both.md$nl" 2>&1); [ "$o" = updated ] && ok || bad "write-block updates a name ending in a newline -- got [$o]"
expect "write-block updates that file" '^Line one, changed\.$' "$(cat "$N/both.md$nl")"
[ "$(cat "$N/both.md")" = Sibling. ] && ok || bad "write-block leaves the file beside it alone -- got [$(cat "$N/both.md")]"
mkdir -p "$N/in$nl"; "$WB" "$W/demo1.md" "$N/in$nl/real.md" >/dev/null; lnk real.md "$N/in$nl/link.md"
o=$("$WB" "$W/demo2.md" "$N/in$nl/link.md" 2>&1); [ "$o" = updated ] && [ -L "$N/in$nl/link.md" ] && ok || bad "write-block follows a link in a folder ending in a newline -- got [$o]"
"$WB" "$W/demo1.md" "$N/t$nl" >/dev/null; lnk "t$nl" "$N/l.md"
o=$("$WB" "$W/demo2.md" "$N/l.md" 2>&1); [ "$o" = updated ] && [ -L "$N/l.md" ] && ok || bad "write-block follows a link whose target ends in a newline -- got [$o]"
# ...and where readlink adds no newline to a target already ending in one (macOS)
NL="$GR_TMP/bsd readlink"; mkdir -p "$NL"
printf '#!/bin/sh\n[ "$1" = -n ] && exec "%s" "$@"\nt=$("%s" -n "$1"; echo .); t=${t%%.}\nprintf "%%s" "$t"\ncase "$t" in *"\n") ;; *) echo ;; esac\n' "$(command -v readlink)" "$(command -v readlink)" > "$NL/readlink"; chmod +x "$NL/readlink"
o=$(PATH="$NL:$PATH" "$WB" "$W/demo3.md" "$N/l.md" 2>&1); [ "$o" = updated ] && ok || bad "write-block follows that link where readlink adds no newline -- got [$o]"
# a CRLF file whose last line has no line ending (as Notepad saves it) stays
# CRLF through an update and a removal, where awk drops CRs too
for aw in "" "$NA"; do
  T10="$GR_TMP/crlf-noeol.md"; printf '# Win\r\n\r\n' > "$T10"; "$WB" "$W/demo1.md" "$T10" >/dev/null; printf '\r\nMy notes.' >> "$T10"
  PATH="$aw${aw:+:}$PATH" "$WB" "$W/demo2.md" "$T10" >/dev/null; PATH="$aw${aw:+:}$PATH" "$WB" "$W/demo3.md" "$T10" >/dev/null
  n_lines=$(wc -l < "$T10" | tr -d ' '); n_crlf=$(tr -cd '\r' < "$T10" | wc -c | tr -d ' ')
  [ "$n_lines" = "$n_crlf" ] && ok || bad "write-block keeps a CRLF file with no final newline CRLF${aw:+ where awk drops the CR} -- $n_crlf of $n_lines lines"
  printf '# Win\r\n\r\n' > "$T10"; "$WB" "$W/demo1.md" "$T10" >/dev/null; printf '\r\nMy notes.' >> "$T10"
  PATH="$aw${aw:+:}$PATH" "$WB" --remove demo "$T10" >/dev/null
  [ "$(tail -c 3 "$T10" | od -An -c | tr -d ' ')" = '.\r\n' ] && ok || bad "write-block --remove ends a CRLF file's last line CRLF${aw:+ where awk drops the CR} -- $(tail -c 3 "$T10" | od -An -c)"
done
# a non-UTF-8 byte (Latin-1 "café") where tr stops on one outside the C locale,
# as macOS's does; and a tr that fails outright stops the tool, file untouched
T11="$GR_TMP/latin1.md"; printf '# Caf\351\n\nRules.\n' > "$T11"; "$WB" "$W/demo1.md" "$T11" >/dev/null
NT="$GR_TMP/bsd tr"; mkdir -p "$NT"; RT=$(command -v tr)
printf '#!/bin/sh\ncase "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in C|POSIX) exec "%s" "$@" ;; esac\nf=$(mktemp); cat > "$f"\nif LC_ALL=C grep -q "$(printf "\\351")" "$f"; then echo "tr: Illegal byte sequence" >&2; rm -f "$f"; exit 1; fi\n"%s" "$@" < "$f"; rc=$?; rm -f "$f"; exit $rc\n' "$RT" "$RT" > "$NT/tr"; chmod +x "$NT/tr"
o=$(LANG=en_US.UTF-8 LC_ALL= PATH="$NT:$PATH" "$WB" "$W/demo2.md" "$T11" 2>&1)
[ "$o" = updated ] && [ "$(grep -c '^<!-- guardrails:demo ' "$T11")" = 1 ] && ok || bad "write-block updates a file with a Latin-1 byte where tr needs the C locale -- got [$o], $(grep -c '^<!-- guardrails:demo ' "$T11") markers"
o=$("$WB" "$W/demo3.md" "$T11"); [ "$o" = updated ] && ok || bad "write-block updates a file with a Latin-1 byte -- got [$o]"
NF="$GR_TMP/failing tr"; mkdir -p "$NF"
printf '#!/bin/sh\n[ "$1" = "\\\\r" ] && { echo "tr: failed" >&2; exit 1; }\nexec "%s" "$@"\n' "$RT" > "$NF/tr"; chmod +x "$NF/tr"
s1=$(sum "$T11"); o=$(PATH="$NF:$PATH" "$WB" "$W/demo2.md" "$T11" 2>&1); rc=$?
expect "write-block says when it cannot read the file" 'could not read .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T11")" = "$s1" ] && ok || bad "write-block stops, file untouched, when tr fails -- rc $rc, $(grep -c '^<!-- guardrails:demo ' "$T11") markers"
o=$(PATH="$NF:$PATH" "$WB" --remove demo "$T11" 2>&1); rc=$?
expect "write-block --remove says when it cannot read the file" 'could not read .*nothing changed' "$o"
[ "$rc" = 1 ] && [ "$(sum "$T11")" = "$s1" ] && ok || bad "write-block --remove stops, file untouched, when tr fails -- rc $rc"

# a block file without the marker is refused, the target untouched
printf '%s\n' '## No marker' > "$W/bad.md"; s1=$(sum "$T2")
exits "write-block refuses a block without a marker" 2 "$WB" "$W/bad.md" "$T2"
[ "$(sum "$T2")" = "$s1" ] && ok || bad "write-block leaves the target after a refusal"

# --remove takes a block out again (the explain block's "off"), text around it kept
o=$("$WB" --remove demo "$T2"); [ "$o" = removed ] && ok || bad "write-block --remove -- got [$o]"
refuse "write-block --remove leaves no marker" 'guardrails:demo' "$(cat "$T2")"
[ "$(head -3 "$T2")" = "$(printf '%s\n' '# My project' '' 'Some rules.')" ] && [ "$(tail -2 "$T2")" = "$(printf '%s\n' '## After' 'Kept.')" ] \
  && ok || bad "write-block --remove keeps the text around it -- got [$(cat "$T2")]"
o=$("$WB" --remove demo "$T2"); [ "$o" = absent ] && ok || bad "write-block --remove when absent -- got [$o]"

# the shipped blocks: each has its marker, and none says operator, cites a
# decision or dates a story
for b in habits explain explain-learning attribution compact lessons; do
  f="$SU/blocks/$b.md"; name=${b%-learning}
  expect "block $b has its marker" "^<!-- guardrails:$name v[0-9]+ -->\$" "$(head -1 "$f" 2>/dev/null)"
  refuse "block $b says the user" '[Oo]perator' "$(cat "$f" 2>/dev/null)"
  refuse "block $b cites no decision" '[Dd]ecision [0-9]{4}|DECISIONS [0-9]+\.[0-9]+' "$(cat "$f" 2>/dev/null)"
  refuse "block $b dates nothing" '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$(cat "$f" 2>/dev/null)"
done
[ "$(head -1 "$SU/blocks/explain.md")" = "$(head -1 "$SU/blocks/explain-learning.md")" ] 2>/dev/null \
  && ok || bad "the two explain variants share one marker, so switching replaces it"
o=$(tr '\n' ' ' < "$SU/blocks/habits.md" 2>/dev/null)
expect "habits names the lanes"          '\*\*Quick\*\*.*\*\*Small\*\*.*\*\*Project\*\*' "$o"
expect "habits lists the full process"   '11\. The user merges' "$o"
expect "habits offers the plan critic"   'plan critic, offered' "$o"
expect "habits: the sources table, one line in chat" 'Built on N rulings and sources' "$o"
expect "habits: one question round, later topics join" 'a topic the user raises later joins the same numbered list' "$o"
expect "habits: the user's time or money" "the user's time or money can be" "$o"
expect "habits: an agent's cost or said to be unknown" 'or said to be unknown' "$o"
expect "habits: the menu's Waiting, who it waits on" 'Waiting.{0,20}each item naming who or what it waits on' "$o"
expect "habits: a menu reply drops the trailing line" 'a menu reply drops that line' "$o"
expect "habits: review findings" 'fix every Critical and Important' "$o"
expect "habits: the review checklist if it has one" "review checklist, if it has one" "$o"
expect "habits: the docs the change makes stale" '[Tt]he docs the change makes stale' "$o"
refuse "habits leaves attribution to its own block" '[Aa]ttribution' "$o"
expect "explain, with context: every term" 'Every term the user may not know' "$(cat "$SU/blocks/explain.md" 2>/dev/null)"
expect "explain, with learning: the workflow's own terms" "workflow's own terms" "$(cat "$SU/blocks/explain-learning.md" 2>/dev/null)"
expect "the attribution block" 'No AI attribution line in a commit or pull request' "$(cat "$SU/blocks/attribution.md" 2>/dev/null)"
o=$(cat "$SU/blocks/habits.md" 2>/dev/null)
refuse "habits leaves out Explain simply"   'Explain simply' "$(cat "$SU/blocks/habits.md")"
expect "habits starts a session with the menu" 'carry on' "$o"
expect "habits has the commit line" 'a short first line saying what changed, a blank line, then why' "$o"
expect "habits has the auto-mode trap" 'Auto mode refuses' "$o"
expect "compact has the instructions" 'When compacting this conversation, keep these word for word' "$(cat "$SU/blocks/compact.md" 2>/dev/null)"
expect "lessons has the tail trap" 'tail -1 && git commit' "$(cat "$SU/blocks/lessons.md" 2>/dev/null)"
o=$(cat "$SU/SKILL.md" 2>/dev/null)
expect "setup names the write command" 'guardrails-write-block' "$o"
expect "setup hands user-level writes to the user" 'separate terminal' "$o"
expect "setup shows the status line setting" '"statusLine"' "$o"
expect "setup asks how much to explain"   'off.{0,80}with context.{0,200}with context and learning' "$(tr '\n' ' ' <<<"$o")"
expect "setup turns explaining off with --remove" 'guardrails-write-block --remove explain' "$o"
expect "setup offers the git hook"        'guardrails-install-git-hooks --data "\$\{CLAUDE_PLUGIN_DATA\}"' "$o"
expect "setup shows attribution false from 2.1.281" '2\.1\.281.{0,80}"attribution": false' "$(tr '\n' ' ' <<<"$o")"
expect "setup's older form" '"commit": "", "pr": "", "sessionUrl": false' "$o"
expect "setup says it is the opposite of the default" "opposite of Claude Code's default" "$o"
expect "setup offers the project's settings too" '\.claude/settings\.json' "$o"
for b in $(grep -oE 'blocks/[a-z-]+\.md' "$SU/SKILL.md" 2>/dev/null | sort -u); do
  [ -f "$SU/$b" ] && ok || bad "setup names $b, which does not exist"
done
exits "the example config exists" 0 test -f "$GR_REPO/examples/guardrails.conf"
o=$(cat "$SU/SKILL.md" 2>/dev/null)
expect "the separate-terminal command names its interpreter" '^ *bash "\$\{CLAUDE_PLUGIN_ROOT\}/bin/guardrails-write-block"' "$o"
expect "setup says Windows runs it in Git Bash" 'on Windows, in Git Bash' "$o"
expect "the repo's remove command runs from the repo root, like its add twin" 'remove explain CLAUDE\.md` from the repo root' "$(tr '\n' ' ' <<<"$o" | tr -s ' ')"
expect "the user-level remove command names its interpreter too" 'bash "\$\{CLAUDE_PLUGIN_ROOT\}/bin/guardrails-write-block" --remove explain ~/\.claude/CLAUDE\.md' "$o"
expect "setup writes a Windows path in the JSON with forward slashes" 'forward slashes \(`C:/Users/' "$o"
o=$(scrub "$SU" "$GR_REPO/examples"); refuse "setup names nothing private" '.' "$o"

# --- the drift warning (maintainer only): habits.md is copied from the
# maintainer's own CLAUDE.md; a WARN line, never a failure, once that changes
HD="$GR_TMP/habits src"; mkrepo "$HD"; echo one > "$HD/CLAUDE.md"
git -C "$HD" add CLAUDE.md; git -C "$HD" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm copy
at=$(git -C "$HD" rev-parse --short HEAD); printf '%s\n%s\n' "$HD/CLAUDE.md" "$at" > "$GR_TMP/habits-source"
o=$(bash "$GR_REPO/tests/habits-drift.sh" "$GR_TMP/habits-source" 2>&1); rc=$?
[ -z "$o" ] && [ "$rc" = 0 ] && ok || bad "drift check quiet while the source is as copied -- rc $rc, got [$o]"
echo two > "$HD/CLAUDE.md"; git -C "$HD" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qam "a new habit"
o=$(bash "$GR_REPO/tests/habits-drift.sh" "$GR_TMP/habits-source" 2>&1); rc=$?
expect "drift check warns, naming the commit" "^WARN: .*CLAUDE\.md changed since habits\.md was copied from it at $at: [0-9a-f]+ a new habit" "$o"
[ "$rc" = 0 ] && ok || bad "drift check never fails -- rc $rc"
o=$(bash "$GR_REPO/tests/habits-drift.sh" "$GR_TMP/no such file" 2>&1); [ -z "$o" ] && ok || bad "drift check silent without the maintainer's file -- got [$o]"
bash "$GR_REPO/tests/habits-drift.sh" 2>/dev/null   # the maintainer's own: prints a WARN line at most
