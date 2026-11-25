# دليل التسليم وسير العمل (Phase 5 Handoff Runbook)

> Read [README.md](README.md), [STATUS.md](STATUS.md), [SMALL-MODEL-GUIDE.md](SMALL-MODEL-GUIDE.md), and the active `PR-5<X>` file before starting.

---

## ١. قواعد المستودع والفروع (Repo & Worktree Safety)

- **Protected branch:** `main` — **never** commit or push directly to `main`.
- **Clean worktrees:** Always create a fresh `git worktree` from `origin/main` (do not edit in a root checkout that has unrelated local changes):
  ```bash
  git fetch origin
  git worktree add ../church-portal-<tag> -b <branch> origin/main
  ```
- **Git hygiene:** Never run `git push --force`, `git push --force-with-lease`, or `git rebase` on a pushed branch (`git fetch origin && git merge origin/main` instead). Always stage with explicit pathspecs (`git add <file1> <file2>`), never `git add -A`.
- **Live data safety:** Never write to production Firestore, run `seed_firestore.js` without `--dry-run`, or trigger the Seed workflow with `force`.

---

## ٢. أوامر التحقق (Standard Verification Commands)

Run inside the PR worktree:

```bash
flutter pub get
flutter analyze
flutter test                                # sandbox/proxy: NO_PROXY=127.0.0.1,localhost flutter test
cd tool/rules_test && npm ci && npm test    # when firestore.rules or rules tests change (Java 11+)
python3 tool/gen_seed.py && git diff --exit-code -- assets/seed/seed.json tool/retired_seed_ids.json tool/known_seed_ids.json
flutter build web --release
python3 tool/fingerprint_icon_fonts.py build/web
node tool/check_web_bundle.mjs build/web
```

If the `hark-workflow` plugin is installed locally (`$KIT` set), `"$KIT/scripts/verify.sh"` runs the full local gate in one command.

---

## ٣. دورة كل PR (PR Lifecycle)

1. **Branch:** Create clean worktree from `origin/main` (for PR 5B, ensure open PR #99 is merged first; for PR 5A-docs, coordinate with PR #95 on `11-open-tasks.md`).
2. **Implement (TDD):** Follow the packets in `PR-5<X>`, locating targets by **symbol name** (`git grep`), committing small logical steps.
3. **Verify locally:** Run `flutter analyze`, `flutter test`, `tool/rules_test` (if rules changed), and `node tool/check_web_bundle.mjs build/web` (must stay `<= 1,399,000 B` gzip `-9` with `0` deferred leaks).
4. **Sync docs in same PR:** Update relevant `docs/memory-bank/` files, `documentation/` (Arabic) if needed, and tick [STATUS.md](STATUS.md).
5. **Open Draft PR → Review Loop:** Push branch, open draft PR with exact test counts and `main.dart.js` gzip size, mark ready once gate is green, request `@coderabbitai review` and `@sentry review`, fix real findings, reply & resolve every thread.
6. **Merge & Deploy Verify:** Confirm CI green on head SHA, squash-merge (never `--admin`), verify `Deploy to Firebase` workflow on merge SHA, live HTTP 200, and bundle checks. Clean up worktree (`git worktree remove ../church-portal-<tag>`).

---

## ٤. كاسر الحلقة (Loop Breaker)

Stop and report to the owner instead of guessing if:
- The same test, build, or CI job fails **twice in a row** for the same reason.
- `node tool/check_web_bundle.mjs build/web` reports any deferred-module leak or gzip > `1,399,000 B`.
- `tool/rules_test` fails on Firestore's 1,000-expression limit.
- Owner decisions `D1`, `D2`, or `D3` need confirmation.
