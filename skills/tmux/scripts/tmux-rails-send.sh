#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tmux-rails-send.sh [options] -t target (-f file | -c code)

Send Ruby code to a Rails console in tmux and wait for it to complete.
Uses load-buffer/paste-buffer to avoid quote-mangling, polls for the
console prompt to return, and auto-dismisses the IRB pager.

Options:
  -t, --target       tmux target (session:window.pane), required
  -f, --file         file containing Ruby code to send
  -c, --code         inline Ruby code string
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -L, --socket       tmux socket name (passed to tmux -L)
  -T, --timeout      seconds to wait before giving up (default: 120)
  -i, --interval     poll interval in seconds (default: 1)
  -l, --lines        scrollback lines to capture (default: 500)
  -p, --prompt       prompt pattern to wait for (auto-detected if omitted)
  -q, --quiet        only print output between command and prompt
  -h, --help         show this help

Environment:
  AGENT_TMUX_SOCKET_DIR  directory to search for sockets
  AGENT_TMUX_SOCKET      full socket path override

Examples:
  tmux-rails-send.sh -t mysession -c 'Product.count'
  tmux-rails-send.sh -t mysession -f /tmp/query.rb
  tmux-rails-send.sh -t mysession -T 300 -f /tmp/big_query.rb
  tmux-rails-send.sh -t mysession --prompt "merchtable" -c 'Order.last'
USAGE
}

target=""
socket_args=()
file=""
code=""
timeout=120
interval=1
lines=500
prompt_pattern=""
quiet=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)      target="${2-}"; shift 2 ;;
    -f|--file)        file="${2-}"; shift 2 ;;
    -c|--code)        code="${2-}"; shift 2 ;;
    -S|--socket-path) socket_args=(-S "${2-}"); shift 2 ;;
    -L|--socket)      socket_args=(-L "${2-}"); shift 2 ;;
    -T|--timeout)     timeout="${2-}"; shift 2 ;;
    -i|--interval)    interval="${2-}"; shift 2 ;;
    -l|--lines)       lines="${2-}"; shift 2 ;;
    -p|--prompt)      prompt_pattern="${2-}"; shift 2 ;;
    -q|--quiet)       quiet=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "error: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "error: --target is required" >&2
  usage
  exit 1
fi

if [[ -z "$file" && -z "$code" ]]; then
  if [[ ! -t 0 ]]; then
    code=$(cat)
  else
    echo "error: one of --file, --code, or stdin is required" >&2
    usage
    exit 1
  fi
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

# Helper: get last non-empty line from pane
get_last_line() {
  "${tmux_cmd[@]}" capture-pane -p -t "$target" -S "-${lines}" 2>/dev/null \
    | sed '/^[[:space:]]*$/d' \
    | tail -1
}

# Helper: get full pane content
get_pane() {
  "${tmux_cmd[@]}" capture-pane -p -J -t "$target" -S "-${lines}" 2>/dev/null
}

# Auto-detect prompt pattern from current pane
if [[ -z "$prompt_pattern" ]]; then
  current_last=$(get_last_line)
  # Rails console prompts look like: irb(main):001:0> or appname(env)> or appname(env)*
  # Match everything up to the > or * at the end
  if [[ "$current_last" =~ ^([a-zA-Z0-9_()-]+\([a-zA-Z0-9_]+\))[^a-zA-Z0-9] ]]; then
    prompt_pattern="${BASH_REMATCH[1]}"
  elif [[ "$current_last" =~ ^(irb\([a-zA-Z0-9_:]+\):[0-9]+:[0-9]+)[^a-zA-Z0-9] ]]; then
    prompt_pattern="${BASH_REMATCH[1]}"
  else
    echo "error: could not auto-detect prompt. Use --prompt to specify." >&2
    echo "Last line was: $current_last" >&2
    exit 1
  fi
fi

# Prepare content in temp file
tmpfile=$(mktemp /tmp/tmux-rails-send-XXXXXX)
trap 'rm -f "$tmpfile"' EXIT

if [[ -n "$file" ]]; then
  if [[ ! -f "$file" ]]; then
    echo "error: file not found: $file" >&2
    exit 1
  fi
  cp "$file" "$tmpfile"
else
  printf '%s' "$code" > "$tmpfile"
fi

# Capture pane state before sending
pre_snapshot=$(get_pane)
pre_line_count=$(printf '%s\n' "$pre_snapshot" | wc -l)

# Paste code and send Enter
"${tmux_cmd[@]}" load-buffer "$tmpfile"
"${tmux_cmd[@]}" paste-buffer -t "$target"
"${tmux_cmd[@]}" send-keys -t "$target" Enter

# Poll until prompt returns or pager appears
elapsed=0
pager_dismissed=false
while true; do
  sleep "$interval"
  elapsed=$((elapsed + interval))

  last_line=$(get_last_line)

  # Check for IRB pager (line ends with just ":" and pane has more content than before)
  if [[ "$last_line" == ":" ]] || [[ "$last_line" =~ ^:$ ]]; then
    # Dismiss pager
    "${tmux_cmd[@]}" send-keys -t "$target" "q"
    pager_dismissed=true
    sleep 0.5
    continue
  fi

  # Check if prompt has returned (line starts with our prompt pattern)
  if [[ "$last_line" == *"$prompt_pattern"* ]]; then
    # Make sure we're not seeing the pre-existing prompt (execution must have started)
    current_pane=$(get_pane)
    current_line_count=$(printf '%s\n' "$current_pane" | wc -l)
    if (( current_line_count > pre_line_count )); then
      break
    fi
  fi

  if (( elapsed >= timeout )); then
    echo "error: timed out after ${timeout}s waiting for Rails console" >&2
    get_pane >&2
    exit 124
  fi
done

# Capture final output
final_pane=$(get_pane)

if [[ "$quiet" == true ]]; then
  # Extract output between the pasted code and the final prompt
  # Find where new content starts (after pre_line_count) and strip the final prompt
  printf '%s\n' "$final_pane" | tail -n +"$((pre_line_count))" | sed '$d'
else
  printf '%s\n' "$final_pane"
fi
