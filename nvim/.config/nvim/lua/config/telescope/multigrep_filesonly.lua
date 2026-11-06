-- lua/config/telescope/multigrep_filesonly.lua
-- File shortlist: files containing every `&&` term. See config/telescope/compound.lua.
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local compound = require("config.telescope.compound")

return function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.uv.cwd()
	opts.shortcuts = opts.shortcuts or compound.shortcuts
	opts.pattern = opts.pattern or "%s"

	local custom_grep = finders.new_async_job({
		command_generator = compound.generator("files", opts),

		-- ripgrep prints names relative to the search directory. The entry keeps
		-- the absolute path, so opening or exporting a result still names this
		-- project's file after the working directory changes (e.g. <leader>sl
		-- resuming the cached picker from another project).
		entry_maker = function(line)
			local path = line:sub(1, 1) == "/" and line or vim.fs.joinpath(opts.cwd, line)
			return {
				value = line,
				display = line,
				ordinal = line,
				path = vim.fs.normalize(path),
				cwd = opts.cwd,
			}
		end,

		cwd = opts.cwd,
	})

	pickers
		.new(opts, {
			debounce = 100,
			prompt_title = "Multi Grep (Files Only)",
			finder = custom_grep,
			previewer = conf.file_previewer(opts),
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
