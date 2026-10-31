#!/usr/bin/env python3
"""Generates assets/seed/seed.json (bundled fallback + Firestore seed).
Values marked "sample": true are plausible placeholders that must be
replaced with the church's real data (phones, doctor names, links...)."""
import json, os
from datetime import datetime
from zoneinfo import ZoneInfo

MAPS_QUERY = "كنيسة القديسين مكسيموس ودوماديوس والأنبا موسى الأسود، شارع 45 العصافرة بحري الإسكندرية"
STREET_QUERY = "شارع 45 العصافرة بحري الإسكندرية"
from urllib.parse import quote

settings = {
  "church": {
    "nameAr": "كنيسة القديسين مكسيموس ودوماديوس والأنبا موسى الأسود",
    "nameEn": "Church of Saints Maximus & Domadius and Anba Moussa the Black",
    "addressAr": "شارع 45، العصافرة بحري، الإسكندرية، مصر",
    "addressEn": "Street 45, El-Asafra Bahary, Alexandria, Egypt",
    "transportAr": "من طريق الجيش (الكورنيش): انزل محطة العصافرة ثم ادخل شارع 45 باتجاه بحري. من شارع جمال عبد الناصر (أبو قير): انزل موقف العصافرة قبلي واستقل ميكروباص العصافرة بحري حتى شارع 45. أقرب محطة قطار: محطة العصافرة (قطار أبو قير).",
    "transportEn": "From the Corniche (El-Geish Rd): get off at El-Asafra and walk inland along Street 45. From Gamal Abdel Nasser (Abu Qir) Rd: get off at Asafra Qebly and take an Asafra Bahary microbus to Street 45. Nearest train: El-Asafra station (Abu Qir line).",
    "lat": 31.2793, "lng": 30.0076, "coordinatesApproximate": True,
    "mapsQuery": STREET_QUERY,
    "mapsUrl": "https://www.google.com/maps/search/?api=1&query=" + quote(STREET_QUERY),
    "phones": [
      {"labelAr": "تليفون الكنيسة", "labelEn": "Church landline", "number": "035501245", "isMobile": False},
      {"labelAr": "مكتب الخدمات", "labelEn": "Services office", "number": "035501246", "isMobile": False},
      {"labelAr": "موبايل الكنيسة (واتساب)", "labelEn": "Church mobile (WhatsApp)", "number": "01200045045", "isMobile": True}
    ],
    "whatsapp": "01200045045",
    "whatsappChannel": "https://whatsapp.com/channel/SAMPLE-asafra-church",
    "facebook": "https://www.facebook.com/SAMPLE.asafra.church",
    "youtube": "https://www.youtube.com/@SAMPLE-asafra-church",
    "verseAr": "كُنْ أَمِينًا إِلَى الْمَوْتِ فَسَأُعْطِيكَ إِكْلِيلَ الْحَيَاةِ",
    "verseEn": "Be faithful until death, and I will give you the crown of life.",
    "verseRef": "Rev 2:10",
    "verseRefAr": "رؤيا ٢: ١٠",
    "heroImageUrl": "",
    "historyAr": "بدأت الخدمة في منطقة العصافرة بحري بشارع 45 كمذبح صغير يخدم الأسر المقيمة والمصطافين، ومع نمو الشعب تحوّلت إلى كنيسة كاملة على اسم القديسين مكسيموس ودوماديوس (أولاد الملك) والقديس الأنبا موسى الأسود. نمت الكنيسة بخدماتها التعليمية والاجتماعية والطبية لتصبح مركزًا روحيًا لأهل المنطقة وزوارها في الصيف، ونالت بركة تدشين مذابحها وزيارة قداسة البابا تواضروس الثاني.",
    "historyEn": "Service in El-Asafra Bahary began on Street 45 as a small altar serving resident families and summer visitors. As the congregation grew it became a full church named after Saints Maximus and Domadius (the Roman princes) and Saint Moses the Black. Its education, social and medical services made it a spiritual centre for the neighbourhood and its summer guests, blessed by the consecration of its altars and a visit from H.H. Pope Tawadros II.",
    "altars": [
      {"nameAr": "المذبح الرئيسي: القديسان مكسيموس ودوماديوس", "nameEn": "Main altar: Saints Maximus & Domadius", "kind": "main"},
      {"nameAr": "المذبح الثاني: القديس الأنبا موسى الأسود", "nameEn": "Second altar: Saint Moses the Black", "kind": "second"},
      {"nameAr": "مذبح السيدة العذراء مريم (الملحق)", "nameEn": "Annex altar: Saint Mary", "kind": "annex"},
      {"nameAr": "مذبح مار مينا ومار جرجس (الملحق)", "nameEn": "Annex altar: St Mina & St George", "kind": "annex"}
    ],
    "assistantEnabled": True,
    "sample": True
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
  "school-blessing-2026": {"titleAr": "قداس بركة بداية العام الدراسي", "titleEn": "Back-to-school blessing liturgy",
    "bodyAr": "الجمعة 6 نوفمبر بعد القداس الثاني: صلاة وتوزيع بركة للطلبة من كل المراحل.", "bodyEn": "Friday 6 Nov after the 2nd liturgy: prayers and blessing for students of all stages.",
    "active": True, "startsAt": T("2026-10-25"), "endsAt": T("2026-11-07", "23:59"), "priority": 2, "link": "/mass-schedule", "sample": True},
  "nativity-fast-2026": {"titleAr": "مواعيد صوم الميلاد وتسبحة كيهك", "titleEn": "Nativity Fast & Kiahk praise times",
    "bodyAr": "تبدأ تسبحة كيهك مساء كل سبت من 12 ديسمبر. قداس عيد الميلاد مساء 6 يناير الساعة 8 م.", "bodyEn": "Kiahk midnight praise every Saturday from 12 Dec. Nativity liturgy on 6 Jan at 8 PM.",
    "active": True, "startsAt": T("2026-11-25"), "endsAt": T("2027-01-08", "23:59"), "priority": 5, "link": "/mass-schedule", "sample": True},
  "holy-week-2027": {"titleAr": "مواعيد صلوات أسبوع الآلام وعيد القيامة", "titleEn": "Holy Week & Easter service times",
    "bodyAr": "صلوات البصخة يوميًا 9 ص و6 م، الجمعة العظيمة من 8 ص، وقداس العيد مساء السبت 1 مايو 9 م.", "bodyEn": "Pascha prayers daily 9 AM & 6 PM, Good Friday from 8 AM, Easter liturgy Saturday 1 May at 9 PM.",
    "active": True, "startsAt": T("2027-04-20"), "endsAt": T("2027-05-03", "23:59", "+03:00"), "priority": 10, "link": "/mass-schedule", "sample": True},
  "summer-2027": {"titleAr": "مواعيد الصيف للمصطافين", "titleEn": "Summer times for vacationers",
    "bodyAr": "قداس إضافي مساء الأحد 7 م طوال الصيف بالكنيسة الأرضي.", "bodyEn": "Extra Sunday evening liturgy at 7 PM all summer in the ground-floor church.",
    "active": True, "startsAt": T("2027-06-15", "00:00", "+03:00"), "endsAt": T("2027-09-15", "23:59", "+03:00"), "priority": 3, "link": "/mass-schedule", "sample": True}
}

seasons = {
  "nativity-2027": {"key": "nativity", "nameAr": "عيد الميلاد المجيد", "nameEn": "Feast of the Nativity", "startsAt": T("2027-01-06"), "endsAt": T("2027-01-07", "23:59"), "active": True},
  "revival-maximus-2027": {"key": "revival_maximus", "nameAr": "نهضة القديسين مكسيموس ودوماديوس", "nameEn": "Revival of Sts Maximus & Domadius", "startsAt": T("2027-01-18"), "endsAt": T("2027-01-25", "23:59"), "active": True},
  "holy-week-2027": {"key": "holy_week", "nameAr": "أسبوع الآلام (البصخة المقدسة)", "nameEn": "Holy Week (Pascha)", "startsAt": T("2027-04-25", "00:00", "+03:00"), "endsAt": T("2027-05-01", "18:00", "+03:00"), "active": True},
  "pascha-2027": {"key": "pascha", "nameAr": "عيد القيامة المجيد", "nameEn": "Feast of the Resurrection", "startsAt": T("2027-05-01", "18:00", "+03:00"), "endsAt": T("2027-05-02", "23:59", "+03:00"), "active": True},
  "revival-moses-2027": {"key": "revival_moses", "nameAr": "نهضة القديس الأنبا موسى الأسود", "nameEn": "Revival of St Moses the Black", "startsAt": T("2027-06-25", "00:00", "+03:00"), "endsAt": T("2027-07-01", "23:59", "+03:00"), "active": True},
  "summer-2027": {"key": "summer", "nameAr": "مواعيد الصيف", "nameEn": "Summer schedule", "startsAt": T("2027-06-15", "00:00", "+03:00"), "endsAt": T("2027-09-15", "23:59", "+03:00"), "active": True}
}

MAIN = ("الكنيسة الرئيسية", "Main church")
ANNEX = ("قاعة الملحق", "Annex hall")
GROUND = ("الكنيسة الأرضي", "Ground-floor church")
MOSES = ("مذبح الأنبا موسى", "St Moses altar")
liturgies = {}
def L(id, type, nameAr, nameEn, start, end, place, weekday=None, date=None, audAr="", audEn="", season=None, order=0):
    d = {"type": type, "nameAr": nameAr, "nameEn": nameEn, "weekday": weekday, "date": date, "start": start, "end": end,
         "placeAr": place[0], "placeEn": place[1], "audienceAr": audAr, "audienceEn": audEn, "seasonKey": season, "order": order}
    liturgies[id] = d

# Regular weekly schedule (sample times based on typical Alexandrian parishes)
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
for i, wd in enumerate([1, 2, 3, 4, 5, 6]):
    L(f"rev-moses-{wd}", "other", "نهضة الأنبا موسى: عشية وعظة", "St Moses revival: vespers & sermon", "18:30", "21:00", MOSES, wd, season="revival_moses", order=i)
L("rev-moses-feast", "mass", "قداس عيد استشهاد الأنبا موسى الأسود", "Martyrdom feast liturgy of St Moses", "06:30", "10:30", MAIN, date=T("2027-07-01", "00:00", "+03:00"), season="revival_moses")
L("sum-sun-1", "mass", "القداس الأول (صيفي)", "1st liturgy (summer)", "06:00", "08:00", MAIN, 7, season="summer", order=1)
L("sum-sun-2", "mass", "القداس الثاني (صيفي)", "2nd liturgy (summer)", "08:00", "10:00", MAIN, 7, season="summer", order=2)
L("sum-sun-eve", "mass", "قداس مسائي للمصطافين", "Evening liturgy for vacationers", "19:00", "21:00", GROUND, 7, season="summer", audAr="للزوار والمصطافين", audEn="For visitors and vacationers", order=3)
L("sum-fri-1", "mass", "القداس الأول (صيفي)", "1st liturgy (summer)", "06:00", "08:00", MAIN, 5, season="summer", order=1)
L("sum-fri-2", "mass", "القداس الثاني (صيفي)", "2nd liturgy (summer)", "08:00", "10:00", MAIN, 5, season="summer", order=2)
L("sum-fri-3", "mass", "القداس الثالث (صيفي)", "3rd liturgy (summer)", "10:00", "12:00", GROUND, 5, season="summer", order=3)
for v in liturgies.values():
    v["sample"] = True

def M(id, stage, ar, en, wd, s, e, hall, notes=""):
    return id, {"stage": stage, "nameAr": ar, "nameEn": en, "weekday": wd, "start": s, "end": e, "hallAr": hall[0], "hallEn": hall[1],
                "facebookUrl": f"https://www.facebook.com/groups/SAMPLE-asafra-{stage}", "whatsappUrl": f"https://chat.whatsapp.com/SAMPLE-asafra-{stage}", "notes": notes, "sample": True}
HALLS = {"annex": ("قاعة الملحق", "Annex hall"), "1": ("قاعة البابا كيرلس - الدور الأول", "Pope Kyrillos hall — 1st floor"),
         "2": ("قاعة الأنبا موسى - الدور الثاني", "St Moses hall — 2nd floor"), "ground": ("الكنيسة الأرضي", "Ground-floor church"), "roof": ("قاعة السطح", "Roof hall")}
meetings = dict([
  M("angels", "angels", "مدارس الأحد — الملائكة (حضانة وروضة)", "Sunday school — Angels (nursery & KG)", 5, "10:30", "12:00", HALLS["annex"], "بعد قداس الأطفال"),
  M("primary", "primary", "مدارس الأحد — ابتدائي", "Sunday school — Primary", 5, "10:30", "12:00", HALLS["1"]),
  M("preparatory", "preparatory", "مدارس الأحد — إعدادي", "Sunday school — Preparatory", 5, "17:00", "18:30", HALLS["2"]),
  M("secondary", "secondary", "مدارس الأحد — ثانوي", "Sunday school — Secondary", 4, "18:00", "19:30", HALLS["2"]),
  M("university", "university", "اجتماع الجامعيين", "University students meeting", 2, "19:30", "21:00", HALLS["roof"]),
  M("graduates", "graduates", "اجتماع الخريجين", "Graduates meeting", 3, "20:00", "21:30", HALLS["roof"]),
  M("youth", "youth", "اجتماع الشباب العام", "General youth meeting", 6, "19:30", "21:00", HALLS["1"], "بعد العشية"),
  M("family", "family", "اجتماع الأسرة", "Family meeting", 1, "19:00", "20:30", HALLS["ground"]),
  M("men", "men", "اجتماع الرجال", "Men's meeting", 7, "19:00", "20:30", HALLS["1"]),
  M("women", "women", "اجتماع السيدات", "Women's meeting", 2, "10:00", "11:30", HALLS["ground"]),
  M("elderly", "elderly", "اجتماع كبار السن", "Elderly meeting", 3, "10:00", "11:30", HALLS["annex"]),
])

activities = {
  "scouts": {"category": "scouts", "titleAr": "الكشافة والمرشدات — فرقة القديس موسى", "titleEn": "Scouts & Guides — St Moses troop",
     "descAr": "أشبال وزهرات (8-12)، كشافة ومرشدات (12-16)، جوالة (16+). تدريبات على الخدمة والقيادة والرحلات والمعسكرات.", "descEn": "Cubs & Brownies (8-12), Scouts & Guides (12-16), Rovers (16+). Training in service, leadership, trips and camps.",
     "scheduleAr": "الجمعة 2-5 م — ملعب الكنيسة", "scheduleEn": "Fridays 2-5 PM — church grounds", "ageRange": "8+", "contactPhone": "01200045046", "sample": True},
  "deacons": {"category": "deacons", "titleAr": "مدرسة الشمامسة", "titleEn": "Deacons school",
     "descAr": "دراسة طقس القداس والتسبحة واللغة القبطية والألحان الأساسية تمهيدًا للرسامة.", "descEn": "Study of the liturgy rite, praise, Coptic language and basic hymns in preparation for ordination.",
     "scheduleAr": "السبت 4-6 م", "scheduleEn": "Saturdays 4-6 PM", "ageRange": "7+ (ذكور)", "contactPhone": "01200045047", "sample": True},
  "hymns": {"category": "hymns", "titleAr": "معهد الألحان والتسبحة", "titleEn": "Hymns & praise institute",
     "descAr": "منهج متدرج لألحان المناسبات والأصوام والتسبحة الكيهكية، مع شهادة في نهاية كل مستوى.", "descEn": "Graded curriculum of seasonal hymns, fasts and Kiahk praise, with a certificate at the end of each level.",
     "scheduleAr": "الثلاثاء 6-8 م", "scheduleEn": "Tuesdays 6-8 PM", "ageRange": "10+", "contactPhone": "01200045047", "sample": True},
  "bible": {"category": "bible", "titleAr": "فصول دراسة الكتاب المقدس", "titleEn": "Bible study classes",
     "descAr": "دراسة منهجية لأسفار الكتاب المقدس للشباب والكبار مع أب كاهن.", "descEn": "Systematic study of the books of the Bible for youth and adults with a priest.",
     "scheduleAr": "الأربعاء 7-8:30 م", "scheduleEn": "Wednesdays 7-8:30 PM", "ageRange": "16+", "contactPhone": "", "sample": True},
  "summer": {"category": "summer", "titleAr": "النادي الصيفي", "titleEn": "Summer club",
     "descAr": "أنشطة صيفية للأطفال: ألعاب، أشغال يدوية، رحلات، مسرح، ومسابقات كتابية.", "descEn": "Summer activities for children: games, crafts, trips, drama and Bible competitions.",
     "scheduleAr": "يوليو وأغسطس — الأحد إلى الخميس 9 ص - 1 م", "scheduleEn": "July & August — Sun-Thu 9 AM - 1 PM", "ageRange": "4-14", "contactPhone": "01200045046", "sample": True},
  "sports": {"category": "sports", "titleAr": "النشاط الرياضي", "titleEn": "Sports",
     "descAr": "كرة قدم، تنس طاولة، ودوري الكنيسة السنوي بين المراحل.", "descEn": "Football, table tennis and the church's annual inter-stage league.",
     "scheduleAr": "الخميس 5-8 م", "scheduleEn": "Thursdays 5-8 PM", "ageRange": "10+", "contactPhone": "", "sample": True},
  "exhibitions": {"category": "exhibitions", "titleAr": "المعارض السنوية", "titleEn": "Annual exhibitions",
     "descAr": "معرض الكتاب الكنسي، ومعرض المنتجات اليدوية لدعم خدمة إخوة الرب.", "descEn": "Church book fair and handicrafts exhibition supporting the service of the needy.",
     "scheduleAr": "نوفمبر ومايو من كل عام", "scheduleEn": "Every November and May", "ageRange": "", "contactPhone": "", "sample": True}
}

def C(id, sp, ar, en, doc, deg, days, s, e, phone):
    return id, {"specialty": sp, "specialtyAr": ar, "specialtyEn": en, "doctorName": doc, "degreeAr": deg, "days": days, "start": s, "end": e,
                "bookingPhone": phone, "whatsapp": phone, "active": True, "sample": True}
clinics = dict([
  C("internal-1", "internal", "باطنة", "Internal medicine", "د. مينا سمير (اسم تجريبي)", "استشاري الباطنة", [1, 4], "17:00", "20:00", "01200045101"),
  C("pediatrics-1", "pediatrics", "أطفال", "Pediatrics", "د. ماريان عادل (اسم تجريبي)", "أخصائي طب الأطفال", [5, 7], "11:00", "14:00", "01200045102"),
  C("pediatrics-2", "pediatrics", "أطفال", "Pediatrics", "د. بيشوي نبيل (اسم تجريبي)", "مدرس طب الأطفال", [2], "18:00", "21:00", "01200045102"),
  C("dental-1", "dental", "أسنان", "Dental", "د. كيرلس فايز (اسم تجريبي)", "أخصائي طب وجراحة الفم والأسنان", [1, 3, 6], "16:00", "20:00", "01200045103"),
  C("ortho-1", "orthopedics", "عظام", "Orthopedics", "د. جورج رأفت (اسم تجريبي)", "استشاري جراحة العظام", [3], "18:00", "21:00", "01200045104"),
  C("eye-1", "ophthalmology", "رمد", "Ophthalmology", "د. إيريني منير (اسم تجريبي)", "أخصائي طب وجراحة العيون", [6], "12:00", "15:00", "01200045105"),
  C("gyn-1", "gynecology", "نساء وتوليد", "Gynecology", "د. نيفين فوزي (اسم تجريبي)", "استشاري النساء والتوليد", [2, 4], "17:00", "20:00", "01200045106"),
  C("physio-1", "physiotherapy", "علاج طبيعي", "Physiotherapy", "د. أندرو ماهر (اسم تجريبي)", "أخصائي العلاج الطبيعي", [1, 3, 5], "10:00", "14:00", "01200045107"),
  C("ent-1", "ent", "أنف وأذن وحنجرة", "ENT", "د. مارك يوسف (اسم تجريبي)", "أخصائي الأنف والأذن والحنجرة", [7], "17:00", "20:00", "01200045108"),
  C("derma-1", "dermatology", "جلدية", "Dermatology", "د. سالي جرجس (اسم تجريبي)", "أخصائي الأمراض الجلدية", [4], "18:00", "21:00", "01200045109"),
  C("cardio-1", "cardiology", "قلب", "Cardiology", "د. رامي لبيب (اسم تجريبي)", "استشاري أمراض القلب", [6], "17:00", "20:00", "01200045110"),
])

facilities = {
  "nursery": {"type": "nursery", "nameAr": "حضانة القديس موسى", "nameEn": "St Moses nursery", "descAr": "حضانة للأطفال من سنتين إلى 5 سنوات مع منهج روحي وتعليمي.", "descEn": "Nursery for children aged 2-5 with a spiritual and educational curriculum.", "phone": "035501247", "hoursAr": "الأحد - الخميس 8 ص - 2 م", "hoursEn": "Sun-Thu 8 AM - 2 PM", "sample": True},
  "employment": {"type": "employment", "nameAr": "مكتب التوظيف", "nameEn": "Employment office", "descAr": "ربط الباحثين عن عمل بفرص متاحة ومساعدة في إعداد السيرة الذاتية.", "descEn": "Connects job seekers with available opportunities and helps with CVs.", "phone": "035501246", "hoursAr": "الاثنين والأربعاء 6 - 8 م", "hoursEn": "Mon & Wed 6-8 PM", "sample": True},
  "halls": {"type": "halls", "nameAr": "قاعات العزاء والمناسبات", "nameEn": "Condolence & occasion halls", "descAr": "قاعات مجهزة للعزاء وحفلات الخطوبة والمناسبات الكنسية. الحجز من مكتب الخدمات.", "descEn": "Equipped halls for condolences, engagements and church occasions. Book through the services office.", "phone": "035501246", "hoursAr": "يوميًا بالحجز المسبق", "hoursEn": "Daily by prior booking", "sample": True},
  "library": {"type": "other", "nameAr": "المكتبة الكنسية", "nameEn": "Church library", "descAr": "كتب روحية وتفاسير ووسائل تعليمية للخدام.", "descEn": "Spiritual books, commentaries and teaching aids for servants.", "phone": "", "hoursAr": "الجمعة بعد القداسات", "hoursEn": "Fridays after the liturgies", "sample": True}
}

priests = {
  "p1": {"name": "القمص (اسم تجريبي) — كاهن الكنيسة", "nameEn": "Hegumen (sample name)", "photoUrl": "", "rank": "hegumen", "ordinationDate": "1995-06-18", "hegumenDate": "2010-11-21", "status": "serving", "bioAr": "", "order": 1, "sample": True},
  "p2": {"name": "القس (اسم تجريبي)", "nameEn": "Fr (sample name)", "photoUrl": "", "rank": "priest", "ordinationDate": "2008-02-24", "hegumenDate": "", "status": "serving", "bioAr": "", "order": 2, "sample": True},
  "p3": {"name": "القس (اسم تجريبي)", "nameEn": "Fr (sample name)", "photoUrl": "", "rank": "priest", "ordinationDate": "2016-09-11", "hegumenDate": "", "status": "serving", "bioAr": "", "order": 3, "sample": True},
  "tadros": {"name": "المتنيح القمص تادرس لبيب يوسف", "nameEn": "The late Hegumen Tadros Labib Youssef", "photoUrl": "", "rank": "hegumen", "ordinationDate": "", "hegumenDate": "", "status": "departed", "bioAr": "من الآباء الأوائل الذين خدموا الكنيسة. بركة صلواته تكون معنا.", "bioEn": "One of the first fathers to serve the church. May his prayers be with us.", "order": 10},
  "maximus": {"name": "المتنيح القس مكسيموس فؤاد", "nameEn": "The late Fr Maximus Fouad", "photoUrl": "", "rank": "priest", "ordinationDate": "", "hegumenDate": "", "status": "departed", "bioAr": "خدم بأمانة ومحبة. نياحًا لنفسه.", "bioEn": "Served with faithfulness and love. May his soul rest in peace.", "order": 11}
}

milestones = {
  "founding": {"titleAr": "تأسيس الكنيسة بشارع 45", "titleEn": "Founded on Street 45", "descAr": "بداية الخدمة بمذبح صغير في العصافرة بحري لخدمة الأسر والمصطافين.", "descEn": "Service began with a small altar in El-Asafra Bahary for families and vacationers.", "year": None, "icon": "church", "order": 1},
  "pastoral": {"titleAr": "بركة الرعاية", "titleEn": "Blessing of pastoral care", "descAr": "آباء كهنة أمناء رعوا الشعب وأسسوا خدمات التربية الكنسية والعيادات.", "descEn": "Faithful priests shepherded the people and founded the education and clinic services.", "year": None, "icon": "people", "order": 2},
  "consecration": {"titleAr": "تدشين المذابح", "titleEn": "Consecration of the altars", "descAr": "تدشين مذبح القديسين مكسيموس ودوماديوس ومذبح الأنبا موسى الأسود بالميرون المقدس.", "descEn": "The altars of Sts Maximus & Domadius and St Moses the Black consecrated with the Holy Myron.", "year": None, "icon": "altar", "order": 3},
  "pope-visit": {"titleAr": "زيارة قداسة البابا تواضروس الثاني", "titleEn": "Visit of H.H. Pope Tawadros II", "descAr": "نالت الكنيسة بركة زيارة قداسة البابا وصلاته مع الشعب.", "descEn": "The church was blessed by His Holiness's visit and prayers with the congregation.", "year": None, "icon": "pope", "order": 4}
}

saints = {
  "maximus-domadius": {"nameAr": "القديسان مكسيموس ودوماديوس (أولاد الملك)", "nameEn": "Saints Maximus & Domadius (the Roman princes)",
     "bioAr": "ابنا الملك فالنتينيانوس، تركا القصر ومجد العالم وترهبا في برية شيهيت تحت إرشاد القديس مقاريوس الكبير، وعاشا في نسك واتضاع حتى تنيحا. سُميت كنيستهما في البرية بدير البراموس (أي دير الروم).",
     "bioEn": "Sons of Emperor Valentinian, they left the palace and worldly glory to become monks in the desert of Scetis under St Macarius the Great, living in asceticism and humility until their repose. Their cell became the Baramous (\"of the Romans\") monastery.",
     "feastCopticAr": "14 طوبة (مكسيموس) و17 طوبة (دوماديوس)", "feastCopticEn": "14 Tobi (Maximus) and 17 Tobi (Domadius)", "feastGregorian": "22 & 25 January", "feastGregorianAr": "22 و25 يناير", "order": 1},
  "moses-black": {"nameAr": "القديس الأنبا موسى الأسود", "nameEn": "Saint Moses the Black",
     "bioAr": "كان لصًا قويًا ثم تاب توبة صادقة وترهب في برية شيهيت، فصار أبًا روحيًا وقسًا ونموذجًا للتوبة والاتضاع، واستشهد على يد البربر.",
     "bioEn": "Once a strong robber, he repented sincerely and became a monk in Scetis, a spiritual father and priest, a model of repentance and humility, martyred by Berber raiders.",
     "feastCopticAr": "24 بؤونة (استشهاده)", "feastCopticEn": "24 Paoni (martyrdom)", "feastGregorian": "1 July", "feastGregorianAr": "1 يوليو", "order": 2}
}

seed = {"settings": settings, "alerts": alerts, "seasons": seasons, "liturgies": liturgies, "meetings": meetings,
        "activities": activities, "clinics": clinics, "facilities": facilities, "priests": priests, "milestones": milestones, "saints": saints}
out = os.path.join(os.path.dirname(__file__), "..", "assets", "seed", "seed.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(seed, f, ensure_ascii=False, indent=1)
print("wrote", out, {k: len(v) for k, v in seed.items()})
