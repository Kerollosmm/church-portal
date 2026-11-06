// Coptic calendar engine (ADR-039). Pure Dart, offline, deterministic.
//
// * Gregorian <-> Coptic (Anno Martyrum, "Year of the Martyrs") through the
//   Julian Day Number. 1 Tout 1 AM = JDN 1825030 (29 Aug 284 Julian). A Coptic
//   year Y is a leap year (6 days of Nasie instead of 5) when Y % 4 == 3, so
//   the next 1 Tout falls on 12 September instead of 11 September
//   (e.g. 1 Tout 1743 = 11 Sep 2026, 1 Tout 1744 = 12 Sep 2027).
// * The liturgical day: the Church's day begins at sunset (the evening
//   prayers belong to the next day). By default the portal rolls to the next
//   Coptic day at a fixed 18:00 (admin-editable); the admin may instead
//   choose the actual sunset at the church in Alexandria (sun.dart, NOAA,
//   church coordinates). The reference place is the church in Alexandria;
//   Africa/Cairo (Egypt's single time zone, CairoTime) is only the clock.
//
// Unit tests: test/coptic_calendar_test.dart (dates checked against
// api.katameros.app, docs/CONTENT_SOURCES.md).

import 'cairo_time.dart';
import 'occasion_theme.dart' show orthodoxEaster;
import 'rules.dart' show toArabicDigits;
import 'sun.dart';
import 'time_format.dart' show weekdayNamesAr, weekdayNamesEn;

/// The 13 Coptic months (month 13 = the little month, Nasie / Epagomenae).
const copticMonthsAr = [
  '', 'توت', 'بابه', 'هاتور', 'كيهك', 'طوبه', 'أمشير', 'برمهات', 'برموده', 'بشنس', 'بؤونه', 'أبيب', 'مسرى', 'النسيء',
];
const copticMonthsEn = [
  '', 'Tout', 'Baba', 'Hatour', 'Kiahk', 'Touba', 'Amshir', 'Baramhat', 'Baramouda', 'Bashans', 'Baouna', 'Abib',
  'Mesra', 'Nasie',
];

const _copticEpochJdn = 1825030;

int _gregorianToJdn(int y, int m, int d) {
  final a = (14 - m) ~/ 12;
  final yy = y + 4800 - a;
  final mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
}

DateTime _jdnToGregorian(int jdn) {
  final a = jdn + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - 146097 * b ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  final day = e - (153 * m + 2) ~/ 5 + 1;
  final month = m + 3 - 12 * (m ~/ 10);
  final year = 100 * b + d - 4800 + m ~/ 10;
  return DateTime.utc(year, month, day);
}

/// A Coptic calendar date.
class CopticDate {
  final int year, month, day;
  const CopticDate(this.year, this.month, this.day);

  /// Is Coptic [year] a leap year (6 days of Nasie)?
  static bool isLeapYear(int year) => year % 4 == 3;

  /// Days in [month] of [year] (30, or 5/6 for the little month).
  static int daysInMonth(int year, int month) => month < 13 ? 30 : (isLeapYear(year) ? 6 : 5);

  int get _jdn => _copticEpochJdn - 1 + 365 * (year - 1) + year ~/ 4 + 30 * (month - 1) + day;

  /// The Coptic date of the Gregorian calendar date [date] (only its y/m/d
  /// are used).
  factory CopticDate.fromGregorian(DateTime date) {
    final jdn = _gregorianToJdn(date.year, date.month, date.day);
    final year = (4 * (jdn - _copticEpochJdn) + 1463) ~/ 1461;
    final start = CopticDate(year, 1, 1)._jdn;
    final month = (jdn - start) ~/ 30 + 1;
    final day = jdn - start - 30 * (month - 1) + 1;
    return CopticDate(year, month, day);
  }

  /// The Gregorian date (UTC midnight, a date-only value).
  DateTime toGregorian() => _jdnToGregorian(_jdn);

  String monthName({required bool arabic}) => arabic ? copticMonthsAr[month] : copticMonthsEn[month];

  /// «٢٥ بابه ١٧٤٣ ش» / "25 Baba 1743 AM".
  String format({required bool arabic}) => arabic
      ? '${toArabicDigits('$day')} ${copticMonthsAr[month]} ${toArabicDigits('$year')} ش'
      : '$day ${copticMonthsEn[month]} $year AM';

  @override
  bool operator ==(Object other) =>
      other is CopticDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'CopticDate($day/$month/$year)';
}

/// How the liturgical day starts (settings/features `dayStartMode`).
class DayStartModes {
  /// At a fixed local time ([defaultDayStartsAt] unless set) — the default.
  static const fixed = 'fixed';

