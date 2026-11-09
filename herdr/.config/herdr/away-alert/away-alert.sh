#!/bin/sh
# Away alert: a macOS notification when an agent is done or needs input, only
# while Ghostty is not the frontmost app. With Ghostty in front, herdr's own
# sound and toast are the only signal.
# Hammerspoon posts it (hammerspoon/.config/hammerspoon/herdr_alert.lua), with
# a sound and a click that returns to the agent. Runs as a herdr event hook;
# decisions are logged to `herdr plugin log list`.
set -eu

event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
field() {
	printf '%s' "$event" | jq -r "$1 // empty"
}

case $(field .data.agent_status) in
done) what="is done" ;;
blocked) what="needs input" ;;
*) exit 0 ;;
esac

if lsappinfo info -only bundleid "$(lsappinfo front)" | grep -q '"com.mitchellh.ghostty"'; then
	echo "away-alert: Ghostty is frontmost; herdr's own alert applies" >&2
	exit 0
fi

herdr=${HERDR_BIN_PATH:-$(command -v herdr)}
agent=$(field '.data.display_agent // .data.agent')
workspace=$(field .data.workspace_id)
pane=$(field .data.pane_id)
label=
if [ -n "$workspace" ]; then
	label=$("$herdr" workspace get "$workspace" | jq -r '.result.workspace.label // empty') || label=
fi

url=$(jq -rn \
	--arg title "${agent:-Agent} $what" --arg body "$label" --arg workspace "$workspace" \
	--arg pane "$pane" --arg bin "$herdr" --arg socket "${HERDR_SOCKET_PATH:-}" \
	'"hammerspoon://herdr-alert?" + ([
		["title", $title], ["body", $body], ["workspace", $workspace],
		["pane", $pane], ["bin", $bin], ["socket", $socket]
	] | map("\(.[0])=\(.[1] | @uri)") | join("&"))')
open -g "$url"
echo "away-alert: sent: ${agent:-Agent} $what ($label)" >&2
