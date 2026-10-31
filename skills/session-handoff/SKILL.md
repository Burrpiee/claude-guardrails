---
name: session-handoff
description: >-
  Save this session's context to the memory directory before "/clear" or a
  compaction, when the user says to wrap up or start fresh, at a natural
  stopping point, or when live external state changed. Rewrites MEMORY.md as the last session's summary, prunes stale memory files,
  records a retro, and checks work is committed and durable facts reached the
  docs. Not for reading memory back at the start of a session.
---

# Session handoff

**At the end of a session, always invoke this skill afresh** -- never work from
a copy loaded earlier. The handoff check is off by default (Finishing, step 1).

**Before launching agent runs that may take over ~10 minutes, write an interim
`MEMORY.md` "Where to resume"** naming the runs and their log: a usage limit
can end the session mid-run with no handoff, and a result kept only in a
gitignored log is then lost.

A cleared session loses everything except what is on disk. This skill decides
what deserves to be on disk, writes it in the memory directory's own format,
and — the part that is easy to skip — corrects the memories this session just
made wrong.

The goal is not a record of the session. It is that the next session can act
without re-deriving. Those are different documents: a transcript summary is
long and mostly worthless, while four sentences about what is actually running
in production can save an hour.

## Where the notes live

Everything below goes in the project's memory folder: Claude Code's own memory
folder for the repo, unless the project's `.claude/guardrails.conf` names
another (`memory =`). `"${CLAUDE_PLUGIN_ROOT}/scripts/config.sh" memory .` prints it.
The notes files this skill keeps there:

- `MEMORY.md` (created when missing): the last session's summary.
- `session-log.md` (created when missing): one line per handoff, the history
  that survives `MEMORY.md` being overwritten.
- `slip-log.md` (created when missing): one line per slip the retro names.
- `pending-improvements.md` (created when missing): proposed fixes the user
  has not yet approved or declined.
- `compaction-log.md` (created when missing, by the plugin's PreCompact
  hooks): one line per compaction. Read it to answer when and why a session
  compacted; never edit it.

The decision log and backlog this skill reads are the ones named in
`.claude/guardrails.conf` (`decisions =`, `backlog =`; defaults
`docs/DECISIONS.md` and `docs/BACKLOG.md`). The decisions may also be a
folder of records, one file each (default `docs/decisions/`); read those
the same way. Skip the steps that need them when the project has neither.

## The two kinds of file, and what each is for

The memory directory holds exactly two things, and confusing them is what makes
handoffs fail:

- **`MEMORY.md` — the last session's summary, and nothing else.** It is
  overwritten every handoff, never appended to. It is the *only* file loaded
  into context automatically, so it is what the next session wakes up knowing:
  what just happened, what is running, what was decided, what is waiting. It is
  **not** an index, not a catalogue of the other files, and not a place to park
  facts that outlive the session.
- **The other `*.md` files — one long-standing fact each.** Traps, closed
  decisions, live external state, how this user works. These persist across many
  sessions and are read on demand, not automatically.

The test for which one a fact goes in: **will this still be true in a month?**
If yes it is a memory file. If it is "where we got to", it is `MEMORY.md` and it
gets overwritten next time.

## Reading it back is not this skill's job

The next session reads the handoff without loading this skill: loading it
there would cost its full length at every session start, and a session that
opens with a task rarely loads it anyway. Three cheap things do the job
instead, so write them well:

- **`MEMORY.md`'s first line** (see "Finishing") tells the next session to
  check every waiting or owed item where it lives before acting or asking.
  Without that line, a session trusts the summary and misses a ruling
  settled after it was written.
- **The plugin's SessionStart hook** prints live git state, the pending
  improvements, and `guardrails-owed-check`'s list of backlog rulings the
  decision log already cites.
- **The "starting a session" habit** (one of the `CLAUDE.md` blocks
  `/guardrails:setup` offers) asks for the menu on "carry on" (still open,
  waiting on you, pending fixes, options), so `MEMORY.md`'s "Where to
  resume" and "Waiting on the user" feed it.

## Before writing anything, read what is already there

Read `MEMORY.md` and skim the existing files. Two things come out of this:

