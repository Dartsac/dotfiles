-- General settings
local general_settings = vim.api.nvim_create_augroup("_general_settings", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
	group = general_settings,
	pattern = { "qf", "help", "man", "lspinfo" },
	command = "nnoremap <silent> <buffer> q :close<CR>",
	desc = "Close quickfix, help, man, or lspinfo buffers with 'q'",
})
vim.api.nvim_create_autocmd("TextYankPost", {
	group = general_settings,
	desc = "Highlight when yanking text",
	callback = function()
		vim.highlight.on_yank({ higroup = "Visual", timeout = 250 })
	end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = general_settings,
	pattern = "*",
	command = "set formatoptions-=cro",
	desc = "Remove 'cro' from formatoptions",
})
vim.api.nvim_create_autocmd("FileType", {
	group = general_settings,
	pattern = "qf",
	command = "set nobuflisted",
	desc = "Do not list quickfix buffers",
})

-- Git settings
local git_settings = vim.api.nvim_create_augroup("_git", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
	group = git_settings,
	pattern = "gitcommit",
	command = "setlocal wrap",
	desc = "Enable wrap for gitcommit",
})
vim.api.nvim_create_autocmd("FileType", {
	group = git_settings,
	pattern = "gitcommit",
	command = "setlocal spell",
	desc = "Enable spell checking for gitcommit",
})

-- Markdown settings
local markdown_settings = vim.api.nvim_create_augroup("_markdown", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
	group = markdown_settings,
	pattern = "markdown",
	command = "setlocal wrap",
	desc = "Enable wrap for markdown",
})
vim.api.nvim_create_autocmd("FileType", {
	group = markdown_settings,
	pattern = "markdown",
	command = "setlocal spell",
	desc = "Enable spell checking for markdown",
})

-- Auto resize windows
local auto_resize = vim.api.nvim_create_augroup("_auto_resize", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
	group = auto_resize,
	pattern = "*",
	command = "tabdo wincmd =",
	desc = "Resize all windows equally on VimResized",
})
