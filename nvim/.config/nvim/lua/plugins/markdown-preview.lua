-- Builds the preview server from source with yarn where yarn is installed;
-- otherwise downloads the plugin's prebuilt server for this version, with
-- curl or wget. With none of them there is no preview and no error: install
-- one, then run `:Lazy build markdown-preview.nvim`.
local function build(plugin)
	local app = plugin.dir .. "/app"
	local args
	if vim.fn.executable("yarn") == 1 then
		args = { "yarn", "install" }
	elseif vim.fn.executable("curl") == 1 or vim.fn.executable("wget") == 1 then
		local version = vim.json.decode(table.concat(vim.fn.readfile(plugin.dir .. "/package.json"), "\n")).version
		args = { "./install.sh", "v" .. version }
	else
		return
	end
	local result = vim.system(args, { cwd = app, text = true }):wait()
	if result.code ~= 0 then
		error(table.concat(args, " ") .. " failed:\n" .. (result.stderr or "") .. (result.stdout or ""))
	end
end

return {
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = build,
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		-- Loaded before FileType for Markdown files: see plugins/markdown.lua.
		event = { "BufReadPre *.md,*.markdown", "BufNewFile *.md,*.markdown" },
		ft = { "markdown" },
	},
}
