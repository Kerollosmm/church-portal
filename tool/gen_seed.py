#!/usr/bin/env python3
"""Generates assets/seed/seed.json (bundled fallback + Firestore seed).
Values marked "sample": true are placeholders awaiting the church's
confirmation (mass/meeting times, clinics, some facilities and priests).
Every other value is sourced: see docs/CONTENT_SOURCES.md.
Also writes tool/retired_seed_ids.json (documents to delete on --force)."""
import json, os
from datetime import datetime
from zoneinfo import ZoneInfo

from urllib.parse import quote

# Verified content (sources: docs/CONTENT_SOURCES.md).
# Everything still marked "sample": True is a placeholder awaiting the
# church's confirmation (mass/meeting times, clinics, some facilities).
LAT, LNG = 31.260138, 30.01129
COORDS = f"{LAT},{LNG}"
WHATSAPP_CHANNEL = "https://whatsapp.com/channel/0029Vb6Kmbs2UPBMUcrlVB0g"
FACEBOOK = "https://www.facebook.com/100070313048338"
YOUTUBE = "https://www.youtube.com/channel/UCJiZ4u0IiUbSvBnTrJnRZBA"
YOUTUBE_PLAYLISTS = "https://www.youtube.com/@-maximuschurch/playlists"
INSTAGRAM = "https://www.instagram.com/maximos_coptic_church"
CHURCH_PHONE = "035368888"  # +20 3 536 8888

settings = {
  "church": {
    "nameAr": "كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود",
    "nameEn": "Church of Saints Maximus & Domadius and the Strong Anba Moussa the Black",
    "addressAr": "آخر شارع 45، العصافرة قبلي، قطاع المنتزه، الإسكندرية",
    "addressEn": "End of Street 45, El-Asafra Qebly, Montaza district, Alexandria, Egypt",
    "transportAr": "الكنيسة في آخر شارع 45 بالعصافرة قبلي، وشارع 45 هو الشارع الرئيسي العريض الذي يربط الطريق الصحراوي بكورنيش شرق الإسكندرية. استخدم زر «الاتجاهات» للوصول بالـGPS.",
    "transportEn": "The church stands at the end of Street 45 in El-Asafra Qebly; Street 45 is the wide main road linking the Cairo–Alexandria desert road to the East Alexandria Corniche. Use the Directions button for GPS navigation.",
    "lat": LAT, "lng": LNG, "coordinatesApproximate": False,
    "mapsQuery": COORDS,
    "mapsUrl": "https://www.google.com/maps/search/?api=1&query=" + quote(COORDS),
    "phones": [
      {"labelAr": "تليفون الكنيسة", "labelEn": "Church landline", "number": CHURCH_PHONE, "isMobile": False},
    ],
    "whatsapp": "",
    "whatsappChannel": WHATSAPP_CHANNEL,
    "facebook": FACEBOOK,
    "youtube": YOUTUBE,
    "instagram": INSTAGRAM,
    "verseAr": "كُنْ أَمِينًا إِلَى الْمَوْتِ فَسَأُعْطِيكَ إِكْلِيلَ الْحَيَاةِ",
    "verseEn": "Be faithful until death, and I will give you the crown of life.",
    "verseRef": "Rev 2:10",
    "verseRefAr": "رؤيا ٢: ١٠",
    "heroImageUrl": "",
    "historyAr": "كنيسة قبطية أرثوذكسية في آخر شارع 45 بالعصافرة قبلي، تتبع قطاع كنائس المنتزه بإيبارشية الإسكندرية تحت رعاية نيافة الأنبا بافلي أسقف قطاع المنتزه، وتحمل اسم القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود. تخدم الكنيسة الشعب منذ عام 1980 على الأقل، حين رُسم القمص تادرس لبيب كاهنًا لها، وهي اليوم من أكبر كنائس الإسكندرية إذ تخدم أكثر من 12 ألف أسرة. في 30 يونيو 2022 رسم نيافة الأنبا بافلي 200 شماس بالكنيسة، وفي 10 نوفمبر 2022 رقّى قداسة البابا تواضروس الثاني ثلاثة من آبائها إلى رتبة القمصية. وفي 25 يونيو 2025 نالت الكنيسة بركة أول زيارة رعوية لقداسة البابا، فألقى عظته الأسبوعية من السرادق المقام بالأرض المجاورة للكنيسة وصلى العشية مع الآباء والشعب. تقيم الكنيسة كل عام نهضة القديسين مكسيموس ودوماديوس في يناير ونهضة الأنبا موسى الأسود في نهاية يونيو، ومن أبرز خدماتها مشروع تطوير خدمة الأنبا أبرآم لرعاية الأسر المحتاجة.",
    "historyEn": "A Coptic Orthodox church at the end of Street 45 in El-Asafra Qebly, part of the Montaza sector of the Alexandria diocese under H.G. Anba Pavly, Bishop of the Montaza sector, dedicated to Saints Maximus and Domadius and the Strong Saint Moses the Black. The parish has served since at least 1980, when Fr Tadros Labib was ordained for it, and today it is one of Alexandria's largest churches, serving more than 12,000 families. On 30 June 2022 Anba Pavly ordained 200 deacons here, and on 10 November 2022 H.H. Pope Tawadros II raised three of its priests to the rank of hegumen. On 25 June 2025 the church received the Pope's first pastoral visit: he gave his weekly Wednesday sermon from the tent on the land next to the church and prayed Vespers with the clergy and congregation. Each year the church holds a revival for Saints Maximus and Domadius in January and one for Saint Moses the Black at the end of June; among its leading services is the Anba Abraam project caring for families in need.",
    "altars": [],
    "assistantEnabled": True,
    "sample": False
  }
}

