// Pure validation / conversion for the admin forms (unit-tested).
import '../../domain/cairo_time.dart';
import '../../domain/rules.dart' show normalizeDigits;
import 'admin_schema.dart';

final timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final dateTimeRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$');
final dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _looseDateRe = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$');
final _phoneRe = RegExp(r'^\+?[0-9]{5,15}$');

/// Real calendar date (rejects e.g. 2027-02-30, which would otherwise roll over).
bool isCalendarDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1) return false;
  final dt = DateTime.utc(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d;
}

bool isValidDate(String v) {
  final m = dateRe.firstMatch(v);
  return m != null && isCalendarDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

bool isValidDateTime(String v) {
  final m = dateTimeRe.firstMatch(v);
  if (m == null) return false;
  final h = int.parse(m[4]!), min = int.parse(m[5]!);
  return h <= 23 && min <= 59 && isCalendarDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// YYYY, YYYY-MM or YYYY-MM-DD.
bool isValidLooseDate(String v) {
  final m = _looseDateRe.firstMatch(v);
  if (m == null) return false;
  final y = int.parse(m[1]!);
  if (m[2] == null) return y >= 1000;
  final mo = int.parse(m[2]!);
  if (m[3] == null) return mo >= 1 && mo <= 12;
  return isCalendarDate(y, mo, int.parse(m[3]!));
}

/// http(s) URL with a host; with [allowPath] also an in-app path like /clinics.
bool isValidUrl(String v, {bool allowPath = false}) {
  if (allowPath && v.startsWith('/') && !v.startsWith('//')) return !v.contains(' ');
  final u = Uri.tryParse(v);
  return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.contains('.') && !v.contains(' ');
}

/// Phone stored as typed digits ("03 536 8888" / "+20 100 …" / Arabic digits ok).
String normalizePhoneInput(String v) => normalizeDigits(v).replaceAll(RegExp(r'[\s\-().]'), '');

bool isValidPhone(String v) => _phoneRe.hasMatch(normalizePhoneInput(v));

/// Error key for l10n (`required`, `invalid`, `invalidUrl`, `invalidPhone`,
/// `invalidTime`, `invalidDate`, `outOfRange`, `tooLong`) or null when valid.
String? validateFieldValue(FieldDef f, String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return f.required ? 'required' : null;
  if (v.length > f.effectiveMaxLength) return 'tooLong';
  switch (f.type) {
    case FieldType.time:
      return timeRe.hasMatch(v) ? null : 'invalidTime';
    case FieldType.integer:
      final n = int.tryParse(normalizeDigits(v));
      if (n == null) return 'invalid';
      return _inRange(f, n) ? null : 'outOfRange';
    case FieldType.decimal:
      final n = double.tryParse(normalizeDigits(v));
      if (n == null || n.isNaN || n.isInfinite) return 'invalid';
      return _inRange(f, n) ? null : 'outOfRange';
    case FieldType.dateTime:
      return isValidDateTime(v) ? null : 'invalidDate';
    case FieldType.date:
      return isValidDate(v) ? null : 'invalidDate';
    case FieldType.looseDate:
      return isValidLooseDate(v) ? null : 'invalidDate';
    case FieldType.url:
      return isValidUrl(v, allowPath: f.allowPath) ? null : 'invalidUrl';
    case FieldType.phone:
      return isValidPhone(v) ? null : 'invalidPhone';
    default:
      return null;
  }
}

bool _inRange(FieldDef f, num n) => (f.min == null || n >= f.min!) && (f.max == null || n <= f.max!);

/// Converts a validated text input to the stored value (null = blank).
Object? parseFieldValue(FieldDef f, String raw) {
  final v = raw.trim();
  switch (f.type) {
    case FieldType.integer:
      return v.isEmpty ? null : int.tryParse(normalizeDigits(v));
    case FieldType.decimal:
      return v.isEmpty ? null : double.tryParse(normalizeDigits(v));
    case FieldType.dateTime:
      final m = dateTimeRe.firstMatch(v);
      return m == null
          ? null
          : CairoTime.at(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!) * 60 + int.parse(m[5]!))
              .toUtc();
    case FieldType.date:
      final m = dateRe.firstMatch(v);
      return m == null ? null : CairoTime.at(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).toUtc();
    case FieldType.phone:
      return normalizePhoneInput(v);
    default:
      return v;
  }
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtDateTime(DateTime v) {
  final c = CairoTime.fromInstant(v);
  return '${c.year}-${two(c.month)}-${two(c.day)} ${two(c.hour)}:${two(c.minute)}';
}

String fmtDate(DateTime v) {
  final c = CairoTime.calendarDate(v);
  return '${c.year}-${two(c.month)}-${two(c.day)}';
}

/// Cross-field checks for a collected document: error key or null.
String? validateDocument(CollectionDef? def, Map<String, dynamic> data) {
  if (def != null && def.requireAnyOf.isNotEmpty && def.requireAnyOf.every((k) => data[k] == null || data[k] == '')) {
    return 'needWeekdayOrDate';
  }
  final start = data['start'], end = data['end'];
  if (start is String && end is String && start.isNotEmpty && end.isNotEmpty && def?.name != 'liturgies') {
    // Liturgies may cross midnight (e.g. midnight praise); others may not.
    if (end.compareTo(start) <= 0) return 'endBeforeStart';
  }
  final s = data['startsAt'], e = data['endsAt'];
  if (s is DateTime && e is DateTime && !e.isAfter(s)) return 'endBeforeStart';
  return null;
}

/// Lower-cased text used by the admin list search.
String searchableText(Map<String, dynamic> data) =>
    data.values.whereType<String>().join(' ').toLowerCase();
