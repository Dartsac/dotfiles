# Tide's prompt settings for a machine that has none yet: config.fish sources
# this file when no tide_* settings exist (a new machine), and Tide keeps them
# as universal variables in fish_variables from then on. `tide configure`
# replaces them.
#
# Tide's Lean style on one line, without the time, in the free Dracula
# theme's colors (https://draculatheme.com/contribute#color-palette).
# Tide shows a Python virtualenv's name itself; activate.fish must not add it.
set -U VIRTUAL_ENV_DISABLE_PROMPT true
set -U tide_aws_bg_color normal
set -U tide_aws_color FFB86C
set -U tide_aws_icon 
set -U tide_character_color 50FA7B
set -U tide_character_color_failure FF5555
set -U tide_character_icon ❯
set -U tide_character_vi_icon_default ❮
set -U tide_character_vi_icon_replace ▶
set -U tide_character_vi_icon_visual V
set -U tide_chruby_bg_color normal
set -U tide_chruby_color FF79C6
set -U tide_chruby_icon 
set -U tide_cmd_duration_bg_color normal
set -U tide_cmd_duration_color F8F8F2
set -U tide_cmd_duration_decimals 0
set -U tide_cmd_duration_icon
set -U tide_cmd_duration_threshold 3000
set -U tide_context_always_display false
set -U tide_context_bg_color normal
set -U tide_context_color_default 6272A4
set -U tide_context_color_root FFB86C
set -U tide_context_color_ssh 8BE9FD
set -U tide_context_hostname_parts 1
set -U tide_crystal_bg_color normal
set -U tide_crystal_color F1FA8C
set -U tide_crystal_icon ⬢
set -U tide_docker_bg_color normal
set -U tide_docker_color 8BE9FD
set -U tide_docker_default_contexts default colima
set -U tide_docker_icon 
set -U tide_git_bg_color normal
set -U tide_git_bg_color_unstable normal
set -U tide_git_bg_color_urgent normal
set -U tide_git_color_branch 50FA7B
set -U tide_git_color_conflicted FF5555
set -U tide_git_color_dirty FFB86C
set -U tide_git_color_operation FF5555
set -U tide_git_color_staged 50FA7B
set -U tide_git_color_stash BD93F9
set -U tide_git_color_untracked FF79C6
set -U tide_git_color_upstream 50FA7B
set -U tide_git_icon
set -U tide_git_truncation_length 24
set -U tide_go_bg_color normal
set -U tide_go_color 8BE9FD
set -U tide_go_icon 
set -U tide_java_bg_color normal
set -U tide_java_color FFB86C
set -U tide_java_icon 
set -U tide_jobs_bg_color normal
set -U tide_jobs_color 6272A4
set -U tide_jobs_icon 
set -U tide_kubectl_bg_color normal
set -U tide_kubectl_color 8BE9FD
set -U tide_kubectl_icon ⎈
set -U tide_left_prompt_frame_enabled false
set -U tide_left_prompt_items pwd git character
set -U tide_left_prompt_prefix ''
set -U tide_left_prompt_separator_diff_color ' '
set -U tide_left_prompt_separator_same_color ' '
set -U tide_left_prompt_suffix ''
set -U tide_nix_shell_bg_color normal
set -U tide_nix_shell_color 6272A4
set -U tide_nix_shell_icon 
set -U tide_node_bg_color normal
set -U tide_node_color 50FA7B
set -U tide_node_icon ⬢
set -U tide_os_bg_color normal
set -U tide_os_color normal
set -U tide_os_icon ''
set -U tide_php_bg_color normal
set -U tide_php_color BD93F9
set -U tide_php_icon 
set -U tide_private_mode_bg_color normal
set -U tide_private_mode_color F8F8F2
set -U tide_private_mode_icon 﫸
set -U tide_prompt_add_newline_before false
set -U tide_prompt_color_frame_and_connection 44475A
set -U tide_prompt_color_separator_same_color 6272A4
set -U tide_prompt_icon_connection ' '
set -U tide_prompt_min_cols 34
set -U tide_prompt_pad_items false
set -U tide_pwd_bg_color normal
set -U tide_pwd_color_anchors BD93F9
set -U tide_pwd_color_dirs 6272A4
set -U tide_pwd_color_truncated_dirs 6272A4
set -U tide_pwd_icon
set -U tide_pwd_icon_home
set -U tide_pwd_icon_unwritable 
set -U tide_pwd_markers .bzr .citc .git .hg .node-version .python-version .ruby-version .shorten_folder_marker .svn .terraform Cargo.toml composer.json CVS go.mod package.json
set -U tide_right_prompt_frame_enabled false
set -U tide_right_prompt_items status cmd_duration context jobs node virtual_env rustc java php chruby go kubectl toolbox terraform aws nix_shell crystal
set -U tide_right_prompt_prefix ' '
set -U tide_right_prompt_separator_diff_color ' '
set -U tide_right_prompt_separator_same_color ' '
set -U tide_right_prompt_suffix ''
set -U tide_rustc_bg_color normal
set -U tide_rustc_color FFB86C
set -U tide_rustc_icon 
set -U tide_shlvl_bg_color normal
set -U tide_shlvl_color 6272A4
set -U tide_shlvl_icon 
set -U tide_shlvl_threshold 1
set -U tide_status_bg_color normal
set -U tide_status_bg_color_failure normal
set -U tide_status_color 50FA7B
set -U tide_status_color_failure FF5555
set -U tide_status_icon ✔
set -U tide_status_icon_failure ✘
set -U tide_terraform_bg_color normal
set -U tide_terraform_color BD93F9
set -U tide_terraform_icon
set -U tide_time_bg_color normal
set -U tide_time_color 6272A4
set -U tide_time_format ''
set -U tide_toolbox_bg_color normal
set -U tide_toolbox_color 6272A4
set -U tide_toolbox_icon ⬢
set -U tide_vi_mode_bg_color_default normal
set -U tide_vi_mode_bg_color_insert normal
set -U tide_vi_mode_bg_color_replace normal
set -U tide_vi_mode_bg_color_visual normal
set -U tide_vi_mode_color_default 6272A4
set -U tide_vi_mode_color_insert 8BE9FD
set -U tide_vi_mode_color_replace 50FA7B
set -U tide_vi_mode_color_visual FFB86C
set -U tide_vi_mode_icon_default D
set -U tide_vi_mode_icon_insert I
set -U tide_vi_mode_icon_replace R
set -U tide_vi_mode_icon_visual V
set -U tide_virtual_env_bg_color normal
set -U tide_virtual_env_color 8BE9FD
set -U tide_virtual_env_icon 