CAIRO = ZoneInfo("Africa/Cairo")

def T(d, hm="00:00", off=None):
    """ISO instant for a Cairo wall-clock time. The UTC offset is taken from
    the tz database (Egypt DST: last Friday of April .. last Thursday of
    October), so pre-/post-DST dates never land on the previous Cairo day.
    `off` is accepted for backwards compatibility and ignored."""
    dt = datetime.fromisoformat(f"{d}T{hm}:00").replace(tzinfo=CAIRO)
    return dt.isoformat()

alerts = {
  "follow-announcements": {"titleAr": "تابع إعلانات الكنيسة أولًا بأول", "titleEn": "Follow the church's announcements",
    "bodyAr": "المواعيد والإعلانات الرسمية تُنشر على قناة الكنيسة على واتساب وصفحتها الرسمية على فيسبوك. انضم إلى القناة لتصلك أولًا بأول.",
    "bodyEn": "Official times and announcements are posted on the church's WhatsApp channel and official Facebook page. Join the channel to get them first.",
    "active": True, "startsAt": T("2026-10-31"), "endsAt": T("2027-12-31", "23:59"), "priority": 1, "link": WHATSAPP_CHANNEL},
  "nativity-fast-2026": {"titleAr": "صوم الميلاد المجيد", "titleEn": "Nativity Fast",
    "bodyAr": "يبدأ صوم الميلاد يوم 25 نوفمبر، وعيد الميلاد المجيد يوم 7 يناير. مواعيد تسبحة كيهك والقداسات تُعلن على قناة الكنيسة.",
    "bodyEn": "The Nativity Fast begins on 25 November and the Feast of the Nativity is on 7 January. Kiahk praise and liturgy times are announced on the church's channel.",
    "active": True, "startsAt": T("2026-11-18"), "endsAt": T("2027-01-07", "23:59"), "priority": 3, "link": WHATSAPP_CHANNEL},
  "revival-maximus-2027": {"titleAr": "نهضة القديسين مكسيموس ودوماديوس", "titleEn": "Revival of Saints Maximus & Domadius",
    "bodyAr": "تقيم الكنيسة كل عام نهضة روحية لمدة خمسة أيام في يناير تُختتم بقداس عيد القديس دوماديوس يوم 25 يناير (17 طوبة). البرنامج والمواعيد تُعلن على قناة الكنيسة.",
    "bodyEn": "Each January the church holds a five-day revival ending with the feast liturgy of St Domadius on 25 January (17 Tuba). The programme and times are announced on the church's channel.",
    "active": True, "startsAt": T("2027-01-10"), "endsAt": T("2027-01-25", "23:59"), "priority": 5, "link": WHATSAPP_CHANNEL},
  "revival-moses-2027": {"titleAr": "نهضة القوي الأنبا موسى الأسود", "titleEn": "Revival of the Strong Saint Moses the Black",
    "bodyAr": "نهضة العشرة أيام السنوية من نحو 22 يونيو حتى عيد استشهاد الأنبا موسى الأسود يوم 1 يوليو (24 بؤونة). البرنامج والمواعيد تُعلن على قناة الكنيسة.",
    "bodyEn": "The annual ten-day revival from about 22 June to the martyrdom feast of St Moses the Black on 1 July (24 Paona). The programme and times are announced on the church's channel.",
    "active": True, "startsAt": T("2027-06-12", "00:00"), "endsAt": T("2027-07-01", "23:59"), "priority": 5, "link": WHATSAPP_CHANNEL},
}

seasons = {
  "nativity-2027": {"key": "nativity", "nameAr": "عيد الميلاد المجيد", "nameEn": "Feast of the Nativity", "startsAt": T("2027-01-06"), "endsAt": T("2027-01-07", "23:59"), "active": True},
  "revival-maximus-2027": {"key": "revival_maximus", "nameAr": "نهضة القديسين مكسيموس ودوماديوس", "nameEn": "Revival of Sts Maximus & Domadius", "startsAt": T("2027-01-21"), "endsAt": T("2027-01-25", "23:59"), "active": True},
  "holy-week-2027": {"key": "holy_week", "nameAr": "أسبوع الآلام (البصخة المقدسة)", "nameEn": "Holy Week (Pascha)", "startsAt": T("2027-04-25", "00:00", "+03:00"), "endsAt": T("2027-05-01", "18:00", "+03:00"), "active": True},
  "pascha-2027": {"key": "pascha", "nameAr": "عيد القيامة المجيد", "nameEn": "Feast of the Resurrection", "startsAt": T("2027-05-01", "18:00", "+03:00"), "endsAt": T("2027-05-02", "23:59", "+03:00"), "active": True},
  "revival-moses-2027": {"key": "revival_moses", "nameAr": "نهضة القوي الأنبا موسى الأسود", "nameEn": "Revival of St Moses the Black", "startsAt": T("2027-06-22"), "endsAt": T("2027-07-01", "23:59"), "active": True},
}

