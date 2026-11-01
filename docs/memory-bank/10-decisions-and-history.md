# 10 — Decisions (ADR-style) & history

Format: context → decision → consequences. Add a new ADR for every non-obvious choice; never rewrite old ones —
supersede them.

## ADR-001 — Public directory, not a church management system
- **Context:** the PRD's core insight — earlier efforts built heavy ERP/CSMS systems nobody needed.
- **Decision:** read-only public portal; only admins authenticate; no member data.
- **Consequences:** tiny data model, public-read rules, near-zero cost; any member/attendance feature is out of scope
  unless re-approved (privacy/PDPL).

## ADR-002 — Flutter (web + Android) + Firebase
- **Decision:** one Flutter codebase; Firebase Hosting, Firestore, Auth, App Check, AI Logic.
- **Consequences:** fast to build and host for free; trade-offs are web first-load size and weak SEO (canvas). Mitigated
  partly by `web/index.html` meta tags + splash; static HTML shell/JSON-LD not done (open task).

## ADR-003 — Arabic-first RTL with English toggle; shareable `?lang=en`
- **Decision:** default locale `ar`; English via toggle; `?lang=en` read at startup and kept in sync by the router
  redirect; `<html lang>` synced; no `dir="rtl"` in `index.html` (breaks the map iframe platform view).
- **Consequences:** language is not stored on the device (only in the URL).

## ADR-004 — All schedule logic in Africa/Cairo via the IANA database
- **Decision:** `CairoTime` (package `timezone`) for every "now"/weekday/date; seed instants generated with
  `ZoneInfo("Africa/Cairo")`.
- **Consequences:** visitors with phones on other zones see correct times; DST (Egypt EEST) handled; never use
  `DateTime.now().weekday` directly.

## ADR-005 — Pure-Dart domain layer
- **Decision:** `lib/domain/` has no Flutter/Firebase imports; all rules (next mass, seasons, alerts, clinics, phones,
  contact validation, toggles, assistant prompt) are unit-tested there.

