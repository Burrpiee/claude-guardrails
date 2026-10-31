# Instruction test questions

For `guardrails-instructions-check <this file> <launch-dir>`: each row is
asked in its own fresh headless session, and the answer is printed beside
what you expected, for you to grade by hand. Write questions a new session
must answer right from your `CLAUDE.md` and rules, and the facts a right
answer must contain. Check the expected facts against the code when you
write them.

Keep your copy OUTSIDE the repo it tests, so a test session searching the
repo cannot find the expected answers. DRY=1 lists the questions and spends
nothing.

| # | Question | Expected (must contain) |
|---|---|---|
| A01 | How do I run the tests? | the exact test command, and where to run it from |
| A02 | What must never be done without asking first? | each action CLAUDE.md lists under "never", by name |
| A03 | Where does a new setting or flag get documented? | the file that lists them |
