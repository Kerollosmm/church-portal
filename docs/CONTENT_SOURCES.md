# Church portal content: field → source → status

Seed generator: `church_portal/tool/gen_seed.py` → `assets/seed/seed.json` (also loaded into Firestore by the Seed workflow).
Research compiled 31 Oct 2026: `web_findings.md` (news/web) and the official Facebook page notes (`facebook-church/findings.md`, `related_pages.md`).

Status key
- **verified**: from the church's own channels (Facebook page, YouTube channel) and/or two or more independent sources. Seeded with `sample: false`.
- **needs church confirmation**: not published, single-source, or last confirmed in 2022. Seeded with `sample: true`; the app shows a "بيانات تجريبية / Sample data" badge, and the schedule, meetings and clinics pages show «مواعيد تقريبية — في انتظار تأكيد الكنيسة / Times pending church confirmation».

Source abbreviations
- **FB**: official Facebook page https://www.facebook.com/100070313048338 (About + public posts, read 31 Oct 2026)
- **YT**: official YouTube channel https://www.youtube.com/channel/UCJiZ4u0IiUbSvBnTrJnRZBA (@-maximuschurch)
- **A**: St-Takla church page https://st-takla.org/Coptic-History/places/africa/egypt/alexandria/saint-maximos-and-st-domadios-church-asafra.html
- **B**: copticorthodox.church, 25 Jun 2025 https://copticorthodox.church/en/2025/06/25/thousands-from-the-al-asafra-district-welcome-h-h-pope-tawadros-ii/
- **C**: Al-Masry Al-Youm, 25 Jun 2025 https://www.almasryalyoum.com/news/details/3485191
- **D**: El-Watan, 25 Jun 2025 https://www.elwatannews.com/news/details/8094035
- **E**: findinegypt https://www.findinegypt.com/c/church-of-saints-maximus-domadius-17690
- **F**: shewaya directory https://eg.shewaya.com/listing/كنيسة-القديسين-مكسيموس-ودوماديوس
- **K**: copt4g/Watani, 25 Jan 2022 http://www.copt4g.com/copticnews/detail/news/55bc207ab7d2174a165d4362ab39ae7b
- **K2**: copt4g/Watani, 1 Jul 2022 http://www.copt4g.com/copticnews/detail/news/505d1490b690db11d25ab6eea07acaf6
- **L**: Al-Masry Al-Youm, 18 Jun 2018 https://www.almasryalyoum.com/news/details/1300870
- **T**: Cairo24, 10 Nov 2022 https://www.cairo24.com/1690192
- **J**: Dostor, 10 Feb 2022 https://www.dostor.org/3711065 ; copt4g reprint http://www.copt4g.com/copticnews/detail/news/18054ce7d6df96f34af6550f67251b24
- **P1–P7**: St-Takla priest pages (listed in web_findings.md)
- **W1/W2**: St-Takla saint bios https://st-takla.org/Saints/Coptic-Orthodox-Saints-Biography/Coptic-Saints-Story_922.html , https://st-takla.org/Saints/Coptic-Orthodox-Saints-Biography/Coptic-Saints-Story_1720.html

## settings/church

| Field | Value | Source | Status |
|---|---|---|---|
| nameAr / nameEn | كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود / Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black | FB (WhatsApp-channel post, 3 weeks before 31 Oct 2026); A; B; C | verified |
| addressAr / addressEn | آخر شارع 45، العصافرة قبلي، قطاع المنتزه، الإسكندرية | A; B; C; E; F; FB ("شارع ٤٥ - العصافرة") | verified |
| lat / lng / mapsQuery / mapsUrl | 31.260138, 30.01129 | E (+ second listing ~20 m away) | verified |
| phones | 03 5368888 (+20 3 536 8888) | FB About; E; F | verified |
| whatsapp (chat number) | empty: the church publishes no WhatsApp number | FB About | n/a |
| whatsappChannel | https://whatsapp.com/channel/0029Vb6Kmbs2UPBMUcrlVB0g | FB About + post | verified |
| facebook | https://www.facebook.com/100070313048338 (no vanity URL exists) | FB | verified |
| youtube | https://www.youtube.com/channel/UCJiZ4u0IiUbSvBnTrJnRZBA | FB About + post; YT | verified |
| instagram | https://www.instagram.com/maximos_coptic_church | FB post | verified |
| transportAr/En | "end of Street 45, the main road linking the desert road to the Corniche" + GPS button | K (single, 2022) + address | verified (general wording only) |
| historyAr/En | built only from the facts in this table (bishop, 1980, 12,000+ families, 2022 deacons/hegumens, 2025 papal visit, revivals, Anba Abraam) | see rows below | verified |
| altars | removed (no source lists the altars) | none | needs church confirmation |
| heroImageUrl | empty: no hotlinkable photo without a Facebook login | none | needs church photos |

