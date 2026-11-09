# 13 — Hark Agent History, Operating Workflow & Detailed Project Evolution

> **Source**: DSAR Memory Archive (`hark-data-export.json`) exported on `2026-11-07T10:34:13Z`, containing 907 total messages across 3 conversation sessions (including 675 messages specifically tracking the end-to-end development of the **Asafra Church Portal** repository).

---

## 1. Executive Summary & Session Background

This document formalizes the exact operating methodology, agent interaction loops, architectural milestones, and project history established during the lifecycle of the **Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black** portal project (`church-portal`).

- **Project Owner**: Kerollos Melad (`kerollosmelad707`)
- **App Name / Parish**: كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود — شارع 45 قبلي، العصافرة، الإسكندرية.
- **Production URL**: <https://maximos-domadios-church.web.app> (hosting project `asafra-church-portal`).
- **Initial Setup Date**: 2026-10-31 18:55:39 UTC.
- **Export Milestone Date**: 2026-11-07 10:34:13 UTC.

---

## 2. Core Agent Operating Model & Workflow (The Hark Loop)

Across the 675 exchanges between the owner and the AI agent, a strict, zero-defect engineering workflow emerged as the standard protocol:

### A. The 6-Stage Execution Pipeline
1. **Intake & Strict Acceptance Planning**:
   - The agent restates the owner's goal precisely in simple Arabic.
   - Any architectural decision or user-facing change is planned in detail *before* any code is edited.
   - For complex tasks, a dedicated tracking plan is established in `.work/<branch>/status.md` or `docs/plans/`.
2. **Feature Branch Isolation (One PR per Worktree)**:
   - Direct commits and pushes to `main` are strictly forbidden.
   - Never force-push or rebase pushed commits; keep history linear or catch up with `git merge --no-ff origin/<base>`.
   - Stacked PR chains (e.g. Phase 2: PR A → PR B → PR C → PR D → PR E) require bottom-up merging once the entire chain passes review.
3. **Test-First Implementation (TDD)**:
   - Business logic is written in pure Dart under `lib/domain/` with Cairo time (`CairoTime`) and full unit test coverage.
   - UI must pass responsive tests at 320 px (with 200% text scale without overflow), 400 px mobile, and 1400 px desktop.
   - Arabic-first RTL is tested alongside English LTR.
4. **Local Verification Gate (`verify.sh`)**:
   - `flutter analyze` with 0 issues.
   - `flutter test` (all tests green; over 1,000 unit/widget tests).
   - Firestore security rules testing in the local emulator (`tool/rules_test/rules.test.mjs`) ensuring whole-doc evaluations stay within the 1,000 expression limit.
   - `python3 tool/gen_seed.py` drift check ensuring `seed.json`, `known_seed_ids.json`, and `retired_seed_ids.json` remain in sync.
5. **Simultaneous Documentation Sync (ADR-035)**:
   - Every single PR that alters a schema, admin screen, feature switch, or business rule **must** simultaneously update:
     - The Memory Bank (`docs/memory-bank/00` through `12`).
     - The Arabic owner/clerk documentation (`documentation/`).
     - English documentation (`documentation/en/`).
     - A dedicated ADR (Architectural Decision Record) in `docs/memory-bank/10-decisions-and-history.md`.
6. **PR Review, Bot Triage & Safe Deployment**:
   - Open PRs in Draft state.
   - Automated reviews using `@coderabbitai review` and `@sentry review` (capped at max 2 review rounds per PR).
   - Every bot finding is addressed explicitly in conversation threads with either a commit or a documented rationale.
   - Merging is done via squash-merge on `main` only after owner approval.
   - Deploy verification verifies HTTP 200, bundle strings, and PageSpeed budgets (Mobile ≥ 61, Desktop ≥ 60).

---

## 3. The 4-Places Rule for Any Data / Field Change

The agent established that modifying any field in the application requires touching four locations simultaneously to avoid schema or rules divergence:
1. **Model**: `lib/domain/models.dart` and `lib/domain/features.dart`.
2. **Admin Schema**: `lib/ui/admin/admin_schema.dart` (form fields, validation, and layout).
3. **Security Rules**: `firestore.rules` (with corresponding positive and negative tests in `tool/rules_test/rules.test.mjs`).
4. **Seed Generator**: `tool/gen_seed.py` (updating `assets/seed/seed.json` and id sets).

---

## 4. Comprehensive Chronology of Project Milestones (PR #1 through PR #51)

Based on the parsed history from the Hark conversation store, the project evolved through the following distinct milestones:

### Initial Scaffolding & Launch (2026-10-31)
- **Firebase Project Provisioning**: Firebase project `asafra-church-portal` created on Kerollos Melad's account; Firestore in Belgium (`europe-west1`), Email/Password Auth, Gemini API integration enabled.
- **PR #1 (Initial Implementation)**: Complete Flutter web application, GitHub Actions CI/CD pipelines, CodeRabbit review bot setup, and seed hydration.
- **PR #3 (Admin Dashboard & CMS)**: Web-only administrative control center under `/admin` with live preview and Firebase Auth guard.

