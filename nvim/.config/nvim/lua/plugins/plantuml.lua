-- Dependencies: Java and Graphviz (brew install openjdk graphviz). The preview
-- runs `java` from PATH with the PlantUML jar bundled with
-- plantuml-previewer.vim; lua/config/local.lua can name others
-- (g:plantuml_previewer#java_path, g:plantuml_previewer#plantuml_jar_path).
return {
	{
		"weirongxu/plantuml-previewer.vim",
		ft = { "puml", "plantuml" },
		dependencies = {
			"aklt/plantuml-syntax",
			"tyru/open-browser.vim",
		},
	},
}
