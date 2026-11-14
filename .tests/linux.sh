#!/bin/sh
# Run CI's Ubuntu job on this machine, in Docker: the Ubuntu release the
# workflow names, the same dependencies (.tests/ubuntu-deps.sh) and the same
# two commands. Run it before pushing a change that could behave differently
# on Linux; tool versions there differ from Homebrew's.
#
#   .tests/linux.sh          ./install's tests, then every standalone check
#   .tests/linux.sh eza      ./install's tests, then the named checks
#
# Needs Docker running. The repository is mounted read-only.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
workflow="$repo/.github/workflows/standalone.yml"
image=$(sed -n 's/.*os: ubuntu-\([0-9][0-9.]*\).*/ubuntu:\1/p' "$workflow" | head -1)
[ -n "$image" ] || { echo "linux.sh: $workflow names no ubuntu-<release> runner" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "linux.sh: Docker is not running" >&2; exit 2; }

echo "linux.sh: $image"
docker run --rm -v "$repo":/dotfiles:ro "$image" sh -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    sh /dotfiles/.tests/ubuntu-deps.sh >/dev/null 2>&1
    # The tests themselves need git and python3. The runner image has both;
    # a bare container has neither.
    apt-get install -y -qq git python3 >/dev/null 2>&1
    useradd -m runner
    su runner -c "git config --global --add safe.directory /dotfiles &&
        cd /dotfiles &&
        python3 -B .tests/test_install.py &&
        python3 -B .tests/standalone.py $*"
' sh "$@"
