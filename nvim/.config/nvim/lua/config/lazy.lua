-- Normally lazy-lock.json beside this config. $NVIM_LAZY_LOCKFILE points it
-- at a copy, so a throwaway (test) session can never rewrite the real one.
local lockfile = vim.env.NVIM_LAZY_LOCKFILE or (vim.fn.stdpath("config") .. "/lazy-lock.json")

--- The lazy.nvim commit lazy-lock.json names, if any.
local function locked_lazy_commit()
	local ok, lock = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
	end)
	return ok and type(lock) == "table" and vim.tbl_get(lock, "lazy.nvim", "commit") or nil
end

-- Bootstrap lazy.nvim at the commit lazy-lock.json names (it installs every
-- other plugin at its locked commit), so a first start leaves the lockfile as
-- it found it; the latest stable release without one.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local commit = locked_lazy_commit()
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		commit and "--no-checkout" or "--branch=stable",
		lazyrepo,
		lazypath,
	})
	if vim.v.shell_error == 0 and commit then
		out = vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
	end
	if vim.v.shell_error ~= 0 then
		vim.fn.delete(lazypath, "rf") -- so the next start tries again
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
-- lazy.nvim puts this directory on the runtime path, and nvim-treesitter
-- installs parsers into it. Neovim caches the runtime path's directories, so
-- one created later (on a first start) is not searched until a restart, and
-- the parsers installed then would go unused for the session.
vim.fn.mkdir(vim.fn.stdpath("data") .. "/site", "p")

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
		-- { "christoomey/vim-tmux-navigator" },
	},
	change_detection = {
		enabled = true,
		notify = false,
	},
	cache = {
		enabled = true,
		-- path = vim.fn.stdpath("cache") .. "/lazy/cache",
	},
	performance = {
		rtp = {
			-- lazy.nvim drops Neovim's site packages from the runtime path. Keep
			-- the Dracula PRO theme that theme-sync installs there, so
			-- :colorscheme and the Telescope picker find it after startup.
			paths = { vim.fn.stdpath("data") .. "/site/pack/themes/start/dracula-pro" },
		},
	},
	lockfile = lockfile,
})
