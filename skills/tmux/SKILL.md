---
name: tmux
description: Remote-control tmux sessions by sending commands, waiting for output, and reading pane contents. Use when you need to interact with long-running processes, Rails consoles, or interactive prompts in tmux.
---

# tmux Session Control

Remote-control tmux sessions by sending commands, waiting for output, and reading pane contents. Includes scripts that handle the polling/waiting automatically so you don't need manual `sleep` calls.

## Concepts

- **Socket** — how you connect to a tmux server process. A custom socket (e.g., `/tmp/agent-tmux-sockets/agent.sock`) isolates the agent's tmux server from your personal one.
- **Session** — a named group of windows/panes on a tmux server. One socket can host many sessions.
- **Target** — tmux addressing format: `session`, `session:window`, or `session:window.pane`.

## Socket Auto-Detection

All scripts auto-detect the socket by checking (in order):

1. `AGENT_TMUX_SOCKET` env var (full path to a socket file)
2. First `.sock` file found in `AGENT_TMUX_SOCKET_DIR` (default: `/tmp/agent-tmux-sockets`)
3. Any socket file in that directory
4. Default tmux socket (no `-S` flag)

You can always override with `-S /path/to/socket` or `-L socket-name`.

## Scripts

All scripts live in `~/.agents/skills/tmux/scripts/`.

### tmux-run.sh — Run a command and wait for it to finish

The primary tool. Sends a command, appends a unique sentinel marker, and polls until the sentinel appears — then returns the captured output. No more guessing sleep times.

```bash
# Basic usage
~/.agents/skills/tmux/scripts/tmux-run.sh -t mysession -- terraform plan -input=false

# With explicit socket and timeout
~/.agents/skills/tmux/scripts/tmux-run.sh -S /tmp/my.sock -t worker-1 -T 300 -- make test

# Quiet mode (only output between command and sentinel)
~/.agents/skills/tmux/scripts/tmux-run.sh -t mysession -q -- ls -la
```

Options:
- `-t, --target` — tmux target (required)
- `-S, --socket-path` — socket path
- `-T, --timeout` — max seconds to wait (default: 120)
- `-i, --interval` — poll interval in seconds (default: 1)
- `-l, --lines` — scrollback lines to capture (default: 500)
- `-q, --quiet` — only print output between the command and sentinel

Exit codes: `0` = success, `124` = timeout, `1` = error.

### tmux-read.sh — Read pane contents

Capture the current visible + scrollback content of a pane.

```bash
# Last 50 lines (default)
~/.agents/skills/tmux/scripts/tmux-read.sh -t mysession

# Last 200 lines
~/.agents/skills/tmux/scripts/tmux-read.sh -t mysession -l 200

# Entire scrollback
~/.agents/skills/tmux/scripts/tmux-read.sh -t mysession --all
```

### tmux-send.sh — Send keys without waiting

For interactive prompts, confirmations, or special keys. Does NOT wait for completion — use `tmux-run.sh` if you need to wait.

```bash
# Confirm a prompt
~/.agents/skills/tmux/scripts/tmux-send.sh -t mysession -- y Enter

# Send Ctrl+C
~/.agents/skills/tmux/scripts/tmux-send.sh -t mysession -- C-c

# Send literal text (no special key parsing)
~/.agents/skills/tmux/scripts/tmux-send.sh -t mysession -l -- "some text with spaces"
```

### tmux-paste.sh — Paste content into a pane (for REPLs)

Sends content using `load-buffer`/`paste-buffer` instead of `send-keys`. This avoids quote-mangling issues, making it ideal for sending code to REPLs like Rails console, irb, python, etc. Does NOT wait for completion.

```bash
# Paste a file into a Rails console
~/.agents/skills/tmux/scripts/tmux-paste.sh -t mysession -f /tmp/script.rb

# Paste and wait 10 seconds, then capture output
~/.agents/skills/tmux/scripts/tmux-paste.sh -t mysession -w 10 -f /tmp/query.rb

# Pipe inline code
echo 'puts "hello"' | ~/.agents/skills/tmux/scripts/tmux-paste.sh -t mysession

# Paste without sending Enter
~/.agents/skills/tmux/scripts/tmux-paste.sh -t mysession -E -f /tmp/partial.rb
```

