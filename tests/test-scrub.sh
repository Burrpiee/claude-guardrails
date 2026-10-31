# test-scrub.sh -- nothing private in the repo: the public patterns over every
# tracked or new (untracked, not ignored) file, and the maintainer's private
# list too, when it exists on this machine (it lives outside the repo, so the
# list itself is never published).

# Lines the public patterns hit on purpose: the made-up Windows home in the
# path tests (C:/Users/Jane Doe). That name only, not whole files.
SCRUB_ALLOW='Users[/\\]Jane Doe'

scrub_tracked() {
  (cd "$GR_REPO" && git ls-files -z --cached --others --exclude-standard 2>/dev/null | xargs -0 sh -c 'for f; do [ -f "$f" ] && printf "%s\0" "$f"; done' sh \
    | xargs -0 grep -nIE -- '/home/[a-z]|/Users/[A-Za-z]|[A-Za-z]:\\Users\\|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null \
    | grep -vE -- "$SCRUB_ALLOW")
}

o=$(scrub_tracked); refuse "no tracked or new file names a home folder or a real email" '.' "$o"

PRIV=${GUARDRAILS_PRIVATE_STRINGS:-$HOME/.config/guardrails/private-strings.txt}
if [ -f "$PRIV" ]; then
  grep -v '^#' "$PRIV" | grep -v '^[[:space:]]*$' > "$GR_TMP/private-strings"
  o=$(cd "$GR_REPO" && git ls-files -z --cached --others --exclude-standard | xargs -0 grep -nIiwF -f "$GR_TMP/private-strings" 2>/dev/null)
  refuse "no tracked or new file holds a private string" '.' "$o"
fi

# no story: no "operator", decision citation, session ordinal, PR number or
# dated story in any public file, apart from the fixtures and checks below
allow='^tests/test-bin\.sh:[0-9]+:(.*RULED, DECISIONS 3\.1|refuse "handoff-check says no operator")|^tests/test-(browser|skills)\.sh:[0-9]+:refuse "the skill says the user, not the operator"|^tests/test-setup\.sh:[0-9]+:# the shipped blocks: each has its marker, and none says operator'
o=$(cd "$GR_REPO" && git ls-files --cached --others --exclude-standard | grep -v '^tests/test-scrub\.sh$' | tr '\n' '\0' \
  | xargs -0 grep -nIE '[Oo]perator|[Dd]ecision 00[0-9]{2}|DECISIONS [0-9]+\.[0-9]+|[0-9]+(st|nd|rd|th) session|#[0-9]{2,}|\(20[0-9]{2}-[0-9]{2}-[0-9]{2}:' 2>/dev/null \
  | grep -vE "$allow")
refuse "no public file tells a story" '.' "$o"
