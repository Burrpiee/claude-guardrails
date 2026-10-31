#!/usr/bin/env bash
# tests/habits-drift.sh [habits-source] -- maintainer only. skills/setup/
# blocks/habits.md is copied, generalised, from the maintainer's own
# CLAUDE.md. habits-source (default ~/.config/guardrails/habits-source) holds
# that file's path on line 1 and the commit it was copied at on line 2. Prints
# one WARN line naming the commits since, when the file changed; silent
# otherwise and wherever the file is missing. Never fails.
hs=${1:-$HOME/.config/guardrails/habits-source}
[ -f "$hs" ] || exit 0
src=$(sed -n 1p "$hs"); at=$(sed -n 2p "$hs")
case "$src" in "~/"*) src="$HOME/${src#??}" ;; esac
d=$(dirname "$src"); f=$(basename "$src")
later=$(git -C "$d" log --format='%h %s' "$at..HEAD" -- "$f" 2>/dev/null | tr '\n' ';' | sed 's/;$//; s/;/; /g')
git -C "$d" diff --quiet "$at" -- "$f" 2>/dev/null || later="${later:+$later; }uncommitted changes"
[ -n "$later" ] && echo "WARN: $src changed since habits.md was copied from it at $at: $later -- compare and refresh skills/setup/blocks/habits.md"
exit 0
