-- Quickfix list history (:colder/:cnewer) without raw E380/E381 errors at
-- either end of the stack.
local M = {}

---@param direction "older"|"newer"
---@return boolean moved
function M.history(direction)
	local ok, err = pcall(vim.cmd, direction == "older" and "colder" or "cnewer")
	if not ok then
		local edge = direction == "older" and "oldest" or "newest"
		local message = tostring(err):match("E38[01]") and ("Already at the " .. edge .. " quickfix list")
			or tostring(err)
		vim.notify(message, vim.log.levels.INFO)
		return false
	end
	return true
end

return M
