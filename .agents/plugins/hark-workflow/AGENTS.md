# AGENTS.md — for any coding agent (Antigravity, Claude Code, Codex, Cursor, Copilot)

This repository is the **hark-workflow** kit v2: an engineering ship loop packaged as a Google Antigravity plugin. The
workflow is plain Markdown plus one Node helper (`scripts/hw.mjs`, Node >= 18, no dependencies), so any agent can
follow it.

## If you are working IN a project that uses this kit

1. Start with [`skills/hw-start/SKILL.md`](skills/hw-start/SKILL.md). It creates or reads
   `.work/<topic>/STATUS.md`, picks the stage, and tells you which of the 18 `hw-*` skills to run next.
2. `<KIT>` in every skill = the folder with `plugin.json` (the session message prints `HW_KIT=…`;
   `node <path>/scripts/hw.mjs kit` prints it too). Commands are written as `node "<KIT>/scripts/hw.mjs" <command>`.
3. First command of a session: `node "<KIT>/scripts/hw.mjs" doctor`. Config `MISSING` → skill `hw-bootstrap`.
4. Main agent with sub-agents (Antigravity App / CLI): [`agents/parent-agent.md`](agents/parent-agent.md). No
   sub-agents (IDE, other tools): run each stage yourself in persona mode — read the stage agent's Role / Checklist /
   Never sections in `agents/<agent>.md`, then follow the stage skill.

| When | Skill |
|---|---|
| Anything (entry point) | [`hw-start`](skills/hw-start/SKILL.md) |
| Set up a repo for the kit | [`hw-bootstrap`](skills/hw-bootstrap/SKILL.md) |
| New request → plan → owner gate G0 | [`hw-intake`](skills/hw-intake/SKILL.md), [`hw-plan`](skills/hw-plan/SKILL.md) |
| Worktree per PR, code, bug fix | [`hw-worktree`](skills/hw-worktree/SKILL.md), [`hw-implement`](skills/hw-implement/SKILL.md), [`hw-fix-bug`](skills/hw-fix-bug/SKILL.md) |
| Docs in the PR / after the merge | [`hw-docs-sync`](skills/hw-docs-sync/SKILL.md) |
| Gate, draft PR, CI | [`hw-local-gate`](skills/hw-local-gate/SKILL.md), [`hw-open-pr`](skills/hw-open-pr/SKILL.md), [`hw-ci-watch`](skills/hw-ci-watch/SKILL.md) |
| AI reviews | [`hw-review-loop`](skills/hw-review-loop/SKILL.md) |
| Dev channel, owner approval, merge, deploy | [`hw-dev-test`](skills/hw-dev-test/SKILL.md), [`hw-owner-approval`](skills/hw-owner-approval/SKILL.md), [`hw-merge`](skills/hw-merge/SKILL.md), [`hw-deploy-verify`](skills/hw-deploy-verify/SKILL.md) |
| Someone else's PR / QA simulation | [`hw-pr-review`](skills/hw-pr-review/SKILL.md), [`hw-qa-sim`](skills/hw-qa-sim/SKILL.md) |

Always-on rules: [`rules/AGENTS.md`](rules/AGENTS.md) (safety), [`rules/quality-bar.md`](rules/quality-bar.md),
[`rules/reporting.md`](rules/reporting.md). Project settings: `.agents/workflow.env`; project rules:
`.agents/rules/*.md` and the project's own `AGENTS.md` — they beat the kit defaults.

Non-negotiables: branch + worktree per change, never push to `main`, never force-push or rebase pushed history, never
merge without the owner's written "merge" / «ادمج» for that PR, no live-data writes without the owner's OK per item,
no secrets anywhere, explicit pathspecs, tests for every change, docs in the same PR, every claim with evidence, stop
and report after the same failure twice.

## If you are changing THIS kit

- Layout: `plugin.json` (Antigravity manifest, v1 schema, <= 3 suggestedPrompts) · `skills/<name>/SKILL.md` (name
  equals the folder; needs a "Definition of done") · `agents/<name>.md` (frontmatter name, description, model
  inherit|flash_lite|flash|pro, tools from the Antigravity tool list, mainAgent, subagent, commandExecutionPolicy;
  body sections Role, Checklist, Never, Single-agent mode) · `rules/*.md` (frontmatter `trigger`; `rules/AGENTS.md`
  has none) · `hooks.json` (commands `node ./scripts/hooks/*.mjs`, cwd = plugin root) · `scripts/hw.mjs` (every
  command has a HELP line) · `scripts/lib/` · `resources/templates/` · `examples/<name>/agents-dir/` (install
  profiles).
- Gate: `node scripts/validate.mjs` must print `VALIDATE: PASS`. It checks the manifest, frontmatter, tool names,
  hooks, cross references (skills, agents, `hw.mjs` commands, templates, workflow.env keys), that README / AGENTS do
  not mention removed v1 scripts or skills, `node --check`, and runs `scripts/test_hooks.mjs` and
  `scripts/test_hw.mjs`. Add a test for every hook or `hw.mjs` change.
- Same workflow as everywhere: branch, draft PR, CI (`Validate plugin`), owner approval, squash-merge. Bump
  `plugin.json` `version` and `CHANGELOG.md` on release.