# Places are not published either: every liturgy below is a placeholder.
MAIN = ("الكنيسة", "Church")
ANNEX = MAIN
GROUND = MAIN
MOSES = MAIN
liturgies = {}
def L(id, type, nameAr, nameEn, start, end, place, weekday=None, date=None, audAr="", audEn="", season=None, order=0):
    d = {"type": type, "nameAr": nameAr, "nameEn": nameEn, "weekday": weekday, "date": date, "start": start, "end": end,
         "placeAr": place[0], "placeEn": place[1], "audienceAr": audAr, "audienceEn": audEn, "seasonKey": season, "order": order}
    liturgies[id] = d

# Regular weekly schedule: PLACEHOLDER times (typical Alexandrian parish), sample=True
# until the church publishes its timetable.
L("fri-1", "mass", "القداس الأول (باكر)", "1st (early) liturgy", "06:30", "08:30", MAIN, 5, order=1)
L("fri-2", "mass", "القداس الثاني", "2nd liturgy", "08:30", "10:30", MAIN, 5, order=2)
L("fri-kids", "mass", "قداس الأطفال", "Children's liturgy", "08:30", "10:00", ANNEX, 5, audAr="للأطفال من الحضانة حتى ابتدائي", audEn="For children from nursery to primary", order=3)
L("fri-3", "mass", "القداس الثالث", "3rd liturgy", "10:30", "12:30", GROUND, 5, order=4)
L("sun-1", "mass", "القداس الأول (باكر)", "1st (early) liturgy", "06:00", "08:00", MAIN, 7, order=1)
L("sun-2", "mass", "القداس الثاني", "2nd liturgy", "08:00", "10:00", MAIN, 7, order=2)
L("sun-youth", "mass", "قداس الشباب والجامعيين", "Youth & university liturgy", "08:00", "10:00", GROUND, 7, audAr="للشباب والجامعيين", audEn="For youth and university students", order=3)
L("wed-1", "mass", "قداس الأربعاء", "Wednesday liturgy", "07:00", "09:00", MAIN, 3, order=1)
L("wed-moses", "mass", "قداس مذبح الأنبا موسى", "St Moses altar liturgy", "09:00", "11:00", MOSES, 3, audAr="قداس مع تمجيد للقديس الأنبا موسى", audEn="Liturgy with doxology for St Moses", order=2)
L("sat-1", "mass", "قداس السبت", "Saturday liturgy", "07:00", "09:00", MAIN, 6, order=1)
L("mon-1", "mass", "قداس الاثنين", "Monday liturgy", "07:00", "08:30", GROUND, 1)
L("tue-1", "mass", "قداس الثلاثاء", "Tuesday liturgy", "07:00", "08:30", GROUND, 2)
L("thu-1", "mass", "قداس الخميس", "Thursday liturgy", "07:00", "08:30", GROUND, 4)
L("sat-vespers", "vespers", "عشية السبت", "Saturday vespers", "18:30", "19:30", MAIN, 6, order=1)
L("sat-praise", "praise", "تسبحة نصف الليل", "Midnight praise", "19:30", "21:30", MAIN, 6, order=2)
L("tue-vespers", "vespers", "عشية الأربعاء", "Tuesday-eve vespers", "18:30", "19:15", MAIN, 2)
L("thu-vespers", "vespers", "عشية الجمعة", "Thursday-eve vespers", "18:30", "19:15", MAIN, 4)
# Seasonal (replace the regular services on the days they cover)
L("nat-eve", "mass", "قداس عيد الميلاد المجيد", "Nativity Feast liturgy", "20:00", "00:30", MAIN, date=T("2027-01-06"), season="nativity", audAr="يرأسه الآباء الكهنة — يُرجى الحضور مبكرًا", audEn="Celebrated by all priests — please arrive early")
L("nat-day", "mass", "قداس صباح العيد", "Feast-day morning liturgy", "08:00", "10:00", MAIN, date=T("2027-01-07"), season="nativity")
L("rev-max-vespers", "other", "نهضة روحية: عشية وتمجيد", "Revival: vespers & doxology", "18:00", "20:30", MAIN, date=None, weekday=None, season="revival_maximus")
for i, wd in enumerate([1, 2, 3, 4, 5, 6, 7]):
    L(f"rev-max-{wd}", "other", "النهضة الروحية: عشية وعظة", "Revival: vespers & sermon", "18:00", "20:30", MAIN, wd, season="revival_maximus", order=i)
