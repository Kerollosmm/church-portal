import 'models.dart';
import 'rules.dart';

/// "06:30 AM" (Latin digits) for an "HH:mm" string.
String formatTimeLatin(String hm) {
  final m = parseHm(hm);
  if (m == null) return hm;
  var h = m ~/ 60;
  final mi = m % 60;
  final pm = h >= 12;
  h = h % 12;
  if (h == 0) h = 12;
  return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')} ${pm ? 'PM' : 'AM'}';
}

/// "٠٦:٣٠ ص" (Arabic-Indic digits, ص/م) for an "HH:mm" string.
String formatTimeArabic(String hm) {
  final m = parseHm(hm);
  if (m == null) return hm;
  var h = m ~/ 60;
  final mi = m % 60;
  final pm = h >= 12;
  h = h % 12;
  if (h == 0) h = 12;
  return toArabicDigits('${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}') + (pm ? ' م' : ' ص');
}

String formatRangeLatin(String start, String end) =>
    end.isEmpty ? formatTimeLatin(start) : '${formatTimeLatin(start)} – ${formatTimeLatin(end)}';

String formatRangeArabic(String start, String end) =>
    end.isEmpty ? formatTimeArabic(start) : '${formatTimeArabic(start)} – ${formatTimeArabic(end)}';

const weekdayNamesAr = ['', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const weekdayNamesEn = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String weekdayName(int? isoWeekday, {required bool arabic}) {
  if (isoWeekday == null || isoWeekday < 1 || isoWeekday > 7) return '';
  return arabic ? weekdayNamesAr[isoWeekday] : weekdayNamesEn[isoWeekday];
}

const _monthsAr = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _monthsEn = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "6 يناير 2027" / "6 Jan 2027" (Arabic version uses Arabic-Indic digits).
String formatDate(DateTime d, {required bool arabic}) {
  if (arabic) return '${toArabicDigits('${d.day}')} ${_monthsAr[d.month]} ${toArabicDigits('${d.year}')}';
  return '${d.day} ${_monthsEn[d.month]} ${d.year}';
}

/// Formats a stored ISO date-ish string ("1987-06-14" or "1987").
String formatLooseDate(String s, {required bool arabic}) {
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  if (d != null && s.length >= 8) return formatDate(d, arabic: arabic);
  return arabic ? toArabicDigits(s) : s;
}
