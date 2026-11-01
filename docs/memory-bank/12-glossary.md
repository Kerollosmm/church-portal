# 12 — Glossary (Coptic / church Arabic ↔ English ↔ code)

## Liturgical services (`liturgies.type`, `seasons.key`)

| Arabic | English | Code |
|---|---|---|
| القداس الإلهي / القداس | (Divine) Liturgy, Mass | `type: 'mass'`; Next-liturgy card considers only these |
| القداس الأول (باكر) | 1st (early) liturgy | seed `fri-1`, `sun-1` |
| قداس الأطفال | Children's liturgy | seed `fri-kids` |
| رفع بخور عشية / العشية | Vespers (evening incense) | `type: 'vespers'` |
| تسبحة نصف الليل / التسبحة | Midnight praise (psalmody) | `type: 'praise'` |
| تسبحة كيهك | Kiahk praise (month before Nativity) | mentioned in alerts/activities text |
| تمجيد | Doxology (for a saint) | liturgy audience text |
| البصخة المقدسة / أسبوع الآلام | Holy Week (Pascha week) | `seasonKey: 'holy_week'`, seed `hw-*` |
| أحد الشعانين | Palm Sunday | `hw-palm` |
| خميس العهد / اللقان | Covenant (Maundy) Thursday / foot-washing | `hw-thursday` |
| الجمعة العظيمة | Good Friday | `hw-friday` |
| ليلة أبو غلمسيس / سبت الفرح | Apocalypse night / Joyous Saturday | `hw-saturday` |
| عيد القيامة المجيد | Feast of the Resurrection (Easter / Pascha) | `seasonKey: 'pascha'` |
| عيد الميلاد المجيد | Feast of the Nativity (7 Jan) | `seasonKey: 'nativity'` |
| صوم الميلاد | Nativity Fast (from 25 Nov) | alert `nativity-fast-2026` |
| نهضة (روحية) | Revival (days of prayer before a patron's feast) | `revival_maximus`, `revival_moses` |
| الصيف | Summer (schedule) | `seasonKey: 'summer'` (allowed, unused) |
| (عيد) استشهاد / نياحة | Martyrdom / repose feast | saint feasts |

Season labels for admins: `opt_holy_week` … `opt_summer` in `lib/core/l10n.dart`.

## Coptic months used

| Coptic | Arabic | Example |
|---|---|---|
| Tuba (Tobi) | طوبة | 14 Tuba = 22 Jan (St Maximus), 17 Tuba = 25 Jan (St Domadius) |
| Paona (Paoni) | بؤونة | 24 Paona = 1 Jul (St Moses the Black) |
| Kiahk (Koiak) | كيهك | month of the Kiahk praises before Nativity |

## Clergy & people

| Arabic | English | Code |
|---|---|---|
| القمص | Hegumen (senior priest rank) | `priests.rank: 'hegumen'`, `hegumenDate` |
| القس | Priest (Father, Fr) | `rank: 'priest'` |
| الرسامة | Ordination | `ordinationDate` |
| القمصية | Elevation to hegumen | `hegumenDate` |
| المتنيح / المتنيحون | Of blessed memory / the departed (clergy) | `status: 'departed'`, admin screen `departedPriests`, section `departedPriests` |
| النياحة | Repose (death of a saint/cleric) | `departedDate` |
| نيافة الأنبا … أسقف | His Grace Anba …, Bishop | `bishopAr/En` |
| قداسة البابا | His Holiness the Pope (Tawadros II) | history/milestones |
| شماس، إبصالتس، أغنسطس | Deacon; psaltos (chanter); anagnostes (reader) | milestone `deacons-2022` |
| خادم / خدام | Servant(s) (lay church ministers/teachers) | activities `servants` |
| إخوة الرب | "The Lord's brethren" (the poor served by the church) | Anba Abraam facility |
| شفعاء الكنيسة | Patron saints of the church | `saints`, section `saints` |
| المذبح / المذابح | Altar(s) | `settings/church.altars[].kind` (main / second / annex) |

## Church education & services

| Arabic | English | Code |
|---|---|---|
| التربية الكنسية | Church education | route `/church-education`, section `meetings` |
| مدارس الأحد | Sunday school | meetings group |
| ملائكة (حضانة وروضة) | Angels (nursery & kindergarten) | `stage: 'angels'` |
| ابتدائي / إعدادي / ثانوي | Primary / Preparatory / Secondary | `primary`, `preparatory`, `secondary` |
| الشباب / الجامعيون / الخريجون | Youth / University / Graduates | `youth`, `university`, `graduates` |
| اجتماع الأسرة / الرجال / السيدات / كبار السن | Family / Men's / Women's / Elderly meeting | `family`, `men`, `women`, `elderly` |
| خورس / كورال | Choir | activity `category: 'choir'` |
| ألحان | (Coptic) hymns | `hymns` |
| إعداد خدام | Servant preparation | `servants` |
| الكشافة | Scouts | `scouts` |
| مدرسة الشمامسة | Deacons school | `deacons` |
| عيادات خيرية | Charity clinics | `clinics` |
| الحضانة / مكتب التوظيف / قاعات العزاء والمناسبات / المكتبة | Nursery / Employment office / Condolence & occasion halls / Library | `facilities.type: nursery, employment, halls, other` |
| خدمة الأنبا أبرآم | Anba Abraam service (care for needy families) | facility `anba-abraam`, `type: 'service'` |

## Portal / UI terms

| Arabic | English | Code |
|---|---|---|
| القداس القادم | Next liturgy | `NextMassCard`, `computeNextMass` |
| يُقام الآن | Happening now | `NextMassResult.happeningNow` |
| المواسم المقدسة | Holy seasons (toggle) | `holySeasons` |
| التنويهات العاجلة | Urgent notices | `alerts` |
| شريط الإعلان | Announcement banner | `settings/features.banner*` |
| بيانات تجريبية | Sample data (badge) | `sample: true`, `SampleBadge` |
| مواعيد تقريبية — في انتظار تأكيد الكنيسة | Times pending church confirmation | `PendingConfirmationNote`, `timesPending` |
| غير مؤكد | Unconfirmed (admin checkbox) | `sample` |
| ظاهر في الموقع | Visible on the site | `visible` |
| هذا القسم غير متاح حاليًا | This section is not available right now | `SectionUnavailable` |
| اسأل الكنيسة | Ask the church (assistant) | `/ask`, section `assistant` |
| لوحة التحكم / المشرفون / مالك / محرر | Dashboard / Admins / Owner / Editor | `/admin`, `admins`, `AdminRoles` |
| العصافرة قبلي، شارع 45 | El-Asafra Qebly, Street 45 | address (PRD said «بحري»; research says قبلي) |
| قطاع المنتزه | Montaza sector/district | diocese sector + address |
