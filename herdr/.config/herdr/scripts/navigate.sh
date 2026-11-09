#!/bin/sh
# Ctrl-h/j/k/l in herdr, like vim-tmux-navigator in tmux.conf: a pane running
# Neovim, Vim or fzf receives the key (Neovim's config/multiplexer.lua hands the
# move back to herdr at its edge split); any other pane moves herdr's focus.
# Usage: navigate.sh left|down|up|right
set -eu

case $1 in
left) key=ctrl+h ;;
down) key=ctrl+j ;;
up) key=ctrl+k ;;
right) key=ctrl+l ;;
*)
	echo "navigate.sh: unknown direction '$1'" >&2
	exit 2
	;;
esac

herdr=${HERDR_BIN_PATH:-herdr}
pane=$HERDR_ACTIVE_PANE_ID

# Same program list as tmux.conf's is_vim, matched against process names.
if "$herdr" pane process-info --pane "$pane" |
	grep -Eq '"name":"g?(view|l?n?vim?x?|fzf)(diff)?"'; then
	exec "$herdr" pane send-keys "$pane" "$key"
fi
exec "$herdr" pane focus --direction "$1" --pane "$pane"
