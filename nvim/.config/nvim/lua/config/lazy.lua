-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Install your plugins here
require("lazy").setup({
	spec = {
		{ import = "plugins" },
		{ "google/vim-searchindex" },
	},
	--  --React ES7+ React/Redux/React-Native snippet
	--  { "dsznajder/vscode-es7-javascript-react-snippets", build = "yarn install --frozen-lockfile && yarn compile" },
	--
	--  -- Emmet
	--  { "mattn/emmet-vim" },
	--
	--  -- Sticky header
	--  { "nvim-treesitter/nvim-treesitter-context" },
	--
	--  -- dadbod
	--  { "tpope/vim-dadbod",
	--  dependencies = {
	--   "kristijanhusak/vim-dadbod-ui",
	--   "kristijanhusak/vim-dadbod-completion",
	--  },
	-- },
	--
	-- { "smjonas/inc-rename.nvim" },
	-- { "christoomey/vim-tmux-navigator" },
})
