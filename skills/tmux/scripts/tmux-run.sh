#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-run.sh [options] -t target -- command...

Send a command to a tmux pane and wait for it to finish.

Appends a unique sentinel marker after the command, polls until the marker
appears in the pane output, then prints everything captured between the
command and the marker.

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -T, --timeout      seconds to wait before giving up (default: 120)
  -i, --interval     poll interval in seconds (default: 1)
  -l, --lines        scrollback lines to capture (default: 500)
  -q, --quiet        only print output between command and sentinel
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
                         (default: /tmp/agent-tmux-sockets)
  AGENT_TMUX_SOCKET      full socket path override

Examples:
  tmux-run.sh -t mysession -- terraform plan -input=false
  tmux-run.sh -S /tmp/agent-tmux-sockets/agent.sock -t worker-1 -- make test
  tmux-run.sh -t mysession -T 300 -- long-running-command
USAGE
}

target=""
socket_args=()
timeout=120
interval=1
lines=500
quiet=false
cmd_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -T|--timeout)     timeout="${2-}"; shift 2 ;;
    -i|--interval)    interval="${2-}"; shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -q|--quiet)       quiet=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; cmd_args=("$@"); break ;;
    *)                cmd_args+=("$1"); shift ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "error: --target is required" >&2
  usage
  exit 1
fi

if [[ ${#cmd_args[@]} -eq 0 ]]; then
  echo "error: no command provided" >&2
  usage
  exit 1
fi

# Auto-detect socket if none specified
if [[ ${#socket_args[@]} -eq 0 ]]; then
  if [[ -n "${AGENT_TMUX_SOCKET:-}" && -S "$AGENT_TMUX_SOCKET" ]]; then
    socket_args=(-S "$AGENT_TMUX_SOCKET")
  else
    socket_dir="${AGENT_TMUX_SOCKET_DIR:-/tmp/agent-tmux-sockets}"
    if [[ -d "$socket_dir" ]]; then
      shopt -s nullglob
      sockets=("$socket_dir"/*.sock "$socket_dir"/*)
      shopt -u nullglob
      for sock in "${sockets[@]}"; do
        if [[ -S "$sock" ]]; then
          socket_args=(-S "$sock")
          break
        fi
      done
    fi
  fi
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "error: tmux not found in PATH" >&2
  exit 1
fi

tmux_cmd=(tmux "${socket_args[@]}")

# Verify the target exists
if ! "${tmux_cmd[@]}" has-session -t "$target" 2>/dev/null; then
  echo "error: tmux session/target '$target' not found" >&2
  echo "Available sessions:" >&2
  "${tmux_cmd[@]}" list-sessions 2>/dev/null || echo "  (no sessions)" >&2
  exit 1
fi

# Generate unique sentinel
sentinel="__DONE_${RANDOM}_${RANDOM}_$$__"

# Build the full command string
cmd_string="${cmd_args[*]}"

# Send command + sentinel echo
"${tmux_cmd[@]}" send-keys -t "$target" "$cmd_string; echo $sentinel" Enter

# Poll until sentinel appears
elapsed=0
while true; do
  sleep "$interval"
  elapsed=$((elapsed + interval))

  pane_text="$("${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}" 2>/dev/null || true)"

  if printf '%s\n' "$pane_text" | grep -qF "$sentinel"; then
    break
  fi

  if (( elapsed >= timeout )); then
    echo "error: timed out after ${timeout}s waiting for command to finish" >&2
    echo "Command: $cmd_string" >&2
    echo "Last ${lines} lines:" >&2
    printf '%s\n' "$pane_text" >&2
    exit 124
  fi
done

# Output the captured pane
if [[ "$quiet" == true ]]; then
  # Extract just the output between command and sentinel
  printf '%s\n' "$pane_text" | sed -n "/$(printf '%s' "$cmd_string" | head -c 40 | sed 's/[[\.*^$()+?{|]/\\&/g')/,/^${sentinel}\$/p" | head -n -1 | tail -n +2
else
  printf '%s\n' "$pane_text"
fi
