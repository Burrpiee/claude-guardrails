# test-skeleton.sh -- the manifests, line endings and file modes.

M="$GR_REPO/.claude-plugin/marketplace.json"
P="$GR_REPO/.claude-plugin/plugin.json"
exits "marketplace.json parses" 0 jq -e . "$M"
exits "plugin.json parses" 0 jq -e . "$P"
o=$(jq -r '.name' "$M" 2>/dev/null);  expect "marketplace name" '^guardrails-tools$' "$o"
o=$(jq -r '.owner.name // empty' "$M" 2>/dev/null); expect "marketplace owner" '.' "$o"
o=$(jq -c '[.plugins[] | {name, source}]' "$M" 2>/dev/null)
expect "marketplace lists the plugin at its root" '^\[\{"name":"guardrails","source":"\./"\}\]$' "$o"
o=$(jq -r '[.name, .version, .license] | join(" ")' "$P" 2>/dev/null)
expect "plugin name, version, licence" '^guardrails 0\.1\.0 MIT$' "$o"
exits "LICENSE is MIT" 0 grep -q '^MIT License' "$GR_REPO/LICENSE"

# Every tracked text file is LF in the index; a CRLF script breaks `sh`.
o=$(git -C "$GR_REPO" ls-files --eol)
refuse "no tracked file has CRLF" 'i/(crlf|mixed)' "$o"
refuse "no checked-out file has CRLF" 'w/(crlf|mixed)' "$o"
# Every script is committed executable.
o=$(git -C "$GR_REPO" ls-files -s scripts bin git-hooks tests/shim | grep -v '^100755')
refuse "scripts committed 100755" '.' "$o"
