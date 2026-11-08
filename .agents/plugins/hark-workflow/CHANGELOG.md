# Changelog

## 2.0.0 — 2026-11-07

A rewrite for weak models and every OS. Skills are renamed (`hw-*`), the bash / python helpers are gone, and the
church-portal workflow (plan gate, stacked chains, dev channel, owner approval, bottom-up merge) is covered end to end.

### Added
- **18 skills**: `hw-start` (entry point, stage map, routing table, delegation) and one skill per stage —
  `hw-bootstrap`, `hw-intake`, `hw-plan`, `hw-worktree`, `hw-implement`, `hw-fix-bug`, `hw-docs-sync`,
  `hw-local-gate`, `hw-open-pr`, `hw-review-loop`, `hw-ci-watch`, `hw-dev-test`, `hw-owner-approval`, `hw-merge`,
  `hw-deploy-verify`, `hw-pr-review`, `hw-qa-sim`. Each is a numbered checklist with exact commands, IF/THEN tables,
  stop conditions and a Definition of done.
- **9 agents**: new `parent-agent` (main agent: delegates, re-checks every claim, owner gates G0–G3), `planner`,
  `pr-reviewer`, `qa-tester`; `orchestrator`, `implementer`, `docs-keeper`, `reviewer-fixer`, `release-verifier`
  rewritten as checklists. Every agent has a single-agent (IDE) mode.
- **`scripts/hw.mjs`**: one zero-dependency Node CLI with 35 commands (doctor, config, STATUS.md, local gate with
  evidence, size budget, ADR numbering without collisions, worktrees, draft PRs, CI wait / logs / single re-run,
  workflow dispatch, review bots and threads, merge with head-SHA guard and recorded approval, deploy verify, dev
  channel URL, PageSpeed, screenshots, Sentry, install workspace / global / profile / skills).
- Templates: STATUS.md, plan, sub-agent brief, owner report, PR-review report, QA phase report; ADR block via
  `hw.mjs adr-new`.
- **church-portal install profile** (`examples/church-portal/agents-dir/`: workflow.env, AGENTS.md overlay, code
  rules) and `hw.mjs install profile <name> <project>`.
- `scripts/validate.mjs` (Node) with hook tests (`scripts/test_hooks.mjs`) and `hw.mjs` offline tests
  (`scripts/test_hw.mjs`); fails on references to removed v1 scripts / skills in README and AGENTS.
- README in English and Arabic with install, first run, start prompts for Gemini, stage map, command reference,
  safety guarantees and known limits.

### Fixed (problems found in v1 1.0.0)
1. Hooks ran `python3`, missing or a Store stub on Windows → a hook error on every command and file write. Hooks are
   now Node (`node ./scripts/hooks/*.mjs`).
2. The commit-gate hook ran a multi-minute check before every agent `git commit` (timeout 900 s, needed bash); weak
   models stalled or reached for `--no-verify`. Removed; the gate is an explicit stage (`hw-local-gate`) with evidence.
3. Skills referenced scripts via `$KIT` / plugin-root paths with no reliable way to find them; models guessed paths.
   The session hook prints `HW_KIT=<absolute path>`, STATUS.md records it, and every command uses
   `node "<KIT>/scripts/hw.mjs" …`.
4. Helpers needed bash, jq, curl and python3 (absent on stock Windows). Replaced by `hw.mjs` (Node >= 18 only).
5. The v1 global installer exited 1 after a successful copy. Replaced by `hw.mjs install`.
6. `orchestrator` and `docs-keeper` ran with `commandExecutionPolicy: sandbox` (no network → push, GitHub and
   `pub get` failed). All agents that need the network use `auto`; the validator rejects sandbox + network.
7. Delegation was presented as universal, but sub-agents exist only in the App and CLI. `parent-agent` + `hw-start`
   now fall back to persona mode in the IDE.
8. Long prose skills with several actions per step and state kept in the model's head; weak models skipped gates and
   claimed results. Now one action per step, STATUS.md after every step, evidence lines required.
9. Missing stages: stacked PR chains, worktree per PR, plan + owner gate G0, ADR collision check, bundle-size budget,
   PSI baseline, dev channel testing, 390 px owner approval, bottom-up chain merge, reviewing someone else's PR,
   QA simulation phases, 2-round bot cap. All covered by the new skills.
10. Squash-merge was a normal step. Merge is now its own gated stage and needs the owner's recorded approval.
11. Status notes were optional prose. STATUS.md has a fixed state table, written with `hw.mjs status`.
12. The church-portal example was outdated (no dev env, chain, PSI or size baselines). Replaced by the full profile.
13. README claims were not tied to the Antigravity docs. Rewritten against the doc pages, with unverified items listed.

### Removed
- v1 skills (`ship-change`, `fix-bug`, `pr-review-loop`, `verify-release`, `docs-sync`, `project-bootstrap`) —
  replaced by the `hw-*` skills.
- v1 bash / python scripts and hooks (`verify.sh`, `pr_status.sh`, `wait_ci.sh`, `verify_deploy.sh`, `new_adr.sh`,
  `install.sh`, `validate_kit.sh`, `scripts/hooks/*.py`, `tests/test_hooks.py`) and the commit-gate hook.

### Not verified yet
- Antigravity loading `.agents/AGENTS.md` from an installed profile; whether `invoke_subagent` needs the
  `hark-workflow:` prefix for plugin agents; the hook shell on Windows.

## 1.0.0 — 2026-11-04
- First release: 6 skills (ship-change, fix-bug, pr-review-loop, verify-release, docs-sync, project-bootstrap),
  5 custom agents, safety / quality / reporting rules, 4 hooks (git safety, secret guard, commit gate, session
  context), bash / python scripts, templates (PR body, memory bank 00–12, feature doc AR/EN, ADR, status, AGENTS.md,
  project rules, workflow.env), church-portal example config.
