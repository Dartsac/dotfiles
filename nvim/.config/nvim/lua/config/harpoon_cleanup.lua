-- Keep Harpoon lists free of entries for deleted files, without guessing.
--
-- 1. After a *successful* Snacks explorer delete/trash, remove the entries that
--    pointed at the deleted path or anything under it. Canceled or failed
--    deletes, and buffer closes, never reach this code.
-- 2. For files that disappeared some other way, `:HarpoonCleanMissing` lists
--    the missing entries and removes them only after confirmation. Nothing is
--    pruned automatically: a branch switch or unmounted drive also makes
--    targets absent.
--
-- Harpoon keeps one list set per project key (the cwd by default), with entry
-- paths relative to that key. Entries are resolved against the current key,
-- so an identically named file in another project is never touched. Removed
-- entries close up; survivors keep their order. Changes are written with
-- harpoon:sync() to the current project's Harpoon data file.
local M = {}

local uv = vim.uv

local function normalize(path)
	return vim.fs.normalize(path)
end

local function under(path, root)
	return path == root or vim.startswith(path, root .. "/")
end

---@param key string Harpoon list key (project directory)
---@param value string entry value, relative to key or absolute
---@return string
function M.resolve(key, value)
	if value:sub(1, 1) == "~" then
		value = vim.fn.expand(value)
	end
	if value:sub(1, 1) ~= "/" then
		value = key .. "/" .. value
	end
	return normalize(value)
end

local function harpoon()
	local ok, mod = pcall(require, "harpoon")
	if ok and type(mod) == "table" and mod.list then
		return mod
	end
	return nil
end

