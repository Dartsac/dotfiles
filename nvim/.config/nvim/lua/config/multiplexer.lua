-- Splits, project sessions and window/pane navigation for the multiplexer that
-- applies here, chosen as fish's functions/multiplexer.fish chooses it: the
-- pane's own (herdr via $HERDR_ENV, tmux via $TMUX), otherwise the Default
-- multiplexer ($DEFAULT_MULTIPLEXER, tmux when unset). External processes are
-- started with argument lists; the only shell strings are the fixed /bin/sh
-- script and the fish-quoted pane input below, so paths stay literal.
local M = {}

local function adapted(args)
	-- Route pane commands through clarity's adapter when available. It is a
	-- transparent pass-through for windows not using always-framed mode.
	local adapter = vim.fn.expand("~/.config/tmux/plugins/tmux-pane-clarity/bin/tmux")
	if args[1] == "tmux" and vim.fn.executable(adapter) == 1 then
		args = vim.deepcopy(args)
		args[1] = adapter
	end
	return args
end

local function in_herdr()
	return vim.env.HERDR_ENV == "1"
end

local function in_tmux()
	return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

--- "herdr" or "tmux": the multiplexer that applies here.
function M.current()
	if in_herdr() then
		return "herdr"
	elseif in_tmux() then
		return "tmux"
	end
	return vim.env.DEFAULT_MULTIPLEXER == "herdr" and "herdr" or "tmux"
end

local function herdr_bin()
	return vim.env.HERDR_BIN_PATH or "herdr"
end

local function report(result, fallback)
	vim.notify(vim.trim(result.stderr or "") ~= "" and result.stderr or fallback, vim.log.levels.ERROR)
end

-- Start a process, reporting a failure to start; on_exit makes it asynchronous.
local function spawn(args, on_exit)
	local ok, process = pcall(vim.system, args, { text = true }, on_exit)
	if not ok then
		vim.notify(tostring(process), vim.log.levels.ERROR)
		return nil
	end
	return process
end

local function run(args)
	local process = spawn(adapted(args))
	return process and process:wait()
end

local function checked(args)
	local result = run(args)
	if not result then
		return nil
	end
	if result.code ~= 0 then
		report(result, args[1] .. " command failed")
		return nil
	end
	return result
end

local function nvim_args(filepath)
	-- Use a fixed POSIX script with literal arguments, regardless of Neovim's
	-- 'shell' or tmux's default-shell. Leave a shell open after Neovim exits.
	return { "/bin/sh", "-c", '"$1" -- "$2"; exec "$SHELL"', "nvim-tmux", vim.v.progpath, filepath }
end

-- herdr panes start their own shell (fish, per herdr's config.toml), so the
-- editor command is typed into it: quote each word for fish.
local function fish_quote(word)
	return "'" .. word:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

local function nvim_command(filepath)
	return fish_quote(vim.v.progpath) .. " -- " .. fish_quote(filepath)
end

local function run_in_herdr_pane(pane, command)
	return checked({ herdr_bin(), "pane", "run", pane, command }) ~= nil
end

local function json_field(result, ...)
	local ok, response = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true } })
	return ok and type(response) == "table" and vim.tbl_get(response, ...) or nil
end

-- Run args and return the JSON field at the given keys (plus the result),
-- reporting a failed command or a missing field as `<what> returned no …`.
local function checked_field(args, what, ...)
	local result = checked(args)
	if not result then
		return nil
	end
	local value = json_field(result, ...)
	if not value then
		vim.notify(what .. " returned no " .. select(select("#", ...), ...):gsub("_", " "), vim.log.levels.ERROR)
	end
	return value, result
end

local function herdr_split(filepath, direction)
	local pane = checked_field({
		herdr_bin(),
		"pane",
		"split",
		"--current",
		"--direction",
		direction == "horizontal" and "down" or "right",
		"--cwd",
		vim.fn.getcwd(),
		"--focus",
	}, "herdr pane split", "result", "pane", "pane_id")
	return pane ~= nil and run_in_herdr_pane(pane, nvim_command(filepath))
end

--- Open filepath in Neovim in a new pane: "vertical" splits side by side
--- (tmux -h, herdr right), "horizontal" stacks it below.
function M.split(filepath, direction)
	if in_herdr() then
		return herdr_split(filepath, direction)
	end
	if not in_tmux() then
		vim.notify("Open Neovim inside tmux or herdr before creating a split", vim.log.levels.WARN)
		return false
	end
	-- tmux executes multiple command arguments directly. Pass paths as positional
	-- arguments so /bin/sh never parses quoting intended for Neovim's 'shell'.
	return checked(vim.list_extend({
		"tmux",
		"split-window",
		direction == "horizontal" and "-v" or "-h",
		"-c",
		vim.fn.getcwd(),
	}, nvim_args(filepath))) ~= nil
