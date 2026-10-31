// The newest complete Playwright headless shell on disk, for standalone scripts
// whose own Playwright's build may have gone: a Playwright install deletes any
// build no other Playwright on the machine still claims, so a script must never
// name one. Copy this file beside the script, then
//   import { HEADLESS_SHELL } from './browser-path.mjs'
// Importing it throws when no complete build is found.
import { existsSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

// Where Playwright keeps its browsers, by its own rules.
export function cacheRoot(platform = process.platform, env = process.env, home = homedir(), cwd = process.cwd()) {
  const p = platform === 'win32' ? path.win32 : path.posix;
  const set = env.PLAYWRIGHT_BROWSERS_PATH;
  if (set === '0') throw new Error('PLAYWRIGHT_BROWSERS_PATH=0 keeps browsers inside node_modules; set it to a folder instead');
  if (set) return p.resolve(env.INIT_CWD || cwd, set);
  if (platform === 'darwin') return p.join(home, 'Library', 'Caches', 'ms-playwright');
  if (platform === 'win32') return p.join(env.LOCALAPPDATA || p.join(home, 'AppData', 'Local'), 'ms-playwright');
  return p.join(env.XDG_CACHE_HOME || p.join(home, '.cache'), 'ms-playwright');
}

// The newest build under root that finished installing and holds the browser.
// Its platform folder (linux64, mac-arm64, win64, ...) is found, not listed.
export function findShell(root, platform = process.platform) {
  const exe = platform === 'win32' ? 'chrome-headless-shell.exe' : 'chrome-headless-shell';
  let builds = [];
  try { builds = readdirSync(root); } catch { /* no folder: no build */ }
  const found = builds
    .filter((d) => /^chromium_headless_shell-\d+$/.test(d))
    .sort((a, b) => Number(b.split('-')[1]) - Number(a.split('-')[1]))
    .map((d) => {
      const build = path.join(root, d);
      if (!existsSync(path.join(build, 'INSTALLATION_COMPLETE'))) return null;
      const sub = readdirSync(build).find((s) => s.startsWith('chrome-headless-shell-') && existsSync(path.join(build, s, exe)));
      return sub ? path.join(build, sub, exe) : null;
    })
    .find(Boolean);
  if (!found) throw new Error(`no complete chromium_headless_shell-* build in ${root}; run: npx playwright install chromium-headless-shell`);
  return found;
}

export const HEADLESS_SHELL = findShell(cacheRoot());
