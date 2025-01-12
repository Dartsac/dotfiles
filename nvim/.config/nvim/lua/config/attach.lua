if os.getenv("NVIM_NO_HARPOON") == "1" then
	return
end

local ok, harpoon = pcall(require, "harpoon")
if ok then
	local marks = harpoon:list().items
	if #marks > 0 then
		harpoon:list():select(1)
	end
end
