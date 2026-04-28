#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-sessions.sh [options]

List tmux sessions. Auto-detects agent sockets.

Options:
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -A, --all          scan all sockets in AGENT_TMUX_SOCKET_DIR
  -q, --query        filter session names (case-insensitive substring)
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
                         (default: /tmp/agent-tmux-sockets)
  AGENT_TMUX_SOCKET      full socket path override
USAGE
}

socket_args=()
query=""
scan_all=false
socket_dir="${AGENT_TMUX_SOCKET_DIR:-/tmp/agent-tmux-sockets}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -A|--all)         scan_all=true; shift ;;
    -q|--query)       query="${2-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v tmux >/dev/null 2>&1; then
  echo "error: tmux not found in PATH" >&2
  exit 1
fi

list_sessions() {
  local label="$1"; shift
  local tmux_cmd=(tmux "$@")

  if ! sessions="$("${tmux_cmd[@]}" list-sessions -F '#{session_name}\t#{session_attached}\t#{session_created_string}' 2>/dev/null)"; then
    return 1
  fi

  if [[ -n "$query" ]]; then
    sessions="$(printf '%s\n' "$sessions" | grep -i -- "$query" || true)"
  fi

  [[ -z "$sessions" ]] && return 0

  echo "Sessions on $label:"
  printf '%s\n' "$sessions" | while IFS=$'\t' read -r name attached created; do
    status=$([[ "$attached" == "1" ]] && echo "attached" || echo "detached")
    printf '  - %s (%s, started %s)\n' "$name" "$status" "$created"
  done
}

if [[ "$scan_all" == true ]]; then
  if [[ ! -d "$socket_dir" ]]; then
    echo "No socket directory at $socket_dir" >&2
    exit 1
  fi
  shopt -s nullglob
  sockets=("$socket_dir"/*)
  shopt -u nullglob
  for sock in "${sockets[@]}"; do
    [[ -S "$sock" ]] && list_sessions "$sock" -S "$sock"
  done

  # Also check default tmux socket
  list_sessions "default socket" 2>/dev/null || true
  exit 0
fi

if [[ ${#socket_args[@]} -eq 0 ]]; then
  # Auto-detect
  if [[ -n "${AGENT_TMUX_SOCKET:-}" && -S "$AGENT_TMUX_SOCKET" ]]; then
    socket_args=(-S "$AGENT_TMUX_SOCKET")
  elif [[ -d "$socket_dir" ]]; then
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

list_sessions "${socket_args[*]:-default socket}" "${socket_args[@]}"
