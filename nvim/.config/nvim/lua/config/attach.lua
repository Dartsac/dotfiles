-- lua/config/attach.lua

-- Only auto-attach to harpoon if no file was explicitly opened
local has_file_arg = vim.fn.argc() > 0

if has_file_arg then
	-- User opened a specific file, don't auto-attach to harpoon
	return
end

local ok, harpoon = pcall(require, "harpoon")
if not ok or vim.tbl_isempty(harpoon:list().items) then
	return
end

-- Don't show the splash
vim.opt.shortmess:append("I")
-- Jump *after* all startup-autocmds run
vim.schedule(function()
	harpoon:list():select(1)
end)
