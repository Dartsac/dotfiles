# herdr-automatic-rename (qu8n): tmux-style tab names, "[1] nvim", and agent
# tabs named after the agent and its task, "[2] pi:sidebar-tab-naming".
# Every other setting is the plugin default; see config.example.sh in its
# checkout (herdr plugin list --json | jq ... managed_path).

# Name tabs after the program only: no directory, branch or ssh-host prefix.
TAB_CONTEXT=0
# Agent tabs show the agent and its task, "claude:sidebar-layout". The task is
# the agent's terminal title: Claude Code writes its own, and Pi's is the
# session name, which the dotfiles Pi extension sets
# (herdr/.config/herdr/pi-extension/topic.mjs). An agent with no task yet shows
# its name alone, and the sidebar shows that tab name in place of a task.
AGENT_TITLES=1
TITLE_STYLE=name_and_task
# Shorten a long title to whole keywords instead of cutting it mid-word.
TITLE_CONDENSE=1
# Agent name, colon and task together; also the longest $topic. 22 is what
# fits after "[N] " in the 30-column sidebar. Pi's labels are written to fit
# (TOPIC_MAX in topic.mjs).
MAX_TITLE_LEN=22
# Don't read Claude Code's transcripts to title a session it hasn't titled.
AGENT_TRANSCRIPT=0
# No agent names on pane borders: borders carry no titles.
NAME_PANES=0
# Report each agent's task alone ("sidebar-tab-labels") as the $topic token,
# which the sidebar's agent rows show on their first line.
PANE_TOPICS=1
# Number tabs ("[1] nvim") but keep workspace names as they are; the project
# picker and sidebar use them.
AUTO_INDEX_WORKSPACES=0
