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
require("config.options")

-- Install your plugins here
require("lazy").setup({
	spec = {
		{ import = "plugins" },
	},
	--  { "echasnovski/mini.icons" },
	--  { "echasnovski/mini.indentscope" },
	--
	--  {"nvim-lua/plenary.nvim"},
	--  { "windwp/nvim-autopairs" },
	--  { "windwp/nvim-ts-autotag" },
	--  { "axelvc/template-string.nvim" },
	--  { "numToStr/Comment.nvim" },
	--  {"JoosepAlviste/nvim-ts-context-commentstring"},
	--  {"nvim-tree/nvim-web-devicons"},
	--
	--  { "kyazdani42/nvim-tree.lua" },
	--  { "akinsho/bufferline.nvim" },
	--  { "moll/vim-bbye" },
	--  { "nvim-lualine/lualine.nvim" },
	--  { "akinsho/toggleterm.nvim" },
	--  { "ahmedkhalf/project.nvim" },
	--  { "lewis6991/impatient.nvim" },
	--  {"lukas-reineke/indent-blankline.nvim"},
	--  -- { "folke/which-key.nvim" },
	--
	--  -- Cmp
	--  {"hrsh7th/nvim-cmp"}, -- The completion plugin
	--  { "hrsh7th/cmp-buffer" }, -- buffer completions
	--  { "hrsh7th/cmp-path"}, -- path completions
	--  --{ "saadparwaiz1/cmp_luasnip"}, -- snippet completions
	--  {"hrsh7th/cmp-nvim-lsp"},
	--  { "hrsh7th/cmp-nvim-lua"},
	--
	--  -- Snippets
	--  --{ "L3MON4D3/LuaSnip"}, --snippet engine
	--  { "rafamadriz/friendly-snippets"}, -- a bunch of snippets to use
	--
	--  -- LSP
	--  {"williamboman/mason.nvim"}, -- simple to use language server installer
	--  {"williamboman/mason-lspconfig.nvim"},
	--  {"neovim/nvim-lspconfig"}, -- enable LSP
	--  {"jose-elias-alvarez/null-ls.nvim"}, -- for formatters and linters
	--  { "RRethy/vim-illuminate"},
	--  {"jose-elias-alvarez/typescript.nvim"},
	--
	--  -- Treesitter
	--  { "nvim-treesitter/nvim-treesitter" },
	--
	--  --React ES7+ React/Redux/React-Native snippet
	--  { "dsznajder/vscode-es7-javascript-react-snippets", build = "yarn install --frozen-lockfile && yarn compile" },
	--
	--  -- Emmet
	--  { "mattn/emmet-vim" },
	--
	--  -- Sticky header
	--  { "nvim-treesitter/nvim-treesitter-context" },
	--
	--  { "maxmellon/vim-jsx-pretty" }, -- The React syntax highlighting and indenting plugin for vim. Also supports the typescript tsx file.
	--  { "yuezk/vim-js" }, -- A Vim syntax highlighting plugin for JavaScript and Flow.js
	--
	--  { "HerringtonDarkholme/yats" }, -- Yet Another TypeScript Syntax file for Vim, adapted from YAJS
	--
	--  -- Git
	--  { "lewis6991/gitsigns.nvim"},
	--
	--  -- increase number limit for hlsearch
	--  { "google/vim-searchindex" },
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
