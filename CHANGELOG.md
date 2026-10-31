# Changelog

All notable changes to this plugin are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The README's install steps for a teammate on project scope: the install
  command alone fails on a clean machine, so the marketplace comes first.

### Planned

- Eval cases for the session-handoff skill in a later version.
- The idle handoff mode, with a setting to switch it on, in a later version.

## [0.1.0] - 2026-10-31

### Added

- Guards on shell commands: the cost guard (asks before the commands a
  project names), the push guard (asks before pushing to a merged or deleted
  branch, before a push that would undo the default branch's recent work, and
  before a push that skips git's hooks), the pkill guard, and the claude word
  guard (refuses `claude <word>` that would run as a paid prompt).
- The agent-launch guard, off unless a project turns it on.
- The undo check in three places: the push guard, git's pre-push hook
  (`guardrails-install-git-hooks`), and a workflow to copy for every pull
  request (`examples/workflows/undo-check.yml`, with the `undo-ok` label).
- The session status at each session start: branches, unmerged work, the
  account, the effort level, dev ports, watched folders, process fixes,
  instruction sizes, and backlog rulings the decision log or records cite.
- The context reminder, the status line, the compaction snapshot and log,
  and the after-handoff skip.
- Commands: `guardrails-owed-check`, `guardrails-handoff-check`,
  `guardrails-instructions-check`, `guardrails-session-messages`,
  `guardrails-review-worktree`, `guardrails-install-git-hooks`,
  `guardrails-write-block`.
- Skills: `/guardrails:setup` (the CLAUDE.md blocks, explaining terms at
  three levels, the project config, the git hook, attribution, the status
  line), `session-handoff` and `browser-testing`.

[Unreleased]: https://github.com/Burrpiee/claude-guardrails/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Burrpiee/claude-guardrails/releases/tag/v0.1.0
