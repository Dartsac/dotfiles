# Live tab names in herdr: herdr-automatic-rename's fish hook renames the tab as
# soon as a command starts or returns to the prompt (herdr has no event for a
# foreground-command change). A no-op outside herdr or when the plugin is absent.
if set -q HERDR_PANE_ID
    for _f in $HOME/.config/herdr/plugins/github-installations/herdr-automatic-rename-*/*/checkout/shell/hook.fish \
            $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
        test -r "$_f"; and source "$_f"; and break
    end
    set -e _f
end
