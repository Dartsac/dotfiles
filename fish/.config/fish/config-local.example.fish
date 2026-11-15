# An example of config-local.fish, this machine's own fish settings. Copy it
# to config-local.fish (git ignores that file) and uncomment what you need.
# config.fish sources it last, so it can also change anything config.fish
# sets. With the Dracula PRO package, theme-sync writes Tide's colors here, in
# a block of its own after the opening comment (from
# tide-dracula-pro.fish.template).

# The name the greeting says hello to (otherwise your login name, $USER).
# set -g greeting_name friend

# The multiplexer the shortcuts (Ctrl-f, dev, a, ke, ...) use outside any
# multiplexer: herdr, where installed. Otherwise tmux.
# set -gx DEFAULT_MULTIPLEXER herdr

# Homebrew tools it does not link into its bin: a pinned Python ahead of
# Homebrew's python3, and Java.
# fish_add_path --path $HOMEBREW_PREFIX/opt/python@3.11/libexec/bin
# fish_add_path --path $HOMEBREW_PREFIX/opt/openjdk/bin

# Perl modules installed with local::lib into ~/perl5. local::lib only exports
# variables; a shell started from another shell (Neovim, tmux, scripts)
# inherits them, so this skips the ~13 ms perl start there.
# if not set -q PERL_LOCAL_LIB_ROOT; and test -d ~/perl5/lib/perl5/local
#     eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)"
# end
