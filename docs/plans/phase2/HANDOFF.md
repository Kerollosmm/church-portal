# دليل التسليم وطريقة العمل (Handoff & workflow — read this first if you are picking the work up)

> Written for **another agent or developer** who must execute Phase 2 without the original author, possibly
> mid-way. Read in this order: this file → [STATUS.md](STATUS.md) (what is done, what is next) →
> [README.md](README.md) (architecture, data contract) → the PR file you are on → repo `AGENTS.md` and
> `docs/memory-bank/` (golden rules). The owner's instructions in chat always win over this file; record any change
> here and in STATUS.md.

## ١. المستودع والفروع (Repo, branches, worktrees)

| Item | Value |
|---|---|
| Repo | `Kerollosmm/church-portal` (public), default branch `main` (auto-deploys Hosting + rules — **never push to it**) |
| Firebase | project `asafra-church-portal`, Hosting site `maximos-domadios-church`, plan **Spark** |
| Live | https://maximos-domadios-church.web.app (`/admin` hidden admin) |
| Plan PR | branch `docs/phase2-plans` → base `main` (ADR-056) |

**Stacked chain (each PR is based on the previous PR's branch):**

| # | PR | Branch | Base branch | ADR |
|---|---|---|---|---|
| 0 | Phase 2 plans (this folder) | `docs/phase2-plans` | `main` | ADR-056 |
| 1 | A — install banner + prefs | `feat/p2a-install-prefs` | `docs/phase2-plans` | ADR-057 |
| 2 | B — Android APK + local notifications | `feat/p2b-android-local-notifications` | `feat/p2a-install-prefs` | ADR-058 |
| 3 | C — admin notification manager + FCM sender + deep links | `feat/p2c-notification-manager` | `feat/p2b-android-local-notifications` | ADR-059 |
| 4 | D — web push + PWA + iPhone | `feat/p2d-web-push` | `feat/p2c-notification-manager` | ADR-060 |
| 5 | E — responsive + size audit | `fix/p2e-responsive-size` | `feat/p2d-web-push` | ADR-061 |

Branch naming: `feat/p2<letter>-<slug>` (features), `fix/p2<letter>-<slug>` (fix-only), `docs/…` (docs-only).
Never reuse a branch name; follow-up fixes inside the chain are new commits on the same branch.

**Worktrees (Hark sandbox layout; adapt the root on your machine):**
```
P=/workspace/projects/d4668d86-9343-4a85-9b9f-8c199bc0a62e
$P/church_portal            main clone — keep it CLEAN on main (only `git fetch` / `git worktree add` here)
$P/work/phase2/wtDocs       docs/phase2-plans
$P/work/phase2/wtA          feat/p2a-install-prefs        (one worktree per chain branch: wtB, wtC, wtD, wtE)
$P/work/phase2/png/<pr>/    screenshots taken locally (before committing selected ones, §6)
$P/work/phase2/logs/        background build / test logs
$P/work/phase2/PLAN.md      original working notes (superseded by this folder)
```
Create a worktree for the next PR from the previous branch:
```bash
cd $P/church_portal && git fetch origin
git worktree add -b feat/p2b-android-local-notifications ../work/phase2/wtB origin/feat/p2a-install-prefs
```

## ٢. تجهيز البيئة (Environment)

```bash
source /workspace/tools/flutter_env.sh          # Flutter on PATH, PUB_CACHE, local storage mirror (sandbox only)
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost   # flutter test needs its local websocket
cd <worktree> && flutter pub get
flutter analyze                                  # must be clean
flutter test                                     # all green (≈ 10+ min in the sandbox)
flutter build web --release --dart-define=SENTRY_ENVIRONMENT=ci --dart-define=GIT_SHA=local --dart-define=APP_VERSION=1.0.0+1
python3 tool/fingerprint_icon_fonts.py build/web
python3 tool/gen_seed.py && git diff --exit-code -- assets/seed/seed.json   # seed unchanged unless intended
# Firestore rules tests (only when firestore.rules changes):
export PATH=/workspace/tools/jre/bin:$PATH FIREBASE_EMULATORS_PATH=$P/work/firebase-emulators JAVA_TOOL_OPTIONS=-Xmx768m
cd tool/rules_test && npm ci && npm test
# Android (PR B+): JDK 17 + Android SDK; locally: flutter build apk --release --split-per-abi
```
Sandbox notes: memory is tight — run **one heavy job at a time** (build, test, emulator). Shell calls time out at
120 s: run long jobs in the background with a log ending in `EXIT <code>` (scripts `work/phase2/run.sh <name>
<cmd>` and `wait.sh <name> <sec>`). Outside the sandbox use normal Flutter stable (CI uses `subosito/flutter-action`
stable) and `npm` with Java 21.

GitHub from the sandbox: `apicall github …` with credentials `[{"provider":"github"}]`; git push/fetch with the same
credentials over https.

## ٣. القواعد الثابتة (Standing rules — non-negotiable)

1. **No live data writes**: never write to production Firestore, never run `seed_firestore.js` or the Seed workflow,
   never `--force` anything. Tests use the emulator / fakes.
2. **Git**: never push `main`; never `git push --force` / `--force-with-lease`; never rebase a pushed branch; stage
   with **explicit pathspecs** only (`git add lib/x.dart test/y.dart …`) — never `git add -A` / `.`; never commit
   `tool/rules_test/node_modules`, `*-debug.log`, `build/`, keys, `.jks`, service-account JSON.
3. **Firebase Spark**: no Cloud Functions, no Cloud Storage; no new visitor listeners or polling; settings as
   top-level keys of `settings/features`; static data on Hosting; document read / write cost in each ADR.
4. **Admin**: everything configurable in `/admin`; admin-only writes in rules; admin stays **web-only** (compiled out
   of the APK).
5. **UI**: palette roles only (`context.pal.*`; the test `no hard-coded colour in lib/ui` must pass), **no violet**
   anywhere, the hero look unchanged, Arabic-first RTL + English, 48 dp targets, 320 px × 200 % text without
   overflow.
6. **Content**: never invent church content (times, names, phones); unverified = `sample: true`.
7. **Every PR** carries: ADR entry in `docs/memory-bank/10-decisions-and-history.md` (+ timeline row), memory-bank
   updates (03/04/05/06/07/08/11 as relevant), Arabic `documentation/` (feature file + `README.md` index +
   `operations.md` when operational), English `documentation/en/`, tests, and a tick in [STATUS.md](STATUS.md).
8. **Reviews**: comment `@coderabbitai review` and `@sentry review` on every PR; fix **real** findings; at most
   **2 review rounds** per PR; reply on each thread with the fix commit or the reason it is not applicable.
9. **Stop and report** if anything loops more than twice (a failing CI job, a review ping-pong, a flaky test).
10. **No merges** until the whole chain is ready and the owner approves (§5.6).

## ٤. سير العمل لكل PR (Per-PR workflow)

1. Read the PR file (§1–§15) and STATUS.md; create the worktree from the previous chain branch (§1).
2. Implement in the PR file's "step-by-step" order. Commit small logical steps:
   `git -c user.name=<login> -c user.email=<id>+<login>@users.noreply.github.com commit -m "<area>: <what> (ADR-05x)"`.
3. Local gates: `flutter analyze` clean, `flutter test` green, rules tests if rules changed, release web build OK,
   `main.dart.js` size recorded (§7).
4. Push the branch (`git push origin <branch>` — plain push).
5. Open a **draft** PR with `pull_create` (base = previous chain branch, head = this branch). Body template (§8).
6. CI: `ci.yml` (analyze, test, build, seed diff, rules emulator) and `deploy.yml` (build + preview channel
   `pr-<n>`, URL commented by the bot) run for stacked PRs too (their `pull_request` trigger has no branch filter).
   Both must be green — check `check_runs_list` and `commit_status_get` on the head SHA.
7. Comment `@coderabbitai review`, then `@sentry review`. Wait for both; fix real findings (round 1); request again
   only if something substantive changed (round 2 max).
8. Screenshots (§6) and the manual QA table of the PR file (what can be done in the sandbox; device rows marked
   "owner" if they need real phones).
9. Update the PR body (CI status, preview URL, review summary, screenshots, size delta, owner decisions needed),
   tick STATUS.md in the same branch, push.
10. Keep it **draft**; never merge. Report to the owner. Move to the next PR only when the owner allows (the owner
    may ask to wait for approval of each PR).

**When a lower PR changes after higher PRs exist** (review fix in A while B–E exist): propagate upwards with merges,
never rebases:
```bash
cd wtB && git fetch origin && git merge --no-ff origin/feat/p2a-install-prefs -m "Merge A fixes into B" && git push origin feat/p2b-android-local-notifications
# then the same for C (merge B), D (merge C), E (merge D)
```

## ٥. الموافقات والدمج (Approval gates & final merge)

### 5.1 Gates
| Gate | Who | When |
|---|---|---|
| G0 plan approved | owner | before any code (this PR) |
| G1 per-PR visual check on the preview URL | owner | after each PR is green (optional per owner) |
| G2 whole chain ready: every PR green, reviewed, STATUS all ticked, PSI checked (§7) | agent → owner | after PR E |
| G3 merge approval | owner (explicit "merge") | after G2 |
| G4 launch | owner | LAUNCH-AND-OPERATIONS §13 |

### 5.2–5.5 Before merging
- Re-run CI on the top PR (E) after the last propagation merge; all previews green.
- Merge commits from propagation are fine (they disappear in the squash).

### 5.6 Final merge procedure (bottom-up squash, no force-push)

The repo squash-merges PRs (AGENTS.md). For a stacked chain:

1. **PR 0** (`docs/phase2-plans` → `main`): mark ready for review (`pull_ready_for_review`), squash-merge. Do **not**
   delete its branch yet.
2. **PR A**: change its base to `main` (`pull_update base=main`). In `wtA`:
   ```bash
   git fetch origin && git merge --no-ff origin/main -m "Merge main (after plans squash) into A" && git push origin feat/p2a-install-prefs
   ```
   The squash commit on `main` has the same content as A's ancestor commits, so the 3-way merge is clean and the
   PR diff shrinks to A's own changes. Wait for CI green → ready for review → squash-merge.
3. Repeat for **B** (base → `main`, merge `origin/main` into B, push, CI, squash), then **C**, **D**, **E**.
4. Only after E is merged: delete the chain branches (GitHub "Delete branch" on each merged PR). Deleting a base
   branch earlier would auto-close or auto-retarget dependent PRs — avoid surprises.
5. Each squash to `main` triggers `deploy.yml` (live Hosting + rules). Rules from C/D deploy with their PRs; the
   `push` flag stays off, so nothing visible changes until launch. If the owner prefers **one** deploy, merge
   in a quiet hour back-to-back; each intermediate state is safe by design (flags off).
6. If a conflict ever appears in step 2/3 (a hotfix landed on `main` meanwhile): resolve it in the worktree with a
   normal merge commit, run the local gates, push. Never `rebase` + force-push.

## ٦. لقطات الشاشة والملاحظات (Screenshots & notes)

- Take at **390 px** (Arabic) and **1280 px** (English) at least; for banners/sheets also **320 px**. From a local
  release build or the preview URL, with any flag forced on **only in a test harness** (never by writing live
  settings).
- Sandbox path: `$P/work/phase2/png/<pr-letter>/…png`. Commit the selected ones (≤ 150 KB each, PNG/WebP) to
  `docs/plans/phase2/screens/<pr-letter>/` and reference them in the PR body with
  `https://raw.githubusercontent.com/Kerollosmm/church-portal/<branch>/docs/plans/phase2/screens/<letter>/<file>`.
- Working notes that are not deliverables stay in `$P/work/phase2/notes/<pr-letter>.md` (sandbox); anything a later
  agent needs goes into STATUS.md "Current state".

## ٧. فحص الأداء والحجم (PageSpeed & size checks)

- Baseline (`main` @ `7e4705b`, local release build 6 Nov 2026): `main.dart.js` **4,898,252 B**, gzip -9
  **1,334,591 B**. Record each PR's numbers in its body and STATUS.md. Phase 2 total budget: ≤ +60 KB gzip.
- PSI: run PageSpeed Insights (mobile) on the PR preview URL after each PR that touches the public page load
  (A, C, D, E) — the live mobile score must not drop below **61**. Record the score + date. Lighthouse variance:
  run 3 times, take the median.
- APK sizes (PR B+): arm64 ≤ 20 MB, arm32 ≤ 18 MB.

## ٨. قالب وصف الـ PR (PR body template)

```markdown
**Phase 2 chain:** ⬅ previous: #<n-1> (<branch>) · ➡ next: #<n+1> (<branch> or "not yet opened")
**Plan:** docs/plans/phase2/PR-<X>-….md · **ADR-05x** · **Do not merge** — merged bottom-up after the whole chain is approved (HANDOFF §5.6)

## What / why
## Sub-features (from the plan) — done / deferred
## Firestore cost (reads / writes / listeners)
## Tests (analyze, test, rules) — results
## CI · Preview URL
## Reviews (CodeRabbit / Sentry) — findings and fixes
## Screenshots
## Size: main.dart.js gzip <before> → <after> (Δ) · APK sizes (B+)
## PSI mobile (median of 3)
## Owner actions needed
```
When the next PR opens, edit the previous PR's body to fill its "next" link.

## ٩. حالة العمل (Where to look for the current state)

[STATUS.md](STATUS.md) is the single source of truth: per-PR checkboxes, PR numbers, head SHAs, preview URLs,
blockers. Update it in the branch you are working on (higher branches get it through propagation merges).
