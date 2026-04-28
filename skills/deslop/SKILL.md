---
name: deslop
description: Comprehensive codebase quality sweep that launches 8 specialized cleanup agents in parallel — deduplication, type consolidation, unused code removal, circular deps, weak types, defensive programming, legacy code, AI slop / unhelpful comments / over-nesting. Use when the user wants to deslop, clean up the codebase, strip AI-generated artifacts, improve code quality, reduce tech debt, run a quality pass, prep a PR for review, or mentions "deslop", "cleanup sweep", "refactor pass", "code quality". Accepts an optional scope argument (PR number, branch name, or directory path); runs on the full codebase if omitted.
disable-model-invocation: true
---

# Deslop

Comprehensive quality sweep. Launches 8 specialized agents in parallel, each focused on one cleanup dimension. Consolidates findings and applies changes with user approval.

## Quick start

```
/deslop                  # full codebase
/deslop src/api          # directory
/deslop 1234             # PR number (gh)
/deslop feat/new-auth    # branch (diff vs default branch)
```

## Workflow

1. **Resolve scope** — turn the argument into a concrete file list:
   - Empty → full codebase
   - All digits or `#N` → `gh pr view N --json files` → changed files
   - Branch name → `git diff --name-only <default>...<branch>`
   - Path → use as-is (dir or glob)

2. **Compute excludes** — build an ignore-list to skip in every agent:
   - Every pattern in `.gitignore` and `.git/info/exclude`
   - Common build output: `dist/`, `build/`, `out/`, `.next/`, `target/`, `__pycache__/`
   - Vendored / generated: `node_modules/`, `vendor/`, `.venv/`, `*.generated.*`, `*.gen.go`, `*_pb2.py`, snapshot files (`__snapshots__/`, `*.snap`)
   - Lockfiles
   Filter the file list from step 1 through these.

3. **Size check** — if scope > 500 files (tunable), stop and prompt the user to narrow:
   - By directory (e.g. `src/api` instead of `src/`)
   - By churn (`git log --since='3 months' --name-only --pretty=format:`)
   - By largest N files
   Agents blow their context on huge scopes — don't try to push through.

4. **Detect tooling** — read `package.json`, `tsconfig*.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`. For polyglot repos, bucket files by language; each language gets its own set of 8 agents. Note installed tools (knip, madge, ts-prune, ruff, vulture, staticcheck, clippy).

5. **Detect model config** — before launching agents, discover the current session's model provider and ID so delegate calls inherit the right config:
   ```js
   // via execute tool
   const session = api.sessions.current();
   // session.model_provider → e.g. "claude_agent_sdk"
   // session.model_id → e.g. "claude-sonnet-4-20250514"
   ```
   Use a smaller/faster model for the delegate calls when available (e.g. `claude-sonnet-4-20250514`). Do **not** pass `modelId`/`modelProvider` to delegate unless you have both values — omitting both lets delegate use its default.

6. **Launch all 8 agents in parallel** — single message, 8 `delegate` tool calls. Each agent gets:
   - The resolved file list (post-exclude) and the exclude patterns
   - The detected tooling
   - Its domain-specific prompt from [AGENTS.md](AGENTS.md)
   - The shared output format
   - `modelProvider` and `modelId` from step 5

   Agents **analyze only** in this pass — no file edits, prevents parallel conflicts.

   As each agent returns, print `[N/8 done: <category>]` to the user so the wait isn't silent.

7. **Consolidate findings** — merge the 8 reports. Deduplicate overlap (agents 1 and 2 often find the same shared-type issue). Group by file. Sort by severity. Write the full consolidated report to `deslop-report.md` at the repo root.

8. **Review with user** — summarise from the report: count per category, a few top examples per category, total files touched. Point them at `deslop-report.md` for the full list. Ask which categories or files to apply.

9. **Apply changes** — when user approves:
   1. Confirm clean working tree. Create branch `deslop/<yyyy-mm-dd>` off the current branch. Refuse to edit on `main`/`master`.
   2. Apply categories sequentially in precedence order: deletion (3, 7) → simplification (6, 8) → consolidation (1, 2) → typing (5) → structural (4). Run build + typecheck + tests between each category. Stop and surface on regressions.
   3. Commit one category at a time.
   4. Final deliverable: the `deslop/<date>` branch with staged commits (one per category) and `deslop-report.md` describing what was applied vs deferred.

## The 8 agents

1. **Deduplication** — DRY where it reduces complexity
2. **Type consolidation** — merge duplicated/near-duplicated type defs
3. **Unused code** — knip/ts-prune/vulture + grep verification
4. **Circular dependencies** — madge/pycycle etc, propose untangles
5. **Weak types** — `any`/`unknown`/untyped; research correct types
6. **Defensive programming** — unjustified try/catch, fallbacks, error hiding
7. **Legacy / deprecated code** — dead flags, v1+v2 paths, compat shims
8. **AI slop / comments / over-nesting** — stubs, larp, narrating comments, in-motion commentary, deeply nested code that should use early returns, style drift from surrounding code

Full per-agent prompts: [AGENTS.md](AGENTS.md).

## Guardrails

- **Keep behavior unchanged** unless fixing a clear bug. Cleanups are refactors, not rewrites — no semantic changes smuggled in.
- **Analysis-only parallel pass.** Edits happen after consolidation, not during.
- **Confidence gate.** Any finding below 0.7 confidence → "needs review" bucket, never auto-applied.
- **Agent 5 researches, never guesses.** If the right type isn't derivable, report location; don't invent.
- **Agent 3 and 7 verify with grep** across the full repo before recommending deletion — tools miss dynamic references.
- **PR scope stays in scope.** Don't propose changes outside the diff unless user opts in.
- **Bias to deletion over rewriting** for agents 3, 6, 7, 8. Surface anything ambiguous.
- **Verify after each apply batch.** Build + typecheck + tests. Stop on regressions.
