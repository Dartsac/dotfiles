#!/bin/sh
# Ctrl-h/j/k/l in herdr, like vim-tmux-navigator in tmux.conf: a pane running
# Neovim, Vim or fzf receives the key (Neovim's config/multiplexer.lua hands the
# move back to herdr at its edge split); any other pane moves herdr's focus.
# Usage: navigate.sh left|down|up|right
set -eu

direction=${1:-}
case $direction in
left) key=ctrl+h ;;
down) key=ctrl+j ;;
up) key=ctrl+k ;;
right) key=ctrl+l ;;
*)
	echo "navigate.sh: expected left|down|up|right, got '$direction'" >&2
	exit 2
	;;
esac

case $0 in */*) here=${0%/*} ;; *) here=. ;; esac # also when run as `sh navigate.sh`
. "$here/herdr-bin.sh" # sets $herdr

# Custom shell bindings supply ACTIVE; direct invocations can use the pane's ID.
pane=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
if [ -z "$pane" ]; then
	echo "navigate.sh: no pane ID (run inside herdr)" >&2
	exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
	echo "navigate.sh: jq is required for foreground-process detection" >&2
	exit 127
fi

# Parse only foreground names, independent of JSON whitespace and name casing.
# Keep the same program list as tmux.conf's is_vim, including fzf.
if "$herdr" pane process-info --pane "$pane" |
	jq -e 'any(.result.process_info.foreground_processes[]?;
		.name | ascii_downcase | test("^g?(view|l?n?vim?x?|fzf)(diff)?$"))' >/dev/null; then
	exec "$herdr" pane send-keys "$pane" "$key"
fi
exec "$herdr" pane focus --direction "$direction" --pane "$pane"
