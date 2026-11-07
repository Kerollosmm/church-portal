---
name: hw-bootstrap
description: >-
  Sets up a project for the hark-workflow loop: .agents/workflow.env with detected values, the project AGENTS.md,
  the memory bank from templates, the owner's standing rules in .agents/rules/, .gitignore entries, size and PageSpeed
  baselines, and a first local gate — delivered as one draft PR. Use when hw.mjs doctor reports the config MISSING,
  or when the owner says "set up the workflow / the kit for this repo".
---

# hw-bootstrap — make a repo ready for the loop

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also the `HW_KIT=` value in the session message). Replace `<KIT>` in
   commands. Keep quotes.
2. Run commands from the repository root (the main checkout).
3. One action per step, in order.

## Step 1 — Check the machine and the repo

1. `node "<KIT>/scripts/hw.mjs" doctor` → fix FAIL rows first (install the tool). WARN rows: note them.
2. `git status --short` → must be empty. IF not → STOP and ask the owner what to do with the changes.
3. `git branch --show-current` → `main` (or the default branch). `git fetch origin`; `git status -sb` must not say
   "behind". IF behind → `git merge --ff-only origin/main`.
4. Topic: `node "<KIT>/scripts/hw.mjs" status init kit-setup --goal "set up hark-workflow for this repo"`.
5. Create the work branch: `node "<KIT>/scripts/hw.mjs" worktree chore/hark-workflow-setup --base main`.
   Move into the printed folder for every later step.

## Step 2 — Ask the owner (one message, max 3 questions)

Only what you cannot detect. Recommended answers included:
1. "Which language should I use with you and in the user docs? Recommended: <language of the existing docs>."
2. "Your standing rules (things every agent must always / never do)? Recommended starting set: <the 6 lines of
   `<KIT>/resources/templates/project-rules.md`>."
3. "Live URL of the site (if any)? I found: <value from firebase.json / README>."
Wait for the answers. Quote them with time in STATUS.md.

## Step 3 — `.agents/workflow.env`

1. IF `.agents/workflow.env` exists → keep it; only fill empty keys. ELSE copy
   `<KIT>/resources/templates/workflow.env.example` to `.agents/workflow.env`.
   A ready profile exists for church-portal: copy `<KIT>/examples/church-portal/workflow.env` instead.
2. Fill each key from a real source:

| Key | Source |
|---|---|
| `PROJECT_NAME`, `GITHUB_REPO` | `git remote get-url origin` (`owner/repo`) |
| `DEFAULT_BRANCH`, `PROTECTED_BRANCHES` | `git symbolic-ref refs/remotes/origin/HEAD` → usually `main` |
| `STACK` | `pubspec.yaml` + `firebase.json` → `flutter-firebase`; `pubspec.yaml` → `flutter`; `package.json` → `node`; `pyproject.toml` → `python` |
| `OWNER_LANGUAGE`, `DOCS_LANGUAGE`, `TIMEZONE` | the owner's answers (church-portal: `ar`, `ar`, `Africa/Cairo`) |
| `CI_WORKFLOW`, `DEPLOY_WORKFLOW` | the exact `name:` line of the files in `.github/workflows/` (CI on PRs; deploy on push to main) |
| `DEV_BRANCH`, `DEV_URL` | only if a dev workflow exists (e.g. `deploy-dev.yml`) — else leave empty |
| `LIVE_URL`, `LIVE_PATHS`, `BUNDLE_PATH` | owner's answer; Flutter web → `BUNDLE_PATH="main.dart.js"` |
| `SIZE_FILE` | Flutter web → `build/web/main.dart.js` |
| `GATE_*` | leave empty (stack defaults) unless the repo has its own commands (seed generator, rules tests dir, fingerprint script) |
| `REVIEW_BOTS` | Step 7 |

3. Workflow env var names: IF a workflow sets `env: CHANNEL: …` and uses `subosito/flutter-action`, tell the owner it
   must be renamed (e.g. `HOSTING_CHANNEL`) — that action reads `$CHANNEL` and installs the wrong Flutter channel.
4. Check: `node "<KIT>/scripts/hw.mjs" config` prints your values; `doctor` row `config` is OK.

## Step 4 — `.gitignore`

Make sure these lines exist (add the missing ones):
```
/.work/
node_modules/
*-debug.log
build/
.dart_tool/
```
Reason: STATUS files and logs are local; `node_modules/` and `firestore-debug.log` / `firebase-debug.log` from
emulator runs were committed by mistake before.

