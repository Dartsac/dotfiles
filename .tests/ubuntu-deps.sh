#!/bin/sh
# The dependencies of every package the standalone check covers, on Ubuntu.
# CI (.github/workflows/standalone.yml) and .tests/linux.sh both run this
# file, so the two cannot drift apart. Add a package's dependencies here when
# its check is added.
set -eu
sudo=
[ "$(id -u)" = 0 ] || sudo=sudo
# The fish package needs fish 4 or newer: the fish project's own PPA has it.
$sudo apt-get update
$sudo apt-get install -y software-properties-common
$sudo add-apt-repository -y ppa:fish-shell/release-4
$sudo apt-get install -y stow direnv eza fish tmux fzf zoxide lazygit git ripgrep curl build-essential ghostty xz-utils

# Ubuntu's neovim and tree-sitter-cli are older than nvim needs (Neovim 0.12,
# tree-sitter 0.26.1): take each project's latest release, as Homebrew does.
case $(uname -m) in
x86_64) nvim_arch=x86_64 ts_arch=x64 ;;
aarch64 | arm64) nvim_arch=arm64 ts_arch=arm64 ;;
*) echo "ubuntu-deps.sh: no Neovim release for $(uname -m)" >&2 && exit 1 ;;
esac
releases=https://github.com
curl -fsSL "$releases/neovim/neovim/releases/latest/download/nvim-linux-$nvim_arch.tar.gz" | $sudo tar -xz -C /opt
$sudo ln -sf "/opt/nvim-linux-$nvim_arch/bin/nvim" /usr/local/bin/nvim
curl -fsSL "$releases/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$ts_arch.gz" |
	gunzip | $sudo tee /usr/local/bin/tree-sitter >/dev/null
$sudo chmod +x /usr/local/bin/tree-sitter

# Hack Nerd Font, in a user's own font folder ($FONTS_DIR, or this user's):
# the standalone check cannot hide a font installed for every user.
fonts=${FONTS_DIR:-$HOME/.local/share/fonts}
mkdir -p "$fonts"
curl -fsSL "$releases/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz" | tar -xJ -C "$fonts"
