# Memory bank — St. Maximus & Domadius Church Portal (Asafra)

This folder is the long-term memory of the project for coding agents (Claude Code, Codex, Cursor, Copilot…) and
for humans joining later. Code is the source of truth; these files explain **what exists, why, and how to change it
safely**. Every statement here was checked against the code on `main` at commit `6a30772` (PR #7, "PR 1" of the
review plan, 1 Nov 2026) plus the changes of PR 2 of the plan (`fix/phase2-ux-a11y-admin`: WCAG 2.2 AA contrast and
theme presets, 320 px / 200 % text layouts, two-way `?lang=` sync, screen-reader semantics, admin fixes; merged as
`bc934d3`, PR #8) plus PR 3 of the plan (`feat/phase3-compliance-seo-perf`: PDPL privacy notice + consent on the
contact form, static canonical + `Church` JSON-LD in `web/index.html`, deferred `/admin` and `/ask` chunks, language
choice remembered in `localStorage`; merged as `ad621cf`, PR #9) plus PR #10 (`fix/pr10-post-audit-polish`, 2 Nov
2026: Cairo-weekday assistant header and dated one-off grounding, admin chip contrast / narrow reflow / tooltips /
stream re-binding, per-route canonical + `noindex` via `setDocumentRouteMeta`, URL fragments kept by `?lang=` sync,
`/clinics` out of the sitemap while off, `validFeatures` on `keysAllowed` + `optUrlOrPath`, `deploy-rules` gated on
`build`) plus PR #11 of the customization plan (`feat/pr11-domain-rules-seed`: item detail-page models, page
headers / footer settings, prefix-aware section gating, budget-aware change-gated rules, seed maps and assistant
grounding — ADR-020) plus PR #12 (`feat/pr12-admin-customization-studio`: grouped `DocEditor` with collapsible
detail / photos / contacts cards, multi-image gallery, split saves within the rules budget, Page headers + Footer
cards in `FeaturesEditor`, 320 px / 200 % admin polish) plus PR #13 (`feat/pr13-public-detail-pages`: 7 shareable
item detail routes + `ItemDetailPage` with lazy zoomable gallery, custom fields, contact/social actions and per-item
SEO, parent-aware phone Back arrow, card Details links, custom page headers / intro notes, FR-G-04 footer) plus
PR #14 (`feat/pr14-detail-pages-default-on`: detail pages on by default — opt-out `detailsEnabled` — with labelled
key facts, add-to-calendar, directions, share link and "More in this section"; ADR-021) plus PR #15
(`design/coptic-identity`: "Golden hour" poster identity, image display styles, seamless hero with a trimmed looping
video on every screen size, new parish seal and regenerated icons; ADR-022 revised, ADR-023, ADR-018 amendment) plus PR #16
(`feat/daily-verse`: verse of the day on the home page — 366 public-domain Arabic Van Dyck verses, rotating at Cairo
midnight, admin on/off and fixed verse; ADR-024; merged as `6759f0d`) plus PR #17 (`feat/occasion-themes`: occasion
themes — Golden hour default, dark Holy Week, festive Resurrection, Nativity, Epiphany, fasts, Marian feasts — with
Cairo-date scheduling and Coptic Easter, contrast-checked palettes and admin colour edits; a YouTube hero video
library (removed again in PR #25, ADR-036); the verse of the day moved into the hero; ADR-025, ADR-026, ADR-024 amendment; merged as `55e2a92`) plus
PR #18 (`feat/categories-pages-contact`: admin-defined categories with items and `/section/<slug>` pages, custom
pages with blocks and donation info linked from notices, contact types with hall booking and anonymous complaints /
suggestions, inbox boxes / booking status / notes; ADR-027, ADR-028; merged as `37a58d5`) plus PR #19
(`feat/assistant-ai-logic`: the "Ask the church" assistant on web + Android — reCAPTCHA Enterprise / Play Integrity
App Check, default model `gemini-3.1-flash-lite`, church-only scope with an admin refusal message, grounding of
contact types and custom sections / pages, per-visit limits, `/admin` → AI assistant settings; stable contact
category ids; ADR-029) plus PR #20 (assistant grounded on live data on the first question, App Check warm-up, one
retry) plus PR #21 (safe Markdown replies, faith questions only via a St-Takla.org search link, 3 questions per
device per Cairo day, no default suggestion chips; ADR-030/031) plus PR #22 (hero without the address pill by
default, verse of the day without a panel; ADR-032) plus PR #23 (`settleFirst` cache-first fix for custom sections /
pages / contact types, fingerprinted icon fonts, admin nav icons; ADR-033) plus PR #24 (`feat/sentry-error-tracking`:
Sentry error tracking on web + Android with PDPL-safe scrubbing and the `/admin` switch
`settings/features.errorReporting`; ADR-034; merged as `d60261d`) plus PR #25 (`docs/feature-documentation`, 4 Nov
2026: the PR #15–#24 behaviour re-checked against the code at `d60261d`, stale assistant / clinics / seeding /
font notes fixed, the Arabic feature documentation in [`/documentation/`](../../documentation/README.md);
ADR-035; plus the removal of the YouTube hero video library — ADR-036 — later PRs are listed in `10-decisions-and-history.md`;
latest: PR #29 PageSpeed (ADR-037) and PR #30 footer bundled-data note fix, sitemap generated from Firestore at deploy,
loading screen until real content (ADR-038); PR #31 Coptic calendar / liturgical day at 18:00 / Coptic date strip
(ADR-039) and the top event of the day (church event > Katameros > computed feasts) + live-stream banner at no
Firestore cost (ADR-040); PR #32 programme details — speaker, topic, choir, venue, audience, Drive PDF link — on
services, meetings and seasons, admin venue / audience lists, parallel services (ADR-041); PR #33 season presets —
one reversible «تجهيز الموسم» action with auto-revert at the season end, season verse sets, assistant season limit
and section-aware topics, hero v2 loops (ADR-042); PR #37 occasion sub-themes follow the season, every UI colour from
the palette (ADR-043); PR #35 liturgical web loading screen (seal, church name, gold progress track), top utility bar
with the Coptic date and a live badge above the app bar, on the palette's title-band roles (ADR-044); PR #38 simulation
fixes — every active season's service on the next-service card, programme while «يُقام الآن», top event falls back to
tonight's programme service, assistant grounds programme / church events / live link / paused weddings, seed templates
never mix into a season with real services (ADR-045); PR #39 live-test fixes — top event only on the stored
features, English title before boot, App Check lazy again, no public sample marks, Coptic date fallback, pope-visit
images on Hosting (ADR-046); PR #40 English verse of the day — bundled public-domain WEB
(British Edition) text, optional English for the admin's fixed and season verses (ADR-047); Docs PR: English
documentation suite in `documentation/en/`, comprehensive project README overhaul with framework logos, and cross-references (ADR-048);
PR #42 season card timing — «يُقام الآن» names the services running now in other halls, overnight services and cross-midnight parallels,
a readable seasonal switch on every theme, the day-to-night handover tested minute by minute, admin 12-hour (AM/PM)
time and date pickers, stored 24-hour (ADR-049)). **Phase 2 (notifications & mobile apps)** is planned in
[`docs/plans/phase2/`](../plans/phase2/README.md) (ADR-056; start with `HANDOFF.md` and `STATUS.md`; PR A ADR-057 install banner & prefs, PR B ADR-058 Android APK & local alarms, PR C ADR-059 notification manager, Cloudflare Worker FCM sender & deep links).

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
| [13-hark-agent-history-and-workflow.md](13-hark-agent-history-and-workflow.md) | Agent interaction history, operating loops, Hark workflow, and detailed evolution of PR #1–#51 |

