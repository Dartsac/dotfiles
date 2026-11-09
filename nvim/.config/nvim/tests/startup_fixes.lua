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
-- The multiplexer is chosen from these; tests set them all (see reset).
local original_env = {}
for _, name in ipairs({ "TMUX", "HERDR_ENV", "HERDR_BIN_PATH", "DEFAULT_MULTIPLEXER" }) do
	original_env[name] = vim.env[name]
end
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
-- inside: true for a tmux pane, "herdr" for a herdr pane, nil for neither.
-- default: the Default multiplexer ($DEFAULT_MULTIPLEXER), unset by default.
local function reset(results, inside, default)
	calls, notifications, responses = {}, {}, results or {}
	vim.env.TMUX = inside == true and "/tmp/test-tmux,123,0" or nil
	vim.env.HERDR_ENV = inside == "herdr" and "1" or nil
	vim.env.HERDR_BIN_PATH = nil
	vim.env.DEFAULT_MULTIPLEXER = default
end

-- The tests up to the herdr ones exercise the module's tmux branch.
local tmux = require("config.multiplexer")
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

test("the pane's multiplexer wins, then the Default multiplexer, then tmux", function()
	reset(nil, "herdr")
	vim.env.TMUX = "/tmp/outer-tmux,1,0" -- herdr launched from a tmux pane
	assert(tmux.current() == "herdr")
	reset(nil, true, "herdr")
	assert(tmux.current() == "tmux")
	reset(nil, nil, "herdr")
	assert(tmux.current() == "herdr")
	reset()
	assert(tmux.current() == "tmux")
end)