del liturgies["rev-max-vespers"]
L("rev-max-feast", "mass", "قداس عيد استشهاد القديس دوماديوس", "Feast liturgy of St Domadius", "06:30", "10:00", MAIN, date=T("2027-01-25"), season="revival_maximus")
for wd, (ar, en) in {1: ("البصخة: الاثنين", "Pascha: Monday"), 2: ("البصخة: الثلاثاء", "Pascha: Tuesday"), 3: ("البصخة: الأربعاء", "Pascha: Wednesday")}.items():
    L(f"hw-day-{wd}", "other", ar + " (ساعات النهار)", en + " (day hours)", "09:00", "13:00", MAIN, wd, season="holy_week")
    L(f"hw-eve-{wd}", "other", ar + " (ساعات الليل)", en + " (night hours)", "18:00", "21:00", MAIN, wd, season="holy_week")
L("hw-palm", "mass", "قداس أحد الشعانين والجناز العام", "Palm Sunday liturgy & general funeral", "06:00", "11:00", MAIN, date=T("2027-04-25", "00:00", "+03:00"), season="holy_week")
L("hw-thursday", "mass", "قداس خميس العهد واللقان", "Covenant Thursday liturgy & foot-washing", "07:00", "12:00", MAIN, date=T("2027-04-29", "00:00", "+03:00"), season="holy_week")
L("hw-friday", "other", "صلوات الجمعة العظيمة", "Good Friday prayers", "08:00", "18:00", MAIN, date=T("2027-04-30", "00:00", "+03:00"), season="holy_week")
L("hw-saturday", "mass", "ليلة أبو غلمسيس وقداس سبت الفرح", "Apocalypse night & Joyous Saturday liturgy", "00:00", "07:00", MAIN, date=T("2027-05-01", "00:00", "+03:00"), season="holy_week")
L("pascha-eve", "mass", "قداس عيد القيامة المجيد", "Easter vigil liturgy", "21:00", "01:00", MAIN, date=T("2027-05-01", "00:00", "+03:00"), season="pascha", audAr="يُرجى الحضور مبكرًا", audEn="Please arrive early")
L("pascha-day", "mass", "قداس صباح العيد", "Easter morning liturgy", "08:00", "10:00", MAIN, date=T("2027-05-02", "00:00", "+03:00"), season="pascha")
for i, wd in enumerate([1, 2, 3, 4, 5, 6, 7]):
    L(f"rev-moses-{wd}", "other", "نهضة الأنبا موسى: عشية وعظة", "St Moses revival: vespers & sermon", "18:30", "21:00", MOSES, wd, season="revival_moses", order=i)
L("rev-moses-feast", "mass", "قداس عيد استشهاد الأنبا موسى الأسود", "Martyrdom feast liturgy of St Moses", "06:30", "10:30", MAIN, date=T("2027-07-01", "00:00", "+03:00"), season="revival_moses")
for v in liturgies.values():
    v["sample"] = True

def M(id, stage, ar, en, wd, s, e, notes="", facebook=""):
    # Meeting days/times are NOT published by the church: placeholders, sample=True.
    return id, {"stage": stage, "nameAr": ar, "nameEn": en, "weekday": wd, "start": s, "end": e, "hallAr": "", "hallEn": "",
                "facebookUrl": facebook, "whatsappUrl": "", "notes": notes, "sample": True}
meetings = dict([
  M("angels", "angels", "مدارس الأحد — الملائكة (حضانة وروضة)", "Sunday school — Angels (nursery & KG)", 5, "10:30", "12:00"),
  M("primary", "primary", "مدارس الأحد — ابتدائي", "Sunday school — Primary", 5, "10:30", "12:00"),
  M("preparatory", "preparatory", "مدارس الأحد — إعدادي (خدمة إعدادي بنين)", "Sunday school — Preparatory (prep-school boys service)", 5, "17:00", "18:30"),
  M("secondary", "secondary", "مدارس الأحد — ثانوي", "Sunday school — Secondary", 4, "18:00", "19:30"),
  M("university", "university", "اجتماع الجامعيين", "University students meeting", 2, "19:30", "21:00"),
  M("graduates", "graduates", "اجتماع الخريجين", "Graduates meeting", 3, "20:00", "21:30"),
  M("youth", "youth", "اجتماع الشباب (Maximous Youth)", "Youth meeting (Maximous Youth)", 6, "19:30", "21:00", facebook="https://www.facebook.com/MaximousYouth"),
  M("family", "family", "اجتماع الأسرة", "Family meeting", 1, "19:00", "20:30"),
  M("men", "men", "اجتماع الرجال", "Men's meeting", 7, "19:00", "20:30"),
  M("women", "women", "اجتماع السيدات", "Women's meeting", 2, "10:00", "11:30"),
  M("elderly", "elderly", "اجتماع كبار السن", "Elderly meeting", 3, "10:00", "11:30"),
])

def A(id, category, titleAr, titleEn, descAr, descEn, link="", scheduleAr="", scheduleEn="", sample=False):
    return id, {"category": category, "titleAr": titleAr, "titleEn": titleEn, "descAr": descAr, "descEn": descEn,
                "scheduleAr": scheduleAr, "scheduleEn": scheduleEn, "ageRange": "", "contactPhone": "", "link": link, "sample": sample}
