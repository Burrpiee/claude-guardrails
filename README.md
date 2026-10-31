# guardrails

A Claude Code plugin that asks before the deploys and spends you name,
refuses a few risky shell habits, checks that a push does not undo recent
work, shows each session's live state at its start, and helps a long session
hand off cleanly before it is compacted.

What it is not: a sandbox. The guards ask about or refuse the commands they
know; anything else runs as Claude Code would run it anyway.

## Requirements

- **Claude Code 2.1.295 or later.** Before that, a guard that crashes lets
  the command through; the session start warns on an older version.
- **git**, and git 2.37 or later for the undo check (below that the check is
  skipped and the push goes through; git's hook and CI say so).
- **jq.** Without it every shell command and agent launch is refused until it
  is installed, and the session start says so. Install it in a terminal
  outside Claude Code: Windows `winget install jqlang.jq`, Mac
  `brew install jq`, Linux your package manager.
- **bash 3.2 or later** (macOS's own bash is fine).
- **Python 3.7 or later**, only for four commands: `guardrails-owed-check`,
  `guardrails-handoff-check`, `guardrails-instructions-check` and
  `guardrails-session-messages`. They run the first of `python3`, `python`
  and `py` that works (on Windows, `python3` is often only the Microsoft
  Store's placeholder); set `GUARDRAILS_PYTHON` to choose one.
- **node and Playwright**, only for the browser-testing skill's scripts.
- **Windows: Git for Windows first.** The hooks run in its Git Bash, even when
  you use the PowerShell tool (the shell guards read PowerShell commands too).

## Install

```
/plugin marketplace add Burrpiee/claude-guardrails
/plugin install guardrails@guardrails-tools
```

Pick **user scope** to have it in every project for yourself, or **project
scope** to share it with a team. With project scope, each teammate also runs
these once:

```
claude plugin marketplace add Burrpiee/claude-guardrails
claude plugin install guardrails@guardrails-tools --scope project
```

Then run `/guardrails:setup` in a session.

## Set up

`/guardrails:setup` offers each piece in turn and writes only what you
accept:

- **CLAUDE.md blocks**, into the project's `CLAUDE.md` or (as a command for you
  to run) your own `~/.claude/CLAUDE.md`:
  - working habits: three lanes sized to the risk (quick, small, project),
    plans that rest on sources read in full, options with their costs, the
    normal way first, a "What's for you to do" list, recording your reasons,
    and a menu when you say "carry on";
  - explaining terms, at one of three levels: off, with context (every term
    you may not know comes with what it is and why it matters here), or with
    context and learning (the workflow's own terms too);
  - compact instructions (what a compaction must keep word for word);
  - lessons (five traps that cost time before).
  Running setup again after an update replaces each block in place.
- **A project config**, `.claude/guardrails.conf`, from
  `examples/guardrails.conf`, every line commented out until you choose.
- **git's pre-push hook** for the undo check (below).
- **Attribution**: Claude Code adds a `Co-Authored-By` trailer to its commits
  and a line to pull requests by default. Setup offers to turn that off, as a
  setting plus a CLAUDE.md block; this is the opposite of Claude Code's
  default, so it is only done when you say yes.
- **The status line**: `ctx 63k · main`, with `⚠ hand off` past the warn
  threshold.

## What is inside

**Hooks** (run by Claude Code; nothing to start):

- `session-status.sh` (session start and after each compaction): the branch
  and uncommitted count of the repo and its partners, branches not yet
  merged, the signed-in account, the effort level, dev ports listening,
  unsaved changes in folders you watch, process fixes waiting in the memory
  folder, instruction files over their word budget, and backlog items still
  marked "ruling owed" that the decision log already cites.
- `cost-guard.sh`: asks before a command your project names as costly or
  deploying (`guard` lines).
- `push-guard.sh`: asks before `git push` sends commits to a branch already
  merged or deleted, before a push that would undo the default branch's
  recent work (the undo check), and before a push that skips git's hooks.
- `pkill-guard.sh`: refuses `pkill -f`, which kills the agent's own shell.
- `claude-word-guard.sh`: refuses `claude <word>` unless the word is a real
  subcommand or a flag, since any other word runs as a paid one-off prompt
  (`claude ps` does not list sessions). Not caught: `bash -c "..."`, `xargs`,
  and a flag before the word.
- `agent-launch-guard.sh` (off unless `agent_launch_guard = on`): refuses to
  launch an agent until a fresh "Where to resume" note is in `MEMORY.md` and
  the prompt is saved in a file, so the work survives a usage limit.
- `context-reminder.sh`: past the warn threshold, reminds the model each
  prompt to suggest a handoff at the next natural break.
- `precompact-snapshot.sh`: before a compaction, saves the live git state to
  the memory folder and adds a line to `compaction-log.md`.
- `precompact-handoff.sh`: skips an automatic compaction while a finished
  handoff is the last thing done (you are about to `/clear`, so compacting
  only spends).
- `statusline.sh`: the status line, run from a copy in the plugin's data
  folder.

**Commands** in `bin/`, on the Bash tool's PATH while the plugin is enabled.
They run inside Claude Code, not in your own terminal: ask Claude to run them.

- `guardrails-owed-check`: backlog items marked "ruling owed" that the
  decision log or records already cite.
- `guardrails-handoff-check`: asks a fresh headless session the four
  questions every next session faces, to check a handoff (paid; see costs).
- `guardrails-instructions-check`: asks fresh sessions the questions in a
  table (`examples/instruction-questions.md` shows the form) to check that
  instruction files still give the right answers (paid).
- `guardrails-session-messages`: every message you sent in a session, in
  order, including ones typed mid-turn and answers to questions.
- `guardrails-review-worktree`: one isolated worktree per reviewer, with the
  ignored files it needs and a smoke test.
- `guardrails-install-git-hooks`: puts the undo check inside `git push`.
- `guardrails-write-block`: writes one of setup's blocks into a CLAUDE.md.

**Skills**: `/guardrails:setup`; `session-handoff` (saves the session's
context to the memory folder before `/clear`, prunes stale memory, and checks
work is committed); `browser-testing` (how to check a change in a real
browser the way a user reaches it).

## The undo check

A branch rebuilt from an older copy of the files puts them back as they were
before work that merged since, and git sees no conflict: a fix merged an hour
ago is quietly deleted. The check names a file the push changes that is now
exactly as it was before a recent default-branch commit to it (14 days;
`GUARDRAILS_UNDO_DAYS`). It runs in three places:

1. **The push guard** asks before such a push from Claude. It checks the
   branch as it is before the command runs, within its time limit
   (`GUARDRAILS_UNDO_SECONDS`, default 10). The limit needs GNU `timeout`
   (Linux and Git Bash have it; on a Mac, `brew install coreutils`); without
   it, a fetch that hangs ends in a hook error that blocks each try of the
   push while it hangs.
2. **git's pre-push hook**, installed per repo by setup or
   `guardrails-install-git-hooks --data "<the plugin's data folder>"`. It
   covers pushes from a terminal or an IDE too and sees a commit made in the
   same command. Git refuses the push; a meant revert is pushed with
   `GUARDRAILS_ALLOW_UNDO=1` after you say so. Each repo gets a small
   `.git/hooks/pre-push` that runs a copy in the plugin's data folder; if
   that copy is missing, the push goes through with a warning. The scripts
   are `scripts/undo-check.sh` and `git-hooks/pre-push`.
3. **CI on every pull request**: copy `examples/workflows/undo-check.yml` into
   your project's `.github/workflows/`. It runs `scripts/undo-check-ci.sh`
   against the pull request's base branch and fails one that would undo its
   recent work; the label `undo-ok` lets a meant revert through and says what
   it let pass. It blocks a merge only if you make it a required status check.
   Public repos run it free; on a private one each run is billed as at least
   one minute of Actions time. Update it by changing the `ref:` tag.

## Configure

Per project, `.claude/guardrails.conf` (commit it) and
`.claude/guardrails.local.conf` (git-ignore it; machine-specific values).
Your own `~/.claude/guardrails.conf` adds `words` and `watch_dirs` for every
project. Lines are `key = value`; a key may repeat. A key read once
(`agent_launch_guard`, `backlog`, `memory`) takes the local file's value;
every other key adds up across both files, so a local file cannot drop a
committed `guard`.

- `guard`: `<runs> :: <requires> :: <forbids> :: <reason>`, asks before a
  matching command. `examples/guardrails.conf` has two examples; the guard
  asks, never refuses, so a pasted example costs one prompt.
- `partners`: other repos whose guards also apply and whose branches the
  status reports.
- `decisions`: the decision log, or a folder of records (default
  `docs/DECISIONS.md` and `docs/decisions/`, each when present).
- `backlog`: the backlog (default `docs/BACKLOG.md`).
- `words`: an instruction file and its word budget.
- `agent_launch_guard`: `on` to turn on the agent-launch guard.
- `memory`: the memory folder, when not Claude Code's own for the repo.
- `ports`: dev servers whose ports the status reports.
- `smoke`: commands run once in each review worktree.
- `worktree_links`: big ignored folders linked into each review worktree.
  Small ignored files (a `.env`) are copied instead when the repo's
  `.worktreeinclude`, Claude Code's own list for its worktrees, names them;
  rare `**/` patterns inside a wholly ignored folder may differ from Claude
  Code's.
- `watch_dirs` (user file only): folders whose unsaved changes the status
  reports.

**Without a config** the session status (branches, account, effort), the push, pkill and
word guards, the context reminder, the compaction snapshot and log, the
after-handoff skip, the status line (once set up) and the commands work; the
cost guard, agent-launch guard, owed check and ports stay silent.

**Environment variables** (in your shell, or `env` in `settings.json`):

- `GUARDRAILS_WARN_TOKENS` (default `250000`): the context size where the
  status line shows `⚠ hand off` and the reminder starts. The default assumes
  a 1M-token window; on a 200k window compaction comes first, so lower it.
- `GUARDRAILS_PYTHON`: the python to run (default: the first of `python3`,
  `python` and `py` that runs as Python 3.7 or later).
- `GUARDRAILS_UNDO_DAYS`, `GUARDRAILS_UNDO_SECONDS`, `GUARDRAILS_ALLOW_UNDO`:
  the undo check, above.
- `GUARDRAILS_HANDOFF_MAX_TOKENS` (default 900000): above it a compaction is
  never skipped.
- `GUARDRAILS_STATE`, `GUARDRAILS_HANDOFF_WAIT`, `GUARDRAILS_TAIL_BYTES`,
  `GUARDRAILS_JQ`: where the handoff marks live (default
  `${CLAUDE_PLUGIN_DATA}/state`), and settings the tests use.

**What it writes where**: `${CLAUDE_PLUGIN_DATA}` (the plugin's data folder,
deleted when the plugin is uninstalled) holds the status line's copy, the git
hook's copy, the cached `claude` subcommands and the handoff marks. The
memory folder of each repo gets `precompact-snapshot.md` and
`compaction-log.md`. Nothing else is written unless setup or a command you
ask for writes it.

## What it costs

No hook calls a model. The session status's report joins the context at each
session start and compaction: about 100 characters in a repo with no config,
about 3,600 (roughly 900 tokens) in a busy project with one, as measured on
two repos. The three skills' descriptions sit in every session; `claude plugin details guardrails` shows
the always-on total. Skipping a compaction after a handoff means that if you
continue instead of `/clear`, the next reply re-reads the whole conversation
uncached.

Spends only when you choose it:

- `guardrails-handoff-check`: one headless call, about 0.15 USD at API
  prices, counted against usage on a subscription. Off by default; the
  session-handoff skill offers it after a very big session.
- `guardrails-instructions-check`: one headless call per question.
- The undo check's CI workflow: free on a public repo, at least one Actions
  minute a run on a private one.

The idle handoff mode (skip Claude Code's compaction of a session you have
stepped away from, and run the handoff instead while the prompt cache is
warm) is coming in a later version, with a setting to switch it on; it is not
wired in this one. A handoff is many requests, each re-reading the session; a
compaction is one.

## Related skills, not bundled

- apple-design, improve-animations, review-animations:
  https://github.com/emilkowalski/skills (`npx skills@latest add emilkowalski/skills`).
- motion-design: https://github.com/LottieFiles/motion-design-skill
  (`npx skills add LottieFiles/motion-design-skill`).

## Updating

Third-party marketplaces do not update on their own: turn on auto-update in
`/plugin` > Marketplaces, or run `claude plugin update guardrails@guardrails-tools`.
Then start a new session and run `/guardrails:setup` again to refresh the
blocks.

## Uninstalling

1. Ask Claude to run `guardrails-install-git-hooks --remove` in each repo
   that has the hook: it belongs to git, so disabling the plugin does not stop
   it.
2. Remove the `statusLine` entry from `~/.claude/settings.json`.
3. `/plugin uninstall guardrails@guardrails-tools`.

The CLAUDE.md blocks and the memory-folder files stay; delete them by hand if
you want them gone.

## Developing

`bash tests/run.sh` runs every test. It spends nothing: a stub `claude` that
exits 99 is first on PATH. `claude plugin validate --strict .` checks the
manifests. CI runs the tests on Linux, macOS (its own bash 3.2) and Windows;
the browser-testing tests need node there (locally they skip without it).
Bump the version in `.claude-plugin/plugin.json` on every release.

The tests refuse home-folder paths and email addresses in any public file.
If you publish a fork from your own machine, list strings that must never
ship (one a line) in `~/.config/guardrails/private-strings.txt`; the tests
check every file against it.

## Licence

MIT.
