local devicons = require("nvim-web-devicons")

devicons.setup()

devicons.set_icon({
	lockb = {
		icon = "",
		color = "#cbcb41",
		name = "lockb",
	},
	["tsx"] = {
		icon = "",
		color = "#519aba",
		cterm_color = "26",
		name = "Tsx",
	},
	toml = {
		icon = "",
		color = "#6e8086",
		name = "toml",
	},
	[".npmignore"] = {
		icon = "",
		color = "#c63c42",
		name = ".npmignore",
	},
	["tsconfig.tsbuildinfo"] = {
		icon = "",
		color = "#cbcb41",
		name = "tsconfig.tsbuildinfo",
	},
})
