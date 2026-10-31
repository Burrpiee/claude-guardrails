# test-browser.sh -- the browser-testing skill and its browser-path.mjs helper.

BT="$GR_REPO/skills/browser-testing"
exits "the browser-testing skill exists" 0 test -f "$BT/SKILL.md"
o=$(cat "$BT/SKILL.md" 2>/dev/null)
expect "the skill is named browser-testing" '^name: browser-testing$' "$o"
expect "the skill has a description" '^description: Use before driving a browser' "$o"
# every file of the skill, not only SKILL.md
all=$(cat "$BT"/* 2>/dev/null)
refuse "the skill says the user, not the operator" '[Oo]perator' "$all"
refuse "the skill cites no decision log entry" 'DECISIONS' "$all"
refuse "the skill carries no dated ruling" '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$all"
refuse "the skill names no machine-specific path" '\.claude/hooks|~/\.local' "$all"
# the rules the rewording must keep
expect "a screenshot before and after each control" 'screenshot before and after each control' "$o"
expect "the regression suite stays exempt" 'automated regression suite is exempt' "$o"
expect "a reported stutter is measured in the same turn" 'measured in the same turn' "$o"
# the usual way first, the helper where the plugin keeps it
expect "the usual browser install comes first" 'npx playwright install chromium-headless-shell' "$o"
expect "the helper is named where the plugin keeps it" '\$\{CLAUDE_PLUGIN_ROOT\}/skills/browser-testing/browser-path\.mjs' "$o"

# --- browser-path.mjs, on every OS's folder layout whatever OS runs the test
if ! command -v node >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then bad "node is missing on CI, so browser-path.mjs went untested"
  else echo "SKIP: browser-path.mjs (no node on PATH)"; fi
else
  # np PATH: a path node can open (Git Bash's /tmp means nothing to node on Windows)
  np() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
  BP=$(np "$BT/browser-path.mjs")
  # bp JS ARGS...: run JS with the helper imported as `m`, ARGS as process.argv[2..].
  # Importing works out HEADLESS_SHELL, which throws with no build, so every
  # call points PLAYWRIGHT_BROWSERS_PATH at a fixture (CI has no browser).
  bp() {
    local js=$1; shift
    PLAYWRIGHT_BROWSERS_PATH=${PBP:-$(np "$H")} node --input-type=module -e "import { pathToFileURL } from 'node:url';
      const m = await import(pathToFileURL(process.argv[1]).href); $js" "$BP" "$@" 2>&1
  }
  # build ROOT N LAYOUT EXE [incomplete]: a chromium_headless_shell-N build, with
  # Playwright's INSTALLATION_COMPLETE marker unless the fifth argument is given
  build() {
    mkdir -p "$1/chromium_headless_shell-$2/chrome-headless-shell-$3"
    : > "$1/chromium_headless_shell-$2/chrome-headless-shell-$3/$4"
    [ -n "${5:-}" ] || : > "$1/chromium_headless_shell-$2/INSTALLATION_COMPLETE"
  }
  END='chromium_headless_shell-1200[/\\]chrome-headless-shell-'
  # a build for whichever OS runs the test: both executable names
  H="$GR_TMP/pw host"; build "$H" 1200 host chrome-headless-shell; : > "$H/chromium_headless_shell-1200/chrome-headless-shell-host/chrome-headless-shell.exe"
  for lay in linux:linux64 linux:linux-arm64 darwin:mac-arm64 darwin:mac-x64 win32:win64; do
    plat=${lay%%:*}; dir=${lay#*:}
    exe=chrome-headless-shell; [ "$plat" = win32 ] && exe=chrome-headless-shell.exe
    R="$GR_TMP/pw $dir"
    build "$R" 999 "$dir" "$exe"
    build "$R" 1200 "$dir" "$exe"
    mkdir -p "$R/chromium_headless_shell-1200/chrome-headless-shell-x"   # a folder without the browser
    build "$R" 1300 "$dir" "$exe" incomplete                            # still installing
    build "$R" 1400 "$dir" "$exe"; mv "$R/chromium_headless_shell-1400" "$R/chromium_tip_of_tree_headless_shell-1400"
    o=$(bp 'console.log(m.findShell(process.argv[2], process.argv[3]))' "$(np "$R")" "$plat")
    expect "findShell on $dir takes the newest complete build" "${END}${dir}[/\\\\]${exe//./\\.}\$" "$o"
  done
  E="$GR_TMP/pw empty"; mkdir -p "$E"
  o=$(bp 'try { m.findShell(process.argv[2], "linux") } catch (e) { console.log("threw:", e.message) }' "$(np "$E")")
  expect "findShell with no build says where it looked" '^threw: .*pw empty.*npx playwright install chromium-headless-shell' "$o"
  o=$(bp 'try { m.findShell(process.argv[2], "linux") } catch (e) { console.log("threw:", e.message) }' "$(np "$GR_TMP/pw missing")")
  expect "findShell with no folder at all says so" '^threw: ' "$o"
  W="$GR_TMP/pw winonly"; build "$W" 1200 win64 chrome-headless-shell.exe
  o=$(bp 'try { m.findShell(process.argv[2], "linux") } catch (e) { console.log("threw:", e.message) }' "$(np "$W")")
  expect "findShell on linux ignores a Windows-only build" '^threw: ' "$o"

  # cacheRoot(platform, env, home, cwd): Playwright's own default folders
  cr() { bp "console.log(m.cacheRoot($1))"; }
  o=$(cr "'linux', {}, '/h', '/w'");                          expect "cacheRoot linux"        '^/h/\.cache/ms-playwright$' "$o"
  o=$(cr "'linux', { XDG_CACHE_HOME: '/x' }, '/h', '/w'");     expect "cacheRoot XDG"          '^/x/ms-playwright$' "$o"
  o=$(cr "'darwin', {}, '/h', '/w'");                         expect "cacheRoot darwin"       '^/h/Library/Caches/ms-playwright$' "$o"
  o=$(cr "'win32', { LOCALAPPDATA: 'C:\\\\Users\\\\x\\\\AppData\\\\Local' }, 'C:\\\\Users\\\\x', 'C:\\\\w'")
  expect "cacheRoot win32" '^C:\\Users\\x\\AppData\\Local\\ms-playwright$' "$o"
  o=$(cr "'win32', {}, 'C:\\\\Users\\\\x', 'C:\\\\w'");       expect "cacheRoot win32 without LOCALAPPDATA" '^C:\\Users\\x\\AppData\\Local\\ms-playwright$' "$o"
  o=$(cr "'linux', { PLAYWRIGHT_BROWSERS_PATH: '/b' }, '/h', '/w'"); expect "cacheRoot takes PLAYWRIGHT_BROWSERS_PATH" '^/b$' "$o"
  o=$(cr "'linux', { PLAYWRIGHT_BROWSERS_PATH: 'b' }, '/h', '/w'");  expect "cacheRoot resolves a relative one from cwd" '^/w/b$' "$o"
  o=$(cr "'linux', { PLAYWRIGHT_BROWSERS_PATH: 'b', INIT_CWD: '/i' }, '/h', '/w'"); expect "cacheRoot prefers INIT_CWD" '^/i/b$' "$o"
  o=$(bp "try { m.cacheRoot('linux', { PLAYWRIGHT_BROWSERS_PATH: '0' }, '/h', '/w') } catch (e) { console.log('threw:', e.message) }")
  expect "cacheRoot refuses PLAYWRIGHT_BROWSERS_PATH=0" '^threw: .*node_modules' "$o"

  # HEADLESS_SHELL, the export scripts import, on this OS
  o=$(bp 'console.log(m.HEADLESS_SHELL)')
  expect "HEADLESS_SHELL is the newest build on this OS" "${END}host[/\\\\]chrome-headless-shell(\\.exe)?\$" "$o"
  o=$(PBP="$(np "$E")" bp 'console.log("imported")')
  expect "importing with no build throws, saying what to run" 'npx playwright install chromium-headless-shell' "$o"
fi
