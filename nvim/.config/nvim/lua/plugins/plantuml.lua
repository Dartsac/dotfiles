-- Dependencies:
-- Java
-- Graphviz
-- brew install graphviz
return {
	{
		"weirongxu/plantuml-previewer.vim",
		ft = { "puml", "plantuml" },
		dependencies = {
			"aklt/plantuml-syntax",
			"tyru/open-browser.vim",
		},
		init = function()
			vim.g["plantuml_previewer#java_path"] = "/opt/homebrew/opt/openjdk/bin/java"
			vim.g["plantuml_previewer#plantuml_jar_path"] = vim.fn.expand("~/tools/plantuml/plantuml.jar")
		end,
	},
}
