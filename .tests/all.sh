#!/bin/sh
# Every suite this checkout holds, one after the other: the tracked tests, the
# standalone check, the Pi extensions' tests and type check where Pi is
# installed, and those only the owner's machines have, which are each
# package's own tests and the tests of the owner's own scripts (.owner/).
#
#   .tests/all.sh              every suite
#   .tests/all.sh nvim herdr   the suites whose name holds one of these words
#   .tests/all.sh --list       name the suites
#
# One line per suite: ok, FAIL (the end of its output follows, with the file
# that holds all of it, and the run ends in exit status 1), or skip with what
# is missing: a tool, the tests themselves, or Pi.
# The suites named `bare` run on a PATH of /usr/bin:/bin with the system's own
# Python, as a commit from a GUI git client runs them (the pre-commit hook):
# there a test must skip, not fail, when a tool it needs is missing.
# .tests/linux.sh runs the tracked suites on Ubuntu, in Docker.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
bare="env -i HOME=$HOME PATH=/usr/bin:/bin /usr/bin/python3"
# How much of a failed suite's output to show (CI asks for all of it).
FAIL_LINES=${FAIL_LINES:-40}

# name | folder, from the repository | what it needs: commands, paths in the
# folder (these end in /), and paths in the home directory (these start with
# ~/) | command
suites="
lint|.|ruff|ruff check
tests|.|python3|python3 -B -m unittest discover -s .tests -p 'test_*.py'
tests-bare|.|/usr/bin/python3|$bare -B -m unittest discover -s .tests -p 'test_*.py'
standalone|.|python3|python3 -B .tests/standalone.py
pi|.|node ~/.pi/agent/install/current-version|node .tests/pi-extensions.mjs
pi-types|.|node tsc ~/.pi/agent/install/current-version|node .tests/pi-extensions.mjs --types
owner|.|.owner/ python3|python3 -B -m unittest discover -s .owner -p 'test_*.py'
owner-bare|.|.owner/ /usr/bin/python3|$bare -B -m unittest discover -s .owner -p 'test_*.py'
fish|fish/.config/fish|tests/ python3 fish|python3 -B -m unittest discover -s tests -p '*_test.py'
tmux|tmux/.config/tmux|tests/ python3 tmux|python3 -B -m unittest discover -s tests -p '*_test.py'
herdr|herdr/.config/herdr|tests/ python3|python3 -B -m unittest discover -s tests -p '*_test.py'
herdr-bare|herdr/.config/herdr|tests/ /usr/bin/python3|$bare -B -m unittest discover -s tests -p '*_test.py'
herdr-node|herdr/.config/herdr|tests/ node|node --test tests/*.test.mjs
hammerspoon|hammerspoon/.config/hammerspoon|tests/ nvim|for t in tests/*_test.lua; do nvim --headless -u NONE -l \"\$t\" || exit 1; done
nvim|nvim/.config/nvim|tests/ nvim tmux|sh tests/run.sh
"

if [ "${1:-}" = "--list" ]; then
    echo "$suites" | sed -n 's/|.*//p'
    exit 0
fi

wanted() {
    [ $# -eq 1 ] && return 0
    name=$1
    shift
    for word in "$@"; do
        case $name in *"$word"*) return 0 ;; esac
    done
    return 1
}

logs=$(mktemp -d)
failed=0 ran=0
while IFS='|' read -r name folder needs command; do
    [ -n "$name" ] && wanted "$name" "$@" || continue
    ran=$((ran + 1))
    missing=
    for need in $needs; do
        case $need in
            "~/"*) [ -e "$HOME/${need#??}" ] ;;
            */) [ -e "$repo/$folder/$need" ] ;;
            *) command -v "$need" >/dev/null 2>&1 ;;
        esac || missing="$missing $need"
    done
    if [ -n "$missing" ]; then
        echo "skip  $name: no$missing"
        continue
    fi
    started=$(date +%s)
    if (cd "$repo/$folder" && sh -c "$command") >"$logs/$name" 2>&1 </dev/null; then
        echo "ok    $name ($(($(date +%s) - started))s)"
        rm "$logs/$name"
    else
        failed=1
        echo "FAIL  $name: the last $FAIL_LINES lines of $logs/$name"
        tail -n "$FAIL_LINES" "$logs/$name" | sed 's/^/      /'
    fi
done <<LIST
$suites
LIST
[ $failed -eq 1 ] || rmdir "$logs"
[ "$ran" -gt 0 ] || { echo "all.sh: no suite named: $*" >&2; exit 2; }
exit $failed
