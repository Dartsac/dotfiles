#!/bin/sh
# prefix+e in herdr, like tmux.conf's `kill-pane -a`: close every pane in the
# focused tab except the focused one.
set -eu

case $0 in */*) here=${0%/*} ;; *) here=. ;; esac # also when run as `sh close-other-panes.sh`
. "$here/herdr-bin.sh" # sets $herdr

"$herdr" pane list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" |
	jq -r --arg tab "$HERDR_ACTIVE_TAB_ID" --arg keep "$HERDR_ACTIVE_PANE_ID" \
		'.result.panes[] | select(.tab_id == $tab and .pane_id != $keep) | .pane_id' |
	while read -r pane; do
		"$herdr" pane close "$pane" >/dev/null
	done