activities = dict([
  A("deacons-choir", "choir", "خورس شمامسة الكنيسة", "Church deacons' choir",
    "خورس الشمامسة يشارك في صلوات الكنيسة وأعيادها، وقد صلى العشية مع قداسة البابا تواضروس الثاني في زيارته للكنيسة يوم 25 يونيو 2025.",
    "The deacons' choir serves at the church's prayers and feasts; it sang Vespers with H.H. Pope Tawadros II during his visit on 25 June 2025."),
  A("avamose-choir", "choir", "كورال أفا موسى (Avamose choir)", "Avamose choir (Anba Moses choir)",
    "كورال الكنيسة باسم القوي الأنبا موسى الأسود. تابع صفحته لمعرفة الحفلات والتسجيلات.",
    "The church choir named after the Strong Saint Moses the Black. Follow its page for concerts and recordings.",
    link="https://www.facebook.com/100069922352210"),
  A("davids-tones", "choir", "كورال نغمات داود (David's Tones)", "David's Tones choir",
    "كورال ترانيم تتابعه الصفحة الرسمية للكنيسة.", "A hymn choir followed by the church's official page.",
    link="https://www.facebook.com/n8amatdawoudchoire"),
  A("hymns-school", "hymns", "مدرسة صانع الأجيال المرتل إسحاق إبراهيم لتعليم الألحان", "Esshaq Ibrahim hymns school",
    "مدرسة لتعليم الألحان الكنسية القبطية تتابعها الصفحة الرسمية للكنيسة.", "A Coptic church-hymns school followed by the church's official page.",
    link="https://www.facebook.com/Esshaqibrahi"),
  A("maximous-youth", "youth", "شباب كنيسة مكسيموس (Maximous Youth)", "Maximous Youth",
    "خدمة الشباب بالكنيسة. تابع صفحتهم لمعرفة الاجتماعات والأنشطة.", "The church's youth ministry. Follow its page for meetings and activities.",
    link="https://www.facebook.com/MaximousYouth"),
  A("prep-boys", "youth", "خدمة إعدادي بنين", "Prep-school boys service",
    "خدمة الأولاد في المرحلة الإعدادية بالكنيسة، ولها صفحة على فيسبوك.", "The church's ministry for preparatory-school boys, with its own Facebook page."),
  A("antibiotic-mime", "drama", "فريق Antibiotic للمايم", "Antibiotic Mime Team",
    "فريق مايم ومسرح صامت تابع للكنيسة.", "A mime and silent-drama team linked to the church.",
    link="https://www.facebook.com/AntibioticMimeTeam"),
  A("karouz-school", "servants", "مدرسة الكاروز لإعداد الخدام", "El-Karouz servant-preparation school",
    "محاضرات إعداد الخدام يوم الجمعة: الآبائيات، اللغة القبطية، الألحان الكنسية، العهد الجديد، العهد القديم، اللاهوت العقيدي، وتاريخ الكنيسة. المحاضرات المسجلة على قناة الكنيسة على يوتيوب.",
    "Friday servant-preparation lectures: Patristics, Coptic language, church hymns, New Testament, Old Testament, dogmatic theology and church history. Recorded lectures are on the church's YouTube channel.",
    link=YOUTUBE_PLAYLISTS, scheduleAr="محاضرات يوم الجمعة", scheduleEn="Friday lectures"),
  A("servant-care", "servants", "كورس صيانة الخادم", "Servant care course",
    "12 لقاءً بواقع لقاء أو اثنين أسبوعيًا في 3 موديولات: صيانة الخادم من الداخل، صيانة العلاقات والفريق، وصيانة عقل الخادم. اشتراك الموديول 50 جنيهًا، والتسجيل عبر النموذج المنشور على صفحة الكنيسة. حلقات الكورس متاحة أيضًا على يوتيوب.",
    "12 sessions, one or two a week, in 3 modules: caring for the servant's inner life, relationships and teamwork, and the servant's mind. EGP 50 per module; register through the form posted on the church's Facebook page. Episodes are also on YouTube.",
    link=FACEBOOK),
  A("media-center", "media", "خدمة المركز الإعلامي والميديا", "Media centre service",
    "خدمة الإعلام والتصوير والبث بالكنيسة. يُعلن عن فتح باب التسجيل فيها على صفحة الكنيسة.",
    "The church's media, photography and broadcast service. Registration openings are announced on the church's page.",
    link=FACEBOOK),
  A("kalimtein", "media", "برنامج «كلمتين في رغيف»", "\"Kalimtein fi Ragheef\" programme",
    "برنامج روحي قصير على قناة الكنيسة على يوتيوب، ضمن برامج وعظات القناة (نهضات، أسبوع الآلام، تسبحة كيهك).",
    "A short spiritual programme on the church's YouTube channel, alongside its revivals, Holy Week sermons and Kiahk praise.",
    link=YOUTUBE_PLAYLISTS),
])

def C(id, sp, ar, en, days, s, e):
    # No clinic, doctor or timetable is published: generic placeholders only.
    return id, {"specialty": sp, "specialtyAr": ar, "specialtyEn": en, "doctorName": f"طبيب {ar} — يُعلن لاحقًا", "degreeAr": "",
                "degreeEn": "", "days": days, "start": s, "end": e,
                "bookingPhone": "", "whatsapp": "", "active": True, "sample": True}
