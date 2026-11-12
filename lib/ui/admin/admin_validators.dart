// Pure validation / conversion for the admin forms (unit-tested).
import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart' show BlockTypes, PageBlock, isValidSlug;
import '../../domain/push.dart';
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

/// Picker output (ADR-049): the admin picks on a 12-hour AM/PM picker, but
/// the time is stored as strictly zero-padded 24-hour "HH:mm" (00:00 …
/// 23:59). Out-of-range parts are clamped, never wrapped.
String formatPickedTime(int hour, int minute) => '${two(hour.clamp(0, 23))}:${two(minute.clamp(0, 59))}';

/// Picker output (ADR-049): a calendar date as strictly "YYYY-MM-DD".
String formatPickedDate(int year, int month, int day) => '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}';

/// Picker output for a date-and-time field: "YYYY-MM-DD HH:mm" (Cairo wall
/// time, the format [parseFieldValue] turns into the stored instant).
String formatPickedDateTime(int year, int month, int day, int hour, int minute) =>
    '${formatPickedDate(year, month, day)} ${formatPickedTime(hour, minute)}';

/// The time already in a field, for prefilling the picker: "HH:mm", also a
/// legacy unpadded "9:00" (Arabic-Indic digits too); null when blank or not
/// a time.
(int, int)? parseFieldTime(String raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalizeDigits(raw.trim()));
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  return h <= 23 && min <= 59 ? (h, min) : null;
}

/// The date (and time) already in a date / date-time field, for prefilling
/// the pickers; null when blank or invalid.
(int, int, int, int, int)? parseFieldDateTime(String raw) {
  final v = normalizeDigits(raw.trim());
  final dt = dateTimeRe.firstMatch(v);
  if (dt != null && isValidDateTime(v)) {
    return (int.parse(dt[1]!), int.parse(dt[2]!), int.parse(dt[3]!), int.parse(dt[4]!), int.parse(dt[5]!));
  }
  final d = dateRe.firstMatch(v);
  if (d != null && isValidDate(v)) return (int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!), 0, 0);
  return null;
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
  // Phones are stored without separators: measure what will be stored.
  final stored = f.type == FieldType.phone ? normalizePhoneInput(v) : v;
  if (stored.length > f.effectiveMaxLength) return 'tooLong';
  if (f.slug && !isValidSlug(v)) return 'invalidSlug';
  if (f.pattern.isNotEmpty && !RegExp('^(?:${f.pattern})\$').hasMatch(v)) return 'invalid';
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
/// Error key (`requiredTitleAnyLang`) when an [list] row (its sub-field
/// texts in [row]) has none of [FieldDef.rowRequireAnyOf] filled, else null.
String? validateRowAnyOf(FieldDef list, Map<String, String> row) {
  if (list.rowRequireAnyOf.isEmpty) return null;
  return list.rowRequireAnyOf.any((k) => (row[k] ?? '').trim().isNotEmpty) ? null : 'requiredTitleAnyLang';
}

/// Error key (`endDateBeforeStart`) when a row's [FieldDef.rowNotBefore] end
/// date is set and earlier than its start date (YYYY-MM-DD compare as text).
String? validateRowOrder(FieldDef list, Map<String, String> row) {
  final o = list.rowNotBefore;
  if (o == null) return null;
  final end = (row[o.key] ?? '').trim(), start = (row[o.value] ?? '').trim();
  if (end.isEmpty || start.isEmpty) return null;
  return end.compareTo(start) < 0 ? 'endDateBeforeStart' : null;
}

/// Error key (`duplicateKey`) when row [index]'s [FieldDef.rowUniqueKey]
/// value (in [values], one per row) is set and an earlier row has it too.
String? validateRowUnique(FieldDef list, List<String> values, int index) {
  if (list.rowUniqueKey.isEmpty || index >= values.length) return null;
  final v = values[index].trim();
  if (v.isEmpty) return null;
  for (var j = 0; j < index; j++) {
    if (values[j].trim() == v) return 'duplicateKey';
  }
  return null;
}

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
  // App & notifications (ADR-057): the default lead must be one of the
  // offered leads (firestore.rules denies the save otherwise).
  final leads = data['reminderLeads'], lead = data['reminderDefaultLead'];
  if (lead is int && leads is List && !leads.contains(lead)) return 'reminderDefaultLeadNotOffered';
  // Custom page blocks (firestore.rules validPageBlock): an image needs an
  // https picture link.
  final blocks = data['blocks'];
  if (blocks is List) {
    for (final raw in blocks) {
      final b = PageBlock.fromStored(raw);
      if (b != null && b.type == BlockTypes.image && !b.url.startsWith('https://')) return 'blockImageUrl';
    }
  }
  return null;
}

