# Agent prompts

Each agent is launched with `subagent_type: "general-purpose"`. Inject into every prompt:
- `{scope}` — the resolved, post-exclude file list
- `{excludes}` — glob patterns to skip if the agent walks the tree itself (node_modules, dist, generated files, lockfiles, snapshots)
- `{tools}` — detected tools available in the repo

All agents share the same output format so consolidation is mechanical.

## Shared output format

Append to every agent prompt:

> Return findings as a JSON array. Each finding:
> - `file` — path relative to repo root
> - `lines` — start-end or single line number
> - `category` — one of: dedup, types, unused, cycles, weak-types, defensive, legacy, slop
> - `severity` — high | med | low
> - `issue` — one-line description
> - `proposed_fix` — concise description of the change
> - `confidence` — 0.0–1.0. Below 0.7 = "needs user review"
>
> Do NOT edit files. Surface uncertain findings rather than guessing. If you recommend a deletion, list every reference you searched for and confirmed absent.

## Agent 1 — Deduplication

Find duplicate and near-duplicate code in `{scope}`. Prioritise duplication that **adds complexity** — not trivial repetition.

Look for:
- Identical or near-identical function bodies
- Same logic expressed differently in 2+ places (semantic duplication)
- Copy-pasted blocks that diverged slightly (bug-risk)
- Utility logic inlined repeatedly when a helper exists nearby

Do NOT flag:
- Three similar lines that don't merit abstraction (premature DRY is worse than repetition)
- Tests with parallel structure — that's usually fine
- Deliberate duplication across service or module boundaries

For each finding: current locations, proposed consolidated form, where it should live.

## Agent 2 — Type consolidation

Find type/interface definitions in `{scope}` that are duplicated or should be shared.

Look for:
- Multiple files defining the same shape
- Near-identical types with drift (bug-risk)
- Types defined locally that belong in a shared types module
- Inline object types used 3+ times — candidates for naming

Before proposing a move, grep the full codebase (not just scope) for the type name and every field combination to find all users. If a shared location already exists (`types/`, `shared/`, package boundary), prefer it.

For each finding: current locations, proposed single location, rename if needed, list of every callsite.

## Agent 3 — Unused code

Find unused code in `{scope}`. Run `{tools}` first:
- TS/JS: `knip`, `ts-prune`, `eslint --rule no-unused-vars`
- Python: `ruff --select F401,F841`, `vulture`
- Go: `staticcheck -unused ./...`, `go vet ./...`
- Rust: `cargo +nightly udeps`, `cargo clippy -- -W dead_code`

Then **verify every finding** by grep across the full codebase — tools miss:
- Dynamic references (string-based imports, reflection, config-driven dispatch)
- Public API surface consumed by external packages
- Entries in config files, route tables, DI containers
- Test-only usage (still counts as "used" unless tests themselves are dead)

High confidence only when: tool flagged AND grep confirms zero refs AND not a public surface. Everything else → needs review with the grep evidence attached.

## Agent 4 — Circular dependencies

Find circular import/dependency cycles involving files in `{scope}`. Run:
- JS/TS: `madge --circular <path>` (and `--extensions ts,tsx,js,jsx`)
- Python: `pycycle` or `pydeps --show-cycles`
- Go: compiler catches these — but report any via `go list -deps`
- Rust: `cargo modules generate tree`

For each cycle: the cycle path (A → B → C → A), the nature (shared type? leaked upward dep? mutual recursion?), and the cleanest break — usually extracting a shared leaf (`types.ts`, interface file) that both sides depend on.

## Agent 5 — Weak types

Find weak-type usage in `{scope}` and propose strong replacements.

Targets by language:
- TS: `any`, `as` casts (esp. `as any`), `@ts-ignore`/`@ts-expect-error`, `Function`, `object`, `{}`, untyped destructuring
- TS `unknown` — **only flag when no narrowing happens before use**. `unknown` from a parser or external boundary that's then validated via typeguard/Zod/etc is correct and must not be flagged. Flag only: (a) `unknown` cast or asserted away (`x as Foo`, `x!`) without a check, or (b) `unknown` passed through unchanged to typed APIs via `any` escape
- Python: missing annotations on public APIs, `Any`, untyped `dict`/`list`, `object`, untyped `*args`/`**kwargs`, missing return types
- Go: `interface{}` / bare `any`, unchecked type assertions (`x.(T)` without ok), `reflect.Value` where a concrete type would work
- Rust: `dyn Any`, `Box<dyn Any>`, `transmute` without invariant

