#!/bin/sh
# Ctrl-h/j/k/l in herdr, like vim-tmux-navigator in tmux.conf: a pane running
# Neovim, Vim or fzf receives the key (Neovim's config/multiplexer.lua hands the
# move back to herdr at its edge split), and a pane running fish receives
# Ctrl-j/k (they move through its completion pager, else fish's
# functions/pager_or_pane.fish moves herdr's focus). Any other pane moves
# herdr's focus. Not Ctrl-h/l to fish: a terminal can send Ctrl-h as Backspace.
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

# Parse only foreground names, independent of JSON whitespace and name casing:
# fish sits under every command it starts (an agent), and those keep pane
# navigation. Keep the same program lists as tmux.conf's is_vim (with fzf) and
# is_fish.
programs='g?(view|l?n?vim?x?|fzf)(diff)?'
case $direction in down | up) programs="$programs|fish" ;; esac
if "$herdr" pane process-info --pane "$pane" |
	jq -e --arg programs "^($programs)\$" 'any(.result.process_info.foreground_processes[]?;
		.name | ascii_downcase | test($programs))' >/dev/null; then
	exec "$herdr" pane send-keys "$pane" "$key"
fi
exec "$herdr" pane focus --direction "$direction" --pane "$pane"
