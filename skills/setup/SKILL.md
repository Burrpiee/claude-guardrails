---
name: setup
description: >-
  Set up the guardrails plugin for a user or a project: offer the CLAUDE.md
  blocks (working habits, explaining terms, compact instructions, lessons)
  one by one, a project config, git's pre-push hook for the undo check, the
  attribution setting, and the status line, writing only what the user
  accepts. Use when the user runs /guardrails:setup, asks to set up or
  configure the guardrails plugin, or wants its blocks refreshed after an
  update.
---

# Set up guardrails

Write nothing the user has not accepted. Show each thing first, ask yes or no,
and move on.

## 1. Check jq

Run `command -v jq`. If it prints nothing, say this line, then carry on with
the rest (the blocks and config need no jq):

> jq is missing, so every command will be refused until it's installed --
> install it in a terminal outside Claude Code (Windows: winget install
> jqlang.jq; Mac: brew install jq; Linux: your package manager), then start a
> new session.

## 2. The CLAUDE.md blocks

They are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/blocks/`:

- `blocks/habits.md` -- how to work with the user: the three lanes (quick,
  small, project) and the full process, plans resting on sources read in
  full, one question round, options with costs, the normal way first, a
  "What's for you to do" list, review findings, recording the user's
  reasons, the menu on "carry on", the commit message layout, and the
  auto-mode trap.
- **Explaining terms**, one block in two versions. Ask which of three the
  user wants: *off* (nothing written), *with context* (the default:
  `blocks/explain.md`, every term the user may not know comes with what it is
  and why it matters here), or *with context and learning*
  (`blocks/explain-learning.md`, the workflow's own terms explained too, for
  someone learning the workflow). Both versions share one marker, so
  choosing again replaces the other; for *off* where a block was written
  before, run `guardrails-write-block --remove explain CLAUDE.md` from the
  repo root; for their own file, hand them this as for writing it below (on
  Windows, in Git Bash):
  `bash "${CLAUDE_PLUGIN_ROOT}/bin/guardrails-write-block" --remove explain ~/.claude/CLAUDE.md`.
- `blocks/compact.md` -- what a compaction must keep word for word.
- `blocks/lessons.md` -- five traps that cost time before.

For each: read the file, show its text to the user, and ask whether they want
it. Then ask once where the accepted blocks go:

- **This project's `CLAUDE.md`** (shared with everyone on the repo): for each
  accepted block run
  `guardrails-write-block "${CLAUDE_PLUGIN_ROOT}/skills/setup/blocks/<name>.md" CLAUDE.md`
  from the repo root, and report what it printed (`added`, `updated` or
  `unchanged`).
- **Their own `~/.claude/CLAUDE.md`** (every project, only them): auto mode
  refuses writes into `~/.claude`, so do not write it. Print one command per
  accepted block, with the plugin path written out in full, for the user to
  run in a separate terminal (on Windows, in Git Bash):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/bin/guardrails-write-block" "${CLAUDE_PLUGIN_ROOT}/skills/setup/blocks/<name>.md" ~/.claude/CLAUDE.md
  ```

Each block sits between `<!-- guardrails:<name> vN -->` and
`<!-- /guardrails:<name> -->`, so running setup again replaces it in place and
never adds it twice. Text outside the markers keeps its bytes, except that a
last line with no line ending gets one.

## 3. The project config

Offer `${CLAUDE_PLUGIN_ROOT}/examples/guardrails.conf` as this repo's
`.claude/guardrails.conf`: show it, and say what it does -- the cost guard asks
before the commands it names, the partners' guards apply too, and the owed
check and handoff skill read the decision log (or folder of records) and
backlog it names. Every line ships commented out; ask which ones to turn on. If the file already exists,
show the difference and change nothing unasked.

Machine-specific values (`memory`, `ports`, `smoke`, `worktree_links`) belong
in `.claude/guardrails.local.conf`, which git must ignore. Show the line
`.claude/guardrails.local.conf` and, if accepted, add it to the repo's
`.gitignore`. Small git-ignored files a review worktree needs, such as a
`.env`, are copied rather than linked when the repo's `.worktreeinclude` (the
list Claude Code reads for its own worktrees) names them.

## 4. The undo check inside git push

The push guard asks before a push from Claude that would put files back as
they were before the default branch's recent work (a branch rebuilt from an
older copy of the files). Git's own pre-push hook makes the same check inside
every `git push`, from a terminal or an IDE too, and sees a commit made in
the same command as the push. Offer it for this repo (and its partners). If
the user wants it, run, with the data folder written out in full:

```bash
guardrails-install-git-hooks --data "${CLAUDE_PLUGIN_DATA}"
```

It writes a small `.git/hooks/pre-push` in each repo, and never replaces a
hook the repo already has. Say that the hook belongs to git, not Claude Code:
disabling the plugin does not stop it, so before uninstalling the plugin run
`guardrails-install-git-hooks --remove`. A meant revert is pushed with
`GUARDRAILS_ALLOW_UNDO=1` after the user says so. For pull requests, a
project can also copy `${CLAUDE_PLUGIN_ROOT}/examples/workflows/undo-check.yml`
into `.github/workflows/`.

## 5. Attribution

By default Claude Code adds a `Co-Authored-By` trailer to the commits it
makes and a line to pull request descriptions. Offer to turn that off; this
plugin's suggestion is the opposite of Claude Code's default, so say so and
let the user choose. Two parts, each only on a yes:

1. The setting. Run `claude --version`. From 2.1.281 the setting is
   `"attribution": false`; an older version rejects that value and skips the
   whole settings file holding it, so there show
   `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` instead.
   Show it for `~/.claude/settings.json` (every project, only them); when the
   blocks went into this project's `CLAUDE.md`, offer this project's
   `.claude/settings.json` too, so teammates' commits match. Auto mode refuses
   edits to Claude Code's own settings, so ask the user to switch to default
   mode (Shift+Tab) for that edit, or to paste it in themselves.
2. `blocks/attribution.md`, the same in words for the CLAUDE.md the other
   blocks went into, written like them.

## 6. The status line

The status line shows the session's context size and branch, e.g.
`ctx 63k · main`, with `⚠ hand off` past 250k tokens. A plugin cannot set it,
and the plugin's own folder moves on every update, so it runs from a copy in
the plugin's data folder. If the user wants it:

1. Copy it yourself:
   `mkdir -p "${CLAUDE_PLUGIN_DATA}" && cp "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh" "${CLAUDE_PLUGIN_DATA}/statusline.sh"`
   (the session-start hook refreshes this copy after each update).
2. Show the setting to add to `~/.claude/settings.json`, the path written out
   in full. On Windows, write it with forward slashes (`C:/Users/...`): a
   single backslash is not valid JSON, and Git Bash takes either form.

   ```json
   {"statusLine": {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_DATA}/statusline.sh\""}}
   ```

   Auto mode refuses edits to Claude Code's own settings, so ask the user to
   switch to default mode (Shift+Tab) for that edit, or to paste it in
   themselves. If `statusLine` is already set, show both and let them choose.

## 7. Finish

List what was written and where, and what was handed to the user to run. Say
that after a plugin update, running `/guardrails:setup` again refreshes the
blocks.
