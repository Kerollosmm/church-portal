# System Architecture & Technical Design

This document details the architectural foundation of the Church Portal: Flutter code layers, routing and code-splitting, Firebase and Firestore data architecture, security rules, offline seed fallback, dynamic theming, and performance engineering.

For deep-dive memory bank references, see:
- [`docs/memory-bank/03-architecture.md`](../../docs/memory-bank/03-architecture.md) — Architectural patterns, providers, and state flows.
- [`docs/memory-bank/04-data-model.md`](../../docs/memory-bank/04-data-model.md) — Comprehensive Firestore collection and document schemas.
- [`docs/memory-bank/05-firebase.md`](../../docs/memory-bank/05-firebase.md) — Security rules, indexes, App Check, and Hosting.

---

## 1. High-Level System Architecture

```
User Device (Web Browser / Android App)
        │
        ▼
 Firebase Hosting (Site: maximos-domadios-church) ──► Static Flutter Web Bundle (build/web)
        │
        ├── Cloud Firestore (europe-west1)  ← Public content, settings, and contact messages
        ├── Firebase Authentication         ← Admin sign-in only (Email/Password)
        ├── App Check                       ← reCAPTCHA Enterprise (Web) / Play Integrity (Android)
        ├── Firebase AI Logic (Gemini)      ← "Ask the Church" Assistant
        └── Sentry Error Monitoring         ← Privacy-scrubbed technical error telemetry
```

### Free-Tier (Spark Plan) Constraints & Solutions
1. **No Cloud Functions:** All business rules (next mass calculation, alert filtering, clinic availability, season replacement) run as pure Dart in the client domain layer (`lib/domain/`).
2. **No Cloud Storage Bucket:** Spark plans cannot provision Cloud Storage buckets without billing. Images uploaded via `/admin` are resized (≤ 800px) and compressed to WebP (~250 KB) in the client browser, then stored as base64 strings in Firestore `media/{id}` documents. The public UI loads these lazily with in-memory caching.
3. **App Check Protection:** Firebase AI Logic API calls are strictly gated behind App Check tokens to prevent quota exhaustion and unauthorized external scraping.

---

## 2. Codebase Organization (`lib/`)

```
lib/
├── main.dart                  # Application entry point: Sentry bootstrap, seed loader, and Firebase init
├── app.dart                   # MaterialApp.router configuration, theme bindings, and localization setup
├── router.dart                # go_router declarative route definitions and navigation guards
├── firebase_options.dart      # Platform Firebase configuration (Web, Android, iOS placeholder)
├── config/
│   └── app_config.dart        # Build-time constants (Gemini model, reCAPTCHA keys, Sentry DSN)
├── core/
│   ├── l10n.dart              # Arabic/English translation dictionary and string helpers
│   ├── theme.dart             # Occasion palette definitions, typography, and contrast enforcement
│   └── url_launcher.dart      # Safe external URL and protocol launchers (tel:, wa.me, maps)
├── domain/                    # PURE DART business logic (Zero Flutter/Firebase dependencies)
│   ├── models.dart            # Immutable entity models with tolerant JSON deserialization
│   ├── cairo_time.dart        # Africa/Cairo timezone calculations and IANA DST rules
│   ├── schedule.dart          # Next-mass computation, liturgical window overrides, and schedule tabs
│   ├── rules.dart             # Alert filtering, clinic availability, phone helpers, and rate limiting
│   ├── features.dart          # Section toggles, route guards, home block ordering, and settings
│   ├── time_format.dart       # Bilingual time formatting (Latin and Arabic-Indic numerals)
│   └── assistant_context.dart # Grounding prompt builder for the AI assistant
├── data/                      # Data sources and repositories
│   ├── content_repository.dart# Public Firestore streams and seed fallback handlers
│   ├── admin_repository.dart  # Authenticated Firestore write operations and audit logging
│   ├── media_repository.dart  # Inline Firestore media storage and compression handlers
│   ├── app_check_providers.dart# Platform-specific App Check provider selection
│   └── error_reporting.dart   # Sentry telemetry with strict client-side PII scrubbing
├── state/
│   └── providers.dart         # Riverpod 3 providers binding repositories to UI components
└── ui/
    ├── pages/                 # Public feature views (Home, Mass Schedule, About, Contact, etc.)
    ├── admin/                 # Hidden dashboard (/admin): schemas, CRUD editors, inbox, toggles
    └── widgets/               # Reusable UI widgets: AppShell, FeatureGate, ItemDetailPage, etc.
```

