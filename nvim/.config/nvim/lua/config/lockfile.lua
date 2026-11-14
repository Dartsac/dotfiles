-- Commit lazy-lock.json by itself after lazy.nvim changes it, so plugin
-- updates never leave it modified. The commit is not pushed. Off unless this
-- machine's local override (lua/config/local.lua) sets
-- vim.g.commit_lazy_lockfile = true: an adopter's clone gets no commits.
local M = {}

local MESSAGE = "[NVIM] Update plugin lockfile"
local EVENTS = { "LazyInstall", "LazyUpdate", "LazySync", "LazyRestore", "LazyClean" }
-- lazy.nvim fires its event just before it writes the lockfile.
local WRITE_DELAY_MS = 1000
-- Present in the git directory while a merge, rebase or cherry-pick is underway.
local IN_PROGRESS = { "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply" }

local function git(dir, args)
	local result = vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait()
	return result.code, vim.trim((result.stdout or "") .. (result.stderr or ""))
end

--- Commit `path` alone if git tracks it and it differs from HEAD.
---@param path string lockfile path; symlinks are resolved
---@return string? what happened: "committed", or why nothing was committed
function M.commit(path)
	local file = vim.uv.fs_realpath(path)
	if not file then
		return "no lockfile"
	end
	local dir = vim.fs.dirname(file)
	if git(dir, { "ls-files", "--error-unmatch", "--", file }) ~= 0 then
		return "not tracked by git"
	end
	if git(dir, { "diff", "--quiet", "HEAD", "--", file }) == 0 then
		return "unchanged"
	end
	local _, git_dir = git(dir, { "rev-parse", "--absolute-git-dir" })
	for _, name in ipairs(IN_PROGRESS) do
		if vim.uv.fs_stat(git_dir .. "/" .. name) then
			return "skipped: " .. name .. " in progress"
		end
	end
	-- A path after "--" commits that file only, whatever else is staged.
	local code, output = git(dir, { "commit", "--quiet", "-m", MESSAGE, "--", file })
	if code ~= 0 then
		vim.notify("lazy-lock.json was not committed:\n" .. output, vim.log.levels.WARN)
		return "failed"
	end
	vim.notify("Committed lazy-lock.json (not pushed)")
	return "committed"
end

function M.setup()
	vim.api.nvim_create_autocmd("User", {
		pattern = EVENTS,
		group = vim.api.nvim_create_augroup("lockfile_commit", { clear = true }),
		callback = function()
			-- Asked when lazy.nvim fires, as the local override loads after this.
			-- Test sessions point lazy.nvim at a throwaway lockfile; leave git alone.
			if vim.g.commit_lazy_lockfile ~= true or vim.env.NVIM_LAZY_LOCKFILE then
				return
			end
			vim.defer_fn(function()
				M.commit(require("lazy.core.config").options.lockfile)
			end, WRITE_DELAY_MS)
		end,
	})
end

return M
