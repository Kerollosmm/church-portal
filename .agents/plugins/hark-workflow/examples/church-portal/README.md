# church-portal profile

Project settings and rules of [Kerollosmm/church-portal](https://github.com/Kerollosmm/church-portal) for the
hark-workflow kit. Everything in `agents-dir/` is copied into the repo's `.agents/` folder:

| File | Lands at | Holds |
|---|---|---|
| `agents-dir/workflow.env` | `.agents/workflow.env` | gate commands, size + PSI baselines, dev channel, Sentry, review limits, safety patterns |
| `agents-dir/AGENTS.md` | `.agents/AGENTS.md` (always on) | owner + process rules: Arabic replies, absolute Cairo dates, Drive links, live-data approval one item at a time, Spark limits, chain + merge order, ADR numbers, budgets |
| `agents-dir/rules/church-portal.md` | `.agents/rules/church-portal.md` (`trigger: always_on`) | code and content rules (four-places rule, generated seed, l10n, toggles, Sentry privacy) |

## Install

```bash
# in a branch of church-portal (never on main):
node "<KIT>/scripts/hw.mjs" install profile church-portal <path-to-church-portal>          # keeps existing files
node "<KIT>/scripts/hw.mjs" install profile church-portal <path-to-church-portal> --force  # overwrites them
node "<KIT>/scripts/hw.mjs" doctor                                                         # in the repo: config found?
```

Commit the three files on a `chore/` or `docs/` branch with explicit paths and open a draft PR.

## Check the profile on a machine

```bash
node "<KIT>/scripts/hw.mjs" config                          # effective values
node "<KIT>/scripts/hw.mjs" gate --only seed,extra-1,extra-2  # fast steps (seconds)
node "<KIT>/scripts/hw.mjs" adr-next                        # Phase 2 claims ADR-056 … 061
node "<KIT>/scripts/hw.mjs" dev-channel-url                 # DEV-URL: SAME … when DEV_URL is current
```

## Keep it true

- New size / PSI baselines only when the owner accepts them, in a docs PR (`SIZE_BASELINE_*`, `PSI_BASELINE_*`).
- `DEV_URL` changes when the dev channel gets a new hash (`hw.mjs dev-channel-url` says `CHANGED`); the owner adds
  the new host to Firebase Auth authorized domains and the reCAPTCHA key first.
- The Phase 2 table in `AGENTS.md` is a snapshot (7 Nov 2026); the live state is in STATUS.md and
  `docs/plans/phase2/HANDOFF.md`.
