#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the most recent session trail
# that operated in it (optional input). Emits a table sorted by size with a
# suggested bucket. Never deletes anything; deletion stays a human-gated step
# in the worktree-cleanup playbook.
#
# Usage: worktree-audit.sh [repo-path] [trails-dir]
#   repo-path   defaults to the current repo
#   trails-dir  a directory of session trail files (resume notes, decision
#               logs, run state). Optional; also read from DF_TRAILS_DIR.
#               Without it the LAST_TRAIL column is "-" and no worktree can
#               be classified verify-recent-trail.
set -u

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1

trails="${2:-${DF_TRAILS_DIR:-}}"

# Portable helpers: GNU first, BSD fallback.
mtime_of() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null; }
day_of() { date -d "@$1" '+%Y-%m-%d' 2>/dev/null || date -r "$1" '+%Y-%m-%d' 2>/dev/null; }
match_files() { # fixed-string search for "$2" or "$3" under dir "$1", one path per line
	if command -v rg >/dev/null 2>&1; then
		rg -lF -e "$2" -e "$3" "$1" 2>/dev/null
	else
		grep -rlF -e "$2" -e "$3" "$1" 2>/dev/null
	fi
}

# Main worktree is the first entry; everything else is a candidate.
main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

# The default branch drives the merge check. Best-effort; stale is fine for a
# first pass.
base_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -z "$base_branch" ] && base_branch=main
git fetch origin "$base_branch" --quiet 2>/dev/null \
	|| echo "warn: could not fetch origin/$base_branch; merged column may be stale" >&2

# PR state by branch, fetched once. Empty if gh is unavailable.
prs=$(mktemp)
gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null > "$prs" || echo "[]" > "$prs"

now=$(date +%s)

printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_TRAIL\tBUCKET\tWORKTREE\n"

git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
	[ "$wt" = "$main_wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of the base branch, so PR state
	# is the real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" "origin/$base_branch" 2>/dev/null && merged=YES || merged=no

	# Distinguish real WIP (tracked edits) from disposable untracked scratch.
	porcelain=$(git -C "$wt" status --porcelain 2>/dev/null)
	if [ -z "$porcelain" ]; then dirty=clean
	elif printf '%s\n' "$porcelain" | grep -qv '^??'; then
		dirty="wip:$(printf '%s\n' "$porcelain" | grep -cv '^??')"
	else dirty="scratch:$(printf '%s\n' "$porcelain" | grep -c '^??')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.headRefName==$b) | "#\(.number)/\(.state)"' "$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	# Most recent session trail that operated in this worktree. Match the path
	# followed by "/" or a quote so repo-x does not match repo-x-r37. Optional:
	# skipped entirely when no trails dir was given.
	last="-"; last_ts=0
	if [ -n "$trails" ] && [ -d "$trails" ]; then
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			ts=$(mtime_of "$f")
			[ -n "$ts" ] && [ "$ts" -gt "$last_ts" ] 2>/dev/null && last_ts=$ts
		done <<-EOF
		$(match_files "$trails" "${wt}/" "${wt}\"")
		EOF
		[ "$last_ts" -gt 0 ] && last=$(day_of "$last_ts")
	fi
	recent=$([ "$last_ts" -gt 0 ] 2>/dev/null && [ $(( (now - last_ts) / 86400 )) -le 4 ] && echo yes || echo no)

	case "$dirty" in wip:*) bucket=hold-wip ;; *)
		case "$pr" in *OPEN*) bucket=hold-open-pr ;; *)
			if [ "$recent" = yes ]; then bucket=verify-recent-trail
			elif [ "$merged" = YES ] || [ "$pr" != "-" ]; then bucket=safe
			else bucket=review; fi ;;
		esac ;;
	esac

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh

rm -f "$prs"