clinics = dict([
  C("internal-1", "internal", "الباطنة", "Internal medicine", [1, 4], "17:00", "20:00"),
  C("pediatrics-1", "pediatrics", "الأطفال", "Pediatrics", [5, 7], "11:00", "14:00"),
  C("pediatrics-2", "pediatrics", "الأطفال", "Pediatrics", [2], "18:00", "21:00"),
  C("dental-1", "dental", "الأسنان", "Dental", [1, 3, 6], "16:00", "20:00"),
  C("ortho-1", "orthopedics", "العظام", "Orthopedics", [3], "18:00", "21:00"),
  C("eye-1", "ophthalmology", "الرمد", "Ophthalmology", [6], "12:00", "15:00"),
  C("gyn-1", "gynecology", "النساء والتوليد", "Gynecology", [2, 4], "17:00", "20:00"),
  C("physio-1", "physiotherapy", "العلاج الطبيعي", "Physiotherapy", [1, 3, 5], "10:00", "14:00"),
  C("ent-1", "ent", "الأنف والأذن والحنجرة", "ENT", [7], "17:00", "20:00"),
  C("derma-1", "dermatology", "الجلدية", "Dermatology", [4], "18:00", "21:00"),
  C("cardio-1", "cardiology", "القلب", "Cardiology", [6], "17:00", "20:00"),
])

facilities = {
  "anba-abraam": {"type": "service", "nameAr": "خدمة الأنبا أبرآم — مشروع تطوير الخدمة", "nameEn": "Anba Abraam service — development project",
     "descAr": "رعاية إخوة الرب والأسر المحتاجة. قدّمها القس يوناثان محفوظ لقداسة البابا تواضروس الثاني في زيارته يوم 25 يونيو 2025 كأبرز خدمات الكنيسة. للاستفسار اتصل بالكنيسة.",
     "descEn": "Care for the poor and families in need. Fr Yonathan Mahfouz presented it to H.H. Pope Tawadros II during his 25 June 2025 visit as the church's leading service. Call the church for enquiries.",
     "phone": CHURCH_PHONE, "hoursAr": "", "hoursEn": "", "sample": False},
  "nursery": {"type": "nursery", "nameAr": "الحضانة", "nameEn": "Nursery", "descAr": "حضانة للأطفال — التفاصيل في انتظار تأكيد الكنيسة.", "descEn": "Children's nursery — details pending church confirmation.", "phone": "", "hoursAr": "", "hoursEn": "", "sample": True},
  "employment": {"type": "employment", "nameAr": "مكتب التوظيف", "nameEn": "Employment office", "descAr": "ربط الباحثين عن عمل بفرص متاحة — التفاصيل في انتظار تأكيد الكنيسة.", "descEn": "Connects job seekers with opportunities — details pending church confirmation.", "phone": "", "hoursAr": "", "hoursEn": "", "sample": True},
  "halls": {"type": "halls", "nameAr": "قاعات العزاء والمناسبات", "nameEn": "Condolence & occasion halls", "descAr": "قاعات للعزاء والمناسبات الكنسية — الحجز والتفاصيل من الكنيسة.", "descEn": "Halls for condolences and church occasions — booking and details from the church.", "phone": "", "hoursAr": "", "hoursEn": "", "sample": True},
  "library": {"type": "other", "nameAr": "المكتبة الكنسية", "nameEn": "Church library", "descAr": "كتب روحية ووسائل تعليمية — التفاصيل في انتظار تأكيد الكنيسة.", "descEn": "Spiritual books and teaching aids — details pending church confirmation.", "phone": "", "hoursAr": "", "hoursEn": "", "sample": True},
}

PENDING_AR = "آخر تأكيد علني لخدمته بالكنيسة كان في 2022 — في انتظار تأكيد الكنيسة."
PENDING_EN = "Last publicly confirmed serving here in 2022 — pending church confirmation."
def P(id, name, nameEn, rank, order, ordination="", hegumen="", bioAr="", bioEn="", sample=False, status="serving", departed=""):
    return id, {"name": name, "nameEn": nameEn, "photoUrl": "", "rank": rank, "ordinationDate": ordination, "hegumenDate": hegumen,
                "departedDate": departed, "status": status, "bioAr": bioAr, "bioEn": bioEn, "order": order, "sample": sample}
