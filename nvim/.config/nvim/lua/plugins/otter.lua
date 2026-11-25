return {
	"jmbuhr/otter.nvim",
	-- Loaded before FileType for Markdown files: see plugins/markdown.lua.
	event = { "BufReadPre *.md,*.markdown", "BufNewFile *.md,*.markdown" },
	ft = "markdown",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	opts = {
		buffers = {
			-- FileType triggers the existing vim.lsp.enable() server setup.
			set_filetype = true,
			write_to_disk = false,
		},
	},
	init = function()
		local group = vim.api.nvim_create_augroup("_markdown_otter", { clear = true })
		-- Activate the buffer once it is on screen: started as the file was read,
		-- otter took 70 of the 165 ms the README took to show. A buffer left
		-- before then waits until it is shown again. otter works on the current
		-- buffer, and makes its raft for it, code or none, so a raft is a buffer
		-- it has taken up.
		local function on_screen(buf)
			vim.b[buf].otter_pending = nil
			if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "markdown" then
				return
			end
			if vim.api.nvim_get_current_buf() ~= buf then
				-- Left meanwhile: once it is entered again, and only one waits.
				vim.b[buf].otter_pending = true
				vim.api.nvim_create_autocmd("BufEnter", {
					group = group,
					buffer = buf,
					once = true,
					callback = function()
						vim.schedule(function()
							on_screen(buf)
						end)
					end,
				})
				return
			end
			-- Requiring the module lazy-loads and configures the plugin first.
			if require("otter.keeper").rafts[buf] then
				return
			end
			-- The screen first: what the event loop has drawn by now is not certain.
			if #vim.api.nvim_list_uis() > 0 then
				vim.cmd.redraw()
			end
			require("otter").activate()
		end
		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = "markdown",
			desc = "Enable language servers in Markdown code fences",
			callback = function(args)
				-- LSP hover/signature floats are unnamed scratch buffers with
				-- filetype=markdown. Otter derives its hidden buffer names from the
				-- main buffer's path, so every float maps to the same name and the
				-- second one fails with E95. Only attach to real files.
				if vim.bo[args.buf].buftype ~= "" or vim.api.nvim_buf_get_name(args.buf) == "" then
					return
				end
				if vim.b[args.buf].otter_pending then
					return
				end
				vim.b[args.buf].otter_pending = true
				local buf = args.buf
				vim.schedule(function()
					on_screen(buf)
				end)
			end,
		})
	end,
}
