-- Jump to the first Harpoon mark only *after* Lazy has had a chance
-- to load Harpoon.  Using vim.schedule guarantees this runs on the
-- very next event‑loop tick, after plug‑ins are initialised.

vim.schedule(function()
	if os.getenv("NVIM_NO_HARPOON") == "1" then
		return
	end

	local ok, harpoon = pcall(require, "harpoon")
	if ok then
		local list = harpoon:list()
		if list and #list.items > 0 then
			list:select(1)
		end
	end
end)
