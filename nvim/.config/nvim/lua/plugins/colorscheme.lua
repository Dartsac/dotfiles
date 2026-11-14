-- The free Dracula theme. config.colorscheme picks it when the Dracula PRO
-- package is not installed, and applies the colorscheme once lazy.nvim has
-- put this plugin on the runtime path.
return {
	"dracula/vim",
	name = "dracula",
	lazy = false,
	priority = 1000, -- before every other plugin, so they see its highlights
	config = function()
		require("config.colorscheme").setup()
	end,
}
