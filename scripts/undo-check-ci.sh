#!/usr/bin/env bash
# undo-check-ci.sh -- the undo check (undo-check.sh) for a GitHub Actions
# pull request: would merging it undo the base branch's recent work? Run from
# the project's checkout, made with `fetch-depth: 0`
# (examples/workflows/undo-check.yml).
#
# A finding is printed as an error annotation and fails the job (exit 1). A
# meant undo passes when the pull request carries the label `undo-ok`: the
# job then prints what the label let through, as a notice. Anything that
# stops the check (not a pull request, the base branch not fetched, no shared
# history, git older than 2.37) is a notice and passes, so a broken check
# never blocks every pull request. The check blocks a merge only where the
# project makes it a required status check.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
LABEL=undo-ok
# One annotation line: GitHub reads %, CR and LF in it as escapes.
note() {
  local m=$2
  m=${m//%/%25}; m=${m//$'\r'/%0D}; m=${m//$'\n'/%0A}
  echo "::$1 title=Undo check::$m"
}
if [ "${GITHUB_EVENT_NAME:-}" != pull_request ] && [ "${GITHUB_EVENT_NAME:-}" != pull_request_target ] \
   || [ -z "${GITHUB_BASE_REF:-}" ]; then
  note notice "not a pull request, so there is nothing to check."
  exit 0
fi
# The pull request's own head: from the event, else the merge commit's second parent.
head=""; labels=""
if [ -f "${GITHUB_EVENT_PATH:-}" ] && gr_jq; then
  head=$(gr_jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null)
  labels=$(gr_jq -r '.pull_request.labels[]?.name' "$GITHUB_EVENT_PATH" 2>/dev/null)
fi
[ -n "$head" ] || head=$(git rev-parse -q --verify HEAD^2 2>/dev/null || git rev-parse -q --verify HEAD 2>/dev/null)
reason=$(bash "$here/undo-check.sh" "$PWD" origin "$head" "" "$GITHUB_BASE_REF" </dev/null); st=$?
if [ "$st" = 2 ]; then
  note notice "could not check this pull request against $GITHUB_BASE_REF (the base branch not fetched -- checkout needs fetch-depth: 0 -- no history in common, or git older than 2.37); passing it unchecked."
  exit 0
elif [ "$st" != 0 ]; then
  note notice "the undo check failed (exit $st); passing this pull request unchecked."
  exit 0
fi
[ -n "$reason" ] || exit 0
if printf '%s\n' "$labels" | grep -qxF "$LABEL"; then
  note notice "the $LABEL label lets this through: $reason."
  exit 0
fi
note error "$reason. If the revert is meant, add the label $LABEL to the pull request."
exit 1
