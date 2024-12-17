-- Dependencies:
-- Java
-- Graphviz
-- brew install graphviz
return {
	{
		"weirongxu/plantuml-previewer.vim",
		ft = { ".puml", "plantuml" },
		dependencies = {
			"aklt/plantuml-syntax",
			"tyru/open-browser.vim",
		},
	},
}
