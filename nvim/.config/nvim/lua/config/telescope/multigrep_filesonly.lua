-- lua/config/telescope/multigrep_filesonly.lua
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")

return function(opts)
	opts = opts or {}
	---@diagnostic disable-next-line: undefined-field
	opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()
	opts.shortcuts = opts.shortcuts
		or {
			["l"] = "*.lua",
			["v"] = "*.vim",
			["n"] = "*.{vim,lua}",
			["c"] = "*.c",
			["r"] = "*.rs",
			["g"] = "*.go",
		}
	opts.pattern = opts.pattern or "%s"

	local custom_grep = finders.new_async_job({
		command_generator = function(prompt)
			if not prompt or prompt == "" then
				return nil
			end

			local prompt_split = vim.split(prompt, "  ")

			local args = { "rg", "-l" }

			if prompt_split[1] then
				table.insert(args, "-e")
				table.insert(args, prompt_split[1])
			end

			if prompt_split[2] then
				table.insert(args, "-g")
				local pattern
				if opts.shortcuts[prompt_split[2]] then
					pattern = opts.shortcuts[prompt_split[2]]
				else
					pattern = prompt_split[2]
				end
				table.insert(args, string.format(opts.pattern, pattern))
			end

			return vim.iter({
				args,
				{ "--color=auto", "--no-heading", "--smart-case" },
			})
				:flatten()
				:totable()
		end,

		entry_maker = function(line)
			return {
				value = line,
				display = line,
				ordinal = line,
				path = line,
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
		})
		:find()
end