1. **Most of what you want to save probably belongs in a file that already
   exists.** A second file on the same subject is worse than no file, because
   the next session reads both and cannot tell which is current. Updating in
   place is the default; a new file is for a genuinely new subject.
2. **Some of what is there is now false.** This session moved things. Anything
   the session disproved has to be fixed *now* — see "Correct what went stale".

## What is worth saving

The test is: **would the next session have to re-derive this, and would getting
it wrong cost real time?** Prefer few, dense, specific memories.

Worth saving:

- **Live external state the repo cannot show.** What migrations are actually
  applied, what is deployed where, which env flags are set on this machine,
  what exists in the third-party dashboard. This is the highest-value category
  because it is invisible to any amount of code reading.
- **Verified vs assumed.** Say which claims were checked against the real thing
  and which are still inference. A session that proves something end to end
  should record *that it was proved*, and by what method.
- **Decisions and their reasoning** — especially closed ones, recorded so they
  are not reopened. Include the options rejected and why.
- **Traps that cost time**, with the symptom that misleads. The symptom matters
  as much as the cause: it is what the next session will actually see first.
- **Work state**: which branches carry this session's work and what each is
  for, what is deliberately uncommitted, and what the next step was going to
  be. **Not commit ids**: the plugin's SessionStart hook prints live git
  state (every unmerged branch with its tip), so a copied id only goes stale.
- **Dead ends**: what was tried this session and did not work, and why.
  Without them the next session re-attempts the same thing.
- **Background processes and side effects this session started** that outlive
  it — a watcher, a tunnel, a listener, a test fixture left in a vendor
  account. The next session cannot see these and will be baffled by their
  effects. This is the single most-forgotten category. Three kinds that have
  cost real time:
  - **A workflow that failed or is still running:** its run id, where its
    journal is, and which agents finished. Resume works only inside the same
    session; a new session passes the finished agents' results as `args` to a
    new workflow.
  - **Anything in the scratchpad:** it dies with the session. Never leave it
    as the only copy of evidence, a verdict list or a screenshot someone will
    want; move it next to the work or into memory first.
  - **Which directory to launch from:** memory is keyed on the launch
    directory, so a session started elsewhere does not see this `MEMORY.md`.
    Say where the next session should start.
