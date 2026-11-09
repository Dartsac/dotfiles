#!/bin/sh
# Away alert: a card when an agent is done or needs input, only while Ghostty
# is not the frontmost app. With Ghostty in front, herdr's own sound and toast
# are the only signal.
# Hammerspoon shows it (hammerspoon/.config/hammerspoon/herdr_alert.lua), and
# a click returns to the agent. Runs as a herdr event hook; decisions are
# logged to `herdr plugin log list`.
set -eu

event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
field() {
	printf '%s' "$event" | jq -r "$1 // empty"
}

status=$(field .data.agent_status)
case $status in
done | idle) what="is done" ;;
blocked) what="needs input" ;;
*) exit 0 ;;
esac

# Appear with herdr's own alert: herdr waits ui.toast.delay_seconds (default 1)
# and alerts only if the state still holds, so wait and recheck the same way.
sleep 1

if lsappinfo info -only bundleid "$(lsappinfo front)" | grep -q '"com.mitchellh.ghostty"'; then
	echo "away-alert: Ghostty is frontmost; herdr's own alert applies" >&2
	exit 0
fi

herdr=${HERDR_BIN_PATH:-$(command -v herdr)}
agent=$(field '.data.display_agent // .data.agent')
workspace=$(field .data.workspace_id)
pane=$(field .data.pane_id)

# A finish is "done" when herdr thinks you have not seen it, but "idle" when
# the pane was on screen, even with Ghostty behind another app. herdr marks
# both as finished work with completion_seq (equal to the state change's
# state_change_seq); starting or restoring an agent goes idle without one.
# Viewing a done agent turns it idle with the same completion_seq, so each
# terminal's last alerted completion is remembered to alert once.
info=$("$herdr" agent get "$pane" 2>/dev/null) || exit 0
if [ "$status" = blocked ]; then
	if [ "$(printf '%s' "$info" | jq -r '.result.agent.agent_status')" != blocked ]; then
		echo "away-alert: no longer blocked" >&2
		exit 0
	fi
else
	completion=$(printf '%s' "$info" | jq -r '.result.agent |
		select(.agent_status == "idle" or .agent_status == "done") |
		select(.completion_seq != null and .completion_seq == .state_change_seq) |
		"\(.terminal_id) \(.completion_seq)"')
	if [ -z "$completion" ]; then
		echo "away-alert: $status is not a finished task" >&2
		exit 0
	fi
	terminal=${completion% *}
	ledger="${HERDR_PLUGIN_STATE_DIR:?}/alerted-$terminal"
	if [ "$(cat "$ledger" 2>/dev/null)" = "${completion#* }" ]; then
		echo "away-alert: already alerted for this finish" >&2
		exit 0
	fi
	printf '%s\n' "${completion#* }" >"$ledger"
fi

# herdr plays its sound only for agents in background workspaces. The card
# plays one only when herdr will not: the agent is in the workspace on screen.
label=
sound=0
if [ -n "$workspace" ]; then
	ws=$("$herdr" workspace get "$workspace") || ws='{}'
	label=$(printf '%s' "$ws" | jq -r '.result.workspace.label // empty')
	if [ "$(printf '%s' "$ws" | jq -r '.result.workspace.focused // false')" = true ]; then
		sound=1
	fi
fi

url=$(jq -rn \
	--arg title "${agent:-Agent} $what" --arg body "$label" --arg workspace "$workspace" \
	--arg pane "$pane" --arg bin "$herdr" --arg socket "${HERDR_SOCKET_PATH:-}" --arg sound "$sound" \
	'"hammerspoon://herdr-alert?" + ([
		["title", $title], ["body", $body], ["workspace", $workspace],
		["pane", $pane], ["bin", $bin], ["socket", $socket], ["sound", $sound]
	] | map("\(.[0])=\(.[1] | @uri)") | join("&"))')
open -g "$url"
echo "away-alert: sent: ${agent:-Agent} $what ($label)$([ "$sound" = 1 ] && echo ', with sound' || echo ', herdr plays the sound')" >&2
