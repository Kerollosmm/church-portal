# Memory bank — Asafra Church Portal

This folder is the long-term memory of the project for coding agents (Claude Code, Codex, Cursor, Copilot…) and
for humans joining later. Code is the source of truth; these files explain **what exists, why, and how to change it
safely**. Every statement here was checked against the code on `main` at commit `fc0e0ad` (PR #3, 1 Nov 2026).

> **Golden rule:** read this folder before changing anything, and update it in the same PR as every change that
> alters behaviour, data shape, rules, workflows, content status or open tasks.

## Index

| File | Read it when you need… |
|---|---|
| [01-project-brief.md](01-project-brief.md) | What the product is, for which church, who uses it, scope and non-goals |
| [02-business-case.md](02-business-case.md) | Why it exists, BRD/FRD summary, priorities, what is implemented vs. still a requirement |
| [03-architecture.md](03-architecture.md) | Flutter app structure, layers, Riverpod providers, routing, offline seed fallback, i18n/RTL, theming (mermaid diagrams) |
| [04-data-model.md](04-data-model.md) | Every Firestore collection/doc and field, flags (`sample`, `visible`, `order`), `settings/features`, admins, contact messages, seed ids |
| [05-firebase.md](05-firebase.md) | Project config, Auth, security rules rule by rule, indexes, Hosting, App Check, Firebase AI Logic (Gemini), service account |
| [06-features.md](06-features.md) | Every public page, feature toggles, the assistant, contact form throttling, business rules (next mass, seasons, feasts) |
| [07-admin-dashboard.md](07-admin-dashboard.md) | The hidden `/admin` dashboard: sign-in, roles, every screen, CRUD/reorder/hide, toggles editor, inbox |
| [08-dev-workflow.md](08-dev-workflow.md) | Local setup, commands, tests, seeding (and its dangers), CI/CD, PR process, conventions, "add a new section" checklist |
| [09-content-status.md](09-content-status.md) | What content is verified vs. pending the church, sources, questions for the church office |
| [10-decisions-and-history.md](10-decisions-and-history.md) | ADR-style key decisions and the PR timeline |
| [11-open-tasks.md](11-open-tasks.md) | Remaining work (infra, security, content, product gaps vs. the requirements) |
| [12-glossary.md](12-glossary.md) | Coptic/church Arabic terms ↔ the English words and keys used in code |

Related files outside this folder:
- [`/AGENTS.md`](../../AGENTS.md) — the short agent guide (golden rules + commands). `CLAUDE.md` and
  `.github/copilot-instructions.md` point to it.
- [`/README.md`](../../README.md) — human-oriented setup, admin guide, deploy and secrets.
- [`/docs/CONTENT_SOURCES.md`](../CONTENT_SOURCES.md) — field → source → status for every seeded value.

## How to use it (agents)

1. Start with `01-project-brief.md` and `03-architecture.md` (10 minutes gives you the whole picture).
2. Before touching data or rules, read `04-data-model.md` and `05-firebase.md` — the Dart model, the admin schema,
   `firestore.rules`, `tool/gen_seed.py` and the tests must change **together** (see the checklist in
   `08-dev-workflow.md`).
3. Before touching content, read `09-content-status.md`: never invent times, names or phone numbers; unknown values
   stay `sample: true`.
4. Before opening a PR, run the commands in `08-dev-workflow.md` and update the relevant memory-bank files.

## Update rules (keep it current after every feature)

- **Same PR, not later.** A PR that changes behaviour updates the matching file(s) here. Reviewers should treat a
  stale memory bank as a bug.
- **Where things go:**
  - New/changed field or collection → `04-data-model.md` (+ `05-firebase.md` if rules changed).
  - New page, toggle, business rule → `06-features.md` (+ `03-architecture.md` if routing/providers changed).
  - Admin UI change → `07-admin-dashboard.md`.
  - New command, workflow, secret or variable → `08-dev-workflow.md` / `05-firebase.md`.
  - Church confirmed or changed content → `09-content-status.md` and `docs/CONTENT_SOURCES.md`.
  - A choice between alternatives (and why) → a new ADR entry in `10-decisions-and-history.md`; also append the PR to
    the timeline there.
  - Task done / discovered → `11-open-tasks.md` (tick it off or add it).
  - New church term in code → `12-glossary.md`.
- **Ground every claim** in a file path, class, function or field name. If you are unsure, check the code; if the
  code and these docs disagree, the code wins and the doc gets fixed.
- **Never write secrets** (service-account JSON, private keys, passwords, reCAPTCHA *secret* key) in these files.
  The Firebase web API key in `lib/firebase_options.dart` is public by design but still is not repeated here.
- Update the "checked against commit" line at the top of this file when you do a full re-verification.
