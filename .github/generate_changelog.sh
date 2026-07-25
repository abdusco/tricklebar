#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate_changelog.sh [<git-log-range>]
#
# Groups commits by their conventional-commit prefix (feat, fix, ...) into
# sections. Commits within each section are sorted oldest-first. Commits
# that don't match a known prefix land in an "Other" section.

range="${1:-}"

types="feat fix refactor perf docs test ci build chore"

label_for() {
  case "$1" in
    feat) echo "Features" ;;
    fix) echo "Fixes" ;;
    refactor) echo "Refactoring" ;;
    perf) echo "Performance" ;;
    docs) echo "Documentation" ;;
    test) echo "Tests" ;;
    ci) echo "CI" ;;
    build) echo "Build" ;;
    chore) echo "Chores" ;;
    *) echo "Other" ;;
  esac
}

commits=$(git log ${range} --reverse --pretty='format:%s')
known_pattern="^(feat|fix|refactor|perf|docs|test|ci|build|chore): "

first_section=1
for type in $types other; do
  if [ "$type" = "other" ]; then
    entries=$(printf '%s\n' "$commits" | grep -v -E "$known_pattern" | sed 's/^/- /' || true)
  else
    entries=$(printf '%s\n' "$commits" | grep -E "^${type}: " | sed -E "s/^${type}: /- /" || true)
  fi

  [ -z "$entries" ] && continue
  [ "$first_section" -eq 0 ] && echo
  first_section=0

  printf '### %s\n\n%s\n' "$(label_for "$type")" "$entries"
done