### Core Coding Rules
- **Four-Point Modification Rule:** Whenever a domain field is added, altered, or removed, four places must be updated simultaneously:
  1. The domain model (`lib/domain/models.dart` or `features.dart`).
  2. The admin schema (`lib/ui/admin/admin_schema.dart`).
  3. Security rules (`firestore.rules`).
  4. Seed generator (`tool/gen_seed.py` + tests).
- **Timezone Sanctity:** Direct usage of `DateTime.now()` is forbidden for business logic; all time computations must execute through `CairoTime.now()` or `CairoTime.toCairo()`.
- **Pure Domain:** The `lib/domain/` directory must never import Flutter UI packages or Firebase SDKs, ensuring 100% deterministic unit testing.

---

## 3. Declarative Routing & Navigation

Routing is implemented with `go_router` using Flutter's `PathUrlStrategy` for clean web URLs (e.g. `/mass-schedule` instead of `/#/mass-schedule`).

| Route | View Component | Section Gate / Access Condition |
|---|---|---|
| `/` | `HomePage` | Always accessible. Content blocks adapt dynamically. |
| `/about` | `AboutPage` | Accessible if any of `history`, `saints`, `priests`, or `departedPriests` is enabled. |
| `/mass-schedule` | `MassSchedulePage` | Controlled by `Sections.schedule`. |
| `/church-education` | `MeetingsPage` | Controlled by `Sections.meetings`. |
| `/church-activities` | `ActivitiesPage` | Controlled by `Sections.activities`. |
| `/clinics` | `ClinicsPage` | Controlled by `Sections.clinics`. Optional `?specialty=` filter. |
| `/public-services` | `PublicServicesPage`| Controlled by `Sections.services`. |
| `/contact` | `ContactPage` | Accessible if `contactInfo`, `socials`, or `contactForm` is enabled. |
| `/section/:slug` | `CustomSectionPage` | Controlled by `customSections` toggle and section visibility. |
| `/page/:slug` | `CustomPage` | Controlled by `customPages` toggle and page visibility. |
| `/priest/:slug`, `/saint/:slug`, etc. | `ItemDetailPage` | Follows the parent section's feature gate. |
| `/ask` | `AssistantPage` | **Deferred chunk.** Gated by `Sections.assistant` and `settings/church.assistantEnabled`. |
| `/admin` | `AdminPage` | **Deferred chunk.** Hidden from search engines (`noindex`). Requires authentication. |

### Architectural Guardrails
- **`FeatureGate` Wrapper:** Every public view is wrapped by `FeatureGate`. If an admin toggles a section off, the view immediately renders a friendly "Section Currently Unavailable" message with a button returning to Home.
- **Code Splitting (Deferred Loading):** The `/admin` dashboard and `/ask` assistant views are loaded as separate JavaScript bundles via `DeferredLoader`. Standard visitors browsing mass times never download admin or AI logic libraries, keeping initial bundle size minimal.
- **Bilingual URL Sync:** The active language state is reflected in the URL via `?lang=en` (English) or root path (Arabic default). Switching languages maintains current scroll positions and URL fragments.

---

## 4. Cloud Firestore Architecture

All application data resides in Cloud Firestore (`europe-west1`). Read operations are open to the public, while write operations are restricted exclusively to authenticated administrators.

### Core Collections Overview

| Collection / Doc | Contents & Purpose | Public Access | Admin Operations |
|---|---|---|---|
| `liturgies` | Regular weekly Divine Liturgies, Vespers, and Praise times. | Read | Full CRUD |
| `seasons` | Holy Seasons (Pascha, Nativity, revivals) with special replacement liturgies. | Read | Full CRUD |
| `meetings` | Sunday schools and youth/adult fellowships by age group. | Read | Full CRUD |
| `clinics` | Charity medical clinics, specialties, and doctor schedules. | Read | Full CRUD |
| `facilities` | Public parish facilities (nursery, library, mourning halls). | Read | Full CRUD |
| `activities` | Scouts, deacon schools, hymns institutes, sports teams. | Read | Full CRUD |
| `priests` | Serving and departed priests (`status: "serving"` or `"departed"`). | Read | Full CRUD |
| `saints` | Patron saints, biographies, and annual feast dates. | Read | Full CRUD |
| `milestones` | "Our Story" historical parish timeline cards. | Read | Full CRUD |
| `alerts` | Urgent banners and announcements with start/end windows. | Read | Full CRUD |
| `categories`, `entries`, `pages` | Admin-defined custom sections, items, and custom page builder docs. | Read | Full CRUD |
| `settings/church` | Core church identity: address, coordinates, landlines, history, altars. | Read | Update |
| `settings/features` | Master feature toggles, home layout ordering, theme settings, daily verse. | Read | Update |
| `settings/contact` | Configurable contact message categories and hall booking types. | Read | Update |
| `settings/assistant` | AI assistant configuration: prompt, limits, allowed topics, welcome text. | Read | Update |
| `media/{id}` | Inlined base64 image data for uploaded photos. | Get single doc | Upload / Delete |
| `contact_messages` | Inbound inquiries, hall bookings, and anonymous suggestions/complaints. | Create only | View, status, delete |
| `meta/contact_rate` | Global anti-spam rate limiter for the contact form. | None | Server batch write |
| `push_queue/{id}` | Batch-written Web Push subscription requests (ADR-060). | Create only (in batch) | None (drained by Worker) |
| `meta/push_rate` | Global anti-spam rate limiter for push_queue batch writes (ADR-060). | None | None |
| `meta/push_topics` | Web push active subscriber stats written by Worker Cron 2 (ADR-060). | None | Admin Read |
| `meta/push_plan` | Compiled upcoming liturgy & meeting reminder topics (ADR-060). | None | Admin Read |
| `admins/{uid}` | Administrator directory mapping Firebase Auth UIDs to roles (`owner`/`editor`). | None (Auth check) | Managed by Owners |

