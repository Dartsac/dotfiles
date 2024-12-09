local status_ok, rename = pcall(require, "inc_rename")
if not status_ok then
	return
end

rename.setup()

vim.keymap.set("n", "<leader>rn", function()
	return ":IncRename " .. vim.fn.expand("<cword>")
end, { expr = true, desc = "Incremental rename", noremap = true })