### Audit, Stabilization & Domain Hardening (2026-11-01 to 2026-11-02)
- **Memory Bank Creation**: Complete memory bank authored under `docs/memory-bank/` to allow seamless local agent handoff.
- **Project Review Audit (8.1/10)**: Audit identified revival liturgical dates, inactive season leaks, public listing fallbacks, and accessibility issues.
- **PR #7 & PR #8**: Remediation plan addressing liturgical domain logic, Cairo timezone grounding, and navigation accessibility.
- **PR #10 (Post-Audit Polish)**: 194 Dart tests, 35 rules tests passing; complete cleanup of sitemap, routing canonical tags, and error gates.

### Customization Studio & Dynamic Sections (2026-11-02 to 2026-11-04)
- **PR #11 (Domain Rules & Seed)**: Flexible models for item details, page headers, custom footer configurations, and assistant grounding.
- **PR #12 (Admin Customization Studio)**: Grouped `DocEditor` with collapsible sections, photo galleries, and split-save architecture to respect Firestore 1,000 expression budgets.
- **PR #13 & PR #14 (Public Detail Pages)**: 7 shareable routes, deep-linking, add-to-calendar, directions, social sharing, and SEO canonical metadata.
- **PR #15 (Coptic Identity & Design Overhaul)**: "Golden Hour" poster theme, video hero, parish seal branding, and iconography generated via `tool/gen_branding.sh`.
- **PR #16 (Daily Verse of the Day)**: 366 public-domain Arabic Van Dyck verses rotating at Cairo midnight with admin override.
- **PR #17 (Occasion Themes & Liturgical Seasons)**: Dynamic theming (Golden hour, dark Holy Week, festive Resurrection, Nativity, Epiphany, Marian feasts) with automatic Cairo-date calculation and Coptic Easter algorithms (1900–2099).
- **PR #18 (Categories, Custom Pages & Contact System)**: Admin-defined categories, notice blocks, hall booking requests, and anonymous complaints/suggestions.
- **PR #19, #20, #21 (Church Assistant via Gemini AI)**: reCAPTCHA Enterprise App Check, Gemini 3.1 Flash-Lite, strictly church-scoped grounding, safe Markdown formatting, and fallback search links to St-Takla.org.
- **PR #24 (Sentry Error Tracking & Zero-PII Policy)**: Privacy-preserving error reporting (`ErrorReporting.capture`), strict data scrubbing (no names, IPs, queries, or form inputs), and owner toggle in `/admin`.

### Liturgical Seasons Simulation & Quality Gates (2026-11-05 to 2026-11-06)
- **PR #42 to PR #48**: Exhaustive 7-phase liturgical season simulation across all Coptic fasts and feasts using the local emulator, locking in edge cases for Good Friday, Holy Saturday, Resurrection midnight, and Nayrouz.
- **PR #49 (Empty State Polish)**: Refined liturgical calendar empty states with upcoming season indicators.

### Phase 2 Architecture: Install, Push Notifications & PWA (2026-11-06 to 2026-11-07)
- **PR #50 (Phase 2 Master Architecture & Plans)**: Formalized ADR-056 covering the roadmap for install banners, push preferences, Android APKs, admin notification dispatching, web push, and responsive audits.
- **PR #51 (Phase 2A — Install Banner & Push Preferences)**:
  - Added bottom install banner for Android APK and PWA.
  - User notification preferences dialog and local storage.
  - Admin toggle in `settings/features` for notification channels.
  - Review status: flagged Firestore rules evaluation budget and reminder lead time bugs, queued for resolution in Draft state.

---

## 5. Architectural & Operating Constraints to Remember

1. **Spark Plan Discipline**:
   - Zero Cloud Functions, Zero Cloud Storage.
   - Uploaded images stored as inline bytes under `media/{id}`.
   - Heavy public data is served as static JSON from Firebase Hosting (`/data/today.json`).
2. **Never Touch Live Production Data Manually**:
   - Never execute `seed_firestore.js --force` or raw write scripts against production without explicit, timestamped owner approval in Cairo time.
   - Pushing to `dev` updates rules on the shared live Firebase project; rules must remain 100% backward compatible with `main`.
3. **Strict Cairo Timezone Handling**:
   - All dates, recurring reminders, liturgical midnight rotations, and schedule comparisons use `CairoTime` (`Africa/Cairo`). Direct `DateTime.now()` usage is forbidden in domain logic.
4. **Bundle & Performance Budgets**:
   - Maximum gzip growth per PR: `+20 KB` for `main.dart.js`.
   - Secondary guides (e.g. APK sideloading walkthrough) must use deferred loading (`deferred as ...`).
   - PageSpeed score thresholds: Mobile ≥ 61, Desktop ≥ 60.

