-- Run from the config directory:
-- nvim --headless -u NONE -i NONE -l tests/startup_fixes.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		error(name .. ": " .. err)
	end
	print("PASS: " .. name)
end

local original_system = vim.system
local original_notify = vim.notify
local original_executable = vim.fn.executable
local original_tmux = vim.env.TMUX
local calls, notifications, responses
vim.notify = function(message)
	table.insert(notifications, message)
end
vim.fn.executable = function()
	return 1
end
vim.system = function(args)
	table.insert(calls, args)
	local result = table.remove(responses, 1) or { code = 0, stdout = "", stderr = "" }
	return {
		wait = function()
			return result
		end,
	}
end
local function reset(results, inside)
	calls, notifications, responses = {}, {}, results or {}
	vim.env.TMUX = inside and "/tmp/test-tmux,123,0" or nil
end

local tmux = require("config.tmux")
vim.api.nvim_buf_set_name(0, "/tmp/a file's $(literal).lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved work" })

test("outside tmux preserves modified buffers and reuses sessions", function()
	reset()
	tmux.create_session()
	assert(#calls == 1 and calls[1][2] == "has-session")
	assert(vim.bo.modified)
	assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "unsaved work")
	assert(notifications[1]:find("tmux attach-session", 1, true))
end)