For **each** finding, research the correct type:
1. Follow the value's origin — what function/external system produced it?
2. Check types from related packages (`node_modules`, `.venv`, vendored deps)
3. Look at all callsites to infer shape
4. For external API responses, check the API's schema/OpenAPI/SDK types

Only propose a replacement with confidence ≥ 0.8. If the correct type isn't derivable from the code, report the location as "needs user input" with what you tried. **Never guess.**

## Agent 6 — Defensive programming

Find try/catch and equivalent error-swallowing patterns in `{scope}` that don't serve a real purpose.

Flag for removal:
- try/catch that re-throws unchanged
- Catches that log and return a default (error hiding)
- `if (x) return` fallbacks on internal, trusted values that can't be null by construction
- Optional chaining on values that can't be null
- try/catch around code that can't throw
- Promise `.catch(() => {})` swallowers, `.catch(() => null)`
- Python bare `except:`, `except Exception: pass`
- Go: ignored errors (`result, _ := ...`) outside deliberate cases
- Rust: `.unwrap_or_default()` on results that represent real failures

Keep (do NOT flag):
- Catches at genuine trust boundaries — user input, external APIs, filesystem, network, `JSON.parse` on untrusted data
- Catches that meaningfully transform the error (adding context, mapping to a domain error)
- Catches with a documented recovery path that's the intended behavior

Propose: removal OR explicit error handling with no fallback (propagate up, or fail loudly).

## Agent 7 — Legacy, deprecated, fallback code

Find legacy and fallback code paths in `{scope}` no longer needed.

Look for:
- `if (newBehaviorFlag)` branches where the flag is always on in prod
- `// DEPRECATED`, `// TODO: remove`, `@deprecated` markers
- Dead feature flags, config toggles always one value
- Multiple implementations of the same concept (v1 + v2)
- `if (oldShape)` branches for data formats no longer written
- Shims for removed/migrated APIs
- Compat code for browsers/runtimes/versions no longer supported

**Before proposing removal**, grep the full repo (and, where relevant, config / feature-flag service) to confirm the legacy path is truly unreachable. If removal depends on a flag state, surface with that context — don't assume.

Aim: **one** canonical path per concept.

## Agent 8 — AI slop, unhelpful comments, over-nesting, style drift

Find and flag low-value content and AI-generation tells in `{scope}`.

Comment / content targets:
- Stubs: `// TODO: implement`, `throw new Error("not implemented")` left behind
- Larp: types / handlers / branches for features not actually implemented
- Narrating comments: `// Fetches the user`, `// Returns the result`, `// Loop over items`
- In-motion commentary: `// Changed from X to Y`, `// Previously this did Z`, `// New implementation`, `// Refactored`
- Task-referential: `// Added for ticket ABC-123`, `// Used by the new checkout flow`
- AI-style docstring preambles, excessive bullet lists inside comments, hedging language
- Commented-out code blocks

Structure targets (AI over-nesting):
- Deeply nested `if`/`else` chains that would flatten with early returns
- Nested conditionals where guard clauses at the top eliminate the pyramid
- `if (x) { doStuff() } else { return }` — invert to `if (!x) return; doStuff()`
- Nested try/except where a single top-level guard covers the same cases
- Deeply indented callback / async chains where `await` + early return is clearer

Style-drift targets (only when scope is a PR or branch diff):
- Read the surrounding *unchanged* code in the same file. Flag changed code that drifts from local conventions: naming style, quote style, import ordering, error-handling idiom, async/callback style, log/assert patterns
- "Looks like it was written by a different person than the rest of the file" is the signal

Keep (do NOT flag):
- Comments that explain non-obvious **why** — hidden constraints, subtle invariants, workarounds with a linked reason
- Public API docstrings where the audience is external consumers
- Pointers to specs / RFCs / issues that are genuinely load-bearing for understanding
- Nesting that reflects genuinely non-linear control flow — don't flatten at the cost of clarity

For each finding: delete OR replace with a concise WHY-comment / flattened structure / style-aligned version. Proposed replacement text: one line unless a real constraint needs more. **Do not change behavior** — only form.
