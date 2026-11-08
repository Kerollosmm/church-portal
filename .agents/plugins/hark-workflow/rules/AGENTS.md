# hark-workflow — rules for every agent and sub-agent (always on)

## Never (a hook blocks some of these; the rest is on you)
1. Never push to `main` (or any branch in `PROTECTED_BRANCHES`). Never commit on `main`.
2. Never force-push. Never rebase a pushed branch. To catch up: `git merge --no-ff origin/<base>`, then a normal push.
3. Never write live data (production database, admin console, seed / migration scripts, the Seed workflow, manual
   deploys) without the owner's explicit OK **in this conversation**, quoted in STATUS.md. Reading live data is fine.
4. Never put a secret in code, config, docs, commits, PR text or chat. Public web keys (Firebase web apiKey, Sentry
   DSN, reCAPTCHA site key) are not secrets.
5. Never merge a PR unless the owner said "merge" (or "ادمج") for that PR in this conversation.
6. Never invent facts: content, names, times, phone numbers, test counts, CI results, review results. Every claim
   comes from a command you ran or a page you read. Unknown stays "unknown".
7. Never stage with `git add -A` or `git add .`. Stage explicit paths: `git add path/one path/two`.

## Always
8. Keep state in `STATUS.md` (`<STATUS_DIR>/<topic>/STATUS.md`). Read it before every step. Update it after every
   step: `stage`, `next_action`, and one log line that ends with evidence (a verdict line, a SHA or a URL).
9. One worktree per PR. One agent per worktree. Two agents never edit the same checkout.
10. Reply to the owner in `OWNER_LANGUAGE` (STATUS.md `owner_language`). Code, paths, commands stay in English.
11. Respect the project's standing rules (`.agents/rules/*.md`, the project `AGENTS.md`). They beat these defaults.
12. Spend nothing (paid plans, quotas, paid APIs) and send nothing outside the repo (e-mail, chat, social) without the
    owner's OK. Bot review requests and replies on your own PR are part of the workflow.

## Loop breaker
13. The same step fails twice for the same reason → STOP. Write `blocked: yes` + the exact error in STATUS.md and
    report to the owner (template: blocked report). Never try a third time blindly.

## Entry point
Start every task with the skill `hw-start`. It tells you which stage skill to run next.
