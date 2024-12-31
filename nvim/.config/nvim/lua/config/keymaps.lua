local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap

-- Mappings
keymap("n", "<S-l>", ":bnext<CR>", opts)
keymap("n", "<S-h>", ":bprevious<CR>", opts)
keymap("n", "<C-d>", "<C-d>zz", opts)
keymap("n", "<C-u>", "<C-u>zz", opts)
keymap("n", "n", "nzzzv", opts)
keymap("n", "N", "Nzzzv", opts)

-- Insert --
keymap("i", "jk", "<ESC>", opts)
keymap("i", "kj", "<ESC>", opts)

-- Visual --
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

-- Visual Block --
keymap("x", "J", ":move '>+1<CR>gv=gv", opts)
keymap("x", "K", ":move '<-2<CR>gv=gv", opts)
keymap("x", "<leader>p", '"_dP', opts)
