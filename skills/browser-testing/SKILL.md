---
name: browser-testing
description: Use before driving a browser against any web app -- checking a change visually, a UI audit, reproducing a layout or interaction bug, screenshots for the user. How to reach a screen the way a user would, what to screenshot and look at, what to fake so a test never touches a live account, and the Playwright traps that have cost time. A project may add its own skill with its servers and fakes; load both.
---

# Testing a web app in a browser

The method, for any project. A project's own skill holds its servers, its
fakes and the screens its demo mode cannot reach; read it too.

## 1. Get there the way a user would

Test the app the way a person uses it, clicking through it, with screenshots
as the proof.

- **Start where a user starts** -- the front page or the app's home -- and
  reach the screen by clicking and typing. Never open a deep address or
  plant state in the page (localStorage, a store, a query string the app
  never builds itself) to skip the way there.
- **Script only what a user cannot do**: faking the server so no real
  account, email or payment happens, or answering a request the local
  server cannot serve (a fixture via `page.route`). Say in the report what
  was faked.
- **A screenshot at each step, looked at**, kept as the proof and listed in
  the report by path. A step that cannot be followed on screen (a menu named
  differently, a button missing) is a finding, not something to route round.
- Why: instructions written from the data rather than the screen can send
  the user to something the page does not show.
- An automated regression suite is exempt, since it opens each page
  directly on purpose, to stay fast.

## 2. Every control by what it visibly does

On a preview or a new screen, take a screenshot before and after each control,
and look at both. Checking that the page recorded a pick is not enough: a
control can record the pick and still show nothing. For a mid-animation look,
pause it at a set time and screenshot
(`document.getAnimations().forEach(a => { a.pause(); a.currentTime = 600 })`,
then `play()`). A control with no resting effect is read from the page's
computed style or its own output.

**A reported stutter is measured in the same turn**, since it may not show
again until someone happens to do the same thing: frames drawn held still and
while scrolling, each suspect switched off in turn, interleaved over several
runs in one page (a single run swings widely), and a trace for where the time
goes. Answer with a cause and a fix, never only "it's the host".

## 3. What to cover

- Widths: phone 390x844, tablet 768x1024, desktop 1440x900; add 375x667 when
  a page may be too tall for a short phone.
- Every theme the app has (light and dark at least). In a script, set the
  browser context's `colorScheme` as well as any stored choice: an app that
  follows "system" ignores the stored one.
- A unit test suite that runs without CSS proves nothing visual. Take the
  screenshot and look at it.

## 4. Safety: fake what is live

Route anything that reaches a live service -- sign-up, sign-in, email,
payments -- to fake replies **before the first navigation**. Register the
catch-all route first and the specific ones after it: Playwright tries the
most recently added route first. Never click a third-party sign-in button
("Continue with Google") that leaves for a live authorize endpoint. Patch
responses in the browser only; never edit app files to reach a state.

## 5. Two ways to drive the browser

- **Playwright MCP** (`mcp__playwright__*`, deferred; load with ToolSearch):
  one shared browser, right for a single session working inline.
  - Its own screenshots go to the working directory's `.playwright-mcp/`,
    but a `filename` you pass is relative to the repo root: give it the
    `.playwright-mcp/` prefix, or the picture lands in the repo untracked.
    Keep `.playwright-mcp/` gitignored.
  - It runs `@playwright/mcp@latest`; after an update it may say
    `Browser "chrome-for-testing" is not installed`: run the command it
    prints (`npx -y @playwright/mcp@latest install-browser
    chrome-for-testing`, ~120 MB) and retry.
  - It keeps routes between calls, and a page route outranks a context
    route: start each walkthrough with `page.unrouteAll()` and
    `page.context().unrouteAll()` (a leftover route can fake a blank page).
- **Standalone Playwright scripts**: whenever agents run in parallel -- they
  must never share the MCP browser. Node resolves `playwright` from the
  script's own folder, so keep the scripts in a folder of their own with
  Playwright installed there (`npm i playwright`, then
  `npx playwright install chromium-headless-shell`), and launch with no
  `executablePath`: Playwright then finds the build it expects.
  - **When that build has gone**, because another Playwright on the machine
    (the MCP's, say) installed a newer one: a Playwright install deletes any
    build no other Playwright still claims, so the build your script expects
    can vanish. Copy
    `${CLAUDE_PLUGIN_ROOT}/skills/browser-testing/browser-path.mjs` beside
    the scripts and take the newest complete build on disk:
    `import { HEADLESS_SHELL } from './browser-path.mjs'`, then
    `chromium.launch({ executablePath: HEADLESS_SHELL, args: ['--no-sandbox'] })`.
    It reads `PLAYWRIGHT_BROWSERS_PATH` and Playwright's default folder on
    Linux, macOS and Windows.

## 6. Waits and quirks

- Never wait for `networkidle` on a page with a captcha or chat widget: it
  holds connections open and the wait times out. Use `waitUntil: 'load'`
  plus a selector.
- Web fonts arrive late. A scroll position or layout measured before
  `await page.evaluate(() => document.fonts.ready)` can move by 100px or more.
- Headless Chromium has `100vh == 100dvh`, so a mobile-toolbar overflow bug
  cannot be seen there; check such code by reading it.
- A widget in a CLOSED shadow root (a captcha widget, for example) cannot be
  reached by any selector.

## 7. Keep the evidence

A session's scratchpad dies with it. Screenshots and measurements someone
will need later go in `.playwright-mcp/` in the working directory, or next
to the work they support.