- **Open questions waiting on the user**, so the next session asks once rather
  than guessing or re-asking. **Point, don't copy**: when the question or its
  answer lives in the decision log or backlog, name the entry ("due dates:
  decision 4.2, backlog T.7") rather than restating it, so there is one
  copy to go stale.
  **Never copy the backlog's rulings owed into `MEMORY.md`**: write one line
  pointing at them and list only
  what the backlog does not hold (`grep -n -i 'ruling owed'` on the
  backlog). A summary that still says "ruling owed" after the ruling was
  made leads the next session to ask a settled question again, more often
  than no summary at all would.

Not worth saving — the repo already records it, or it dies with the task:

- Code structure, file layouts, function behaviour. Read the code.
- What a commit changed. Read the diff.
- Anything already written in `CLAUDE.md` or project docs. Duplicating it means
  two copies that drift; if the fact belongs there, put it there instead.
- Blow-by-blow narrative of how a bug was found. Keep the *conclusion* and the
  *symptom*, drop the journey.

If the user asks to remember something in the "not worth saving" list, don't
refuse and don't file it as-is — ask what was non-obvious about it, and save
that. Usually there is a real memory hiding inside the request.

## Correct what went stale

This is the step that gets skipped, and it is where the damage is. A memory
that was true last week and is false today is worse than a missing one: it
reads as current and gets acted on.

Sweep for these specifically:

- **Claims of absence.** "No X has ever been set", "nothing has been run yet",
  "the table is empty". These are the first things a working session
  invalidates. Grep the memory directory for the subject you worked on.
- **Every number.** Counts, totals, "how many are live", backlog sizes, costs.
  These rot fastest and are the most damaging, because a stale number reads
  exactly like a fresh one. If this session measured a figure that a memory
  file states differently, **fix the file now** — do not leave both.
- **Whole files that have been overtaken.** A file whose subject is closed, or
  whose every claim has been superseded, should be **deleted**, not annotated.
  A directory where half the files are half-true is worse than a smaller one
  that is trustworthy. Be ruthless: the next session cannot tell which
  paragraphs still hold.
- **"Still unverified" lists**, once you verify one of the items.
- **Branch and push state**, which changes almost every session.

Prefer revising the sentence over appending a contradiction. Where the old
claim is worth remembering as a correction — because someone might otherwise
re-derive it — strike it and date the replacement:

```markdown
~~The app sends no email~~ — **out of date as of 2026-03-02:**
due-date reminders now go out from the nightly `notify` job.
```

That form is right when the change is surprising or when a previous session
asserted the opposite. For a routine update, just rewrite the sentence; a file
full of strikethroughs is unreadable.

Delete a memory outright when it is simply wrong and nothing is learned from
having believed it.

## Format

Match whatever the directory already does — read a neighbouring file rather
than assuming. The usual shape is one fact per file:

```markdown
---
name: <short-kebab-case-slug>
description: <one line; this is what a future session matches on to decide relevance>
metadata:
  type: user | feedback | project | reference
  last_verified: YYYY-MM-DD
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:**.>
```

**`last_verified`** is the date someone last checked the file against the real
thing. Set it
whenever you write or re-check a file. At handoff, list the files whose date is
more than about four weeks old; re-check or delete the ones this session's work
touched, and name the rest in `MEMORY.md` so the user can decide.

**Do not add an index line to `MEMORY.md`.** It is the last session's
summary, not a catalogue. Files are found by their `description:`, which is
why that field has to be written for retrieval.

Conventions that matter:

- **Absolute dates, always.** "Today", "yesterday", "last week" are wrong the
  moment they are read. Convert as you write.
- **Link related memories** with `[[name]]`. A link to a file that does not
  exist yet is fine — it marks something worth writing.
- **Write the description for retrieval.** It is matched against a future
  situation, so it should name the subject and the situation, not summarise
  the prose. "What broke and how it was fixed" is useless; "which export
  formats have been tried on a real file and which only on samples" is
  findable.
- **Be specific enough to act on.** Names, ids, exact flags, exact error text.
  "There was an API mismatch" is not actionable; "`export --since` is
  rejected by `tool` 2.4 (it arrived in 2.5)" is.

## Finishing

A handoff is not done when the memory files are written. Four things have to be
true before the context is cleared, and only the first is this skill's own work.

1. **`MEMORY.md` rewritten from scratch** as this session's summary, **opening
   with this line** under its heading, naming the project's own files (its
   decision log and backlog; drop the ones it lacks):

   ```markdown
   **Before acting on or asking about anything listed below as waiting or owed,
   check it where it lives -- rulings in `docs/DECISIONS.md`, tasks in
   `docs/BACKLOG.md`, branches in git. This summary predates any later ruling.**
   ```

   Before writing the waiting list, run `guardrails-owed-check`.
   It lists backlog rulings the decision log *mentions* -- a mention is not a
   ruling. Strike a backlog item only when you can quote the decision-log
   sentence recording the user's ruling on that exact question, and put the
   quote in the strike; otherwise leave it and name it in the summary as
   "possibly settled -- check". Then the summary — what
   happened, what is running, what was decided, what is waiting, and the branch
   and commit state. Overwrite it; do not append to the previous session's.
   Write it at the true end: if the user rules on anything after it is
   written, rewrite it. Then **append one line to `session-log.md`** in the
   memory directory (date, a one-line summary, the branches) -- the history
   that survives `MEMORY.md` being overwritten. The handoff check is **off by
   default** (`guardrails-handoff-check` from the launch repo, one headless
   Sonnet call, about 0.15 USD at API prices, counted against usage on a
   subscription): after a very big session (the context past ~350k tokens),
   offer it in one line with its cost, before the final mark; run it only on
   a yes, and read its answers against what you wrote.
   **And stale claims corrected in the memory files**, including deleting any
   that this session has made obsolete. Both halves, every time: the summary
   without the pruning is how a directory of confident, wrong facts accumulates.