## ADR-006 — Seasons replace regular services per occurrence window
- **Context:** naive "season active today ⇒ replace the whole day" broke days where a season starts mid-day.
- **Decision (PR #1 review):** a seasonal service counts only if it starts inside its season's `[startsAt, endsAt]`, and
  it replaces only regular services that start inside that window; replacement is decided on all seasonal services
  (Holy Week hours suspend weekday masses) before filtering by type.

## ADR-007 — Offline/unconfigured fallback to bundled seed
- **Decision:** `assets/seed/seed.json` == the Firestore seed; app never crashes when Firebase fails; if
  `settings/church` is missing the whole app uses the seed; per-stream fallback on errors; footer notice when on seed.
- **Consequences:** `gen_seed.py` is the single source of the seed; CI enforces the generated file is committed;
  `seed_firestore.js` writes `settings` last.

## ADR-008 — Seed safety: create-only by default, retired ids, known ids
- **Decision:** default seeding skips existing docs; `--force` overwrites but deletes retired ids only if not edited in
  /admin; `--fill-missing` adds absent top-level fields in a transaction; `--force` + `--fill-missing` refused;
  `known_seed_ids.json` (grow-only) + `retired` list asserted by `gen_seed.py` and tests.
- **Consequences:** admin edits are never clobbered accidentally; removing a seeded id requires retiring it.

## ADR-009 — No invented content; `sample` flag
- **Decision (PR #2):** replace sample data with verified data; anything unverified stays as clearly labelled
  placeholders (`sample: true`, badge, page notice, assistant `[UNCONFIRMED]`); sources in `docs/CONTENT_SOURCES.md`.

## ADR-010 — Contact form abuse control without auth
- **Decision:** client validation + honeypot + client limiter (60 s, 3/h) + **server global throttle** via
  `meta/contact_rate` written in the same batch (rules: `lastAt == request.time`, ≥ 20 s apart) + strict field
  validation; create-only for the public.
- **Consequences:** two visitors submitting within 20 s → the second is rejected (acceptable at parish scale).

## ADR-011 — Two admin roles; editors manage settings too
- **Context:** business case wanted settings, flags and message deletion owner-only.
- **Decision (PR #3):** `owner` manages admins (never themselves, so an owner always remains); `editor` can edit all
  content, `settings/church`, `settings/features` and the inbox. Missing role = editor.
- **Consequences:** simpler rules; trust editors more. Revisit if the church wants stricter separation (would need
  `isOwner()` on `settings/*` and message delete, plus UI gating).

## ADR-012 — Validated writes with key allow-lists that tolerate legacy fields
- **Decision:** per-collection allow-lists; creates use only allowed keys, updates may only *change* allowed keys
  (`diff().affectedKeys()`); admin edits write only changed fields (`changedFields`). `str()` helper on big settings docs
  to stay under the rules' 1000-expression budget.

## ADR-013 — Feature toggles in one streamed doc
- **Decision (PR #3):** `settings/features` holds section on/off, home layout, hero texts, banner, theme; missing key =
  on; a switched-off section disappears everywhere including the assistant prompt; routes show "not available";
  gated pages wait for the doc to avoid flashes.

## ADR-014 — Assistant gated by App Check and grounded on live content
- **Decision:** Gemini (`gemini-2.5-flash`, Developer API) via Firebase AI Logic; system prompt built from the live
  content of enabled sections; App Check enforced, so the assistant is hidden when App Check is not active (no
  reCAPTCHA key, preview channels).
- **Consequences:** the assistant is currently hidden on the live site until `RECAPTCHA_SITE_KEY` is set.

## ADR-015 — Deploy with firebase-tools CLI and a tolerant credentials action
- **Context:** `FirebaseExtended/action-hosting-deploy` and a secret with stray trailing characters broke PR deploys;
  the deploy SA lacks `serviceusage.services.get`.
- **Decision (PR #1):** composite action `.github/actions/firebase-credentials` (first JSON object only, 0600 file,
  primes the API-enablement cache); `npx firebase-tools@latest` for live/rules/preview; preview builds without the
  reCAPTCHA key.

## ADR-016 — Path URL strategy + Hosting SPA rewrite
- **Decision:** `usePathUrlStrategy()` for clean URLs; Hosting rewrites `**` → `/index.html`; `no-cache` on HTML/JS
  because Flutter bundles are not content-hashed.

## Timeline

| When | PR / commit | What |
|---|---|---|
| 31 Oct 2026 | `6f4a0d8` Initial commit | Empty repo (Kerollosmm) |
| 31 Oct 2026 | **PR #1** `5eb9820` — "Church portal: Flutter + Firebase app, rules, seed, CI/CD" | The whole app: public pages, next-mass/season logic, assistant, contact form, Firestore rules, seed generator + seeder, CI, deploy (live + PR previews), Seed workflow (admin by email + set-password link), Codespaces. Review rounds: server-side contact throttle, hide assistant without App Check, safe workflow inputs, tolerant SA handling, firebase-tools CLI deploy, Node 24 actions, per-occurrence season windows, DST-correct seed instants, admin lookup retry, lang query sync, `<html lang>`, compact app bar for large text, map fallback, splash failure path; CI skip of the serviceusage probe. |
| 31 Oct 2026 | **PR #2** `c42837a` — "Content: replace sample data with verified church data" | Real name/address (Qebly)/coordinates/landline/socials/bishop/history/milestones, reconciled priests, saints, activities with links, Anba Abraam, real alerts; times stay sample with page notice; no invented doctors/phones; `--force` deletes retired ids; `docs/CONTENT_SOURCES.md`. Review: unconfirmed one-offs in assistant, partner orgs labelled, new unconfirmed priests not seeded. |
| 1 Nov 2026 | **PR #3** `fc0e0ad` — "Admin dashboard overhaul + per-section feature toggles" | `settings/features` (15 sections, home layout, hero, banner, theme), visible/order on items, responsive dashboard (overview, church info, every collection, search/filters, hide/show, drag reorder, validated forms, inbox, owner-only admins), rules for every write + emulator tests + CI job, seed `--fill-missing`/`--only` + known ids, README admin guide. Review: no flash of disabled content, live role, rules expression budget, stamps bound to request time/admin, clinic days 1–7, bannerLink format, changed-fields-only saves, reload banner. |
| 1 Nov 2026 | **PR #4** (this) — docs/memory-bank | This memory bank + `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`. |

Append new PRs to this table.
