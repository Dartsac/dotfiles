"""A made-up Dracula PRO theme package, for tests of what theme-sync does with
one. Its colors are invented here, never the paid ones: each is a shade no
other name uses, neither grey nor one of the free Dracula theme's.

  write_package(folder)   the package, in the shape theme-sync reads
  PALETTES                {variant: {name: "#rrggbb"}}, as theme-sync names them
"""
from importlib.machinery import SourceFileLoader
import importlib.util
from pathlib import Path
import sys

# Loading theme-sync must not leave its bytecode in __pycache__ at the
# repository's root: a folder there that is not hidden is a package to `stow */`.
sys.dont_write_bytecode = True


def load_theme_sync():
    """theme-sync as a module, loaded afresh."""
    loader = SourceFileLoader("theme_sync", str(Path(__file__).resolve().parents[1] / "theme-sync"))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


# How theme-sync names a palette.md row, and the free Dracula theme's colors,
# which a made-up one must not be.
THEME_SYNC = load_theme_sync()
snake = THEME_SYNC.snake
# palette.md's rows, as the package names them, in the order of a terminal's
# 16 colors, then the rest.
ROWS = [
    "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
    "BrightBlack", "BrightRed", "BrightGreen", "BrightYellow", "BrightBlue", "BrightMagenta", "BrightCyan", "BrightWhite",
    "DimBlack", "DimRed", "DimGreen", "DimYellow", "DimBlue", "DimMagenta", "DimCyan", "DimWhite",
    "Background", "Foreground", "Comment", "Selection", "Cursor", "Orange",
]
# The background shades, which only the Vim theme names.
SHADES = ["bg", "bglight", "bglighter", "bgdark", "bgdarker"]
# Variant (the name of its Ghostty theme) -> its name in palette.md, and the
# stem of its Vim theme.
VARIANTS = {"pro": ("Base", "dracula-pro"), "van-helsing": ("Van Helsing", "dracula-pro-van-helsing")}


def made_up_palettes():
    palettes, used = {}, set()
    step = 0
    for variant in VARIANTS:
        colors = {}
        for name in [snake(row) for row in ROWS] + SHADES:
            while True:
                step += 1
                red, green, blue = (40 + step * 37) % 216 + 20, (90 + step * 71) % 216 + 20, (150 + step * 113) % 216 + 20
                value = f"{red:02x}{green:02x}{blue:02x}"
                if value not in used and value not in THEME_SYNC.FREE_DRACULA and not red == green == blue:
                    break
            used.add(value)
            colors[name] = "#" + value
        colors.update(purple=colors["blue"], pink=colors["magenta"])  # the theme's own names
        palettes[variant] = colors
    return palettes


PALETTES = made_up_palettes()


def ghostty_theme_text(colors):
    terminal = [snake(row) for row in ROWS[:16]]
    lines = [f"palette = {i}={colors[name]}" for i, name in enumerate(terminal)]
    lines += [f"background = {colors['background']}", f"foreground = {colors['foreground']}",
              f"cursor-color = {colors['cursor']}", f"selection-background = {colors['selection']}"]
    return "\n".join(lines) + "\n"


def vim_theme(colors, stem):
    """A colorscheme with only what Neovim's config reads: the palette, in
    the shape the package's own gives it, and a Normal group."""
    def entry(name):
        return f"['{colors[name]}', 0]"

    keys = {"fg": "foreground", "comment": "comment", "selection": "selection", "red": "red", "orange": "orange",
            "yellow": "yellow", "green": "green", "purple": "purple", "cyan": "cyan", "pink": "pink"}
    lines = ["hi clear", "if exists('syntax_on') | syntax reset | endif", "set background=dark",
             "let g:dracula_pro#palette = {}"]
    lines += [f"let g:dracula_pro#palette.{key} = {entry(name)}" for key, name in keys.items()]
    lines += [f"let g:dracula_pro#palette.{shade} = {entry(shade)}" for shade in SHADES]
    lines += [f"let g:dracula_pro#palette.color_11 = '{colors['bright_yellow']}'",
              f"hi Normal guifg={colors['foreground']} guibg={colors['bg']}",
              f"let g:colors_name = '{stem}'"]
    return "\n".join(lines) + "\n"


def write_package(folder):
    """Write the package into `folder` (a new directory); return it."""
    folder = Path(folder)
    sections = ["# Dracula PRO, made up for tests", "", "# Color Palette - Terminal Standard", ""]
    for variant, (title, stem) in VARIANTS.items():
        colors = PALETTES[variant]
        sections += [f"## Dracula PRO - {title}", "", "| Palette | Hex |", "| --- | --- |"]
        sections += [f"| {row} | `{colors[snake(row)]}` |" for row in ROWS] + [""]
        (folder / "themes/ghostty").mkdir(parents=True, exist_ok=True)
        (folder / "themes/ghostty" / variant).write_text(ghostty_theme_text(colors))
        (folder / "themes/vim/colors").mkdir(parents=True, exist_ok=True)
        (folder / "themes/vim/colors" / f"{stem}.vim").write_text(vim_theme(colors, stem))
    (folder / "design").mkdir(parents=True, exist_ok=True)
    (folder / "design/palette.md").write_text("\n".join(sections))
    return folder
