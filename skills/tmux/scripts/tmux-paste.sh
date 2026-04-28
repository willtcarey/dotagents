#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-paste.sh [options] -t target -- file_or_text

Paste content into a tmux pane using load-buffer/paste-buffer.
This avoids the quote-mangling issues of send-keys, making it ideal
for sending code to REPLs like Rails console, irb, python, etc.

Input can be a file path or text via stdin.

Options:
  -t, --target       tmux target (session:window.pane), required
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -f, --file         file to paste (alternative to positional arg)
  -e, --enter        send Enter after pasting (default: true)
  -E, --no-enter     don't send Enter after pasting
  -w, --wait         seconds to wait after pasting (default: 0)
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
  AGENT_TMUX_SOCKET      full socket path override

Examples:
  # Paste a file
  tmux-paste.sh -t mysession -f /tmp/script.rb

  # Paste inline text
  echo 'puts "hello"' | tmux-paste.sh -t mysession

  # Paste file without sending Enter
  tmux-paste.sh -t mysession -E -f /tmp/partial.rb

  # Paste and wait 10 seconds for output
  tmux-paste.sh -t mysession -w 10 -f /tmp/query.rb
USAGE
}

target=""
socket_args=()
file=""
send_enter=true
wait_secs=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -f|--file)        file="${2-}"; shift 2 ;;
    -e|--enter)       send_enter=true; shift ;;
    -E|--no-enter)    send_enter=false; shift ;;
    -w|--wait)        wait_secs="${2-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; [[ -n "${1-}" ]] && file="$1"; break ;;
    *)                file="$1"; shift ;;
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

# Get content into a temp file
tmpfile=$(mktemp /tmp/tmux-paste-XXXXXX)
trap 'rm -f "$tmpfile"' EXIT

if [[ -n "$file" && -f "$file" ]]; then
  cp "$file" "$tmpfile"
elif [[ -n "$file" ]]; then
  echo "error: file not found: $file" >&2
  exit 1
elif [[ ! -t 0 ]]; then
  cat > "$tmpfile"
else
  echo "error: no file or stdin provided" >&2
  usage
  exit 1
fi

# Load into tmux buffer and paste
"${tmux_cmd[@]}" load-buffer "$tmpfile"
"${tmux_cmd[@]}" paste-buffer -t "$target"

if [[ "$send_enter" == true ]]; then
  "${tmux_cmd[@]}" send-keys -t "$target" Enter
fi

if (( wait_secs > 0 )); then
  sleep "$wait_secs"
  "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S -500
fi
