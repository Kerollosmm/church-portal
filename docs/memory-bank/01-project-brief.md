# 01 — Project brief

## One sentence

A **light, fast, Arabic-first public portal** (البوابة الرقمية العامة) that lets anyone on a phone find, within
**3 seconds**, the next liturgy, the clinic and its booking phone, their age group's meeting, and the church's phones
and exact map location — **without logging in** and without the church running a management system.

Live: <https://asafra-church-portal.web.app> (Firebase Hosting, deployed from `main`).
Repo: `Kerollosmm/church-portal`. Owner/developer: Kerollos Melad (GitHub `Kerollosmm`).

## The church

| | |
|---|---|
| Official name (AR) | **كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود** |
| Official name (EN, as used in the app) | **Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black** |
| Short name in the UI | «كنيسة العصافرة» / "Asafra Church" (`l10n` key `appShort`) |
| Denomination | Coptic Orthodox |
| Address (AR) | آخر شارع 45، العصافرة قبلي، قطاع المنتزه، الإسكندرية |
| Address (EN) | End of Street 45, El-Asafra Qebly, Montaza district, Alexandria, Egypt |
| Coordinates | `31.260138, 30.01129` (lat, lng) — `LAT/LNG` in `tool/gen_seed.py` |
| Landline | 03 536 8888 (`035368888`, +20 3 536 8888) |
| Bishop | نيافة الأنبا بافلي أسقف قطاع المنتزه — H.G. Anba Pavly, Bishop of the Montaza sector |
| Diocese | Montaza sector of the Alexandria (Patriarchal) diocese |
| Patron saints | Sts Maximus & Domadius (feasts 14 & 17 Tuba = 22 & 25 Jan); St Moses the Black (24 Paona = 1 Jul) |
| Official channels | Facebook page `facebook.com/100070313048338`, YouTube channel `UCJiZ4u0IiUbSvBnTrJnRZBA` (@-maximuschurch), Instagram `maximos_coptic_church`, WhatsApp channel (URL in `gen_seed.py` `WHATSAPP_CHANNEL`) |
| Scale | Serves 12,000+ families (2025 sources) |

All of the above are verified and sourced in [`docs/CONTENT_SOURCES.md`](../CONTENT_SOURCES.md).

> **Address naming note.** The original Arabic PRD and early docs (`SPEC.md`, business case) say «العصافرة بحري»
> (El-Asafra *Bahary*). Research (St-Takla, copticorthodox.church, Al-Masry Al-Youm, directories) consistently gives
> **العصافرة قبلي (El-Asafra Qebly)**, so the code, seed, README and `web/index.html` use **Qebly** since PR #2.
> The business case also flags an old "Street 54" typo — the street is **45**.

## Goal: the four 3-second journeys

From the PRD (§1.1) and the business case (§2.2):

1. **J1** — next suitable liturgy today/tomorrow → Home `NextMassCard` + `/mass-schedule`.
2. **J2** — clinics, doctor, hours, booking phone → `/clinics` (specialty chips, "available today", call/WhatsApp).
3. **J3** — my child's / my group's meeting day, time, hall + Facebook/WhatsApp link → `/church-education`.
4. **J4** — church/priest phones and exact Google Maps location → Home quick contacts + map, `/contact`.

Plus the **admin journey**: an editor posts an urgent alert in under 2 minutes (`/admin` → Alerts → Add).

## Users / personas (business case §2)

| Persona | Who | Top need |
|---|---|---|
| P1 Umm Mina (أم مينا) | Parent, local, Arabic only, mid-range Android | Children's meeting time/hall/link |
| P2 Michael | Summer visitor / expat (El-Asafra is a beach district), prefers English, phone may be on another time zone | "Is there a mass tomorrow morning and how do I get there?" |
| P3 Am Guirguis (عم جرجس) | Elderly, weak eyesight, calls rather than types | Is the eye clinic open today, which number |
| P4 Marina | Youth servant | Youth meeting time, official pages to share |
| P5 Office editor (سكرتارية الكنيسة) | Church office, non-technical | Update times quickly, post an urgent alert |

Audiences named in the PRD: local parishioners (شعب الكنيسة), visitors/expats/summer vacationers (الزوار والمصطافون),
parents (أولياء الأمور) following angels/primary/prep/secondary, nursery, summer club, scouts.

## Scope

In scope (implemented — see `06-features.md`):
- Public pages: `/`, `/about`, `/mass-schedule`, `/church-education`, `/church-activities`, `/clinics`,
  `/public-services`, `/contact`, optional `/ask` (Gemini assistant).
- Hidden `/admin` dashboard for content editors (Firebase Auth email/password + `admins/{uid}`).
- Arabic-first RTL with English toggle; Africa/Cairo time for all schedule logic.
- Web (Firebase Hosting) + Android; iOS-ready but not registered.
- Works offline / unconfigured on bundled seed data (`assets/seed/seed.json`).

## Non-goals (scope guard — PRD §1.1, BR-2)

- **Not** a church management system / ERP: no member accounts, attendance, membership databases, donations,
  confession booking, servant management.
- Only admins sign in. Any feature that stores personal data about parishioners needs explicit approval because it
  changes the privacy (Egyptian PDPL, Law 151/2020) and cost profile.
- No invented content: unknown times/names/phones stay placeholders flagged `sample: true` (see `09-content-status.md`).

## Success metrics (business case §1.6 — targets, mostly not yet instrumented)

| KPI | Target |
|---|---|
| K1 time-to-answer | < 3 s p75 on mobile 4G; < 1.5 s repeat |
| K2 LCP | < 2.5 s repeat, < 3 s first visit |
| K3 weekly visitors | baseline first; ~500/week off-season, ~1,500/week Jul–Aug |
| K4 clinic call clicks | page view → contact tap ≥ 25% |
| K6 contact form | ≥ 1 genuine message/week, spam < 5% |
| K7 content freshness | ≥ 95% of liturgies/meetings/clinics verified in the last 30 days |
| K8 journey UAT | ≥ 90% complete in ≤ 3 taps and ≤ 10 s |
| K9 availability | ≥ 99.9% monthly |

**Status:** Analytics is **not** integrated yet (no `firebase_analytics` in `pubspec.yaml`), so K1/K3–K6 cannot be
measured today. Tracked in `11-open-tasks.md`.

## Benchmark

<https://stathanasius-elseyouf.com/> (St Athanasius church, El-Seyouf, Alexandria): calm Arabic home with a verse,
history timeline, services grid, tap-to-call phones, embedded map. The portal adopts that structure and adds the
Next-liturgy smart card, season-aware schedule, clinic specialty filter and a unified age-stage timeline.

## Source documents

- Original Arabic PRD (3 pages): project workspace `files/uploads/CHURCH_PORTAL_PRD.md-7a189e5194de.pdf`
  (not in the repo).
- `church_portal_docs/SPEC.md` and `church_portal_docs/Church_Portal_Business_Case_and_Requirements.md`
  (project workspace, not in the repo) — summarised in `02-business-case.md`.
- `docs/CONTENT_SOURCES.md` (in the repo).
