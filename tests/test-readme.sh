# test-readme.sh -- the README and CHANGELOG, each claim read from the code it
# describes, so the text cannot drift from it. jq reads go through tr -d '\r'
# (a Windows jq.exe may end lines with CR).

RD="$GR_REPO/README.md"; CL="$GR_REPO/CHANGELOG.md"
r=$(cat "$RD" 2>/dev/null); rf=$(tr '\n' ' ' < "$RD" 2>/dev/null | tr -s ' ')
# every command, skill, hook script and example file is named
for f in "$GR_REPO"/bin/*; do expect "README names ${f##*/}" "${f##*/}" "$r"; done
for s in /guardrails:setup session-handoff browser-testing; do expect "README names the skill $s" "$s" "$r"; done
for s in $(jq -r '.hooks[][].hooks[].command' "$GR_REPO/hooks/hooks.json" 2>/dev/null | tr -d '\r' | grep -oE '[a-z-]+\.sh' | sort -u) \
         statusline.sh undo-check.sh undo-check-ci.sh; do
  expect "README names the script $s" "$s" "$r"
done
for f in $(cd "$GR_REPO" && find examples -type f | sort); do expect "README names $f" "${f#examples/}" "$r"; done
# every config key, as code
for k in $(grep -oE '^# [a-z_]+ =' "$GR_REPO/examples/guardrails.conf" | awk '{print $2}' | sort -u) watch_dirs words; do
  expect "README names the key $k" "\`$k\`" "$r"
done
expect "README names .worktreeinclude" '`\.worktreeinclude`' "$r"
# the precedence sentence: the keys read once are those the code reads with head -1
want=$(grep -rhoE 'get "[^"]*" [a-z_]+ \| *head -1' "$GR_REPO/scripts" "$GR_REPO/bin" | awk '{print $3}' | sort -u | tr '\n' ' ')
got=$(printf '%s\n' "$rf" | grep -oE 'A key read once \([^)]*\)' | grep -oE '`[a-z_]+`' | tr -d '`' | sort -u | tr '\n' ' ')
[ -n "$want" ] && [ "$got" = "$want" ] && ok || bad "README's read-once keys match the code -- want [$want], got [$got]"
expect "README says the other keys add up" 'every other key adds up' "$rf"
# ...and the example config's header, which setup copies into every repo, says the same
eh=$(sed -n '1,/^$/{s/^# *//;p;}' "$GR_REPO/examples/guardrails.conf" 2>/dev/null | tr '\n' ' ' | tr -s ' ')
refuse "the example's header does not say the local file's values win" 'values win' "$eh"
got=$(printf '%s\n' "$eh" | grep -oE 'A key read once \([^)]*\)' | sed 's/.*(//' | grep -oE '[a-z_]+' | sort -u | tr '\n' ' ')
[ -n "$want" ] && [ "$got" = "$want" ] && ok || bad "the example's read-once keys match the code -- want [$want], got [$got]"
expect "the example says the other keys add up" 'every other key adds up' "$eh"
refuse "README does not say the push guard reports an old git" 'below that it says it' "$rf"
expect "README says the time limits need GNU timeout" 'brew install coreutils' "$rf"
# every environment variable the scripts read is named
for v in $(grep -ohE 'GUARDRAILS_[A-Z_]+' "$GR_REPO"/scripts/* "$GR_REPO"/bin/* "$GR_REPO"/git-hooks/* | sort -u); do
  expect "README names $v" "\`$v\`" "$r"
done
expect "README names CLAUDE_PLUGIN_DATA" 'CLAUDE_PLUGIN_DATA' "$r"
# numbers as the code has them
floor=$(grep -oE 'older than [0-9]+\.[0-9]+\.[0-9]+' "$GR_REPO/scripts/session-status.sh" | head -1 | awk '{print $3}')
expect "README names the Claude Code floor $floor" "${floor//./\\.}" "$r"
warn=$(grep -oE 'GUARDRAILS_WARN_TOKENS:-[0-9]+' "$GR_REPO/scripts/statusline.sh" | head -1 | cut -d- -f2)
expect "README names the warn default $warn" "\`$warn\`" "$r"
expect "README names git 2.37" 'git 2\.37' "$r"
for l in 'winget install jqlang.jq' 'brew install jq'; do
  grep -qF "$l" "$GR_REPO/scripts/lib.sh" && expect "README gives the jq line as printed: $l" "${l//./\\.}" "$r"
done
# the install lines, from the manifests
repo=$(jq -r .repository "$GR_REPO/.claude-plugin/plugin.json" | tr -d '\r' | sed -E 's#^https://github.com/##')
mk=$(jq -r .name "$GR_REPO/.claude-plugin/marketplace.json" | tr -d '\r')
pn=$(jq -r '.plugins[0].name' "$GR_REPO/.claude-plugin/marketplace.json" | tr -d '\r')
expect "README: the marketplace line" "^/plugin marketplace add $repo\$" "$r"
expect "README: the install line" "^/plugin install $pn@$mk\$" "$r"
# ...and a teammate's, the marketplace first: the install alone fails on a clean machine
expect "README: a teammate's marketplace line" "^claude plugin marketplace add $repo\$" "$r"
expect "README: a teammate's install line" "^claude plugin install $pn@$mk --scope project\$" "$r"
tm=$(grep -n '^claude plugin marketplace add' "$RD" | head -1 | cut -d: -f1); ti=$(grep -n '^claude plugin install' "$RD" | head -1 | cut -d: -f1)
[ -n "$tm" ] && [ -n "$ti" ] && [ "$tm" -lt "$ti" ] && ok || bad "README has a teammate add the marketplace before the install"
gfw=$(grep -n 'Git for Windows' "$RD" | head -1 | cut -d: -f1); pl=$(grep -n '^/plugin' "$RD" | head -1 | cut -d: -f1)
[ -n "$gfw" ] && [ -n "$pl" ] && [ "$gfw" -lt "$pl" ] && ok || bad "README names Git for Windows before the first /plugin line"
for h in '## Updating' '## Uninstalling'; do expect "README has $h" "^$h" "$r"; done
expect "README: uninstalling removes the git hooks first" 'guardrails-install-git-hooks --remove' "$r"
expect "README: updating" 'claude plugin update' "$r"
# every paid call is named under "What it costs"
costs=$(awk '/^## What it costs/ { on = 1; next } on && /^## / { exit } on' "$RD" 2>/dev/null)
for f in $(grep -lE '\$\(claude[[:space:]]+(-p|--print)' -r "$GR_REPO/bin" "$GR_REPO/scripts" "$GR_REPO/skills" 2>/dev/null); do
  expect "What it costs names ${f##*/}" "${f##*/}" "$costs"
done
price='about 0.15 USD at API prices, counted against usage on a subscription'
for f in "$RD" "$GR_REPO/bin/guardrails-handoff-check" "$GR_REPO/skills/session-handoff/SKILL.md"; do
  grep -qF "$price" <<<"$(tr '\n' ' ' < "$f" | sed 's/# //g; s/  */ /g')" && ok || bad "${f##*/} gives the handoff check's price in the one wording"
done
refuse "no public file says ten times" '(ten|10) ?(times|x) an idle compaction' "$(cat "$RD" "$GR_REPO"/scripts/* "$GR_REPO"/skills/*/SKILL.md 2>/dev/null)"
# the undo check's three places, the word guard, explaining terms, attribution
for p in 'GUARDRAILS_ALLOW_UNDO=1' 'undo-ok' 'guardrails-install-git-hooks' 'workflows/undo-check.yml'; do expect "README: the undo check ($p)" "$p" "$r"; done
expect "README: the word guard's gaps" 'bash -c' "$r"
expect "README: explaining terms" 'with context and learning' "$rf"
expect "README: attribution is the opposite of the default" "opposite of Claude Code's default" "$rf"
expect "README: the idle mode is coming, not switchable" 'idle.{0,200}later version' "$rf"
expect "README: node for the browser tests" 'node' "$(awk '/^## Developing/ { on = 1 } on' "$RD")"
# the linked skills, each with its source and install line; none bundled
for s in apple-design improve-animations review-animations; do
  expect "README links $s" "$s" "$r"; [ -e "$GR_REPO/skills/$s" ] && bad "$s is bundled" || ok
done
expect "README: emilkowalski/skills and its install line" 'npx skills@latest add emilkowalski/skills' "$r"
expect "README: motion-design and its install line" 'npx skills add LottieFiles/motion-design-skill' "$r"
[ -e "$GR_REPO/skills/motion-design" ] && bad "motion-design is bundled" || ok
# no story, no log
refuse "README dates no story" '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$r"
refuse "README cites no log" '[Oo]perator|DECISIONS [0-9]' "$r"
# the CHANGELOG
c=$(cat "$CL" 2>/dev/null)
expect "CHANGELOG is Keep a Changelog" 'keepachangelog\.com' "$c"
expect "CHANGELOG has Unreleased" '^## \[Unreleased\]$' "$c"
expect "CHANGELOG plans the evals in a later version" '[Ee]val cases for the session-handoff skill in a later version' "$c"
refuse "CHANGELOG names no later number" '0\.2|v0\.[2-9]' "$c"
# ...and its newest section is the version the manifest ships, dated and linked
ver=$(jq -r .version "$GR_REPO/.claude-plugin/plugin.json" | tr -d '\r'); vre=${ver//./\\.}
expect "CHANGELOG's newest section is version $ver, dated" "^## \[$vre\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\$" "$(grep -m1 -E '^## \[[0-9]' "$CL")"
expect "CHANGELOG links $ver to its tag" "^\[$vre\]: https://github\.com/$repo/releases/tag/v$vre\$" "$c"
expect "CHANGELOG compares Unreleased with that tag" "^\[Unreleased\]: https://github\.com/$repo/compare/v$vre\.\.\.HEAD\$" "$c"
# the manifests say the same thing
d1=$(jq -r .description "$GR_REPO/.claude-plugin/plugin.json" | tr -d '\r'); d2=$(jq -r '.plugins[0].description' "$GR_REPO/.claude-plugin/marketplace.json" | tr -d '\r')
[ "$d1" = "$d2" ] && ok || bad "plugin.json and marketplace.json describe the plugin alike"
expect "the description names the undo check" 'undo' "$d1"
