# 09 — Content status

Authoritative, field-by-field table with source URLs: **[`docs/CONTENT_SOURCES.md`](../CONTENT_SOURCES.md)**
(research compiled 31 Oct 2026 from the church's Facebook page, YouTube channel and news/web sources). This file is the
summary agents need before touching content.

## Rules

- **Never invent** times, names, phone numbers, doctors, halls or photos. PR #2 removed every invented value.
- Anything not published by the church or single-sourced/old stays **`sample: true`**: the site shows the
  «بيانات تجريبية» badge, the «مواعيد تقريبية — في انتظار تأكيد الكنيسة» notice on schedule/meetings pages,
  and the assistant says it is unconfirmed (`[UNCONFIRMED]`).
- When the church confirms an item: untick **Unconfirmed** in `/admin` (and fix the values), **and** update
  `tool/gen_seed.py` (+ regenerate) and `docs/CONTENT_SOURCES.md`, so the offline seed and a fresh database agree.
- Live Firestore may differ from the seed after admin edits — the database is the truth for the live site; the seed is
  the truth for offline fallback and new environments.

## Verified (`sample: false`)

| Area | What |
|---|---|
| Identity | Name, address (end of Street 45, El-Asafra Qebly, Montaza), coordinates 31.260138, 30.01129, landline 03 536 8888 |
| Channels | Facebook (`100070313048338`), YouTube channel, Instagram `maximos_coptic_church`, WhatsApp channel (no WhatsApp chat number is published → `whatsapp` empty) |
| Bishop | H.G. Anba Pavly, Bishop of the Montaza sector |
| History & milestones | Serving since at least 1980 (Fr Tadros Labib ordained 1 Aug 1980); 12,000+ families; 30 Jun 2022 200 deacons ordained; 10 Nov 2022 three hegumens; 25 Jun 2025 first visit of Pope Tawadros II; annual revivals; Anba Abraam service |
| Saints | Maximus & Domadius (14/17 Tuba = 22/25 Jan), Moses the Black (24 Paona = 1 Jul) |
| Priests | Bemwa, Bedaba, Doumadious, Moussa, Yonathan, Loukas (serving); departed Tadros Labib |
| Activities | All 11 (choirs, hymns school, Maximous Youth, prep boys, Antibiotic Mime, El-Karouz servant school, servant-care course, media centre, «كلمتين في رغيف»); two are labelled partner organisations, not confirmed church ministries |
| Facilities | Anba Abraam service (phone = church landline) |
| Alerts | Follow-announcements (WhatsApp channel), Nativity fast 2026, two 2027 revivals (no times, "announced on the channel") |
| Seasons | 2027 dates from the Coptic calendar and revival patterns; Nativity, Holy Week, Pascha replace the regular schedule, the two revivals are additive (`replacesRegular`) |

## Pending church confirmation (`sample: true`)

| Area | Count | Notes |
|---|---|---|
| Liturgies | **all 47** | Typical Alexandrian-parish placeholder times; places reduced to «الكنيسة / Church». All titles, season liturgies, and Pascha services aligned with authentic parish posters (see `docs/authentic-parish-vocabulary.md`); corrected St Domadius feast to departure (تذكار نياحة وتطييب الرفات) |
| Meetings | **all 11** | Placeholder days/times, no halls; youth meeting links the real Maximous Youth page; stage names aligned with authentic Sunday School titles (اجتماع أسرة الملائكة، ابتدائي، إعدادي، ثانوي، خريجين، شباب، أسرة، رجال، سيدات، بركة كبار السن) |
| Facilities | nursery, employment, halls, library | No source; fake phones/hours removed |
| Priests | Bigol, Saleeb (last confirmed 2022), Barnaba (single 2025 source), departed Maximus Fouad (single source) | |
| Altars | none seeded | No source lists the altars (PRD lists main: Sts Maximus & Domadius; second: St Moses; annexes: St Mary, St Mina & St George — unverified) |
| Hero / priest photos | none | No hotlinkable verified photos (`heroImageUrl`, `photoUrl` empty) |
| Saint images (live data) | AI paintings, set by the site owner | 3 Nov 2026 (PR #15): the owner asked to use the Gemini-painted icons as the main image of `saints/moses-black` and `saints/maximus-domadius` (`image.url` = `https://maximos-domadios-church.web.app/art/saint-moses-black.webp` / `.../art/saints-maximus-domadius.webp`, served from `web/art/`). Decorative paintings, not historical icons; replace with real icons when the church provides them |

Deliberately **not seeded**: Fr Yassa Ibrahim and Fr Philemon Fawzy (named in priestly-calling congratulations on
31 Oct 2026 — ordination may be upcoming), "القمص اسحق" and "ابونا مكسيموس" (ambiguous mentions).

## Questions for the church office (open)

1. Weekly liturgy, vespers and praise timetable (+ revival and Holy Week times and places/altars).
2. Sunday-school and meeting days, times and halls, and official contact/channel per stage (no open group invites for
   children — privacy).
3. Nursery, employment office, condolence/occasion halls, library: confirm or remove; hours and phone.
5. Current priest roster (confirm Bigol, Saleeb, Barnaba; ordination/assignment of Yassa Ibrahim and Philemon
   Fawzy), with photos and consent.
6. Founding/consecration year and altar names (Hegumen Bemwa Ghaly's history talk on 25 Jun 2025 is the lead).
7. Photos of the church building (Facebook cover album has a bell-tower photo) for the hero.
8. An official mobile/WhatsApp number for enquiries, if any.
9. Who are the owners/editors (`admins`) and who approves content (sponsor: priest in charge).

## Sources (abbreviations used in CONTENT_SOURCES.md)

FB official Facebook page; YT official YouTube channel; A St-Takla church page; B copticorthodox.church (25 Jun 2025);
C Al-Masry Al-Youm (25 Jun 2025); D El-Watan (25 Jun 2025); E findinegypt; F shewaya; K/K2 copt4g/Watani (2022);
L Al-Masry Al-Youm (2018); T Cairo24 (10 Nov 2022); J Dostor (10 Feb 2022); P1–P7 St-Takla priest pages; W1/W2
St-Takla saint bios. Full URLs in `docs/CONTENT_SOURCES.md`.

## Push notifications (Phase 6H close-out)

This does not change seeded church content or the verification tables above.

- **28 Nov 2026, 7:05 PM Africa/Cairo:** the owner gave explicit go for Stage 2 broad launch and is turning on «تشغيل الإشعارات» in `/admin → الإعلانات والإشعارات` himself.
- **Stage 1 Android test passed** the same evening: GitHub Actions «Push Sender (Manual Fallback)» run [`46168247091`](https://github.com/Kerollosmm/church-portal/actions/runs/46168247091) on `main` @ `c75f878`, `topic_override: test_kerollos1`, arrived once, Arabic title/body rendered cleanly, and the tap opened `/notifications`.
- **Web / PWA test was not run.**
- A 24–48 h post-launch watch (Sentry, Spark Firestore/Hosting, `/admin → متقدم` heartbeats, `capReached == false`) is still pending.
- Android test enrollment and public release **1.0.6** (`pubspec.yaml` `1.0.6+7`, arm64 versionCode `2007` / arm32 `1007`, tag `apk-v1.0.6`).
- Ops, enrollment, the Actions secret, and the kill switch: [`documentation/operations.md`](../../documentation/operations.md). Decision: [`ADR-093`](10-decisions-and-history.md). Tracker: [`docs/plans/phase6/STATUS.md`](../plans/phase6/STATUS.md).

