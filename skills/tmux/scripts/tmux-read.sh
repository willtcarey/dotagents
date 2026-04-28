#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-read.sh [options] -t target

Capture and print the current contents of a tmux pane.

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -l, --lines        scrollback lines to capture (default: 50)
  -a, --all          capture entire scrollback history
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
  AGENT_TMUX_SOCKET      full socket path override

Examples:
  tmux-read.sh -t mysession
  tmux-read.sh -t mysession -l 200
  tmux-read.sh -t mysession --all
USAGE
}

target=""
socket_args=()
lines=50
all=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -a|--all)         all=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "error: --target is required" >&2
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

if ! "${tmux_cmd[@]}" has-session -t "$target" 2>/dev/null; then
  echo "error: tmux session/target '$target' not found" >&2
  exit 1
fi

if [[ "$all" == true ]]; then
  "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S -
else
  "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}"
fi
