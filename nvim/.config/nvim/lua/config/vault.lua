-- The one Obsidian vault this config integrates with, if any. Everything
-- vault-specific (obsidian.nvim loading, Marksman exclusion, vault-only keys)
-- asks this module. There is none unless this machine's local override
-- (lua/config/local.lua) sets vim.g.obsidian_vault. $OBSIDIAN_VAULT comes
-- first: tests point it at a synthetic fixture so they never open the real
-- vault.
local M = {}

local function normalize(path)
	return (vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", ""))
end

---@return string? nil when no vault is configured
function M.path()
	-- An empty value, like a missing one, names no vault.
	for _, configured in ipairs({ vim.env.OBSIDIAN_VAULT or "", vim.g.obsidian_vault or "" }) do
		if configured ~= "" then
			return normalize(configured)
		end
	end
	return nil
end

--- The vault root as configured and, if different, as resolved on disk; none
--- without a vault.
---@return string[]
function M.roots()
	local root = M.path()
	if not root then
		return {}
	end
	local real = vim.uv.fs_realpath(root)
	return (real and real ~= root) and { root, real } or { root }
end

--- Whether `file` is inside the vault, comparing both the path as given and
--- its resolved form (so a symlinked route into the vault still counts).
---@param file string
---@return boolean
function M.contains(file)
	if not file or file == "" then
		return false
	end
	local candidates = { normalize(file) }
	local real = vim.uv.fs_realpath(file)
	if real then
		candidates[#candidates + 1] = real
	end
	for _, path in ipairs(candidates) do
		for _, base in ipairs(M.roots()) do
			if path == base or vim.startswith(path, base .. "/") then
				return true
			end
		end
	end
	return false
end

return M
