---
name: hw-docs-sync
description: >-
  Docs stage of the hark-workflow loop, two modes. In-PR (stage 04b): update the memory bank, fill the reserved ADR,
  update the user docs in the owner's language with the real admin labels, tick or add open tasks, and add the history
  line — all in the SAME PR as the code. After-merge (stage 13): check the merged main carries those docs and record
  live-state facts (merge sha, deploy, switches) in a small docs PR when needed. Use after implementing, and after
  deploy verification.
---

# hw-docs-sync — docs in the same PR, history after merge (stages 04b and 13)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Pick the mode:

| STATUS `stage` | Mode |
|---|---|
| `04b-docs` (or any time code changed in the PR) | **A — in-PR** (run from the PR `worktree`) |
| `13-docs-final` | **B — after-merge** (run from the main checkout) |

3. Read `.agents/workflow.env`: `MEMORY_BANK_DIR`, `DOCS_DIR`, `DOCS_LANGUAGE`, `ADR_FILE`, `OPEN_TASKS_FILE`.
4. One action per step, in order.

## Rules

- Docs ship in the **same PR** as the code they describe. A PR without its docs is not done.
- Every sentence must be checkable in the code: file names, function names, field names, admin labels copied from
  the code — never from memory, never from the plan.
- User docs (`DOCS_DIR`) are written in `DOCS_LANGUAGE` (church-portal: Arabic) for a non-technical admin. Admin
  labels are quoted exactly as the UI shows them «…».
- Memory bank (`MEMORY_BANK_DIR`) is for agents and developers: English, precise, with file paths.
- Never invent facts (dates, content, numbers). Unknown → "unknown" or an open task.

## Mode A — in-PR (stage 04b)

### A1 — List what changed

1. `git diff --stat origin/<base>...HEAD` → the files this PR changes.
2. Map each kind of change to the docs it needs:

| The PR changes … | Update |
|---|---|
| a data field / collection | `04-data-model.md` (field, type, default, who writes it) + `05-backend.md` (rules) |
| security rules | `05-backend.md`: the rule, why, the 1000-expression budget if a big function grew |
| an admin screen / field / switch | `07-admin-dashboard.md` + the user doc of that feature in `DOCS_DIR` |
| a visitor feature | `06-features.md` + the user doc (create it from `<KIT>/resources/templates/feature-doc.md` if new) |
| routes, packages, build, deferred imports | `03-architecture.md` |
| CI, workflows, commands, dev environment | `08-dev-workflow.md` (and the dev doc, e.g. `docs/DEV-ENVIRONMENT.md`) |
| real vs sample content | `09-content-status.md` |
| new domain words | `12-glossary.md` |
| any decision | the ADR (A3) |
| a task finished / found | `OPEN_TASKS_FILE` (A4) |

### A2 — Memory bank

1. Edit each file from the table. Write what is true in the code now (replace old text; do not append "update:" notes).
2. Update the "Checked against … at commit …" line in `00-README.md` to `<base> @ <base sha7>` + today's date.
3. Read each changed paragraph once more against the code (open the file, compare names and defaults).

### A3 — ADR

1. The number was reserved in `hw-plan` (STATUS log `ADR-NEXT:`). IF none was reserved → run
   `node "<KIT>/scripts/hw.mjs" adr-next` and use the printed number; never reuse a `claimed:` number.
2. IF the block does not exist yet: `node "<KIT>/scripts/hw.mjs" adr-new "<title>" --pr <n> --id ADR-<nnn>`
3. Fill every field: Context (with evidence), Decision (checkable), Consequences, Alternatives rejected,
   Cost / budget (reads/writes per visit, `SIZE:` delta), Where in the code. Leave no `<!-- -->` placeholder.
4. A decision that replaces an older ADR → the old heading gets `— **superseded by ADR-<nnn>**`; its text stays.

### A4 — Open tasks and history

1. `OPEN_TASKS_FILE`: tick (or delete) the items this PR finishes; add follow-ups found during the work
   ("valid-later" review findings, out-of-scope bugs) with why / where / what done means.
2. `ADR_FILE` → section `## Timeline`: add one row `| <YYYY-MM-DD> | #<n> | <what changed, one line> (ADR-<nnn>) |`.
3. IF the repo keeps a separate history log (e.g. `PROJECT_HISTORY.md`, `CHANGELOG.md`) → add the same line there.

### A5 — User docs (owner's language)

1. Open (or create from the template) `DOCS_DIR/<feature>.md`.
2. Copy admin labels from the code: the admin screen file, the admin schema, the l10n table (church-portal:
   `admin_page.dart`, `admin_schema.dart`, `lib/core/l10n.dart`). Quote them «…» with the code id in backticks.
3. Fill: current state (what is ON/OFF live, with date), what the visitor gets, how the admin controls it (screen →
   field → switch → «حفظ التغييرات»), how it works technically, limits and known problems.
4. Times: say the zone (church-portal: «بتوقيت القاهرة»).
5. IF the repo has an English mirror (e.g. `documentation/en/`) → update it too.

### A6 — Commit (same PR)

1. `git add <each doc file by path>` (never `-A` / `.`). `git status --short` → only docs staged.
2. `git commit -m "docs(<area>): memory bank, ADR-<nnn>, <DOCS_DIR> for <feature>"`
3. `status set <TOPIC> docs "<sha7>: <file list>"`; log it.
4. `stage` = `05-local-gate`, `next_action` = `run the local gate`.

## Mode B — after-merge (stage 13)

1. `git fetch origin`. For each file in row `docs`: `git show origin/main:<file> | grep -c "ADR-<nnn>"` (or another
   unique line of your change) → must be ≥ 1. 0 → the docs did not land: STOP, tell the owner.
2. Collect live-state facts that only exist after the deploy: merge sha(s), deploy run id, date live, switches the
   owner turned on or off, new PSI baseline the owner accepted, a changed `DEV_URL`.
3. IF there are no such facts that the docs must state → log `docs final: nothing to add` → go to step 6.
4. ELSE open a small docs PR: `hw-worktree` (`docs/<topic>-live`, base main) → edit the "Current state" lines, the
   Timeline row (add the merge sha), `workflow.env` baselines → commit with explicit paths → `hw-local-gate`
   (`--no-build` is enough for docs-only) → `hw-open-pr` → `hw-ci-watch`. Bot review optional (max 2 rounds). Merge
   only with the owner's merge approval (`hw-owner-approval` → `hw-merge`).
5. `status set <TOPIC> docs "<existing> ; final: <PR #m or 'nothing to add'>"`.
6. Final report to the owner (`<KIT>/resources/templates/owner-report.md`, owner's language, "Done"): what is live,
   evidence lines (`MERGE:`, `DEPLOY:`, `PSI:`, Sentry), docs files, follow-ups.
7. `stage` = `done`.

## Definition of done

- Mode A: [ ] each change kind from A1 has its doc edited (file list in row `docs`) · [ ] ADR block complete, no
  placeholders · [ ] Timeline row added · [ ] open tasks ticked/added · [ ] user doc in `DOCS_LANGUAGE` with labels
  copied from code · [ ] committed in the PR branch (sha7 logged).
- Mode B: [ ] grep proof that main carries the docs · [ ] live facts recorded (docs PR #m) or "nothing to add" ·
  [ ] final owner report sent · [ ] `stage` = `done`.
