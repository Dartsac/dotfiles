# herdr-automatic-rename (qu8n): tmux-style tab names, "[1] nvim".
# Every other setting is the plugin default; see config.example.sh in its
# checkout (herdr plugin list --json | jq ... managed_path).

# Name tabs after the program only: no directory, branch or ssh-host prefix.
TAB_CONTEXT=0
# Agent tabs show the agent ("pi", "claude"), not their task title. The task is
# in the sidebar's terminal-title / activity rows instead.
AGENT_TITLES=0
AGENT_TRANSCRIPT=0
# No agent names on pane borders: borders carry no titles.
NAME_PANES=0
# The sidebar doesn't show $topic, so don't compute it.
PANE_TOPICS=0
# Number tabs ("[1] nvim") but keep workspace names as they are; the project
# picker and sidebar use them.
AUTO_INDEX_WORKSPACES=0
