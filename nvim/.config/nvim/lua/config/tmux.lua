-- Keep tmux arguments separate from shell commands, including paths with spaces.
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

local function in_tmux()
	return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function report(result, fallback)
	vim.notify(vim.trim(result.stderr or "") ~= "" and result.stderr or fallback, vim.log.levels.ERROR)
end

local function run(args)
	args = adapted(args)
	local ok, result = pcall(function()
		return vim.system(args, { text = true }):wait()
	end)
	if not ok then
		vim.notify(tostring(result), vim.log.levels.ERROR)
		return nil
	end
	return result
end

local function checked(args)
	local result = run(args)
	if not result then
		return nil
	end
	if result.code ~= 0 then
		report(result, "tmux command failed")
		return nil
	end
	return result
end

local function nvim_args(filepath)
	-- Use a fixed POSIX script with literal arguments, regardless of Neovim's
	-- 'shell' or tmux's default-shell. Leave a shell open after Neovim exits.
	return { "/bin/sh", "-c", '"$1" -- "$2"; exec "$SHELL"', "nvim-tmux", vim.v.progpath, filepath }
end

function M.split(filepath, direction)
	if not in_tmux() then
		vim.notify("Open Neovim inside tmux before creating a tmux split", vim.log.levels.WARN)
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

function M.create_session()
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
		local current_file = vim.fn.expand("%:p")
		if current_file ~= "" and vim.bo.buftype == "" then
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

return M