## Step 5 — Rules and AGENTS.md

1. `.agents/rules/project-rules.md`: copy `<KIT>/resources/templates/project-rules.md`; replace the example lines with
   the owner's standing rules (short imperatives). Keep the frontmatter EXACTLY (`trigger: always_on` + `description`):
   a rule file with missing or wrong frontmatter is silently ignored by Antigravity.
   church-portal: copy `<KIT>/examples/church-portal/project-rules.md`.
2. `AGENTS.md` at the repo root:
   - IF missing → copy `<KIT>/resources/templates/AGENTS.md.tmpl` to `AGENTS.md`; fill "What this is", "Golden rules"
     (copy the owner's rules), "Commands" (the real commands of this repo).
   - IF it exists → do not rewrite it. Add only the "Workflow" paragraph from the template if it is missing.
3. Keep each rule file under 24,000 bytes.

## Step 6 — Memory bank

1. Folder `MEMORY_BANK_DIR` (default `docs/memory-bank/`). Copy every file from
   `<KIT>/resources/templates/memory-bank/` that does NOT exist yet. Never overwrite an existing file.
2. Replace `{{PROJECT_NAME}}`, `{{DEFAULT_BRANCH}}`, `{{COMMIT}}` (`git rev-parse --short origin/main`), `{{DATE}}`,
   `{{DOCS_DIR}}` in the new files.
3. Fill what you can verify from the code now (architecture, data model, dev workflow). Unknown → write "unknown"
   and add an open task. Never invent.
4. `DOCS_DIR` (user docs): IF missing → create `<DOCS_DIR>/README.md` in `DOCS_LANGUAGE` with one line per feature
   (to be filled by `hw-docs-sync`).

## Step 7 — Bots and baselines

1. `node "<KIT>/scripts/hw.mjs" bots` → write the active bots into `REVIEW_BOTS` (keep the configured ones that are
   active; empty → `REVIEW_BOTS=""`).
2. Size baseline (when `SIZE_FILE` is set): in the setup worktree (same code as main so far):
   `node "<KIT>/scripts/hw.mjs" gate --only setup,build` then `node "<KIT>/scripts/hw.mjs" size`.
   Copy raw / gzip into `SIZE_BASELINE_RAW` / `SIZE_BASELINE_GZ`, `SIZE_BASELINE_REF="main@<sha7>"`. Ask the owner for
   `SIZE_BUDGET_GZ` (recommended: 20000 per PR).
3. PageSpeed baseline (when `LIVE_URL` is set): `node "<KIT>/scripts/hw.mjs" psi`. Copy the medians into
   `PSI_BASELINE_MOBILE` / `PSI_BASELINE_DESKTOP` (format `perf/a11y/bp/seo`). Quota error → leave empty, note it.

## Step 8 — Prove and deliver

1. `node "<KIT>/scripts/hw.mjs" gate --status kit-setup` → `GATE: PASS` (it proves the gate commands work here).
   FAIL on code that existed before → do not fix it in this PR; write it as a finding for the owner.
2. Stage explicit paths only:
   `git add .agents/workflow.env .agents/rules/project-rules.md AGENTS.md .gitignore <MEMORY_BANK_DIR> <DOCS_DIR>/README.md`
   `git status --short` → nothing else staged (no `node_modules/`, no `*-debug.log`, no `build/`).
3. `git commit -m "chore: set up hark-workflow (workflow.env, rules, memory bank)"`
4. Run `hw-open-pr` (draft PR, body: what was added, detected values, baselines, findings) → `hw-ci-watch`.
5. Report to the owner with the PR link. Merge only through `hw-owner-approval` → `hw-merge`.

## Definition of done

- [ ] `doctor` prints `config` OK; `config` shows real values (no example placeholders like `owner/repo`).
- [ ] `.gitignore` has `/.work/`, `node_modules/`, `*-debug.log`.
- [ ] `.agents/rules/project-rules.md` with valid frontmatter and the owner's rules; `AGENTS.md` present.
- [ ] Memory bank files present, placeholders replaced; nothing existing overwritten.
- [ ] `GATE: PASS` (or the owner informed of pre-existing failures); baselines filled or "not measured" noted.
- [ ] Draft PR open with CI result; nothing pushed to main.
