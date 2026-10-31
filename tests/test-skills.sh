# test-skills.sh -- the session-handoff skill, generalised for anyone.

SK="$GR_REPO/skills/session-handoff/SKILL.md"
o=$(scrub "$GR_REPO/skills"); refuse "skills name nothing private" '.' "$o"
exits "the handoff skill exists" 0 test -f "$SK"
o=$(cat "$SK" 2>/dev/null)
# every command it names ships with the plugin
for c in $(grep -oE 'guardrails-[a-z-]+' "$SK" 2>/dev/null | sort -u); do
  [ -x "$GR_REPO/bin/$c" ] && ok || bad "the skill names $c, which bin/ does not hold"
done
for c in $(grep -oE 'scripts/[a-z-]+\.sh' "$SK" 2>/dev/null | sort -u); do
  [ -x "$GR_REPO/$c" ] && ok || bad "the skill names $c, which does not exist"
done
refuse "the skill names no machine-specific path" '\.claude/hooks|~/\.local' "$o"
refuse "the skill cites no decision log entry"   'DECISIONS [0-9]+\.[0-9]+' "$o"
refuse "the skill says the user, not the operator" '[Oo]perator' "$o"
refuse "the skill dates no story from its own history" '[Mm]easured 20[0-9]{2}|\(20[0-9]{2}-[0-9]{2}-[0-9]{2}:' "$(tr '\n' ' ' <<<"$o")"
expect "the skill marks the handoff from the plugin" 'GUARDRAILS_STATE="\$\{CLAUDE_PLUGIN_DATA\}/state" "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/precompact-handoff\.sh" mark' "$o"
for f in MEMORY.md session-log.md slip-log.md pending-improvements.md compaction-log.md; do
  expect "the skill names $f and creates it when missing" "\`$f\`.*created when missing" "$o"
done
expect "the skill's description ends as before" 'Not for reading memory back at the start of a session\.$' \
  "$(awk 'NR > 1 && /^---/ { exit } NR > 1' "$SK" 2>/dev/null | sed -n '/^description:/,$p' | tr '\n' ' ' | sed 's/ *$//')"
refuse "the skill has no start-of-session section" '^## (Starting|At the start)' "$o"
expect "the skill audits the docs at the end" 'Last verified' "$o"
refuse "the skill no longer runs the handoff check every time" 'run the handoff check last' "$o"
expect "the handoff check is off by default" 'handoff check.{0,80}off by default' "$(tr '\n' ' ' <<<"$o")"
expect "the skill pushes a feature branch without asking, asks before the default branch" 'Push the open feature branch without.{0,10}asking; ask before pushing the default branch' "$(tr '\n' ' ' <<<"$o")"
expect "the check is offered before the mark, run only on a yes" 'offered the handoff check.{0,120}then run the mark' "$(tr '\n' ' ' <<<"$o")"

# the eval scenarios return in a later version, rewritten on invented data,
# and their checks with them
[ -e "$GR_REPO/skills/session-handoff/evals" ] \
  && bad "the evals ship -- they return in a later version, rewritten on invented data" || ok
refuse "the skill quotes no test figures" '[Ii]n testing|[Tt]est sessions?|[0-9]+ of [0-9]+ (sessions|times)|~[0-9,]+ tokens each' "$(tr '\n' ' ' < "$SK")"
