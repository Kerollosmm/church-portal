# PR 5A-docs — Fix Repo Docs, Broken Links & Machine-Specific Paths

> **Branch:** `docs/p5-docs-links-and-paths` (clean `git worktree` from `origin/main`)
> **Scope:** Docs-only PR. Can run in parallel with PR 5A (coordinate with open PR #95 if touching `docs/memory-bank/11-open-tasks.md`).

---

## Targets

1. **`AGENTS.md` and `.agents/rules/project-rules.md`:**
   - Replace references to nonexistent `scripts/verify.sh`, `scripts/new_adr.sh`, and `scripts/verify_deploy.sh` with real repo commands (`flutter analyze`, `flutter test`, `cd tool/rules_test && npm test`, `python3 tool/gen_seed.py`, `node tool/check_web_bundle.mjs build/web`).
   - Mention `$KIT/scripts/...` only as an optional local helper for setups that have the `hark-workflow` plugin installed — **zero hardcoded personal or OS-specific paths**.
2. **`CLAUDE.md`:**
   - Fix broken targets `GLOSSARY.md` → `docs/memory-bank/12-glossary.md` and `docs/adr/` → `docs/memory-bank/10-decisions-and-history.md`.
   - Keep existing valid links (`docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`).
3. **`docs/memory-bank/07-admin-dashboard.md`:**
   - Replace stale `adminExpiresAt` reference in the `AdminsScreen` section with the actual keys used in `AdminsScreen` (`adminNoExpiry`, `adminExpiresOn`, `adminExpiredOn`, `clearEndDate`).
4. **Tracked `file:///` links (`264` occurrences across repo docs):**
   - Find all tracked occurrences via `git grep -n "file:///"` (excluding any intentional format examples in `AGENTS.md` / `.agents/`).
   - Replace machine-local `file:///` paths in `lib/*/README.md` and `docs/` with clean repo-relative markdown links.

---

## Steps
- [ ] Run `git grep -n "file:///"` and `git grep -n "scripts/" AGENTS.md .agents/rules/project-rules.md` to inventory exact targets.
- [ ] Apply the doc fixes above across `AGENTS.md`, `.agents/rules/project-rules.md`, `CLAUDE.md`, `docs/memory-bank/07-admin-dashboard.md`, and README/doc files containing `file:///`.
- [ ] Verify `git grep -n "file:///"` returns `0` unintended hits across the repo.
- [ ] Update `docs/plans/phase5/STATUS.md`, commit, open PR, review, and squash-merge.
