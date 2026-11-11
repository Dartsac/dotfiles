#!/bin/sh
# Sets the workspace token `changes` to "<N> changed" while the workspace's repo
# has uncommitted changes (modified, staged or untracked files), and clears it
# when the repo is clean or the directory isn't a repo. The Spaces sidebar row
# shows $changes beside the branch.
#
# The repo is the workspace's project_path (set by the project picker), else
# its first pane's directory. git runs with --no-optional-locks so this never
# takes index.lock while an agent is committing.
set -eu
. "$HOME/.config/herdr/scripts/herdr-bin.sh" # sets $herdr

event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
only=
if [ "${1:-}" != all ]; then
	# An agent turn is working -> idle: count once, when it settles.
	status=$(printf '%s' "$event" | jq -r '.data.agent_status // empty')
	case $status in
	'' | idle | done | blocked) ;;
	*)
		echo "git-changes: skipped agent $status ($(printf '%s' "$event" | jq -r '.data.pane_id // "?"'))" >&2
		exit 0
		;;
	esac
	# Some events carry only a tab or pane id; those start with the workspace id ("wE:t3").
	only=$(printf '%s' "$event" | jq -r '.data | .workspace_id // ((.tab_id // .pane_id // "") | split(":")[0]) // empty')
	if [ -z "$only" ]; then
		echo "git-changes: no workspace in event: $(printf '%s' "$event" | jq -c '.data // {}')" >&2
		exit 0
	fi
fi

snapshot=$("$herdr" api snapshot)
# One "<workspace id><TAB><directory>" line per workspace.
printf '%s' "$snapshot" | jq -r --arg only "$only" '.result.snapshot as $s
	| $s.workspaces[] | select($only == "" or .workspace_id == $only)
	| .workspace_id as $w
	| [$w, (.tokens.project_path
		// ([$s.panes[] | select(.workspace_id == $w) | .cwd // .foreground_cwd] | first)
		// "")] | @tsv' |
	while IFS="$(printf '\t')" read -r workspace dir; do
		count=
		if [ -n "$dir" ] && [ -d "$dir" ] &&
			git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			count=$(git --no-optional-locks -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
		fi
		echo "git-changes: $workspace: ${count:-not a repo} ($dir)" >&2
		if [ -n "$count" ] && [ "$count" -gt 0 ]; then
			"$herdr" workspace report-metadata "$workspace" --source dotfiles:git-changes \
				--token "changes=$count changed" >/dev/null
		else
			"$herdr" workspace report-metadata "$workspace" --source dotfiles:git-changes \
				--clear-token changes >/dev/null
		fi
	done