priests = dict([
  P("bemwa", "القمص بموا غالي موسى", "Hegumen Bemwa Ghaly Moussa", "hegumen", 1, "1998-03-21", "2022-11-10",
    "رُسم كاهنًا بيد البابا شنودة الثالث، ونال رتبة القمصية بيد البابا تواضروس الثاني في 10 نوفمبر 2022. قدّم نبذة عن تاريخ الكنيسة في زيارة قداسة البابا (يونيو 2025).",
    "Ordained by Pope Shenouda III; raised to hegumen by Pope Tawadros II on 10 Nov 2022. Presented the church's history during the Pope's visit (June 2025)."),
  P("bigol", "القمص بيجول صالح نخلة", "Hegumen Bigol Saleh Nakhla", "hegumen", 2, "2000-03-23", "2022-11-10",
    "نال رتبة القمصية في 10 نوفمبر 2022. " + PENDING_AR, "Raised to hegumen on 10 Nov 2022. " + PENDING_EN, sample=True),
  P("bedaba", "القمص بضابا بخيت شنودة", "Hegumen Bedaba Bekhit Shenouda", "hegumen", 3, "2000-03-23", "2022-11-10",
    "رُسم كاهنًا بيد البابا شنودة الثالث، ونال رتبة القمصية في 10 نوفمبر 2022.",
    "Ordained by Pope Shenouda III; raised to hegumen on 10 Nov 2022."),
  P("doumadious", "القس دوماديوس حليم عطية", "Fr Doumadious Halim Atteya", "priest", 4, "2009-03-08"),
  P("moussa", "القس موسى جمال", "Fr Moussa Gamal", "priest", 5, "2017-02-16",
    bioAr="رُسم بيد البابا تواضروس الثاني بدير الأنبا بيشوي.", bioEn="Ordained by Pope Tawadros II at St Bishoy Monastery."),
  P("yonathan", "القس يوناثان محفوظ", "Fr Yonathan Mahfouz", "priest", 6,
    bioAr="يخدم مشروع تطوير خدمة الأنبا أبرآم لرعاية الأسر المحتاجة.", bioEn="Serves the Anba Abraam development project for families in need."),
  P("loukas", "القس لوكاس رفاعي", "Fr Loukas Refaey", "priest", 7),
  P("saleeb", "القس صليب سمير", "Fr Saleeb Samir", "priest", 8, bioAr=PENDING_AR, bioEn=PENDING_EN, sample=True),
  P("barnaba", "القس برنابا أمير", "Fr Barnaba Amir", "priest", 9,
    bioAr="ورد اسمه في عظات قناة الكنيسة (2025) — في انتظار تأكيد الكنيسة.",
    bioEn="Named in the church channel's sermons (2025) — pending church confirmation.", sample=True),
  P("yassa", "القس يسى إبراهيم", "Fr Yassa Ibrahim", "priest", 10,
    bioAr="ورد اسمه في تهنئة بدعوة كهنوتية على صفحة الكنيسة (أكتوبر 2026) — في انتظار تأكيد الكنيسة.",
    bioEn="Named in a priestly-calling congratulation on the church's page (Oct 2026) — pending church confirmation.", sample=True),
  P("philemon", "القس فيليمون فوزي", "Fr Philemon Fawzy", "priest", 11,
    bioAr="ورد اسمه في تهنئة بدعوة كهنوتية على صفحة الكنيسة (أكتوبر 2026) — في انتظار تأكيد الكنيسة.",
    bioEn="Named in a priestly-calling congratulation on the church's page (Oct 2026) — pending church confirmation.", sample=True),
  P("tadros", "المتنيح القمص تادرس لبيب يوسف", "The late Hegumen Tadros Labib Youssef", "hegumen", 20, "1980-08-01", "2012-09-27",
    "أقدم آباء الكنيسة المعروفين؛ خدم أكثر من 41 عامًا في الكهنوت وتنيح في 10 فبراير 2022. بركة صلواته تكون معنا.",
    "The church's earliest known priest; served over 41 years in the priesthood and departed on 10 Feb 2022. May his prayers be with us.",
    status="departed", departed="2022-02-10"),
  P("maximus", "المتنيح القس مكسيموس فؤاد أندراوس", "The late Fr Maximous Fouad Andarawes", "priest", 21, "2009-03-08", "",
    "خدم بالكنيسة ثم انتقل إلى كنيسة السيدة العذراء بالمعمورة، وتنيح في 4 فبراير 2021. نياحًا لنفسه.",
    "Served here before moving to St Mary Church, El-Maamoura; departed on 4 Feb 2021. May his soul rest in peace.",
    sample=True, status="departed", departed="2021-02-04"),
])

milestones = {
  "since-1980": {"titleAr": "الخدمة منذ 1980 على الأقل", "titleEn": "Serving since at least 1980", "descAr": "رُسم القمص تادرس لبيب كاهنًا للكنيسة في 1 أغسطس 1980، وهو أقدم تاريخ معروف لخدمتها.", "descEn": "Fr Tadros Labib was ordained for the church on 1 Aug 1980, its earliest known date of service.", "year": 1980, "icon": "church", "order": 1},
  "deacons-2022": {"titleAr": "رسامة 200 شماس", "titleEn": "200 deacons ordained", "descAr": "في 30 يونيو 2022 رسم نيافة الأنبا بافلي 150 إبصالتس و50 أغنسطس بالكنيسة.", "descEn": "On 30 Jun 2022 Anba Pavly ordained 150 psaltoi and 50 anagnostai at the church.", "year": 2022, "icon": "people", "order": 2},
  "hegumens-2022": {"titleAr": "ثلاثة قمامصة جدد", "titleEn": "Three new hegumens", "descAr": "في 10 نوفمبر 2022 رقّى قداسة البابا تواضروس الثاني الآباء بموا غالي وبيجول صالح وبضابا بخيت إلى رتبة القمصية.", "descEn": "On 10 Nov 2022 Pope Tawadros II raised Frs Bemwa Ghaly, Bigol Saleh and Bedaba Bekhit to hegumen.", "year": 2022, "icon": "altar", "order": 3},
  "pope-visit": {"titleAr": "أول زيارة لقداسة البابا تواضروس الثاني", "titleEn": "First visit of H.H. Pope Tawadros II", "descAr": "في 25 يونيو 2025 ألقى قداسة البابا عظة الأربعاء من الكنيسة وصلى العشية، وسط آلاف من شعب العصافرة.", "descEn": "On 25 Jun 2025 the Pope gave his Wednesday sermon from the church and prayed Vespers with thousands from El-Asafra.", "year": 2025, "icon": "pope", "order": 4}
}

