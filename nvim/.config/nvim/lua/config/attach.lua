-- lua/config/attach.lua
local ok, harpoon = pcall(require, "harpoon")
if ok then
	local marks = harpoon:list().items
	if #marks > 0 then
		harpoon:list():select(1)
	end
end
