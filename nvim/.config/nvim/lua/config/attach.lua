-- lua/config/attach.lua

-- Started without a file to open: go to the project's first Harpoon entry.
if vim.fn.argc() > 0 then
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
