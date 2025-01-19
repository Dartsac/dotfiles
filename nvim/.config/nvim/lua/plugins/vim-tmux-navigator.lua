return {
	"christoomey/vim-tmux-navigator",
	cmd = {
		"TmuxNavigateLeft",
		"TmuxNavigateDown",
		"TmuxNavigateUp",
		"TmuxNavigateRight",
		"TmuxNavigatePrevious",
		"TmuxNavigatorProcessList",
	},
	keys = {
		{ "<c-h>", "<cmd>TmuxNavigateLeft<cr>", mode = { "n", "v" } },
		{ "<c-j>", "<cmd>TmuxNavigateDown<cr>", mode = { "n", "v" } },
		{ "<c-k>", "<cmd>TmuxNavigateUp<cr>", mode = { "n", "v" } },
		{ "<c-l>", "<cmd>TmuxNavigateRight<cr>", mode = { "n", "v" } },
		{ "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", mode = { "n", "v" } },
		{ "<c-h>", "<C-o>:TmuxNavigateLeft<CR>", mode = "i" },
		{ "<c-j>", "<C-o>:TmuxNavigateDown<CR>", mode = "i" },
		{ "<c-k>", "<C-o>:TmuxNavigateUp<CR>", mode = "i" },
		{ "<c-l>", "<C-o>:TmuxNavigateRight<CR>", mode = "i" },
	},
}
