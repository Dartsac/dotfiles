-- Shared prompt parsing and ripgrep commands for the multigrep pickers.
--
-- Prompt: `<query>  <glob>` (two spaces before an optional glob or shortcut).
-- Query:  `primary && filter && ...`
--   * A qualifying file contains every term, anywhere in the file.
--   * Location results are the lines matching the primary (first) term,
--     taken only from qualifying files. Filter terms never add lines.
--   * Files-only results are the qualifying files.
--
-- A compound query runs as a NUL-separated ripgrep pipeline: list files with
-- the primary term (applying the glob and ignore rules once), narrow that list
-- with each filter term, then report primary-term lines from the survivors.
-- Terms, the glob and file names travel as positional arguments, never as
-- shell text.
local M = {}

M.shortcuts = {
	["l"] = "*.lua",
	["v"] = "*.vim",
	["n"] = "*.{vim,lua}",
	["c"] = "*.c",
	["r"] = "*.rs",
	["g"] = "*.go",
}

local LOCATION_FLAGS =
	{ "--color=never", "--no-heading", "--with-filename", "--line-number", "--column", "--smart-case" }
local FILES_FLAGS = { "--files-with-matches", "--color=never", "--smart-case" }

-- Cancellation: Telescope stops a search by sending SIGTERM to the process it
-- started (this shell) only. A shell runs traps only after a foreground
-- pipeline finishes, so the pipeline runs in the background while the shell
-- waits; on TERM/HUP/INT the trap snapshots every descendant (rg, xargs and
-- the subshells between them) and terminates them all.
M.SCRIPT = [[
mode=$1 glob=$2 primary=$3
shift 3
descendants() {
  for child in $(pgrep -P "$1" 2>/dev/null); do
    echo "$child"
    descendants "$child"
  done
}
stop() {
  trap - TERM HUP INT
  pids=$(descendants $$)
  [ -n "$pids" ] && kill -TERM $pids 2>/dev/null
  exit 143
}
trap stop TERM HUP INT
search() {
  {
    if [ -n "$glob" ]; then
      rg --null --files-with-matches --smart-case --glob "$glob" -e "$primary" </dev/null
    else
      rg --null --files-with-matches --smart-case -e "$primary" </dev/null
    fi
  } | qualify "$@" | if [ "$mode" = files ]; then
    tr '\0' '\n'
  else
    xargs -0 -r rg --color=never --no-heading --with-filename --line-number --column --smart-case -e "$primary" --
  fi
}
qualify() {
  if [ "$#" -eq 0 ]; then
    cat
    return
  fi
  term=$1
  shift
  xargs -0 -r rg --null --files-with-matches --smart-case -e "$term" -- | qualify "$@"
}
search "$@" &
wait $!
]]

---@class CompoundQuery
---@field terms string[] primary term first
---@field glob string|nil

---@param prompt string|nil
---@param shortcuts? table<string, string>
---@return CompoundQuery|nil
function M.parse(prompt, shortcuts)
	if not prompt or vim.trim(prompt) == "" then
		return nil
	end
	shortcuts = shortcuts or M.shortcuts
	local query, glob = prompt:match("^(.-)  (.*)$")
	query = query or prompt

	-- `&&` needs whitespace before it, so a regex such as `[a&&b]` stays intact.
	-- A trailing `&&` while typing simply has no filter yet.
	local terms = {}
	for _, term in ipairs(vim.split(query, "%s+&&%s*")) do
		term = vim.trim(term)
		if term ~= "" then
			terms[#terms + 1] = term
		end
	end
	if #terms == 0 then
		return nil
	end

	glob = glob and vim.trim(glob) or ""
	if glob == "" then
		glob = nil
	elseif shortcuts[glob] then
		glob = shortcuts[glob]
	end
	return { terms = terms, glob = glob }
end

---@param parsed CompoundQuery
---@param mode "lines"|"files"
---@param pattern? string format applied to the glob (picker option)
---@return string[]
function M.command(parsed, mode, pattern)
	local glob = parsed.glob and string.format(pattern or "%s", parsed.glob) or nil
	if #parsed.terms == 1 then
		local args = { "rg" }
		vim.list_extend(args, mode == "files" and FILES_FLAGS or LOCATION_FLAGS)
		if glob then
			vim.list_extend(args, { "--glob", glob })
		end
		vim.list_extend(args, { "-e", parsed.terms[1] })
		return args
	end
	local args = { "/bin/sh", "-c", M.SCRIPT, "rg-compound", mode, glob or "" }
	vim.list_extend(args, parsed.terms)
	return args
end

--- Telescope `command_generator` for the given mode.
---@param mode "lines"|"files"
---@param opts? { shortcuts?: table<string, string>, pattern?: string }
function M.generator(mode, opts)
	opts = opts or {}
	return function(prompt)
		local parsed = M.parse(prompt, opts.shortcuts)
		if not parsed then
			return nil
		end
		return M.command(parsed, mode, opts.pattern)
	end
end

return M
