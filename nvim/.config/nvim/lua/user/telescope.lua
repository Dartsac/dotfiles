local status_ok, telescope = pcall(require, "telescope")
if not status_ok then
	return
end

local actions = require("telescope.actions")
local cwd = vim.fn.getcwd()

telescope.setup({
	defaults = {
		file_ignore_patterns = { "node_modules" },
		-- prompt_prefix = " ",
		-- selection_caret = " ",
		-- path_display = { "smart" },

		mappings = {
			i = {
				["<C-j>"] = actions.move_selection_next,
				["<C-k>"] = actions.move_selection_previous,
				["<Tab>"] = actions.move_selection_worse,
				["<S-Tab>"] = actions.move_selection_better,

				["<esc>"] = actions.close,
				["<CR>"] = actions.select_default,
			},
		},
	},
	pickers = {
		-- Default configuration for builtin pickers goes here:
		-- picker_name = {
		--   picker_config_key = value,
		--   ...
		-- }
		-- Now the picker_config_key will be applied every time you call this
		-- builtin picker
	},
	extensions = {
		-- Your extension configuration goes here:
		-- extension_name = {
		--   extension_config_key = value,
		-- }
		-- please take a look at the readme of the extension you want to configure
	},
})

vim.api.nvim_set_keymap("n", "<C-f>", ":Telescope find_files cwd=" .. cwd .. "<CR>", { noremap = true, silent = true })
-- Map Ctrl+Shift+F to Telescope live_grep in iTerm2
-- To make this work in iTerm2, create a custom keybinding for Ctrl+Shift+F
-- and send the escape sequence "O5F":
-- 1. Open iTerm2 Preferences (Cmd+,)
-- 2. Go to the "Keys" tab
-- 3. Click the "+" button under "Key Mappings" to create a new keybinding
-- 4. In the "Keyboard Shortcut" field, press Ctrl+Shift+F
-- 5. In the "Action" dropdown menu, select "Send Escape Sequence"
-- 6. In the "Esc+" field, enter the escape sequence "O5F" (capital letter O, number 5, and capital letter F)
-- 7. Click "OK" to save the new keybinding
vim.api.nvim_set_keymap(
	"n",
	"<Esc>O5F",
	":Telescope live_grep cwd=" .. cwd .. "<CR>",
	{ noremap = true, silent = true }
)
