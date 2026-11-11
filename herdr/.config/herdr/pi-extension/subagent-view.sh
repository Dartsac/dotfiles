#!/bin/sh
# Runs inside a child's Herdr tab. Arguments arrive as environment variables set
# by `tab create --env`, so the shell never parses run ids, paths or titles.
#
# child-viewer.mjs draws the child's Pi session with Pi's own components. If it
# can't start (no Pi package passed, or Pi's exports changed), fall back to
# pi-subagents' text dashboard so the tab is never blank.
set -u
printf '\033]2;%s\007' "${PI_SUBAGENT_VIEW_TITLE:-subagent}"
here=$(dirname "$0")
if [ -n "${PI_SUBAGENT_VIEW_PI_ROOT:-}" ]; then
	"$PI_SUBAGENT_VIEW_NODE" "$here/child-viewer.mjs" && exit 0
	printf '\nThe Pi-styled viewer stopped; showing the plain dashboard instead.\n'
	sleep 2
fi
set -- "$PI_SUBAGENT_VIEW_RUNNER" \
	--async-dir "$PI_SUBAGENT_VIEW_ASYNC_DIR" --run-id "$PI_SUBAGENT_VIEW_RUN_ID" \
	--allow-steer "${PI_SUBAGENT_VIEW_STEER:-true}" --allow-stop "${PI_SUBAGENT_VIEW_STOP:-true}"
[ -z "${PI_SUBAGENT_VIEW_INDEX:-}" ] || set -- "$@" --index "$PI_SUBAGENT_VIEW_INDEX"
[ -z "${PI_SUBAGENT_VIEW_ROOTS:-}" ] || set -- "$@" --session-roots "$PI_SUBAGENT_VIEW_ROOTS"
exec "$PI_SUBAGENT_VIEW_NODE" "$@"
