local status_ok, comment = pcall(require, "Comment")
if not status_ok then
	return
end

-- Ensure ts_context_commentstring is available
local ts_status_ok, ts_context_commentstring = pcall(require, "ts_context_commentstring")
if not ts_status_ok then
	return
end

comment.setup({
	pre_hook = function(ctx)
		local U = require("Comment.utils")

		-- Determine the location of the commentstring calculation
		local location = nil
		if ctx.ctype == U.ctype.block then
			location = require("ts_context_commentstring.utils").get_cursor_location()
		elseif ctx.cmotion == U.cmotion.v or ctx.cmotion == U.cmotion.V then
			location = require("ts_context_commentstring.utils").get_visual_start_location()
		end

		-- Use ts_context_commentstring to calculate the correct commentstring
		return require("ts_context_commentstring.internal").calculate_commentstring({
			key = ctx.ctype == U.ctype.line and "__default" or "__multiline",
			location = location,
		})
	end,
})

-- Optional: Set Treesitter context for commentstring handling
ts_context_commentstring.setup({
	enable_autocmd = false, -- Disable automatic context updates if not needed
})
