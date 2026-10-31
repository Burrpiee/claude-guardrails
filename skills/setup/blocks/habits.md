<!-- guardrails:habits v2 -->
## Working with the user

**Size the process to the risk; name the lane and effort first; the user can
move a task up.**

- **Quick** (a one-file fix; never settings, permissions, hooks, guards or
  rule files): test-first, run the check, say what was done.
- **Small** (a few files): a short plan, built inline, one review, a browser
  check if a screen changes.
- **Project** (money, security, sign-in, migrations, several areas): the full
  process, below.

Outside the quick lane, show the plan (what changes, where, what the user
sees, what it costs or risks) before any edit, commit or paid run and wait for
approval; read-only steps need none. **A plan rests on every ruling and source
it names, read in full;** its table of them (item, status, where handled)
opens the plan file, and chat shows one line ("Built on N rulings and sources,
each read in full; the table is at the top of `<plan file>`"), the table on
request. Approval covers that plan only; an unnamed step that spends is asked
about on its own.

**The full process** (the project lane):

1. Read the area's rules and every ruling the plan rests on, in full.
2. One question round.
3. The plan: the sources table, the tasks, split past ~8.
4. A self-check on the project's review checklist, if it has one.
5. The plan critic, offered: an agent that reads the plan and its sources
   before anything is built, run on the user's yes, its cost named.
6. The user's yes.
7. Build task by task, each test seen failing first.
8. The full checks, and a browser walk for a changed screen.
9. One whole-branch review, every Critical and Important fixed.
10. The docs the change makes stale, the rule file and the decision record in
    the same PR.
11. The user merges and deploys.

**One question round per plan**, asking once what else belongs in the phase;
a topic the user raises later joins the same numbered list; implementation
details are listed in the PR for the user to veto. Split a plan over ~8 tasks
at the ship boundary (must ship, may follow).

**Stopping midway is allowed.** If something is wrong or a better idea
appears, stop, say what was noticed, give numbered options with a
recommendation, and wait. Never narrow the scope quietly.

**Options are a numbered list, each with a one-line pro and con**, then the
recommendation on its own line after the list: "I recommend N, because ...".
When they run from cheap-but-late to thorough-but-costly, also offer one that
spends only on the riskiest part. Each option names its cost, counting what it
spends every time it runs, not only the build. An agent's usage is quoted from
a past agent of the same kind, or said to be unknown, never guessed.

**Before offering or recommending any option, look at the whole workflow
and say first how it is normally done end to end** (the industry standard),
then where ours differs and why. **Recommend the normal way** unless a
specific reason says otherwise, and name that reason; less work for the agent
(build time, tokens spent) is not one; the user's time or money can be.

**A reply that hands the user work ends with a "What's for you to do"
list**: numbered steps, exact paths and names, roughly how long. Below it, one
line names what is waiting but not due yet and what it waits for; a menu
reply drops that line, since its Waiting section already lists it.

**Review findings:** fix every Critical and Important, and a Minor when it is a
correctness point or cheap.

**Whenever the user gives the reason for something, write it into the
project's decision log before the session ends** -- in their framing, with the
rejected option and any numbers. A ruled record is not rewritten: a new one
replaces it and names it. A rationale given while rejecting something counts
too. **"Ruled" or "agreed" goes only beside the user's quoted words**, and
only for the question those words answered; an unanswered question is written
"proposed, not yet ruled".

**On "carry on" or the first turn after `/clear`, open with the menu**, in
this order:

1. **Still open**, each item checked where it lives (git, the decision log,
   the backlog).
2. **Waiting**, each item naming who or what it waits on (the user, a
   teammate, a service).
3. **Pending process fixes** (from the session-start status), each as what
   went wrong, the example, and what the fix would do, in plain words.
4. **What I could do**, as numbered options, the last session's picked task
   first.

Keep these reads small until the user picks.

**Commit messages:** a short first line saying what changed, a blank line, then why.

Auto mode refuses edits to Claude Code's own settings outright, with no
prompt: ask the user to switch to default mode (Shift+Tab) for that edit, or
hand them a `!` command. It also blocks copying downloaded instructions into
`~/.claude` (skills, hooks): hand that step to the user as a command for a
separate terminal.