test("herdr splits type a literal, fish-quoted editor command into the new pane", function()
	local split_ok = { code = 0, stdout = '{"result":{"pane":{"pane_id":"w1:p7"}}}' }
	for direction, herdr_direction in pairs({ vertical = "right", horizontal = "down" }) do
		reset({ split_ok }, "herdr")
		assert(tmux.split("/tmp/x.lua", direction))
		assert(vim.deep_equal(calls[1], {
			"herdr", "pane", "split", "--current", "--direction", herdr_direction,
			"--cwd", vim.fn.getcwd(), "--focus",
		}), vim.inspect(calls[1]))
		assert(vim.deep_equal(vim.list_slice(calls[2], 1, 4), { "herdr", "pane", "run", "w1:p7" }))
	end
	reset({ { code = 1, stderr = "split failed" } }, "herdr")
	assert(not tmux.split("/tmp/x.lua", "vertical"))
	assert(#calls == 1 and notifications[1] == "split failed")

	-- Run the typed command in fish, with a stand-in for Neovim.
	local executable = vim.fn.tempname() .. "-capture"
	vim.fn.writefile({ "#!/bin/sh", "printf '%s\\0' \"$@\"" }, executable)
	assert(vim.fn.setfperm(executable, "rwx------") == 1)
	local ok, err = xpcall(function()
		for _, path in ipairs({ "/tmp/a file.lua", "/tmp/file's.lua", "/tmp/a\\b.lua", "/tmp/x\\'y.lua", "/tmp/$(literal);file.lua" }) do
			reset({ split_ok }, "herdr")
			assert(tmux.split(path, "vertical"))
			local typed = calls[2][5]
			local editor = "'" .. vim.v.progpath .. "'"
			assert(typed:sub(1, #editor) == editor, typed)
			typed = "'" .. executable .. "'" .. typed:sub(#editor + 1)
			local result = original_system({ "fish", "--no-config", "-c", typed }):wait()
			assert(result.code == 0, result.stderr)
			assert(result.stdout == "--\0" .. path .. "\0", vim.inspect(result.stdout))
		end
	end, debug.traceback)
	vim.fn.delete(executable)
	assert(ok, err)
end)

test("herdr navigation hands the edge to herdr; <C-\\> stays in Neovim", function()
	reset(nil, "herdr")
	vim.cmd("silent! only")
	vim.cmd("vsplit")
	vim.cmd("wincmd h")
	tmux.navigate("l") -- inside Neovim: no herdr call
	assert(#calls == 0)
	tmux.navigate("l") -- right edge: herdr takes over
	assert(vim.deep_equal(calls[1], { "herdr", "pane", "focus", "--direction", "right", "--current" }))
	tmux.navigate("p") -- herdr has no previous pane
	assert(#calls == 1)
	vim.cmd("silent! only")
end)

test("herdr sessions go through the project picker; existing workspaces get a new tab", function()
	local picker = vim.fn.expand("~/.config/herdr/scripts/project-picker.py")
	local file = vim.fn.expand("%:p")
	local typed_file = file:gsub("'", "\\'")
	reset({ { code = 0, stdout = '{"workspace_id": "w3", "root_pane_id": "w3:p1"}\n' } }, "herdr")
	tmux.create_session()
	assert(vim.deep_equal(calls[1], { "python3", picker, "--json", vim.fn.getcwd() }), vim.inspect(calls[1]))
	assert(vim.deep_equal(vim.list_slice(calls[2], 1, 4), { "herdr", "pane", "run", "w3:p1" }))
	assert(calls[2][5]:find(typed_file, 1, true), calls[2][5])
	assert(#notifications == 0)

	reset({
		{ code = 0, stdout = '{"workspace_id": "w2", "root_pane_id": null}\n' },
		{ code = 0, stdout = '{"result": {"root_pane": {"pane_id": "w2:p5"}}}' },
	}, "herdr")
	tmux.create_session()
	assert(#calls == 3, vim.inspect(calls))
	assert(vim.deep_equal(calls[2], {
		"herdr", "tab", "create", "--workspace", "w2", "--cwd", vim.fn.getcwd(), "--focus",
	}), vim.inspect(calls[2]))
	assert(vim.deep_equal(vim.list_slice(calls[3], 1, 4), { "herdr", "pane", "run", "w2:p5" }))
	assert(calls[3][5]:find(typed_file, 1, true))

	reset({ { code = 0, stdout = '{"workspace_id": "w1", "root_pane_id": "w1:p1"}' } }, nil, "herdr")
	tmux.create_session() -- outside herdr: default session, then a hint to attach
	assert(vim.deep_equal(calls[1], { "python3", picker, "--json", "--default-session", vim.fn.getcwd() }))
	assert(notifications[1]:find("herdr", 1, true))

	local buftype = vim.bo.buftype
	vim.bo.buftype = "nofile" -- nothing to open: the workspace is only focused
	reset({ { code = 0, stdout = '{"workspace_id": "w4", "root_pane_id": null}' } }, "herdr")
	tmux.create_session()
	vim.bo.buftype = buftype
	assert(#calls == 1)
end)

vim.system = original_system
vim.notify = original_notify
vim.fn.executable = original_executable
for name, value in pairs(original_env) do
	vim.env[name] = value
end

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

-- Use the bundled themes for a real highlight smoke test.
local readfile = vim.fn.readfile
local colorscheme = require("config.colorscheme")
-- Ghostty uses the last `theme =` line: so must Neovim, to match it and tmux.
local configs = {
	unknown = { "theme = Unknown" },
	known = { "theme = Dracula-Blade" },
	last = { "theme = Dracula-Pro", "# theme = Dracula-Buffy", "theme = Dracula-Blade" },
}
for _, scenario in ipairs({ "missing", "unknown", "known", "last" }) do
	test("colorscheme fallback: " .. scenario, function()
		vim.fn.readfile = function(path, ...)
			if path == vim.fn.expand("~/.config/ghostty/config") then
				if scenario == "missing" then
					error("missing config")
				end
				return configs[scenario]
			end
			return readfile(path, ...)
		end
		colorscheme.setup()
		local blade = scenario == "known" or scenario == "last"
		assert(vim.g.colors_name == (blade and "dracula_pro_blade" or "dracula_pro"))
		local palette = vim.g["dracula_pro#palette"]
		assert(palette.fg)
		-- The overrides are applied on top of the theme, from its palette.
		local red = tonumber(palette.red[1]:sub(2), 16)
		local virt = vim.api.nvim_get_hl(0, { name = "DiagnosticVirtualTextError" })
		assert(virt.bg == red and virt.bold, vim.inspect(virt))
		assert(vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "Normal" })))
		local visual = vim.api.nvim_get_hl(0, { name = "Visual" })
		assert(visual.reverse and visual.bold, vim.inspect(visual))
	end)
end
vim.fn.readfile = readfile
print("All startup-fix regression tests passed")