--- Every list for the current project key, including lists only in the data file.
---@return string|nil key, table[] lists
local function current_lists(h)
	local key = h.config.settings.key()
	local default = require("harpoon.config").DEFAULT_LIST
	local seen = { [default] = true }
	for name in pairs(h.lists[key] or {}) do
		seen[name] = true
	end
	local raw = h.data and h.data._data and h.data._data[key]
	for name in pairs(type(raw) == "table" and raw or {}) do
		seen[name] = true
	end
	local lists = {}
	for name in pairs(seen) do
		local ok, list = pcall(h.list, h, name)
		if ok and list then
			lists[#lists + 1] = list
		end
	end
	return key, lists
end

---@class HarpoonCandidate
---@field list table HarpoonList
---@field item table HarpoonItem
---@field index integer
---@field path string resolved entry path

---@param h table
---@param match fun(path: string, real: string|nil): boolean
---@return HarpoonCandidate[]
local function collect(h, match)
	local key, lists = current_lists(h)
	local found = {}
	for _, list in ipairs(lists) do
		for index = 1, list:length() do
			local item = list.items[index]
			if item and type(item.value) == "string" and item.value ~= "" then
				local path = M.resolve(key, item.value)
				if match(path, uv.fs_realpath(path)) then
					found[#found + 1] = { list = list, item = item, index = index, path = path }
				end
			end
		end
	end
	return found
end

--- Remove the given items from their lists, keeping survivors in order.
---@param h table
---@param candidates HarpoonCandidate[]
---@return integer removed
local function remove(h, candidates)
	local by_list = {}
	for _, candidate in ipairs(candidates) do
		by_list[candidate.list] = by_list[candidate.list] or {}
		by_list[candidate.list][candidate.item] = true
	end
	local removed = 0
	for list, items in pairs(by_list) do
		local survivors = {}
		for index = 1, list:length() do
			local item = list.items[index]
			if item then
				if items[item] then
					removed = removed + 1
				else
					survivors[#survivors + 1] = item
				end
			end
		end
		list.items = survivors
		list._length = #survivors
	end
	if removed > 0 then
		h:sync()
	end
	return removed
end

--- Entries that a delete of `path` would affect: the path itself or anything
--- below it, by literal path or (when `path` is not itself a symlink) by
--- resolved path. Call before deleting, while symlinks still resolve.
---@param path string absolute path about to be deleted
---@return HarpoonCandidate[]
function M.candidates(path)
	local h = harpoon()
	if not h then
		return {}
	end
	local target = normalize(path)
	local stat = uv.fs_lstat(target)
	local target_real = stat and stat.type ~= "link" and uv.fs_realpath(target) or nil
	return collect(h, function(entry, real)
		return under(entry, target) or (target_real ~= nil and real ~= nil and under(real, target_real))
	end)
end

--- After a successful delete: drop candidates whose target is now gone.
---@param candidates HarpoonCandidate[]
---@return integer removed
function M.remove_deleted(candidates)
	local h = harpoon()
	if not h or #candidates == 0 then
		return 0
	end
	local gone = vim.tbl_filter(function(candidate)
		return uv.fs_stat(candidate.path) == nil
	end, candidates)
	local removed = remove(h, gone)
	if removed > 0 then
		vim.notify(
			("Harpoon: removed %d entr%s for the deleted path"):format(removed, removed == 1 and "y" or "ies"),
			vim.log.levels.INFO
		)
	end
	return removed
end

--- Wrap Snacks' explorer trash/delete so successful deletions clean Harpoon.
--- `actions.trash(path)` returns true only when the path was actually trashed
--- or deleted; the explorer's confirmation happens before it is called.
---@param actions table require("snacks.explorer.actions")
---@return boolean wrapped
function M.wrap_snacks_delete(actions)
	if type(actions) ~= "table" or type(actions.trash) ~= "function" then
		vim.notify("Harpoon cleanup: Snacks explorer delete hook not found", vim.log.levels.WARN)
		return false
	end
	if actions._harpoon_cleanup then
		return true
	end
	local trash = actions.trash
	actions.trash = function(path, ...)
		local ok_candidates, candidates = pcall(M.candidates, path)
		local ok, err = trash(path, ...)
		if ok and ok_candidates then
			local cleaned, cleanup_err = pcall(M.remove_deleted, candidates)
			if not cleaned then
				vim.notify("Harpoon cleanup failed: " .. tostring(cleanup_err), vim.log.levels.ERROR)
			end
		end
		return ok, err
	end
	actions._harpoon_cleanup = true
	return true
end

--- Entries in the current project whose target does not exist right now.
---@return HarpoonCandidate[]
function M.missing()
	local h = harpoon()
	if not h then
		return {}
	end
	return collect(h, function(path)
		return uv.fs_stat(path) == nil
	end)
end

--- Reviewed cleanup of missing entries: list them, confirm, then remove.
---@return integer removed
function M.clean_missing()
	local h = harpoon()
	if not h then
		vim.notify("Harpoon is not available", vim.log.levels.WARN)
		return 0
	end
	local missing = M.missing()
	if #missing == 0 then
		vim.notify("Harpoon: no missing entries in this project", vim.log.levels.INFO)
		return 0
	end
	local lines = {
		"These Harpoon entries point at missing files.",
		"(Deleted, renamed, on another branch, or on an unavailable drive.)",
		"",
	}
	for _, entry in ipairs(missing) do
		local list = entry.list.name ~= require("harpoon.config").DEFAULT_LIST and (" [" .. entry.list.name .. "]")
			or ""
		lines[#lines + 1] = ("  %d. %s%s"):format(entry.index, entry.item.value, list)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Remove them from Harpoon?"
	local choice = vim.fn.confirm(table.concat(lines, "\n"), "&Remove\n&Keep", 2)
	if choice ~= 1 then
		vim.notify("Harpoon: kept all entries", vim.log.levels.INFO)
		return 0
	end
	-- Re-check: only remove what is still missing now.
	local still = vim.tbl_filter(function(entry)
		return uv.fs_stat(entry.path) == nil
	end, missing)
	local removed = remove(h, still)
	vim.notify(
		("Harpoon: removed %d missing entr%s"):format(removed, removed == 1 and "y" or "ies"),
		vim.log.levels.INFO
	)
	return removed
end

return M