saints = {
  "maximus-domadius": {"nameAr": "القديسان مكسيموس ودوماديوس (الروميان)", "nameEn": "Saints Maximus & Domadius (the Roman saints)",
     "bioAr": "أخوان، ابنا الإمبراطور الروماني فالنتيانوس. اشتاقا للرهبنة فتتلمذا في سوريا على القديس الأنبا أغابيوس، ثم جاءا إلى برية شيهيت عند القديس مقاريوس الكبير، وعاشا في صمت وصلاة لا يخرجان إلا للتناول. تنيح مكسيموس في 14 طوبة ولحقه دوماديوس في 17 طوبة، وهما أول من تنيح من رهبان الإسقيط. بنى القديس مقاريوس كنيسة في موضع قلايتهما، ومكانها اليوم دير البراموس (دير الروم).",
     "bioEn": "Brothers, sons of the Roman emperor Valentinian. Longing for monastic life, they became disciples of Abba Agabius in Syria and then came to St Macarius the Great in Scetis, living in silence and prayer and leaving their cell only for Communion. Maximus departed on 14 Tuba and Domadius on 17 Tuba — the first monks to repose in Scetis. Macarius built a church on their cell; the site is today's Baramous (\"of the Romans\") Monastery.",
     "feastCopticAr": "14 طوبة (مكسيموس) و17 طوبة (دوماديوس)", "feastCopticEn": "14 Tuba (Maximus) and 17 Tuba (Domadius)", "feastGregorian": "22 & 25 January", "feastGregorianAr": "22 و25 يناير", "order": 1},
  "moses-black": {"nameAr": "القوي الأنبا موسى الأسود", "nameEn": "The Strong Saint Moses the Black",
     "bioAr": "كان عبدًا ثم رئيس عصابة قوي البنية، فتاب على يد القديس إيسيذوروس والقديس مقاريوس الكبير الذي عمّده. ترهب في الإسقيط وجاهد جهادًا عظيمًا وسيم قسًا، واستشهد على يد البربر مع سبعة إخوة في 24 بؤونة سنة 408م، وهو أول شهيد في الإسقيط. جسده في دير البراموس. من أقواله: «اذهب واجلس في قلايتك، وهي تعلّمك كل شيء».",
     "bioEn": "A slave who became a strong robber-chief, he repented through Abba Isidore and St Macarius the Great, who baptized him. He became a monk in Scetis, known for fierce ascetic struggle, and was ordained priest. He was martyred by Berber raiders with seven brothers on 24 Paona 408 AD — the first martyr of Scetis. His relics are at Baramous Monastery. He said: \"Go, sit in your cell, and your cell will teach you everything.\"",
     "feastCopticAr": "24 بؤونة (استشهاده)", "feastCopticEn": "24 Paona (martyrdom)", "feastGregorian": "1 July", "feastGregorianAr": "1 يوليو", "order": 2}
}

# Documents earlier seeds created that no longer exist (sample content that
# was replaced). `seed_firestore.js --force` deletes them.
retired = {
  "alerts": ["school-blessing-2026", "holy-week-2027", "summer-2027"],
  "seasons": ["summer-2027"],
  "liturgies": ["sum-sun-1", "sum-sun-2", "sum-sun-eve", "sum-fri-1", "sum-fri-2", "sum-fri-3"],
  "activities": ["scouts", "deacons", "hymns", "bible", "summer", "sports", "exhibitions"],
  "priests": ["p1", "p2", "p3"],
  "milestones": ["founding", "pastoral", "consecration"],
}

seed = {"settings": settings, "alerts": alerts, "seasons": seasons, "liturgies": liturgies, "meetings": meetings,
        "activities": activities, "clinics": clinics, "facilities": facilities, "priests": priests, "milestones": milestones, "saints": saints}
out = os.path.join(os.path.dirname(__file__), "..", "assets", "seed", "seed.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(seed, f, ensure_ascii=False, indent=1)
print("wrote", out, {k: len(v) for k, v in seed.items()})
for col, ids in retired.items():
    clash = set(ids) & set(seed[col])
    assert not clash, f"retired ids still in seed: {col} {clash}"
rout = os.path.join(os.path.dirname(__file__), "retired_seed_ids.json")
with open(rout, "w", encoding="utf-8") as f:
    json.dump(retired, f, ensure_ascii=False, indent=1)
    f.write("\n")
print("wrote", rout)
