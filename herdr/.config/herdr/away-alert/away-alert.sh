#!/bin/sh
# Away alert: a card when an agent is done or needs input, only while Ghostty
# is not the frontmost app. With Ghostty in front, herdr's own sound and toast
# are the only signal.
# Hammerspoon shows it (hammerspoon/.config/hammerspoon/herdr_alert.lua), and
# a click returns to the agent. Runs as a herdr event hook; decisions are
# logged to `herdr plugin log list`.
set -eu

# status, agent, workspace and pane, read from the event in one jq call.
event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
fields=$(printf '%s' "$event" | jq -r '.data | @sh "
	status=\(.agent_status // "") agent=\(.display_agent // .agent // "")
	workspace=\(.workspace_id // "") pane=\(.pane_id // "")"')
eval "$fields"
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

# The plugin runs from its own folder; the shared lookup is with the scripts.
. "$HOME/.config/herdr/scripts/herdr-bin.sh" # sets $herdr

# A finish is "done" when herdr thinks you have not seen it, but "idle" when
# the pane was on screen, even with Ghostty behind another app. herdr marks
# both as finished work with completion_seq (equal to the state change's
# state_change_seq); starting or restoring an agent goes idle without one.
# Viewing a done agent turns it idle with the same completion_seq, so each
# terminal's last alerted completion is recorded, after delivery, to alert once.
ledger=
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
	completion_seq=${completion#* }
	ledger="${HERDR_PLUGIN_STATE_DIR:?}/alerted-$terminal"
	# herdr can run two handlers for one finish at once (done, then idle).
	# mkdir is atomic, so only one claims it; a claim left by a killed handler
	# blocks only this finish, never later ones. Check the ledger after
	# claiming: the other handler may have delivered and released its claim.
	claim="$ledger.$completion_seq.sending"
	if ! mkdir "$claim" 2>/dev/null; then
		echo "away-alert: another handler is alerting for this finish" >&2
		exit 0
	fi
	trap 'rmdir "$claim"' EXIT
	if [ "$(cat "$ledger" 2>/dev/null)" = "$completion_seq" ]; then
		echo "away-alert: already alerted for this finish" >&2
		exit 0
	fi
fi

label=
if [ -n "$workspace" ]; then
	label=$("$herdr" workspace get "$workspace" | jq -r '.result.workspace.label // empty') || label=
fi

url=$(jq -rn \
	--arg status "$status" --arg title "${agent:-Agent} $what" --arg body "$label" \
	--arg workspace "$workspace" --arg pane "$pane" --arg socket "${HERDR_SOCKET_PATH:-}" \
	'"hammerspoon://herdr-alert?" + ([
		["status", $status], ["title", $title], ["body", $body], ["workspace", $workspace],
		["pane", $pane], ["socket", $socket]
	] | map("\(.[0])=\(.[1] | @uri)") | join("&"))')
open -g "$url"
if [ -n "$ledger" ]; then
	printf '%s\n' "$completion_seq" >"$ledger"
fi
echo "away-alert: sent: ${agent:-Agent} $what ($label)" >&2