2. **Finished work committed and pushed; half-done work written down, not
   finished.** Work that is complete and passing its tests is committed and
   pushed, not *reported*: the next session reads the branch, not the
   transcript, and "it's in memory" does not survive a lost worktree. Name the
   branch each piece of work is on. **Push the open feature branch without
   asking; ask before pushing the default branch**, which may deploy.
   **Edit no code during a handoff** -- work
   that is half-done or failing stays as it is: under "Not done" in
   `MEMORY.md`, name its files, what fails and why, and the next step. Fixing
   it now is new work the user has not approved, and a wrap-up in a hurry
   tends to patch a test to make half-done work committable.
   Where something is deliberately uncommitted, name the file and the reason, so
   it reads as a decision rather than an oversight.

3. **Durable facts written to the project's own docs, not to memory.** A closed
   decision belongs in the decision log; a changed contract belongs in the
   architecture document that describes it; a rule the next agent must follow
   belongs in the instructions file. Memory is for what the repo cannot show —
   live external state, work state, open questions. Anything that belongs in a
   doc and gets put in memory instead becomes two copies that drift, and the
   one in memory is the one nobody maintains.
   Then audit the project's docs for statements this session made false: in
   the decision log, edit the entry, re-read it whole and sweep it for
   self-contradiction; in any architecture doc, bump its "Last verified" date
   and say what moved.

4. **A size check.** `wc -l` the project `CLAUDE.md` files and flag any over
   about 200 lines, naming what could move to a path-scoped `.claude/rules/`
   file or a skill. Keep `MEMORY.md` well under what auto-loads (its first 200
   lines / 25KB). A trap now covered by a code fix plus a test leaves
   `CLAUDE.md`: its one-line lesson may stay, the story goes to the decision
   log or a history doc.

## A retro, so each session improves the next

Before telling the user you are done, answer three questions in a line or two
each:

1. What cost the most time or tokens this session, and why?
2. Which instruction (`CLAUDE.md`, a skill, a memory) was wrong, stale, ignored
   or missing?
3. What did the user have to correct or repeat?

**Note every slip; propose a fix for few.** One new rule per slip piles up
into instruction files that get ignored. Add each slip the answers name to
`slip-log.md` in the memory directory -- one line, the date and what went
wrong -- and delete its lines older than 30 days. A slip earns a proposed fix
only if `slip-log.md` already holds the same kind of slip, or it cost money, a
paid re-run or lost work; otherwise the log line is the whole response. **At
most one proposal per handoff**; none is the usual answer.

Route a proposal to the cheapest durable fix, in this order: a code fix plus a
test (no text needed at all); a hook (enforced, costs no context); a
path-scoped rule in `.claude/rules/`; a skill edit; a line in `CLAUDE.md` that
replaces or shortens one already there -- **never a new paragraph**. The files
that load every session can have word budgets (`words = <file> <max>` in
`.claude/guardrails.conf`, or `~/.claude/guardrails.conf` for your own), and
the session-start hook names any file over its budget. Propose the fix; apply a change to an
instruction file only when the user asks. Put the retro in `MEMORY.md` so the
next session sees it, **and copy every proposal not applied this session into
`pending-improvements.md`** in the memory directory (create it if absent): one
line each with the date, the symptom that prompted it and the proposed fix.
Remove a line once the user has approved and it is applied, or declined it.
`MEMORY.md` is overwritten every handoff; this file is what carries an
unapproved fix forward.

**The very last action, just before telling the user you are done:** run
`GUARDRAILS_STATE="${CLAUDE_PLUGIN_DATA}/state" "${CLAUDE_PLUGIN_ROOT}/scripts/precompact-handoff.sh" mark </dev/null`.
It tells a hook the handoff is finished, so Claude Code does not compact the
idle session before the user's `/clear`: the handoff already saved what a
summary would keep, so the compaction would only spend. Any message from the
user afterwards lifts it, so if you offered the handoff check, wait for the
answer first: on a yes, run it and read its answers, then run the mark.

## When tools are blocked

If Bash, git or edits outside the memory directory are unavailable (for
example the auto-mode check failing with "gave no verdict (error)"), still write
memory: the memory directory usually keeps working. Under "Not done" in
`MEMORY.md`, list the exact uncommitted work and the commands that would commit
and push it, and do **not** report the handoff as complete. Tell the user which
of the finishing steps could not run.

Then tell the user what you wrote, what you revised, what you deliberately left
out and the retro's proposals — the omissions are a judgement call and they may
disagree. Keep it to a few lines; they are about to clear the context, so a long
summary is wasted.
