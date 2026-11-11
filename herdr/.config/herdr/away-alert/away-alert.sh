#!/bin/sh
# A revalidated, deduplicated away-only card. Native Herdr supplies the sound.
# Hammerspoon watches the delivered identity and removes resolved/stale cards.
set -eu

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

sleep 1 # Match ui.toast.delay_seconds; never deliver an obsolete transition.
if lsappinfo info -only bundleid "$(lsappinfo front)" | grep -q '"com.mitchellh.ghostty"'; then
 echo "away-alert: Ghostty is frontmost; herdr's own alert applies" >&2
 exit 0
fi
. "$HOME/.config/herdr/scripts/herdr-bin.sh"
info=$("$herdr" agent get "$pane" 2>/dev/null) || exit 0
if [ "$status" = blocked ]; then
 if [ "$(printf '%s' "$info" | jq -r '.result.agent.agent_status')" != blocked ]; then
  echo "away-alert: no longer blocked" >&2
  exit 0
 fi
 fields=$(printf '%s' "$info" | jq -r '.result.agent | @sh "
  terminal=\(.terminal_id) completion=\("") attention=\(.tokens["attention-id"] // "")
  title=\(.tokens["attention-title"] // "") detail=\(.tokens.activity // "")
  identity=\("blocked-" + (.tokens["attention-id"] // (.state_change_seq | tostring)))"')
else
 fields=$(printf '%s' "$info" | jq -r '.result.agent |
  select(.agent_status == "idle" or .agent_status == "done") |
  select(.completion_seq != null and .completion_seq == .state_change_seq) |
  @sh "terminal=\(.terminal_id) completion=\(.completion_seq | tostring)
   attention=\("") title=\(.tokens["completion-title"] // "")
   detail=\(if .tokens["completion-title"] then .tokens.activity // "" else "" end)
   identity=\("completion-" + (.completion_seq | tostring))"')
 if [ -z "$fields" ]; then
  echo "away-alert: $status is not a finished task" >&2
  exit 0
 fi
fi
eval "$fields"
# API IDs are data, never path components unless restricted to this alphabet.
case $terminal in '' | *[!A-Za-z0-9_-]*) exit 0 ;; esac
case $identity in '' | *[!A-Za-z0-9:_-]*) exit 0 ;; esac
ledger="${HERDR_PLUGIN_STATE_DIR:?}/alerted-$terminal"
claim="$ledger.$identity.sending"
if ! mkdir "$claim" 2>/dev/null; then
 echo "away-alert: another handler is alerting for this event" >&2
 exit 0
fi
trap 'rmdir "$claim"' EXIT
recorded=$(cat "$ledger" 2>/dev/null) || recorded=
# Older versions stored a bare completion sequence; don't re-alert that finish.
if [ "$recorded" = "$identity" ] || { [ -n "$completion" ] && [ "$recorded" = "$completion" ]; }; then
 echo "away-alert: already alerted for this event" >&2
 exit 0
fi

label=
if [ -n "$workspace" ]; then
 label=$("$herdr" workspace get "$workspace" | jq -r '.result.workspace.label // empty') || label=
fi
[ -n "$title" ] || title="${agent:-Agent} $what"
body=$label
[ -z "$detail" ] || body="$label · $detail"
url=$(jq -rn --arg status "$status" --arg title "$title" --arg body "$body" \
 --arg workspace "$workspace" --arg pane "$pane" --arg socket "${HERDR_SOCKET_PATH:-}" \
 --arg terminal "$terminal" --arg completion "$completion" --arg attention "$attention" \
 '"hammerspoon://herdr-alert?" + ([
  ["status", $status], ["title", $title], ["body", $body], ["workspace", $workspace],
  ["pane", $pane], ["socket", $socket], ["terminal", $terminal],
  ["completion", $completion], ["attention", $attention]
 ] | map("\(.[0])=\(.[1] | @uri)") | join("&"))')
open -g "$url"
printf '%s\n' "$identity" >"$ledger"
echo "away-alert: sent: $title ($label)" >&2
