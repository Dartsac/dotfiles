return {
	{
		"windwp/nvim-autopairs",
		event = "InsertCharPre",
		dependencies = {
			{
				"windwp/nvim-ts-autotag",
				event = "InsertCharPre",
				config = function()
					require("nvim-ts-autotag").setup()
				end,
			},
			{
				"axelvc/template-string.nvim",
				event = "InsertCharPre",
				config = function()
					require("template-string").setup({
						filetypes = {
							"html",
							"typescript",
							"javascript",
							"typescriptreact",
							"javascriptreact",
							"vue",
							"svelte",
							"python",
						}, -- filetypes where the plugin is active
						jsx_brackets = true, -- must add brackets to JSX attributes
						remove_template_string = false, -- remove backticks when there are no template strings
						restore_quotes = {
							-- quotes used when "remove_template_string" option is enabled
							normal = [[']],
							jsx = [["]],
						},
					})
				end,
			},
		},
		config = function()
			-- Helper function to check plugin availability
			local safe_require = function(module)
				local ok, lib = pcall(require, module)
				return ok and lib or nil
			end

			-- Safely load required modules
			local npairs = safe_require("nvim-autopairs")
			if not npairs then
				return
			end
			local Rule = safe_require("nvim-autopairs.rule")
			local cond = safe_require("nvim-autopairs.conds")
			local cmp = safe_require("cmp")
			local cmp_autopairs = safe_require("nvim-autopairs.completion.cmp")

			-- Main nvim-autopairs setup
			npairs.setup({
				check_ts = true, -- Enable treesitter integration
				ts_config = {
					lua = { "string", "source" }, -- Exclude Lua strings
					javascript = { "string", "template_string" },
					java = false, -- Disable treesitter for Java
				},
				disable_filetype = { "TelescopePrompt", "spectre_panel" },
				fast_wrap = {
					map = "<C-e>",
					chars = { "{", "[", "(", '"', "'" },
					pattern = string.gsub([[ [%'%"%)%>%]%)%}%,%;] ]], "%s+", ""),
					offset = 0,
					end_key = "$",
					keys = "qwertyuiopzxcvbnmasdfghjkl",
					check_comma = true,
					highlight = "PmenuSel",
					highlight_grey = "LineNr",
				},
			})

			-- Add custom rules
			if Rule and cond then
				npairs.add_rules({
					-- Rule for function body braces
					Rule("%(.*%)%s*%=$", "> {}", { "typescript", "typescriptreact", "javascript" })
						:use_regex(true)
						:set_end_pair_length(1),

					-- Rule for `=` pairs
					Rule("=", "")
						:with_pair(cond.not_inside_quote())
						:with_pair(function(opts)
							local last_char = opts.line:sub(opts.col - 1, opts.col - 1)
							return last_char:match("[%w%=%s]") ~= nil
						end)
						:replace_endpair(function(opts)
							local prev_2char = opts.line:sub(opts.col - 2, opts.col - 1)
							local next_char = opts.line:sub(opts.col, opts.col) == " " and "" or " "
							if prev_2char:match("%w$") then
								return "<bs> =" .. next_char
							end
							if prev_2char:match("%=$") then
								return next_char
							end
							if prev_2char:match("=") then
								return "<bs><bs>=" .. next_char
							end
							return ""
						end)
						:set_end_pair_length(0)
						:with_move(cond.none())
						:with_del(cond.none()),
				})

				-- Handle brackets with custom space rules
				local brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } }
				for _, bracket in ipairs(brackets) do
					npairs.add_rules({
						Rule(" ", " "):with_pair(function(opts)
							local pair = opts.line:sub(opts.col - 1, opts.col)
							return vim.tbl_contains({
								brackets[1][1] .. brackets[1][2],
								brackets[2][1] .. brackets[2][2],
								brackets[3][1] .. brackets[3][2],
							}, pair)
						end),
						Rule(bracket[1] .. " ", " " .. bracket[2])
							:with_pair(function()
								return false
							end)
							:with_move(function(opts)
								return opts.prev_char:match(".%" .. bracket[2]) ~= nil
							end)
							:use_key(bracket[2]),
					})
				end
			end

			-- Integrate with nvim-cmp if available
			if cmp and cmp_autopairs then
				cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done({ map_char = { tex = "" } }))
			end
		end,
	},
}
