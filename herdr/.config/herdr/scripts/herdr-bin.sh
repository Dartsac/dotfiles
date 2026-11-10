# Sourced by the herdr shell scripts: sets $herdr to HERDR_BIN_PATH, or to herdr
# on PATH when that path is stale (a running server keeps it across an update).
# Same rule as herdr_cli.py and Neovim's config/multiplexer.lua: only an
# executable regular file counts.
herdr=${HERDR_BIN_PATH:-}
if ! { [ -f "$herdr" ] && [ -x "$herdr" ]; }; then
	herdr=$(command -v herdr) || {
		echo "${0##*/}: no usable herdr binary (check HERDR_BIN_PATH and PATH)" >&2
		exit 127
	}
fi
