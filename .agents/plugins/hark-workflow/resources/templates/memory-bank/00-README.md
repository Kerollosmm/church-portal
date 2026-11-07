# Memory bank — {{PROJECT_NAME}}

Long-term memory of this project for coding agents (Antigravity, Claude Code, Codex, Cursor…) and for humans joining
later. **Code is the source of truth**; these files explain what exists, why, and how to change it safely.

Checked against `{{DEFAULT_BRANCH}}` at commit `{{COMMIT}}` ({{DATE}}). Update this line in every PR that edits the bank.

## Rules for this folder
- Update it **in the same PR** as the code change it describes.
- Every statement must be checkable in the code (file / function / field names).
- Human-facing manual: `{{DOCS_DIR}}/` (one file per feature). Decisions: `10-decisions-and-history.md`.

## Index
| File | Holds |
|---|---|
| [01-project-brief](01-project-brief.md) | what the product is, for whom, what it is not |
| [02-business-case](02-business-case.md) | why it exists, constraints |
| [03-architecture](03-architecture.md) | layers, routes, state, packages, builds |
| [04-data-model](04-data-model.md) | collections / tables, fields, flags, seed |
| [05-backend](05-backend.md) | security rules, hosting, auth, quotas, services |
| [06-features](06-features.md) | features and business rules |
| [07-admin-dashboard](07-admin-dashboard.md) | admin screens, fields, switches |
| [08-dev-workflow](08-dev-workflow.md) | commands, CI/CD, branch & PR rules, checklists |
| [09-content-status](09-content-status.md) | real vs sample content, sources |
| [10-decisions-and-history](10-decisions-and-history.md) | ADR log + timeline |
| [11-open-tasks](11-open-tasks.md) | open items |
| [12-glossary](12-glossary.md) | domain terms |
