#!/bin/sh
# The dependencies of every package the standalone check covers, on Ubuntu.
# CI (.github/workflows/standalone.yml) and .tests/linux.sh both run this
# file, so the two cannot drift apart. Add a package's dependencies here when
# its check is added.
set -eu
sudo=
[ "$(id -u)" = 0 ] || sudo=sudo
$sudo apt-get update
$sudo apt-get install -y stow direnv eza lazygit git