test("new session starts the editor with literal arguments, never send-keys", function()
	reset({ { code = 1 } }, true)
	tmux.create_session()
	assert(#calls == 3)
	assert(calls[2][2] == "new-session" and calls[2][7] == vim.fn.getcwd())
	assert(calls[2][8] == "/bin/sh" and calls[2][9] == "-c")
	assert(calls[2][12] == vim.v.progpath and calls[2][13] == vim.fn.expand("%:p"))
	assert(calls[3][2] == "switch-client")
	assert(calls[1][4] == "=" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"):gsub("[.:]", "_"))
end)

test("sessions are named as tmux-sessionizer.sh names them", function()
	local cwd = vim.fn.getcwd()
	local directory = vim.fn.tempname() .. "/my.project:v2"
	vim.fn.mkdir(directory, "p")
	vim.cmd.cd(directory)
	reset(nil, true)
	tmux.create_session()
	vim.cmd.cd(cwd)
	vim.fn.delete(vim.fn.fnamemodify(directory, ":h"), "rf")
	assert(calls[1][4] == "=my_project_v2", calls[1][4])
	assert(vim.deep_equal(vim.list_slice(calls[2], 2), { "switch-client", "-t", "=my_project_v2" }))
end)

test("new session with a special buffer starts only the default shell", function()
	local buftype = vim.bo.buftype
	vim.bo.buftype = "nofile"
	reset({ { code = 1 } })
	tmux.create_session()
	vim.bo.buftype = buftype
	assert(#calls == 2 and #calls[2] == 7)
	assert(calls[2][2] == "new-session")
end)

test("existing session is switched without typing into its pane", function()
	reset(nil, true)
	tmux.create_session()
	assert(#calls == 2 and calls[2][2] == "switch-client")
end)

test("session creation failure stops before switching", function()
	reset({ { code = 1 }, { code = 1, stderr = "creation failed" } }, true)
	tmux.create_session()
	assert(#calls == 2 and notifications[1] == "creation failed")
end)

test("split arguments preserve paths and report failure", function()
	reset(nil, true)
	local path = "/tmp/a file's $(literal).lua"
	assert(tmux.split(path, "vertical"))
	assert(calls[1][3] == "-h" and calls[1][5] == vim.fn.getcwd())
	assert(calls[1][6] == "/bin/sh" and calls[1][7] == "-c")
	assert(calls[1][9] == "nvim-tmux")
	assert(calls[1][10] == vim.v.progpath and calls[1][11] == path)
	reset({ { code = 1, stderr = "split failed" } }, true)
	assert(not tmux.split(path, "horizontal"))
	assert(calls[1][3] == "-v" and notifications[1] == "split failed")
	reset()
	assert(not tmux.split(path, "vertical") and #calls == 0)
end)

test("split and session shells preserve literal paths with Fish configured", function()
	local shell = vim.o.shell
	local directory = vim.fn.tempname() .. " space's"
	vim.fn.mkdir(directory, "p")
	local executable = directory .. "/capture\\args"
	vim.fn.writefile({ "#!/bin/sh", "printf '%s\\0' \"$@\"" }, executable)
	assert(vim.fn.setfperm(executable, "rwx------") == 1)
	local ok, err = xpcall(function()
		vim.o.shell = "fish"
		for _, direction in ipairs({ "vertical", "horizontal", "session" }) do
			for _, path in ipairs({ "/tmp/a file.lua", "/tmp/file's.lua", "/tmp/a\\b.lua", "/tmp/$(literal);file.lua" }) do
				local args
				if direction == "session" then
					reset({ { code = 1 } }, true)
					vim.api.nvim_buf_set_name(0, path)
					tmux.create_session()
					args = vim.list_slice(calls[2], 8)
				else
					reset(nil, true)
					assert(tmux.split(path, direction))
					args = vim.list_slice(calls[1], 6)
				end
				assert(args[5] == vim.v.progpath)
				args[5] = executable
				local result = original_system(args, { env = { SHELL = "/usr/bin/true" } }):wait()
				assert(result.code == 0, result.stderr)
				assert(result.stdout == "--\0" .. path .. "\0", vim.inspect(result.stdout))
			end
		end
	end, debug.traceback)
	vim.o.shell = shell
	vim.fn.delete(directory, "rf")
	assert(ok, err)
end)

test("navigation moves between windows, then hands the edge to tmux without a shell", function()
	reset(nil, true)
	vim.env.TMUX_PANE = "%5"
	vim.o.shell = "fish" -- must not be used
	vim.cmd("silent! only")
	vim.cmd("vsplit")
	vim.cmd("wincmd h")
	local left = vim.api.nvim_get_current_win()
	tmux.navigate("l") -- inside Neovim: no tmux call
	assert(vim.api.nvim_get_current_win() ~= left and #calls == 0)
	tmux.navigate("l") -- right edge: tmux takes over
	assert(#calls == 1, vim.inspect(calls))
	assert(calls[1][1]:match("tmux%-pane%-clarity/bin/tmux$"))
	assert(vim.deep_equal(vim.list_slice(calls[1], 2), { "select-pane", "-t", "%5", "-R" }))
	tmux.navigate("p") -- back to tmux's last pane, not Neovim's previous window
	assert(vim.deep_equal(vim.list_slice(calls[2], 2), { "select-pane", "-t", "%5", "-l" }))
	tmux.navigate("h") -- a Neovim move resets the hand-over
	tmux.navigate("p")
	assert(#calls == 2 and vim.api.nvim_get_current_win() ~= left)
	reset(nil, false) -- outside tmux the edge is a no-op
	vim.cmd("wincmd l")
	tmux.navigate("l")
	assert(#calls == 0)
	vim.cmd("silent! only")
	vim.env.TMUX_PANE = nil
end)

vim.system = original_system
vim.notify = original_notify
vim.fn.executable = original_executable
vim.env.TMUX = original_tmux

-- Capture plugin setup without loading the editor's full plugin stack.
test("Colorizer filetypes and CSS overrides reach setup", function()
	local options
	package.loaded.colorizer = {
		setup = function(opts)
			options = opts
		end,
	}
	dofile("lua/plugins/colorizer.lua").config()
	assert(options.filetypes[1] == "css")
	assert(options.filetypes.css.rgb_fn and options.filetypes.scss.hsl_fn)
	assert(options[1] == nil)
	package.loaded.colorizer = nil
end)

test("Treesitter is eager-loaded", function()
	local spec = dofile("lua/plugins/treesitter.lua")
	assert(spec.lazy == false and spec.event == nil)
end)

test("quickfix and undo-stage mappings call the correct APIs", function()
	local mappings
	package.loaded["which-key.plugins.spelling"] = {}
	package.loaded["which-key"] = {
		setup = function() end,
		add = function(items)
			mappings = items
		end,
	}
	dofile("lua/plugins/whichkey.lua")[1].config()
	local found = {}
	for _, mapping in ipairs(mappings) do
		found[mapping[1]] = mapping[2]
	end
	assert(found["<leader>lq"]:find("setqflist", 1, true))
	assert(found["<leader>gu"]:find("undo_stage_hunk", 1, true))
	package.loaded["which-key"] = nil
	package.loaded["which-key.plugins.spelling"] = nil
end)

-- Use the installed Colorbuddy and bundled themes for a real highlight smoke test.
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/colorbuddy.nvim")
local readfile = vim.fn.readfile
local theme_spec = dofile("lua/plugins/colorscheme.lua")
for _, scenario in ipairs({ "missing", "unknown", "known" }) do
	test("colorscheme fallback: " .. scenario, function()
		vim.fn.readfile = function(path, ...)
			if path == vim.fn.expand("~/.config/ghostty/config") then
				if scenario == "missing" then
					error("missing config")
				end
				return { scenario == "known" and "theme = Dracula-Blade" or "theme = Unknown" }
			end
			return readfile(path, ...)
		end
		theme_spec.config()
		assert(vim.g.colors_name == (scenario == "known" and "dracula_pro_blade" or "dracula_pro"))
		assert(vim.g["dracula_pro#palette"].fg)
	end)
end
vim.fn.readfile = readfile
print("All startup-fix regression tests passed")
