#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-send.sh [options] -t target -- keys...

Send keys to a tmux pane without waiting for completion.
Use this for interactive prompts, confirmations, or when you don't want
to wait (use tmux-run.sh for commands you want to wait on).

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -l, --literal      use send-keys -l (literal, no special key parsing)
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
  AGENT_TMUX_SOCKET      full socket path override

Examples:
  tmux-send.sh -t mysession -- y Enter           # confirm a prompt
  tmux-send.sh -t mysession -- C-c                # send ctrl+c
  tmux-send.sh -t mysession -l -- "literal text"  # no key parsing
USAGE
}

target=""
socket_args=()
literal=false
keys=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -l|--literal)     literal=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; keys=("$@"); break ;;
    *)                keys+=("$1"); shift ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "error: --target is required" >&2
  usage
  exit 1
fi

if [[ ${#keys[@]} -eq 0 ]]; then
  echo "error: no keys provided" >&2
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

send_args=()
if [[ "$literal" == true ]]; then
  send_args+=(-l)
fi

"${tmux_cmd[@]}" send-keys -t "$target" "${send_args[@]}" "${keys[@]}"