end

local function editable_file()
	local current_file = vim.fn.expand("%:p")
	if current_file ~= "" and vim.bo.buftype == "" then
		return current_file
	end
end

local function create_herdr_workspace()
	-- The project picker owns workspace matching (project_path metadata), so
	-- Ctrl-f and this command find each other's workspaces.
	local cwd = vim.fn.getcwd()
	local args = { "python3", vim.fn.expand("~/.config/herdr/scripts/project-picker.py"), "--json" }
	if not in_herdr() then
		table.insert(args, "--default-session")
	end
	table.insert(args, cwd)
	local workspace, result = checked_field(args, "The herdr project picker", "workspace_id")
	if not workspace then
		return
	end
	local file = editable_file()
	if file then
		-- A new workspace's first pane gets the editor; an existing workspace
		-- gets it in a new tab.
		local pane = json_field(result, "root_pane_id")
			or checked_field(
				{ herdr_bin(), "tab", "create", "--workspace", workspace, "--cwd", cwd, "--focus" },
				"herdr tab create",
				"result",
				"root_pane",
				"pane_id"
			)
		if not pane or not run_in_herdr_pane(pane, nvim_command(file)) then
			return
		end
	end
	if not in_herdr() then
		vim.notify("Workspace ready. Attach from a shell with: herdr")
	end
end

function M.create_session()
	if M.current() == "herdr" then
		return create_herdr_workspace()
	end
	if vim.fn.executable("tmux") == 0 then
		vim.notify("tmux is not installed", vim.log.levels.ERROR)
		return
	end

	local cwd = vim.fn.getcwd()
	-- Named as tmux-sessionizer.sh names it (`basename | tr . _`), so each finds
	-- the other's session. tmux itself turns ':' into '_' too.
	local basename = vim.fn.fnamemodify(cwd, ":t"):gsub("[.:]", "_")
	local session_name = basename ~= "" and basename or "project"
	local target = "=" .. session_name
	local exists = run({ "tmux", "has-session", "-t", target })
	if not exists then
		return
	end

	if exists.code ~= 0 then
		local args = { "tmux", "new-session", "-d", "-s", session_name, "-c", cwd }
		local current_file = editable_file()
		if current_file then
			-- Start the editor directly instead of typing into an unknown shell.
			vim.list_extend(args, nvim_args(current_file))
		end
		if not checked(args) then
			return
		end
	end

	if in_tmux() then
		checked({ "tmux", "switch-client", "-t", target })
	else
		-- Do not quit the editor or write a shared shell-wrapper marker. Modified
		-- buffers remain here; another Neovim process only sees files saved to disk.
		vim.notify("Session ready. Attach from a shell with: tmux attach-session -t " .. session_name)
	end
end

-- Window/pane navigation (formerly vim-tmux-navigator). Move between Neovim
-- windows; at the edge, hand over to the multiplexer. It is started directly
-- and not waited for: vim-tmux-navigator went through system(), which starts
-- Neovim's 'shell' (fish, with its whole config) on every move.
local TMUX_FLAG = { h = "-L", j = "-D", k = "-U", l = "-R", p = "-l" }
local HERDR_DIRECTION = { h = "left", j = "down", k = "up", l = "right" }
local last_was_tmux = false

local function start(args, failure)
	return spawn(args, function(result)
		if result.code ~= 0 then
			vim.schedule(function()
				report(result, failure)
			end)
		end
	end)
end

function M.navigate(direction)
	local window = vim.api.nvim_get_current_win()
	if in_herdr() then
		-- herdr has no "previous pane", so <C-\> stays inside Neovim.
		pcall(vim.cmd.wincmd, direction)
		local herdr_direction = HERDR_DIRECTION[direction]
		if not herdr_direction or vim.api.nvim_get_current_win() ~= window then
			return nil
		end
		return start(
			{ herdr_bin(), "pane", "focus", "--direction", herdr_direction, "--current" },
			"herdr pane focus failed"
		)
	end

	local pane = in_tmux() and vim.env.TMUX_PANE
	-- Like vim-tmux-navigator: "previous" returns to tmux's last pane if the
	-- previous move left tmux, otherwise to Neovim's previous window.
	local to_last_tmux_pane = direction == "p" and last_was_tmux
	if not to_last_tmux_pane then
		pcall(vim.cmd.wincmd, direction)
	end
	local at_edge = vim.api.nvim_get_current_win() == window
	if not pane or not (to_last_tmux_pane or at_edge) then
		last_was_tmux = false
		return nil
	end
	last_was_tmux = true
	return start(adapted({ "tmux", "select-pane", "-t", pane, TMUX_FLAG[direction] }), "tmux select-pane failed")
end

return M
