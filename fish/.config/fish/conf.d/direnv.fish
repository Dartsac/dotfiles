# Nothing, on purpose. fish reads one file of each name from its conf.d
# folders, the user's first, so this one stands in for the direnv.fish that
# Homebrew's direnv puts in fish's vendor folder. That one hooks direnv in
# every shell before config.fish does it again: asked twice, direnv cost each
# start, `fish -c` too, some 20 ms. And its hook names direnv by its folder in
# Homebrew's Cellar, which goes with the next `brew upgrade direnv`.
# config.fish hooks direnv once, by the name PATH has for it.