## Facts used in history / milestones

| Fact | Source | Status |
|---|---|---|
| Supervising bishop: نيافة الأنبا بافلي أسقف قطاع المنتزه | FB post 27 Sep 2026; C; D | verified |
| Parish serving by 1980 (Fr Tadros Labib ordained for it 1 Aug 1980) | P1; J | verified (founding year itself unknown) |
| Serves 12,000+ families | B; C | verified |
| 30 Jun 2022: Anba Pavly ordained 150 psaltoi + 50 anagnostai (200 deacons) | K2 | single source, 2022: kept as a dated historical milestone |
| 10 Nov 2022: Bemwa, Bigol, Bedaba raised to hegumen by Pope Tawadros II | T (+ Al-Masry Al-Youm, Ahram-Canada excerpts) | verified |
| 25 Jun 2025: Pope Tawadros II's first visit, Wednesday sermon from the tent next to the church + Vespers | B; C; D | verified |
| Annual 5-day revival in January (21–25 Jan in 2022) | K | pattern, single source: alert says "the programme and times are announced on the church's channel" |
| Annual 10-day revival ~22 Jun–1 Jul for St Moses | L (2018); K2 (2022) | verified pattern; exact days need confirmation each year |

## alerts

| id | Content | Source | Status |
|---|---|---|---|
| follow-announcements | Join the WhatsApp channel / Facebook page for official announcements (links the channel) | FB | verified |
| nativity-fast-2026 | Nativity Fast from 25 Nov; Nativity 7 Jan (no times) | Coptic calendar | verified |
| revival-maximus-2027 | 5-day January revival ending with the 25 Jan feast (no times) | K; calendar | verified pattern |
| revival-moses-2027 | 10-day revival ~22 Jun → 1 Jul feast (no times) | L; K2 | verified pattern |
| removed: school-blessing-2026, holy-week-2027, summer-2027 | invented times | none | deleted (`tool/retired_seed_ids.json`) |

## seasons
Nativity 2027, Holy Week and Pascha 2027 (Palm Sunday 25 Apr, Easter 2 May 2027) are Coptic calendar dates. Revival seasons: 21–25 Jan 2027 and 22 Jun–1 Jul 2027 (patterns above). The invented "summer schedule" season was removed.

