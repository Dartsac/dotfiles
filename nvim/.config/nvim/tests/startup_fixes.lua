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

print("All startup-fix regression tests passed")