---

## 5. Security Rules Design (`firestore.rules`)

Security rules enforce multi-layered protection while strictly respecting Firestore's **1,000-expression evaluation limit**:
1. **Per-Collection Key Allow-Lists:** Every collection enforces an explicit allow-list of keys. Documents containing unexpected fields are immediately rejected.
2. **Changed-Field Delta Auditing:** Updates use `diff().affectedKeys()` to validate only the attributes being modified, preventing unnecessary expression tree evaluations.
3. **Contact Form Abuse Protection:** 
   - Public creation requires valid string lengths (Name: 2–80, Message: 5–1,000, valid Egyptian phone or email).
   - Rate limiting is enforced through an atomic batch write to `meta/contact_rate`, requiring at least 10 seconds between global submissions.
   - The honeypot field (`website`) must be absent or strictly empty.
4. **Role-Based Access Control:**
   - `owner`: Can edit all content, settings, and manage administrator access in `admins/{uid}`.
   - `editor`: Can edit all content, settings, and process inbound contact messages, but cannot alter `admins/{uid}`.

---

## 6. Dynamic Liturgical Theming Engine

The Church Portal features an adaptive theming engine that alters color palettes, backgrounds, typography, and contrast based on the Coptic liturgical calendar:

| Occasion Theme | Visual Identity & Dominant Accents | Liturgical Association |
|---|---|---|
| **Golden Hour (Default)** | Parchment ground, rich burgundy (`#6E1C1C`), and gold leaf accents. | Standard year-round identity. |
| **Holy Week (Dark)** | Charcoal black cloth, ashen silver, deep crimson accents (zero gold/violet). | Pascha Week (Holy Monday to Good Friday). |
| **Resurrection (Festive)** | Luminous ivory ground, royal Easter red, and brilliant gold radiance. | 50 Days of Pentecost and Feast of the Resurrection. |
| **Nativity & Epiphany** | Deep midnight navy, starlight white, and celebration gold. | Nativity and Theophany seasons. |
| **Fasts & Apostles** | Warm stone, muted ash, and deep oxblood accents. | Apostles Fast, Jonah's Fast, St. Mary Fast. |
| **Marian Feasts** | Soft heavenly blue, silver trim, and radiant white. | Feasts of the Theotokos. |

### WCAG 2.2 AA Contrast Walk
Every theme palette is programmatically checked against WCAG 2.2 AA contrast standards (minimum 4.5:1 for body text, 3.0:1 for large display headers). If an admin customizes accent colors in `/admin`, the contrast engine automatically adjusts lightness to maintain readability.

---

## 7. Performance Engineering

1. **PageSpeed 90+ Optimization:**
   - **CSS-Animated Ambient Layer:** Ray shimmering and subtle atmospheric effects in the hero section are implemented via a pure CSS DOM overlay (`HeroAmbientLayer`) on web, eliminating per-frame Flutter canvas repaints.
   - **Deferred App Check:** App Check tokens are fetched lazily only when a visitor actually navigates to or opens the AI Assistant `/ask`, saving ~700 KB of initial JavaScript payload.
   - **Static HTML Loading Shell:** The initial page load displays a warm cream (`#FBF3E4`) liturgical screen with the parish seal and a gold progress track in pure CSS, providing instantaneous visual feedback while Flutter's engine initializes.
2. **Automated Sitemap Generation:** The CI/CD deploy pipeline executes `tool/build_sitemap.sh` on every release to generate an up-to-date `sitemap.xml` directly from Firestore content, optimizing search engine discoverability.
