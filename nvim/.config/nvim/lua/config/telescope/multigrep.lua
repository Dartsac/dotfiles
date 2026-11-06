-- lua/config/telescope/multigrep.lua
-- Location results: `primary && filter ...  glob`. See config/telescope/compound.lua.
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local make_entry = require("telescope.make_entry")
local pickers = require("telescope.pickers")
local compound = require("config.telescope.compound")

return function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.uv.cwd()
	opts.shortcuts = opts.shortcuts or compound.shortcuts
	opts.pattern = opts.pattern or "%s"

	local custom_grep = finders.new_async_job({
		command_generator = compound.generator("lines", opts),
		entry_maker = make_entry.gen_from_vimgrep(opts),
		cwd = opts.cwd,
	})

	pickers
		.new(opts, {
			debounce = 100,
			prompt_title = "Multi Grep (primary && filters  glob)",
			finder = custom_grep,
			previewer = conf.grep_previewer(opts),
			sorter = require("telescope.sorters").empty(),
			selection_strategy = "reset",
			sorting_strategy = "ascending",
			layout_config = {
				horizontal = {
					prompt_position = "top",
				},
			},
		})
		:find()
end
