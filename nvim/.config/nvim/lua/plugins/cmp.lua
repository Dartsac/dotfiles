return {
	"hrsh7th/nvim-cmp",
	event = "InsertEnter",
	dependencies = {
		{ "hrsh7th/cmp-nvim-lsp", event = "InsertEnter" },
		{ "hrsh7th/cmp-path", event = "InsertEnter" },
		{ "hrsh7th/cmp-buffer", event = "InsertEnter" },
		{ "L3MON4D3/LuaSnip", event = "InsertEnter", dependencies = "rafamadriz/friendly-snippets" },
		{ "saadparwaiz1/cmp_luasnip", event = "InsertEnter" },
	},
	config = function()
		local cmp_status_ok, cmp = pcall(require, "cmp")
		if not cmp_status_ok then
			return
		end

		local snip_status_ok, luasnip = pcall(require, "luasnip")
		if not snip_status_ok then
			return
		end

		local icons = require("config.icons")

		local s = luasnip.snippet
		local i = luasnip.insert_node
		local fmt = require("luasnip.extras.fmt").fmt

		luasnip.add_snippets("typescriptreact", {
			s("work", fmt("console.log({})", { i(1) })),
		})

		require("luasnip/loaders/from_vscode").lazy_load()

		local check_backspace = function()
			local col = vim.fn.col(".") - 1
			return col == 0 or vim.fn.getline("."):sub(col, col):match("%s")
		end

		cmp.setup({
			snippet = {
				expand = function(args)
					luasnip.lsp_expand(args.body) -- For `luasnip` users.
				end,
			},
			mapping = {
				["<C-Space>"] = cmp.mapping.complete(),
				["<CR>"] = cmp.mapping.confirm({ select = true }),
				["<Tab>"] = cmp.mapping(function(fallback)
					if cmp.visible() then
						cmp.select_next_item()
					elseif luasnip.expandable() then
						luasnip.expand()
					elseif luasnip.expand_or_jumpable() then
						luasnip.expand_or_jump()
					elseif check_backspace() then
						fallback()
					else
						fallback()
					end
				end, {
					"i",
					"s",
				}),
				["<S-Tab>"] = cmp.mapping(function(fallback)
					if cmp.visible() then
						cmp.select_prev_item()
					elseif luasnip.jumpable(-1) then
						luasnip.jump(-1)
					else
						fallback()
					end
				end, {
					"i",
					"s",
				}),
			},
			formatting = {
				fields = { "kind", "abbr", "menu" },
				format = function(entry, vim_item)
					-- Kind icons
					-- vim_item.kind = string.format("%s", kind_icons[vim_item.kind])
					vim_item.kind = string.format("%s %s", icons.kind[vim_item.kind], vim_item.kind) -- This concatonates the icons with the name of the item kind
					vim_item.menu = ({
						nvim_lsp = "[LSP]",
						luasnip = "[Snippet]",
						buffer = "[Buffer]",
						path = "[Path]",
					})[entry.source.name]
					return vim_item
				end,
			},
			sources = {
				{ name = "nvim_lsp" },
				{ name = "luasnip" },
				{ name = "buffer" },
				{ name = "path" },
			},
			confirm_opts = {
				behavior = cmp.ConfirmBehavior.Replace,
				select = false,
			},
			window = {
				documentation = {
					border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
				},
			},
			experimental = {
				ghost_text = false,
				native_menu = false,
			},
		})

		--sql specific dadbod completion
		-- cmp.setup.filetype({ "sql" }, {
		-- 	sources = {
		-- 		{ name = "vim-dadbod-completion" },
		-- 		{ name = "buffer" },
		-- 	},
		-- })
	end,
}
