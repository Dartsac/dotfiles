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
		-- In the buffer, once: otter works on the current buffer.
		local function activate(buf)
			if vim.bo[buf].filetype ~= "markdown" or require("otter.keeper").rafts[buf] then
				return
			end
			-- Requiring the module lazy-loads and configures the plugin first.
			vim.api.nvim_buf_call(buf, function()
				require("otter").activate()
			end)
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
				-- Once the file is on screen: started as the file was read,
				-- otter took 70 of the 165 ms the README took to show. A
				-- buffer left meanwhile waits until it is shown again.
				local buf = args.buf
				vim.schedule(function()
					if vim.api.nvim_get_current_buf() == buf then
						activate(buf)
					elseif vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_create_autocmd("BufEnter", {
							group = group,
							buffer = buf,
							once = true,
							callback = function()
								activate(buf)
							end,
						})
					end
				end)
			end,
		})
	end,
}
