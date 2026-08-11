---
name: code-review
description: Review the current branch's code changes for bugs and correctness issues using GPT 5.5 with extra-high reasoning. Use when the user asks to review code, review a branch, or run a code review after verifying things work in the browser.
disable-model-invocation: true
---
# Code Review
Performs a thorough code review of the current branch's diff against the base branch, using OpenAI GPT 5.5 with extra-high reasoning for maximum analysis depth.
**IMPORTANT:** This review MUST run in a sub-agent because the current session uses a different provider (Anthropic) and cannot switch to OpenAI mid-session. You must use the `delegate` tool immediately — do NOT attempt to switch the current session's model.
> Note: The `delegate` tool is only available in task sessions. If this is a scratch/assistant session, tell the user you need to run this from a task session.

## Steps
### 1. Gather the diff FIRST (before delegating)
Gather the diff in the current session so it can be passed to the sub-agent in the prompt. This avoids the sub-agent needing to figure out the base branch.
```bash
# Determine the base branch
git merge-base HEAD origin/<base_branch>
# Get the full diff
git diff $(git merge-base HEAD origin/<base_branch>)..HEAD
```

If the diff is very large, also get a summary:
```bash
git diff --stat $(git merge-base HEAD origin/<base_branch>)..HEAD
```

### 2. Delegate to a sub-agent with GPT 5.5 xhigh
Use the `delegate` tool to spawn a sub-session. Set the model to `openai-codex/gpt-5.5` with `xhigh` thinking level. Pass the **entire review prompt below** with the diff inserted as the delegation prompt.
The delegate call should look like:
```
delegate(
  prompt: "<the full review prompt below with diff inserted>",
  model: "gpt-5.5",
  provider: "openai-codex",
  thinkingLevel: "xhigh"
)
```
### 3. Build the delegation prompt
The review prompt lives in `review-prompt.md` in this skill's directory. Read it verbatim:
```
<skill_dir>/review-prompt.md
```
Construct the delegation prompt by concatenating:
1. The **entire contents** of `review-prompt.md` exactly as-is (do NOT paraphrase, summarize, or modify it)
2. Then append the diff:
```
Here is the diff to review:
\`\`\`diff
<INSERT THE DIFF HERE>
\`\`\`
```
---
### 4. Present the results
The sub-agent's response will come back formatted as human-readable markdown. Present it directly to the user — no additional transformation needed.
## Notes
- This skill is designed to be run once development is complete and browser testing has confirmed functionality.
- The delegation only works in **task sessions** (not scratch/assistant sessions) since the `delegate` tool is task-only.
- If the diff is extremely large (>10,000 lines), consider reviewing in chunks by directory or feature area — delegate multiple sub-agents, one per area.
