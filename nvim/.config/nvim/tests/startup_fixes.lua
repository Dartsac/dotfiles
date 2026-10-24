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
