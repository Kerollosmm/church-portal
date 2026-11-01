# 02 — Business case & requirements (summary)

Condensed from the original Arabic PRD (`CHURCH_PORTAL_PRD.md`, 3 pages) and
`Church_Portal_Business_Case_and_Requirements.md` v1.0 (31 Oct 2026). Both live in the project workspace, not in this
repo. The **"Status"** columns below were checked against the code on `main` (PR #3) — they tell you what is real
today versus still a requirement.

## Problem

Earlier church digital efforts built heavy internal **Church Management Systems (CSMS/ERP)** — member accounts,
attendance, permissions, membership databases — that cost a lot and solved problems the congregation did not have
(PRD §1.1 «التحول الجوهري عن أنظمة الإدارة الداخلية»). Meanwhile the real questions ("when is the next mass?", "is the
eye clinic open today?", "when is my son's prep-stage meeting?", "what's the church number and where is it?") are
answered by phone calls, Facebook comments and stale WhatsApp forwards.

## Value

- Visitors: answers in seconds, Arabic or English, any phone, even offline/weak connection.
- Church office: fewer repeated calls; one place to update times.
- Clinics: more bookings via one-tap call/WhatsApp.
- Servants/parents: every stage's meeting and link in one timeline.
- Witness: a dignified public face (history, saints, priests).
- Cost: near zero at parish scale (Firebase free tiers; see below).

## Business requirements (BRD)

| ID | Requirement | Pri. | Status |
|---|---|---|---|
| BR-1 | Four core journeys in ≤ 3 s and ≤ 3 taps | M | UI flows exist; not measured (no analytics/Lighthouse budget) |
| BR-2 | Public directory, no member accounts; only admins sign in | M | ✅ |
| BR-3 | Arabic default (RTL) + one-tap English | M | ✅ (`localeProvider`, `?lang=en`) |
| BR-4 | Content editable by church editors without a developer | M | ✅ `/admin` |
| BR-5 | Seasonal schedules override regular ones automatically | M | ✅ `occurrencesForDay` / `computeNextMass` |
| BR-6 | Urgent announcements only while valid | M | ✅ `visibleAlerts` |
| BR-7 | Contact without login; PDPL-minimised personal data | M | ⚠️ form + rules ✅; consent checkbox / privacy notice / retention ❌ |
| BR-8 | Identity & history presented with dignity | M | ✅ (altars list empty pending church) |
| BR-9 | Near-zero running cost with spending alerts | M | Infra choice; budget alerts are a console task |
| BR-10 | Usage measurable | M | ❌ no Analytics |
| BR-11 | Children's privacy (no identifiable minors' data/photos) | M | ✅ by content policy (no photos, no children's data collected) |
| BR-12 | Optional AI assistant, grounded, kill switch, cost cap | v2 | ✅ built early (`/ask`), hidden without App Check; quota cap is a console task |

## Functional requirements (FRD) — summary with status

Global
| ID | Requirement | Status |
|---|---|---|
| FR-G-01 | Navbar with highlighted "Mass times" + "Clinics" | ✅ `AppShell._HighlightButton` (compact circles on narrow screens) |
| FR-G-02 | AR⇄EN toggle, remembered | ⚠️ toggle ✅, `?lang=en` kept in URL by the router redirect; not persisted in local storage |
| FR-G-03 | Times in Arabic-Indic **and** Latin digits | ✅ `TimeRangeText`, `formatRangeArabic/Latin` |
| FR-G-04 | Footer: address, phones, socials, quick links, last updated | ⚠️ `Footer` has name, address, quick links, ©, "Showing bundled content" note; no phones/socials/last-updated |
| FR-G-05 | Deep links + friendly 404 | ✅ go_router + `errorBuilder` (`notFound` + Back home); Hosting SPA rewrite |
| FR-G-06 | Offline cached content with note | ✅ Firestore persistence + seed fallback (`servingSeed`) |
| FR-G-07 | Analytics events (`answer_visible`, `clinic_call`, …) | ❌ |
| FR-G-08 | PWA install prompt | ❌ (manifest only) — v1.1 |

Pages
| ID | Requirement | Status |
|---|---|---|
| FR-H-01 | Next-mass smart card | ✅ `NextMassCard` |
| FR-H-02 | Hero with photo + verse Rev 2:10 | ✅ verse; `heroImageUrl` empty (no verified photo) → gradient + Coptic cross |
| FR-H-03 | CTA buttons Mass / Clinics / Contact | ✅ (hidden when their section is off) |
| FR-H-04 | Urgent alert banner | ✅ `AlertBanner` (2 shown, expand for more) |
| FR-H-05 | Four highlight cards (milestones) | ✅ 4 verified milestones (1980, 2022 deacons, 2022 hegumens, 2025 papal visit) |
| FR-H-06 | Directory grid | ✅ `_directory` in `home_page.dart` (+ "Ask" card) |
| FR-H-07 | Embedded map + Open in Google Maps | ✅ `ChurchMap` (iframe on web) + Directions |
| FR-H-08 | Floating *Live now* / *Doctors' times* | ❌ v1.1 |
| FR-A-01..05 | History, altars, saints, priests, departed | ✅ (altars empty in seed) |
| FR-M-01..05 | Day tabs, liturgy cards, vespers & praise, Holy Seasons toggle (auto-on in season), one-off dates | ✅ |
| FR-M-06 | Add to calendar (.ics) | ❌ v2 |
| FR-E-01/02 | Age-stage timeline with links | ✅ `EducationPage` (grouped in 3 sections) |
| FR-E-03 | "Today" badge on meetings | ❌ |
| FR-E-04 | Children's stages link to official contact/channel, not open groups | Content policy (seed has only Maximous Youth FB link) |
| FR-AC-01..04 | Activities (scouts, deacons, hymns, Bible, summer…) + contact phone | ✅ generic `activities` with categories; seed holds verified choirs/youth/servant school/media |
| FR-C-01..05 | Specialty chips, doctor card, call/WhatsApp, today-first sort, facilities | ✅ (sort = open today → admin `order` → specialty → doctor) |
| FR-C-06 | "Schedules may change, call to confirm" | ✅ `clinicsIntro` subtitle |
| FR-CT-01..05 | Phones, socials, address+transport, map+GPS, contact form | ✅ |
| FR-CT-06 | Privacy notice + consent checkbox | ❌ |

Admin
| ID | Requirement | Status |
|---|---|---|
| FR-AD-01 | Hidden `/admin`, email/password, non-admin sees "no access" | ✅ (no `noindex` meta/robots yet) |
| FR-AD-02 | CRUD with validation | ✅ `DocEditor` + `admin_validators.dart` + rules |
| FR-AD-03 | "Simulate now" preview of Next mass | ❌ |
| FR-AD-04 | Inbox: mark read/done, delete | ✅ new ⇄ handled, delete (no "spam" status) |
| FR-AD-05 | Owner-only: admins, `settings/church`, feature flags | ⚠️ **Deviation:** only *Admins* is owner-only. Editors may edit `settings/church`, `settings/features` and delete messages (rules use `isAdmin()`). See ADR-011. |
| FR-AD-06 | Content-freshness view | ❌ v1.1 (overview shows latest edits only) |

## Non-functional requirements (NFR) — key points

| NFR | Requirement | Status |
|---|---|---|
| Performance | Time-to-answer < 3 s p75, LCP < 2.5/3 s, ≤ 2 MB first visit, ≤ 60 reads/session | Not measured. Splash in `web/index.html`; Firestore cache; `no-cache` HTML/JS (Flutter bundles not content-hashed) |
| Accessibility | WCAG 2.2 AA intent, 200% text, 48 dp targets | Partly: app bar switches to compact when text is scaled (`AppShell`); no formal audit |
| RTL/bilingual | Arabic default, Cairo font, Ar/En field pairs with fallback | ✅ `context.pick(ar, en)` falls back to the non-empty one |
| Offline | Persistence + app shell cache | ✅ Firestore persistence (40 MB cache); no custom service-worker strategy |
| Security | Public read only on content; admin writes; contact create-only; App Check | ✅ rules; App Check only for AI Logic (reCAPTCHA key pending) |
| Privacy (PDPL) | Consent, minimisation, 12-month retention, no children's data | ⚠️ minimisation ✅; consent/notice/retention ❌ |
| Maintainability | Content-driven UI, rules tests in emulator, README | ✅ |
| Cost | Budget alert, Gemini quota | Console tasks (open) |

## Priorities / phases (business case §7)

| Phase | Window (target) | Scope |
|---|---|---|
| 0 Setup & content | Nov 2026 | Firebase project, repo, CI, content checklist, seed — **done except church content** |
| MVP | 23 Nov – 15 Dec 2026 | Core routes, next mass, alerts, seasons, clinics filter, contact form, AR/EN, offline, analytics, static SEO shell |
| Soft launch | 18 Dec 2026 | QR posters, Nativity alert live by 23 Dec |
| v1.1 | Jan – Mar 2027 | Activities/facilities (built), App Check, SEO snapshot, PWA prompt, floating buttons, freshness dashboard, TTL retention, Play Store |
| v2 | Apr – Jun 2027 | Assistant (built early behind toggles), FCM push, daily synaxarium, .ics, iOS, live-stream embed |

Key dates the content must support: Nativity eve 6 Jan 2027; patron revival 21–25 Jan 2027; Palm Sunday 25 Apr 2027;
Pascha 2 May 2027; St Moses revival ~22 Jun – 1 Jul 2027.

## Costs (business case §1.7, prices checked 31 Oct 2026)

- Spark (no-cost) quotas: Hosting 360 MB/day transfer, Firestore 50K reads/day. At ~5,000 visitors/month the
  average is already near the Hosting daily cap; summer peaks would exceed it.
- Business case **recommends Blaze with a $5/month budget alert** and a hard Gemini quota; expected bill a few dollars
  a month (≈ $20–40 at 50,000 visitors/month incl. assistant). The project currently runs on **Spark** (per project
  setup; not visible in code) — see `11-open-tasks.md`.
- Gemini: 2.5 Flash-Lite is closed to new projects; the app uses `gemini-2.5-flash` (`AppConfig.geminiModel`).

## Risks (top ones)

R1 Flutter web first-load size (mitigation ideas: static HTML shell, font subset, deferred imports — mostly not done);
R2 weak SEO for canvas rendering (meta tags exist in `web/index.html`; JSON-LD/sitemap not done);
R3 content staleness (alerts auto-expire; no freshness view yet); R4 children's privacy; R5 phone-number spam
(publish only official numbers); R6 contact-form abuse (honeypot + client + server throttle); R7 PDPL compliance
(legal advice needed; Firestore stores data outside Egypt); R8 time zone/DST (all logic in Africa/Cairo via
`timezone`); R9 single-person dependency (keep two owners); R10 assistant hallucination (grounded prompt, kill switches).

## Governance (business case §1.9)

Sponsor: priest in charge. **Owners** (`admins.role = owner`): church office manager + one technical servant.
**Editors**: section secretaries (liturgies, church education, clinics, activities). Cadence: weekly 10-minute check of
the next 7 days, monthly verification sweep, seasonal content 14 days ahead.
