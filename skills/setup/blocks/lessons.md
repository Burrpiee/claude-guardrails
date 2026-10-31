<!-- guardrails:lessons v1 -->
## Lessons that cost time before

- **Every number in a note is a lead, not a fact.** Re-measure before quoting
  one.
- **`cmd | tail -1 && git commit` commits on a failing run**: the pipe's exit
  is `tail`'s. Run tests as their own step and read the count.
- **When an AI result looks wrong, read what it actually said** and check your
  own code that handles it before blaming the model or re-running it.
- **Use absolute paths in shell commands**; an agent shell's working directory
  persists between commands.
- **A value copied in several files changes in all of them together.**