  /// At the actual sunset at the church in Alexandria.
  static const sunset = 'sunset';
  static const values = [fixed, sunset];
}

/// Default fixed start of the liturgical day (Alexandria wall clock).
const defaultDayStartsAt = '18:00';

/// The liturgical day in force at [instant].
class LiturgicalDay {
  /// Gregorian calendar date (UTC midnight) of the liturgical day. After the
  /// cut-over it is tomorrow's civil date.
  final DateTime date;

  /// The Cairo civil date of [instant] (UTC midnight).
  final DateTime civilDate;

  /// The Coptic date of [date].
  final CopticDate coptic;

  const LiturgicalDay({required this.date, required this.civilDate, required this.coptic});

  @override
  bool operator ==(Object other) => other is LiturgicalDay && other.date == date && other.civilDate == civilDate;

  @override
  int get hashCode => Object.hash(date, civilDate);

  /// True between the cut-over and midnight ("the eve of …").
  bool get isEve => date != civilDate;

  /// ISO weekday (1 = Monday) of the liturgical day.
  int get weekday => date.weekday;

  /// «الأربعاء ٢٥ بابه ١٧٤٣ ش» / "Wednesday 25 Baba 1743 AM"; on the eve
  /// «ليلة الخميس …» / "Eve of Thursday …". In Holy Week the day's name
  /// replaces the weekday (ADR-051): «ليلة الجمعة العظيمة ٢٢ برموده ١٧٤٣ ش».
  String label({required bool arabic}) {
    final wd = holyWeekDayName(date, arabic: arabic) ?? (arabic ? weekdayNamesAr[weekday] : weekdayNamesEn[weekday]);
    final day = isEve ? (arabic ? 'ليلة $wd' : 'Eve of $wd') : wd;
    return '$day ${coptic.format(arabic: arabic)}';
  }
}

/// Holy Week day names by their offset from Coptic Easter Sunday (ADR-051).
const _holyWeekNames = <int, (String, String)>{
  -7: ('أحد الشعانين', 'Palm Sunday'),
  -6: ('اثنين البصخة', 'Holy Monday'),
  -5: ('ثلاثاء البصخة', 'Holy Tuesday'),
  -4: ('أربعاء البصخة', 'Holy Wednesday'),
  -3: ('خميس العهد', 'Covenant Thursday'),
  -2: ('الجمعة العظيمة', 'Good Friday'),
  -1: ('سبت النور', 'Joyous Saturday'),
};

/// The Holy Week name of the Gregorian date [date] (y/m/d; Palm Sunday to
/// Joyous Saturday, from the app's Coptic Easter computus), or null on any
/// other day (ADR-051, issue 13).
String? holyWeekDayName(DateTime date, {required bool arabic}) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final n = _holyWeekNames[d.difference(orthodoxEaster(d.year)).inDays];
  return n == null ? null : (arabic ? n.$1 : n.$2);
}

/// Minutes after local midnight of a fixed "HH:mm" start; blank /
/// malformed = [defaultDayStartsAt]; "00:00" = the civil day (midnight).
int dayStartMinutes(String? hm) {
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch((hm ?? '').trim());
  if (m == null) return 18 * 60;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// Minutes after local midnight at which the liturgical day of the civil
/// date [civil] starts: the fixed [fixedAt] ([DayStartModes.fixed], the
/// default and anything unknown) or sunset at the church ([lat]/[lng],
/// default the church in Alexandria).
int dayStartOn(DateTime civil, {String mode = DayStartModes.fixed, String? fixedAt, double? lat, double? lng}) =>
    mode == DayStartModes.sunset
        ? sunsetLocalMinutes(civil, lat: lat ?? churchLat, lng: lng ?? churchLng)
        : dayStartMinutes(fixedAt);

/// The liturgical day at [instant] (wall clock of Africa/Cairo, Egypt's
/// single time zone; DST handled by [CairoTime]).
LiturgicalDay liturgicalDayAt(DateTime instant,
    {String mode = DayStartModes.fixed, String? fixedAt, double? lat, double? lng}) {
  final c = CairoTime.fromInstant(instant);
  final civil = DateTime.utc(c.year, c.month, c.day);
  final cut = dayStartOn(civil, mode: mode, fixedAt: fixedAt, lat: lat, lng: lng);
  final minutes = c.hour * 60 + c.minute;
  final date = cut > 0 && minutes >= cut ? civil.add(const Duration(days: 1)) : civil;
  return LiturgicalDay(date: date, civilDate: civil, coptic: CopticDate.fromGregorian(date));
}
