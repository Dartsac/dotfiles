#!/bin/sh
# Runs inside a child's Herdr tab: pi-subagents' read-only live viewer for one
# subagent. Arguments arrive as environment variables set by `tab create --env`,
# so the shell never parses run ids, paths or titles.
set -eu
printf '\033]2;%s\007' "${PI_SUBAGENT_VIEW_TITLE:-subagent}"
set -- "$PI_SUBAGENT_VIEW_RUNNER" \
	--async-dir "$PI_SUBAGENT_VIEW_ASYNC_DIR" --run-id "$PI_SUBAGENT_VIEW_RUN_ID" \
	--allow-steer "${PI_SUBAGENT_VIEW_STEER:-true}" --allow-stop "${PI_SUBAGENT_VIEW_STOP:-true}"
[ -z "${PI_SUBAGENT_VIEW_INDEX:-}" ] || set -- "$@" --index "$PI_SUBAGENT_VIEW_INDEX"
[ -z "${PI_SUBAGENT_VIEW_ROOTS:-}" ] || set -- "$@" --session-roots "$PI_SUBAGENT_VIEW_ROOTS"
exec "$PI_SUBAGENT_VIEW_NODE" "$@"
