# `dev` — real-world testing environment

Set up 7 Nov 2026 (owner decision, during PR #51 / Phase 2 PR A) so chain PRs can be
tried on the **real** Firebase project before anything reaches production.

| | `main` (production) | `dev` (testing) |
|---|---|---|
| Workflow | `deploy.yml` | `deploy-dev.yml` (push to `dev` + manual run) |
| Hosting | live site `https://maximos-domadios-church.web.app` (+ legacy redirect) | channel **`dev`** of the same site — stable URL **https://maximos-domadios-church--dev-7qxh72kj.web.app** (the hash stays while the channel exists; a deleted/expired channel gets a new one) |
| Firestore rules + indexes | deployed after the rules tests | **also deployed to the live project `asafra-church-portal`** after the rules tests |
| Data | live Firestore | the same live Firestore (no separate database) |
| Sentry environment | `production` | `dev` |

The channel expires **30 days after its latest deploy**; every push to `dev` (or a manual
"Run workflow") refreshes it. Runs never overlap (`concurrency: deploy-dev`).

## Flow

1. Chain PRs (A → B → …) are merged into `dev` with a normal `git merge --no-ff` (no
   rebase, no force-push) when the owner wants to test them for real. `dev` is never
   merged into `main`, and no PR from `dev` to `main` is opened.
2. Pushing `dev` builds the web release, runs the rules emulator suite, deploys
   `firestore.rules`/`firestore.indexes.json` to the live project, then the `dev` channel.
3. Test on the dev URL. Sign-in at `/admin` and App Check work there because the channel
   domain is in Firebase Auth → Authorized domains and in the reCAPTCHA Enterprise key
   `church-portal-web` → Domains (added 7 Nov 2026). If the channel is ever recreated with a
   new hash, add the new domain to both lists (the dev build ships with App Check on).
4. Final merges to `main` still follow the normal rule: **bottom-up, squash, after the
   owner approves the whole chain**, merging `main` into the next branch (HANDOFF §5.6).
   `main` stays production; nothing on `dev` changes that.

## Rules on `dev` must stay backward compatible with `main`

Firestore rules are **project-wide**: whatever `dev` deploys is what the production app
talks to. So:

- `dev` rules must be a **superset** of `main`'s: every write the production app makes
  (admin saves of `settings/features`, `settings/church`, every collection) must still be
  allowed. New fields go in new, separately gated keys (e.g. ADR-057's
  `installPushKeys()` beside `legacyFeatureKeys()`); never tighten or rename a legacy key.
- The rules suite (`tool/rules_test`, includes the legacy cases) must pass before the
  deploy — the workflow enforces it.
- **A push to `main` redeploys `main`'s rules** and silently undoes `dev`'s additions
  (e.g. admin saves of the new Phase 2 fields are then denied on the dev URL). After any
  production deploy, re-run `deploy-dev.yml` (Actions → Run workflow, branch `dev`) to put
  the dev rules back. `main`'s rules only validate the keys a write changes, so fields
  that `dev` wrote into a document never block production saves.
- Fields added on `dev` live in the real documents; production code ignores unknown
  fields, so turning a Phase 2 switch on from the dev admin does not change the live site.