### tmux-rails-send.sh — Send code to a Rails console and wait

Sends Ruby code to a Rails console using `load-buffer`/`paste-buffer` (no quote mangling), then polls for the console prompt to reappear. Auto-detects the prompt pattern and auto-dismisses the IRB pager.

```bash
# Inline code
~/.agents/skills/tmux/scripts/tmux-rails-send.sh -t mysession -c 'Product.count'

# From a file
~/.agents/skills/tmux/scripts/tmux-rails-send.sh -t mysession -f /tmp/query.rb

# With a longer timeout for slow queries
~/.agents/skills/tmux/scripts/tmux-rails-send.sh -t mysession -T 300 -f /tmp/big_query.rb

# Only print the output (no scrollback noise)
~/.agents/skills/tmux/scripts/tmux-rails-send.sh -t mysession -q -c 'Order.last'

# Custom prompt pattern
~/.agents/skills/tmux/scripts/tmux-rails-send.sh -t mysession --prompt "merchtable" -c 'Order.last'
```

### tmux-sessions.sh — List sessions

```bash
# Auto-detect socket, list sessions
~/.agents/skills/tmux/scripts/tmux-sessions.sh

# Scan all sockets in the socket directory
~/.agents/skills/tmux/scripts/tmux-sessions.sh --all

# Filter by name
~/.agents/skills/tmux/scripts/tmux-sessions.sh -q terraform
```

## When to Use Each Script

| Scenario | Script |
|----------|--------|
| Run a shell command and get output | `tmux-run.sh` |
| Send code to Rails console and wait | `tmux-rails-send.sh` |
| Paste code to any REPL (no wait) | `tmux-paste.sh` |
| Check what's on screen right now | `tmux-read.sh` |
| Answer a y/n prompt or send Ctrl+C | `tmux-send.sh` |
| Find available sessions | `tmux-sessions.sh` |

## When NOT to Use tmux

- Running one-off commands that don't need an existing session → use `exec` / `bash` directly
- Non-interactive scripts → use `exec` / `bash` directly
- The process isn't in tmux

## Session Naming

When creating a new tmux session, **always use the agent socket** so the tmux skill scripts can find it automatically:

```bash
SOCK="${AGENT_TMUX_SOCKET:-/tmp/agent-tmux-sockets/agent.sock}"

# From /home/will/Workspaces/reins → session name: reins-dev
tmux -S "$SOCK" new-session -d -s "$(basename "$PWD")-dev"
```

Name sessions using the current directory as a prefix for easy identification. Use the basename of the working directory followed by a short descriptor.

This makes `tmux-sessions.sh` output meaningful when multiple projects have sessions running.

## Typical Workflow

```bash
SCRIPTS=~/.agents/skills/tmux/scripts

# 1. Find sessions
$SCRIPTS/tmux-sessions.sh

# 2. Run a command and wait for output
$SCRIPTS/tmux-run.sh -t reins-dev -- terraform init

# 3. Check the output if needed
$SCRIPTS/tmux-read.sh -t terraform-migration -l 30

# 4. If a prompt appears, answer it
$SCRIPTS/tmux-send.sh -t terraform-migration -- yes Enter

# 5. Run another command
$SCRIPTS/tmux-run.sh -t terraform-migration -T 300 -- terraform plan -input=false
```

## Raw tmux Commands

If the scripts don't cover your case, use tmux directly:

```bash
# List sessions
tmux -S /path/to/socket list-sessions

# Send keys
tmux -S /path/to/socket send-keys -t session "command" Enter

# Capture pane
tmux -S /path/to/socket capture-pane -t session -p -S -50

# Create session
tmux -S /path/to/socket new-session -d -s newsession

# Kill session
tmux -S /path/to/socket kill-session -t sessionname
```

## Notes

- `tmux-run.sh` works by appending `; echo __SENTINEL__` after your command — this means it only works for shell commands, not interactive TUI inputs
- For interactive prompts, use `tmux-send.sh` then `tmux-read.sh` to check the result
- Target format: `session:window.pane` (e.g., `shared:0.0`) — session name alone works for the default window/pane
- Sessions persist across SSH disconnects
