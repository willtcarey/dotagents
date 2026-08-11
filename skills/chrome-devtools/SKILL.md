---
name: chrome-devtools
description: Operate the shared Chrome browser through Chrome DevTools MCP/CLI. Use when inspecting pages, navigating, taking snapshots/screenshots, evaluating JavaScript, or checking browser state on devmachine.
---

# Chrome DevTools Browser Control

Use the `chrome-devtools` CLI to operate the shared Chrome instance exposed from `beepboop` over Tailscale.

The browser endpoint is:

```bash
http://beepboop.otter-byzantine.ts.net:9222
```

## First: Check or Start the MCP CLI Daemon

Before using DevTools commands, check whether the daemon is already running:

```bash
chrome-devtools status
```

If it is not running, or if it is connected to the wrong browser, start/restart it with the shared browser URL:

```bash
chrome-devtools start --browserUrl=http://beepboop.otter-byzantine.ts.net:9222 --no-usage-statistics
```

Then verify:

```bash
chrome-devtools status
chrome-devtools list_pages --output-format=json
```

## Important Model

- `chrome-devtools-mcp` is the MCP server used by MCP clients.
- `chrome-devtools` is the CLI for operating that server/browser.
- Do **not** manually run `chrome-devtools-mcp` and then expect `chrome-devtools` to connect to that terminal process.
- For CLI usage, use `chrome-devtools start --browserUrl=...`; subsequent `chrome-devtools <command>` calls talk to the daemon.

## Common Browser Operations

List open tabs/pages:

```bash
chrome-devtools list_pages --output-format=json
```

Open a new page:

```bash
chrome-devtools new_page https://example.com --timeout=10000
```

Select an existing page by ID:

```bash
chrome-devtools select_page 1
```

Navigate the selected page:

```bash
chrome-devtools navigate_page --type=url --url=https://example.com --timeout=10000
```

Take an accessibility/text snapshot, preferred before interacting with the page:

```bash
chrome-devtools take_snapshot
```

Evaluate JavaScript in the selected page:

```bash
chrome-devtools evaluate_script '() => document.title'
```

Take a screenshot:

```bash
chrome-devtools take_screenshot --filePath=/tmp/page.png
```

Inspect console messages:

```bash
chrome-devtools list_console_messages --output-format=json
```

Inspect network requests:

```bash
chrome-devtools list_network_requests --output-format=json
```

## Troubleshooting

If commands fail or appear connected to the wrong browser:

```bash
chrome-devtools status
chrome-devtools stop
chrome-devtools start --browserUrl=http://beepboop.otter-byzantine.ts.net:9222 --no-usage-statistics
chrome-devtools list_pages --output-format=json
```

If the browser endpoint itself might be unavailable from `devmachine`:

```bash
curl -sS --max-time 3 http://beepboop.otter-byzantine.ts.net:9222/json/version
```

A healthy response includes `Browser`, `Protocol-Version`, and `webSocketDebuggerUrl`.

## Notes

- Prefer `take_snapshot` over screenshots when possible; snapshots expose stable element `uid`s for click/fill/hover commands.
- Use `--output-format=json` for machine-readable results when available.
- This controls the shared visible Chrome instance on `beepboop`, not a local headless browser on `devmachine`.