Related files outside this folder:
- [`/AGENTS.md`](../../AGENTS.md) — the short agent guide (golden rules + commands). `CLAUDE.md` and
  `.github/copilot-instructions.md` point to it.
- [`/README.md`](../../README.md) — human-oriented setup, admin guide, deploy and secrets.
- [`/docs/CONTENT_SOURCES.md`](../CONTENT_SOURCES.md) — field → source → status for every seeded value.
- [`/documentation/en/`](../../documentation/en/README.md) — **English** human documentation suite (Architecture, Operations runbook, Master Feature Reference).
- [`/documentation/`](../../documentation/README.md) — **Arabic** documentation for the owner, church office and
  anyone joining: what every feature does for visitors, how to control it from `/admin` (real screen / switch
  labels), how it works technically, limits, plus `operations.md` (deploy, admins, seed safety, Sentry, common
  problems). The memory bank is the agents' long-term memory; `documentation/` is the human manual. **Both are
  updated in the same PR as a feature change** (ADR-035).

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
  - Any feature, admin screen / switch, workflow or operational change → the matching Arabic file in
    `/documentation/` (one file per feature; `operations.md` for deploy / seed / admins / Sentry) — same PR.
- **Ground every claim** in a file path, class, function or field name. If you are unsure, check the code; if the
  code and these docs disagree, the code wins and the doc gets fixed.
- **Never write secrets** (service-account JSON, private keys, passwords, reCAPTCHA *secret* key) in these files.
  The Firebase web API key in `lib/firebase_options.dart` is public by design but still is not repeated here.
- Update the "checked against commit" line at the top of this file when you do a full re-verification.