## liturgies (all 47), meetings (all 11)
**Not published** on FB, YT or the web. Kept as placeholder times with `sample: true` (badge + page notice). Hall and place names were removed because they were invented too. The youth meeting links the real Maximous Youth page (https://www.facebook.com/MaximousYouth).
Status: **needs church confirmation**.

## clinics (all 11)
No clinic, dispensary or doctor appears in any public source. Doctor names replaced with generic «طبيب <التخصص> — يُعلن لاحقًا», with no booking phones; `sample: true`.
Status: **needs church confirmation**, including whether the church runs clinics at all.

## facilities

| id | Source | Status |
|---|---|---|
| anba-abraam (Anba Abraam service development project, needy families; phone = church landline) | C; copts-united excerpt; presented by Fr Yonathan Mahfouz on 25 Jun 2025 | verified |
| nursery, employment, halls, library | none (fake phones and hours removed) | needs church confirmation |

## activities (all `sample: false`; no days or times are published unless stated)

| id | Link | Source | Status |
|---|---|---|---|
| deacons-choir (خورس الشمامسة) | none | C; K; K2 | verified |
| avamose-choir (كورال أفا موسى) | https://www.facebook.com/100069922352210 | FB "Following" | verified |
| davids-tones (كورال نغمات داود) | https://www.facebook.com/n8amatdawoudchoire | FB "Following" (may be a partner choir rather than the church's own) | verified as followed by the church |
| hymns-school (مدرسة المرتل إسحاق إبراهيم) | https://www.facebook.com/Esshaqibrahi | FB "Following" (may be a partner school) | verified as followed by the church |
| maximous-youth | https://www.facebook.com/MaximousYouth | FB "Following" | verified |
| prep-boys (خدمة إعدادي بنين) | none (URL truncated in capture) | FB "Following" | verified |
| antibiotic-mime | https://www.facebook.com/AntibioticMimeTeam | FB "Following" | verified |
| karouz-school (مدرسة الكاروز، Friday lectures + subjects) | https://www.youtube.com/@-maximuschurch/playlists | YT playlists/home | verified |
| servant-care (كورس صيانة الخادم: 12 sessions, 3 modules, EGP 50/module) | FB page (registration form posted there) | FB post 27 Sep 2026; YT podcast playlist | verified |
| media-center | FB page | FB post ~22 Sep 2026 | verified |
| kalimtein («كلمتين في رغيف») | YT playlists | YT | verified |
| removed: scouts, deacons, hymns, bible, summer, sports, exhibitions | none | invented | deleted |

## priests

| id | Name / rank | Dates | Source | Status |
|---|---|---|---|---|
| bemwa | القمص بموا غالي موسى | ord. 1998-03-21, hegumen 2022-11-10 | P2; A; T; C (Jun 2025) | verified, current |
| bigol | القمص بيجول صالح نخلة | ord. 2000-03-23, hegumen 2022-11-10 | P3; A; T; last named Jul 2022 | **needs church confirmation** |
| bedaba | القمص بضابا بخيت شنودة | ord. 2000-03-23, hegumen 2022-11-10 | P4; T; YT sermon 2025 titled "القمص بضابا بخيت" | verified, current |
| doumadious | القس دوماديوس حليم عطية | ord. 2009-03-08 | P5; K; K2; YT sermon 2025 | verified, current |
| moussa | القس موسى جمال | ord. 2017-02-16 | P7; C (Jun 2025); YT sermon 2025 | verified, current |
| yonathan | القس يوناثان محفوظ | — | K; K2; C (Jun 2025) | verified, current |
| loukas | القس لوكاس رفاعي | — | K2 (Jul 2022); YT sermon 2025 | verified, current |
| saleeb | القس صليب سمير | — | K; K2 (2022 only) | **needs church confirmation** |
| barnaba | القس برنابا أمير | — | YT sermon 2025 (single source) | **needs church confirmation** |
| yassa | القس يسى إبراهيم | — | FB post comments, 31 Oct 2026 (priestly-calling congratulation) | **needs church confirmation** |
| philemon | القس فيليمون فوزي | — | FB post comments, 31 Oct 2026 (wording suggests ordination may still be upcoming) | **needs church confirmation** |
| tadros (departed) | المتنيح القمص تادرس لبيب يوسف | ord. 1980-08-01, hegumen 2012-09-27, departed 2022-02-10 | P1; J | verified |
| maximus (departed) | المتنيح القس مكسيموس فؤاد أندراوس | ord. 2009-03-08, departed 2021-02-04 (had moved to St Mary, El-Maamoura) | P6 (single) | **needs church confirmation** |

Not seeded: "القمص اسحق" (FB post credit "برسوم القمص اسحق" is ambiguous) and "ابونا مكسيموس" (a congratulation comment with no surname). No priest photos are verified; `photoUrl` is empty for all.

## saints

| id | Feast | Source | Status |
|---|---|---|---|
| maximus-domadius | 14 Tuba = 22 Jan (Maximus), 17 Tuba = 25 Jan (Domadius) | A; W1; CopticChurch.net synaxarium | verified |
| moses-black | 24 Paona = 1 Jul | A; W2 | verified (bio details single source: St-Takla) |

## Open items for the church office
1. Weekly liturgy, vespers and praise timetable (+ revival and Holy Week times).
2. Sunday school and meeting days, times and halls.
3. Whether the church runs clinics or a dispensary; specialties, doctors, days and booking phone.
4. Nursery, employment office, halls and library: confirm or remove.
5. Current priest roster (confirm Bigol, Saleeb, Barnaba, Yassa, Philemon), with photos.
6. Founding / consecration year and altar names (Hegumen Bemwa Ghaly's history talk on 25 Jun 2025 is the lead).
7. Photos of the church building (the Facebook cover album a.217655827254851 has a bell-tower photo).
