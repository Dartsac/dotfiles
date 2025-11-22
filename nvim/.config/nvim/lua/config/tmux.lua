-- lua/config/tmux.lua
local M = {}

function M.create_session()
	-- Get the root directory name (project name)
	local cwd = vim.fn.getcwd()
	local session_name = vim.fn.fnamemodify(cwd, ":t")

	-- Get the current file path
	local current_file = vim.fn.expand("%:p")

	-- Check if we're already in a tmux session
	local in_tmux = vim.fn.getenv("TMUX") ~= vim.NIL

	-- Create or switch to tmux session
	if in_tmux then
		-- We're already in tmux, create a new session in the background and switch to it
		-- Create with just a shell so it persists after nvim quits
		local create_cmd = string.format("tmux new-session -d -s '%s' -c '%s'", session_name, cwd)
		vim.fn.system(create_cmd)

		-- If we have a current file, send keys to open it in nvim
		if current_file ~= "" then
			local escaped_file = vim.fn.shellescape(current_file)
			local edit_cmd = string.format("tmux send-keys -t '%s' 'clear && nvim %s' C-m", session_name, escaped_file)
			vim.fn.system(edit_cmd)
		end

		-- Switch to the new session
		vim.cmd(string.format("silent !tmux switch-client -t '%s'", session_name))
	else
		-- Not in tmux - create detached session, then attach
		-- First, check if session already exists
		local check_session = vim.fn.system(string.format("tmux has-session -t '%s' 2>/dev/null", session_name))
		local session_exists = vim.v.shell_error == 0

		if not session_exists then
			-- Create detached session with just a shell (not nvim directly)
			-- This way when you quit nvim, you stay in the shell
			local create_cmd = string.format("tmux new-session -d -s '%s' -c '%s'", session_name, cwd)
			vim.fn.system(create_cmd)

			if vim.v.shell_error ~= 0 then
				vim.notify("Failed to create tmux session", vim.log.levels.ERROR)
				return
			end

			-- Now if we have a current file, send keys to open it in nvim
			if current_file ~= "" then
				-- Escape the file path properly for shell
				local escaped_file = vim.fn.shellescape(current_file)
				local nvim_cmd = string.format("tmux send-keys -t '%s' 'clear && nvim %s' C-m", session_name, escaped_file)
				vim.fn.system(nvim_cmd)
			end
		end

		-- Write the session name to a marker file
		-- A shell wrapper (see instructions below) will detect this and attach
		local marker_file = vim.fn.getenv("HOME") .. "/.vim-tmux-attach"
		local file = io.open(marker_file, "w")
		if file then
			file:write(session_name)
			file:close()

			-- Print instructions if they haven't set up the shell wrapper
			local shell_setup_file = vim.fn.getenv("HOME") .. "/.vim-tmux-setup-done"
			if vim.fn.filereadable(shell_setup_file) == 0 then
				print("\n" .. string.rep("=", 70))
				print("TMUX INTEGRATION SETUP REQUIRED")
				print(string.rep("=", 70))
				print("\nAdd this to your shell config:\n")
				print("--- For Fish (~/.config/fish/config.fish) ---")
				print([[
function nvim
    command nvim $argv
    set marker_file ~/.vim-tmux-attach
    if test -f $marker_file
        set session (cat $marker_file)
        rm -f $marker_file
        tmux attach -t $session
        if test -f $marker_file
            rm -f $marker_file
        end
    end
end
]])
				print("\n--- For Bash/Zsh (~/.bashrc or ~/.zshrc) ---")
				print([[
nvim() {
    command nvim "$@"
    if [ -f ~/.vim-tmux-attach ]; then
        local session=$(cat ~/.vim-tmux-attach)
        rm -f ~/.vim-tmux-attach
        tmux attach -t "$session"
        [ -f ~/.vim-tmux-attach ] && rm -f ~/.vim-tmux-attach
    fi
}
]])
				print("\nAfter adding, run: touch ~/.vim-tmux-setup-done")
				print("\nFor now, manually run: tmux attach -t " .. session_name)
				print(string.rep("=", 70))
				vim.fn.getchar()
			end

			-- Quit vim - the shell wrapper will attach to tmux
			vim.cmd("qall!")
		else
			vim.notify("Failed to create marker file", vim.log.levels.ERROR)
		end
	end
end

return M