/// Deep equality for collected form values (lists, maps, DateTime, scalars).
bool sameValue(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !sameValue(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// Metadata stamped on every save; not content.
const _metadataKeys = {'updatedAt', 'updatedBy'};

/// True when the stored version [next] differs from the version the editor
/// was built from ([shown]) only in metadata, or in fields whose new value
/// the editor already holds ([editorValues]) — typically the snapshot of the
/// editor's own save. The form then stays mounted (no scroll reset, BUG-12)
/// instead of being rebuilt from [next].
bool isEchoOfEditor(Map<String, dynamic>? shown, Map<String, dynamic>? next, Map<String, dynamic> editorValues) {
  if (shown == null || next == null) return false;
  for (final k in {...shown.keys, ...next.keys}) {
    if (_metadataKeys.contains(k) || sameValue(shown[k], next[k])) continue;
    if (!editorValues.containsKey(k) || !sameValue(editorValues[k], next[k])) return false;
  }
  return true;
}

/// Only the keys whose value differs from [initial]: an edit never writes
/// back stale values of fields another admin changed meanwhile.
Map<String, dynamic> changedFields(Map<String, dynamic> initial, Map<String, dynamic> current) => {
      for (final e in current.entries)
        if (!initial.containsKey(e.key) || !sameValue(initial[e.key], e.value)) e.key: e.value,
    };

/// Lower-cased text used by the admin list search.
String searchableText(Map<String, dynamic> data) =>
    data.values.whereType<String>().join(' ').toLowerCase();

/// Keys saved in a write of their own: Firestore evaluates at most 1,000
/// rule expressions per request, and a full gallery (8 photos) plus a full
/// `extraFields` list (15 rows) in one write exceeds it (firestore.rules,
/// validGallery / validExtraFields; ADR-020). `dayEvents` (settings/features,
/// «اليوم والبث المباشر»): 20 events with end dates plus any other changed
/// Today key (strip, live switch…) in one write exceeds it too (ADR-044).
const separatelySavedKeys = ['gallery', 'extraFields', 'blocks', 'dayEvents'];

/// Splits a save [payload] into writes made one after the other: everything
/// else first (it creates a new document), then each non-empty list in
/// [separatelySavedKeys] order (`gallery`, `extraFields`, `blocks`, `dayEvents`). Empty or cleared lists cost almost nothing and
/// stay in the first write. Empty writes are dropped.
List<Map<String, dynamic>> splitSavePayload(Map<String, dynamic> payload) {
  bool own(String k) => separatelySavedKeys.contains(k) && payload[k] is List && (payload[k] as List).isNotEmpty;
  final base = {
    for (final e in payload.entries)
      if (!own(e.key)) e.key: e.value,
  };
  return [
    if (base.isNotEmpty) base,
    for (final k in separatelySavedKeys)
      if (own(k)) {k: payload[k]},
  ];
}

/// Validates a notification template string against placeholder rules and character limits.
String? validateNotifyTemplate(String typeId, String? text, {int maxLength = 300}) {
  if (text == null || text.trim().isEmpty) return null;
  if (text.length > maxLength) return 'err_max_length';
  final unknown = unknownPlaceholders(typeId, text);
  if (unknown.isNotEmpty) return 'err_unknown_placeholder';
  return null;
}

/// Validates a scheduled notification draft before saving: the same limits
/// as `validNotifyRow` in firestore.rules and `parseScheduleRow` in
/// tool/push_sender.js (Arabic title AND body are required by both).
/// Returns an l10n key, or null.
String? validateScheduledNotification(ScheduledNotification n) {
  bool sep(String s) => s.contains('\u001f');
  if (n.titleAr.trim().isEmpty) return 'err_title_required';
  if (n.bodyAr.trim().isEmpty) return 'err_body_required';
  if (n.titleAr.length > 120 || n.titleEn.length > 120) return 'err_title_length';
  if (n.bodyAr.length > 300 || n.bodyEn.length > 300) return 'err_body_length';
  if (sep(n.titleAr) || sep(n.titleEn) || sep(n.bodyAr) || sep(n.bodyEn)) return 'err_bad_char';
  if (!validNotificationLink(n.link)) return 'err_bad_link';
  if (n.eventKey.isNotEmpty && !isValidPushEventKey(n.eventKey)) {
    return 'err_invalid_event_key';
  }
  if (!['all', 'web', 'app'].contains(n.targets)) return 'err_invalid_targets';
  if (!RegExp(r'^[a-z0-9_-]{1,24}$').hasMatch(n.id)) return 'err_invalid_id';
  return null;
}

/// An in-app path the rules accept for a scheduled push: `/` or `/…` with no
/// spaces, at most 201 characters.
bool validNotificationLink(String link) =>
    link == '/' || RegExp(r'^/[^\s\u001f]{1,200}$').hasMatch(link);

/// `lit-` / `meeting-` / `day-` / `season-` + lowercase id (firestore.rules).
bool isValidPushEventKey(String key) => RegExp(r'^(lit|meeting|day|season)-[a-z0-9-]{1,40}$').hasMatch(key);

/// `HH:mm` (24 h) or empty.
bool isValidHm(String s) => s.isEmpty || RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(s);

/// The Web Push public key: empty or 80–100 URL-safe base64 characters.
bool isValidVapidKey(String s) => s.isEmpty || isWebPushVapidPublicKey(s);
