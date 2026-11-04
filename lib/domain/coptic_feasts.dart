// Computed feast list (ADR-039): the offline fallback of the "top event of
// the day" when the Katameros commemoration is unavailable (offline, API
// down, admin switched it off). Pure Dart.
//
// Only well-established feasts are listed: the fixed ones by their Coptic
// date (the Nativity on 7 January, as the Coptic Church keeps it in
// 1900–2099) and the movable ones from the Coptic Easter computus already
// used by the Holy Week theme (orthodoxEaster in occasion_theme.dart).
// Dates were checked against api.katameros.app (docs/CONTENT_SOURCES.md).

import 'coptic_calendar.dart';
import 'occasion_theme.dart' show orthodoxEaster;

/// Higher ranks win when several feasts fall on one day.
enum FeastRank { commemoration, minor, fast, major }

class CopticFeast {
  final String ar, en;
  final FeastRank rank;
  const CopticFeast(this.ar, this.en, this.rank);

  @override
  bool operator ==(Object other) => other is CopticFeast && other.ar == ar && other.en == en && other.rank == rank;

  @override
  int get hashCode => Object.hash(ar, en, rank);

  @override
  String toString() => 'CopticFeast($en)';
}

/// Fixed feasts by Coptic (month, day).
const Map<(int, int), CopticFeast> _fixed = {
  (1, 1): CopticFeast('عيد النيروز (رأس السنة القبطية)', 'Feast of El-Nayrouz (Coptic New Year)', FeastRank.major),
  (1, 17): CopticFeast('عيد الصليب المجيد', 'Feast of the Glorious Cross', FeastRank.major),
  (3, 16): CopticFeast('بدء صوم الميلاد', 'Beginning of the Nativity Fast', FeastRank.fast),
  (5, 6): CopticFeast('عيد الختان', 'Feast of the Circumcision', FeastRank.minor),
  (5, 11): CopticFeast('عيد الغطاس المجيد (الظهور الإلهي)', 'Feast of the Theophany (Epiphany)', FeastRank.major),
  (5, 13): CopticFeast('عيد عرس قانا الجليل', 'Feast of the Wedding at Cana', FeastRank.minor),
  (6, 8): CopticFeast('عيد دخول السيد المسيح الهيكل', 'Feast of the Presentation in the Temple', FeastRank.minor),
  (7, 10): CopticFeast('تذكار الصليب المجيد', 'Commemoration of the Glorious Cross', FeastRank.minor),
  (7, 29): CopticFeast('عيد البشارة المجيد', 'Feast of the Annunciation', FeastRank.major),
  (9, 24): CopticFeast('عيد دخول السيد المسيح أرض مصر', 'Entry of the Lord into Egypt', FeastRank.minor),
  (11, 5): CopticFeast('عيد الرسولين بطرس وبولس', 'Feast of the Apostles Peter and Paul', FeastRank.minor),
  (12, 1): CopticFeast('بدء صوم السيدة العذراء', 'Beginning of the Fast of the Virgin Mary', FeastRank.fast),
  (12, 13): CopticFeast('عيد التجلي المجيد', 'Feast of the Transfiguration', FeastRank.minor),
  (12, 16): CopticFeast('عيد صعود جسد السيدة العذراء', 'Assumption of the Body of the Virgin Mary', FeastRank.major),
};

const _nativity = CopticFeast('عيد الميلاد المجيد', 'Feast of the Nativity (Christmas)', FeastRank.major);
const _monthly29 = CopticFeast('تذكار البشارة والميلاد والقيامة', 'Commemoration of the Annunciation, Nativity and Resurrection',
    FeastRank.commemoration);

/// Movable days by their offset from Coptic Easter Sunday.
const Map<int, CopticFeast> _movable = {
  -69: CopticFeast('بدء صوم يونان (نينوى)', 'Beginning of the Fast of Nineveh (Jonah)', FeastRank.fast),
  -66: CopticFeast('فصح يونان', 'Jonah\'s Passover', FeastRank.minor),
  -55: CopticFeast('بدء الصوم الكبير', 'Beginning of Great Lent', FeastRank.fast),
  -8: CopticFeast('سبت لعازر', 'Lazarus Saturday', FeastRank.minor),
  -7: CopticFeast('أحد الشعانين', 'Palm Sunday', FeastRank.major),
  -6: CopticFeast('اثنين البصخة المقدسة', 'Holy Monday', FeastRank.fast),
  -5: CopticFeast('ثلاثاء البصخة المقدسة', 'Holy Tuesday', FeastRank.fast),
  -4: CopticFeast('أربعاء البصخة المقدسة', 'Holy Wednesday', FeastRank.fast),
  -3: CopticFeast('خميس العهد', 'Covenant Thursday', FeastRank.major),
  -2: CopticFeast('الجمعة العظيمة', 'Good Friday', FeastRank.major),
  -1: CopticFeast('سبت الفرح (سبت النور)', 'Joyous Saturday', FeastRank.major),
  0: CopticFeast('عيد القيامة المجيد', 'Feast of the Resurrection (Easter)', FeastRank.major),
  7: CopticFeast('أحد توما', 'Thomas Sunday', FeastRank.minor),
  39: CopticFeast('عيد الصعود المجيد', 'Feast of the Ascension', FeastRank.major),
  49: CopticFeast('عيد العنصرة (حلول الروح القدس)', 'Feast of Pentecost', FeastRank.major),
  50: CopticFeast('بدء صوم الرسل', 'Beginning of the Apostles\' Fast', FeastRank.fast),
};

/// Feasts on the Gregorian calendar date [date] (y/m/d only), highest rank
/// first.
List<CopticFeast> copticFeastsOn(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final c = CopticDate.fromGregorian(d);
  final out = <CopticFeast>[];
  final offset = d.difference(orthodoxEaster(d.year)).inDays;
  final movable = _movable[offset];
  if (movable != null) out.add(movable);
  if (d.month == 1 && d.day == 7) out.add(_nativity);
  final fixed = _fixed[(c.month, c.day)];
  if (fixed != null) out.add(fixed);
  // The 29th of each month, except Kiahk (the Nativity), Touba and Amshir.
  if (c.day == 29 && c.month != 4 && c.month != 5 && c.month != 6 && out.isEmpty) out.add(_monthly29);
  out.sort((a, b) => b.rank.index.compareTo(a.rank.index));
  return out;
}
