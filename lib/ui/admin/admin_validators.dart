// Pure validation / conversion for the admin forms (unit-tested).
import 'package:firebase_core/firebase_core.dart';

import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart'
    show
        BlockTypes,
        ListStyles,
        PageBlock,
        PagePlacements,
        detailsBodyMax,
        detailsSummaryMax,
        isValidSlug,
        listBlockMaxItems,
        listItemMax,
        slugMaxLength;
import '../../domain/media.dart' show MediaImage, MediaSource, isValidImageUrl;
import '../../domain/push.dart';
import '../../domain/rules.dart' show normalizeDigits;
import 'admin_schema.dart';

const _arabicSlugMap = <String, String>{
  'ا': 'a', 'أ': 'a', 'إ': 'a', 'آ': 'a', 'ى': 'a',
  'ب': 'b', 'ت': 't', 'ة': 't', 'ث': 'th',
  'ج': 'g', 'ح': 'h', 'خ': 'kh',
  'د': 'd', 'ذ': 'dh', 'ر': 'r', 'ز': 'z',
  'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'd',
  'ط': 't', 'ظ': 'z', 'ع': 'a', 'غ': 'gh',
  'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l',
  'م': 'm', 'ن': 'n', 'ه': 'h', 'و': 'w', 'ؤ': 'w',
  'ي': 'y', 'ئ': 'y', 'ء': '',
};

String _fitSlug(String s, int maxLen) {
  var out = s.length > maxLen ? s.substring(0, maxLen) : s;
  out = out.replaceAll(RegExp(r'^-+|-+$'), '');
  return out.isEmpty ? 'page' : out;
}

/// Deterministic URL slug generated from an Arabic or Latin [title], always
/// satisfying [isValidSlug] and unique against [taken] (P1-14).
String slugFromTitle(String title, {required Set<String> taken}) {
  final normalized = normalizeDigits(title).replaceAll(RegExp(r'[\u0640\u064B-\u065F\u0670]'), '');
  final buf = StringBuffer();
  for (final rune in normalized.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_arabicSlugMap[ch] ?? ch.toLowerCase());
  }
  final cleaned = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final base = _fitSlug(cleaned.isEmpty ? 'page' : cleaned, slugMaxLength);
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    final suffix = '-$n';
    final candidate = '${_fitSlug(base, slugMaxLength - suffix.length)}$suffix';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Result of preparing unsaved defaults for duplicating a custom page.
typedef DuplicatePageResult = ({Map<String, Object?> defaults, bool droppedOwnedImage});

String _prefixedTitle(String raw, String prefix, int maxLen) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final combined = trimmed.startsWith(prefix) ? trimmed : '$prefix$trimmed';
  return combined.length > maxLen ? combined.substring(0, maxLen) : combined;
}

String _duplicateSlug(String rawSlug, String fallbackTitle, Set<String> taken) {
  final trimmed = rawSlug.trim();
  if (!isValidSlug(trimmed)) return slugFromTitle(fallbackTitle, taken: taken);
  final stripped = trimmed.replaceFirst(RegExp(r'-copy(?:-\d+)?$'), '');
  final stem = stripped.isEmpty ? trimmed : stripped;
  final first = '${_fitSlug(stem, slugMaxLength - 5)}-copy';
  if (!taken.contains(first)) return first;
  for (var n = 2;; n++) {
    final suffix = '-copy-$n';
    final candidate = '${_fitSlug(stem, slugMaxLength - suffix.length)}$suffix';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Builds safe initial field values for duplicating a `pages` document:
/// resets `visible` and `featured` to false, avoids double-prefixing titles,
/// reserves a unique valid slug against [takenSlugs], deep-copies blocks, and
/// drops uploaded/storage cover images so the original retains ownership.
DuplicatePageResult buildDuplicatePageDefaults(
  Map<String, dynamic> source, {
  required Set<String> takenSlugs,
}) {
  final titleAr = _prefixedTitle(source['titleAr'] is String ? source['titleAr'] as String : '', 'نسخة من ', 200);
  final titleEn = _prefixedTitle(source['titleEn'] is String ? source['titleEn'] as String : '', 'Copy of ', 200);
  final subtitleAr = source['subtitleAr'] is String ? (source['subtitleAr'] as String).trim() : '';
  final subtitleEn = source['subtitleEn'] is String ? (source['subtitleEn'] as String).trim() : '';
  final rawPlacement = source['placement'] is String ? source['placement'] as String : '';
  final placement = PagePlacements.all.contains(rawPlacement)
      ? rawPlacement
      : (source['showInNav'] == true ? PagePlacements.nav : PagePlacements.link);
  final categoryId = source['categoryId'] is String ? source['categoryId'] as String : '';
  final order = source['order'] is int
      ? source['order'] as int
      : (source['order'] is num ? (source['order'] as num).toInt() : 0);
  final blocks = <dynamic>[
    for (final b in (source['blocks'] is List ? source['blocks'] as List : const []))
      if (b is String) b else if (b is Map) Map<String, dynamic>.from(b),
  ];

  // MediaImage.ownedMediaId only covers inline; check source explicitly so both
  // inline and storage covers are dropped while external https URLs stay intact.
  final rawImg = source['image'];
  final img = MediaImage.fromMap(rawImg);
  final Map<String, dynamic>? copiedImg;
  final bool droppedOwnedImage;
  if (img != null && img.source == MediaSource.url) {
    copiedImg = img.toMap();
    droppedOwnedImage = false;
  } else {
    copiedImg = null;
    droppedOwnedImage =
        rawImg is Map && (rawImg['source'] == MediaSource.inline || rawImg['source'] == MediaSource.storage);
  }

  final slug = _duplicateSlug(
    source['slug'] is String ? source['slug'] as String : '',
    titleAr.isEmpty ? titleEn : titleAr,
    takenSlugs,
  );

  return (
    defaults: <String, Object?>{
      'titleAr': titleAr,
      'titleEn': titleEn,
      'subtitleAr': subtitleAr,
      'subtitleEn': subtitleEn,
      'image': copiedImg,
      'blocks': blocks,
      'placement': placement,
      'categoryId': categoryId,
      'showInNav': placement == PagePlacements.nav,
      'featured': false,
      'visible': false,
      'slug': slug,
      'order': order,
    },
    droppedOwnedImage: droppedOwnedImage,
  );
}

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

/// Days in Gregorian calendar [month] (1–12) of [year].
int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Parses a `looseDate` string (`YYYY`, `YYYY-MM`, or `YYYY-MM-DD`, including
/// Arabic-Indic digits) into parts; returns null when blank or invalid.
({int year, int? month, int? day})? parseLooseDate(String raw) {
  final v = normalizeDigits(raw.trim());
  if (!isValidLooseDate(v)) return null;
  final m = _looseDateRe.firstMatch(v)!;
  return (
    year: int.parse(m[1]!),
    month: m[2] == null ? null : int.parse(m[2]!),
    day: m[3] == null ? null : int.parse(m[3]!),
  );
}

/// Formats `YYYY`, `YYYY-MM`, or `YYYY-MM-DD` from [looseDate] picker parts.
String formatLooseDateValue(int year, [int? month, int? day]) {
  final y = year.clamp(1000, 9999).toString().padLeft(4, '0');
  if (month == null) return y;
  final m = month.clamp(1, 12);
  if (day == null) return '$y-${two(m)}';
  final d = day.clamp(1, daysInMonth(year.clamp(1000, 9999), m));
  return '$y-${two(m)}-${two(d)}';
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

/// Validates a heading block in custom pages: Arabic heading text is required.
String? validateHeadingBlock(Map<String, String> row, String blockType) {
  if (blockType == BlockTypes.heading && (row['textAr'] ?? '').trim().isEmpty) {
    return 'required';
  }
  return null;
}

/// One validation issue inside a [BlockTypes.list] block.
typedef ListBlockIssue = ({int? itemIndex, bool isEn, String code});

String _cleanListItem(String raw) =>
    raw.replaceAll(PageBlock.separator, '').replaceAll(PageBlock.listSeparator, '').trim();

/// Validates a [BlockTypes.list] block's items and style against the limits
/// mirrored in `firestore.rules` (`validListBlock`).
List<ListBlockIssue> validateListBlock({
  required List<String> arItems,
  List<String> enItems = const [],
  String style = ListStyles.bullet,
}) {
  final issues = <ListBlockIssue>[];
  if (arItems.isEmpty) {
    issues.add((itemIndex: null, isEn: false, code: 'blockListEmpty'));
  }
  if (arItems.length > listBlockMaxItems || enItems.length > listBlockMaxItems) {
    issues.add((itemIndex: null, isEn: false, code: 'blockListTooMany'));
  }
  for (var i = 0; i < arItems.length; i++) {
    final clean = _cleanListItem(arItems[i]);
    if (clean.isEmpty) {
      issues.add((itemIndex: i, isEn: false, code: 'blockListItemRequired'));
    } else if (clean.length > listItemMax) {
      issues.add((itemIndex: i, isEn: false, code: 'blockListItemTooLong'));
    }
  }
  for (var i = 0; i < enItems.length; i++) {
    if (_cleanListItem(enItems[i]).length > listItemMax) {
      issues.add((itemIndex: i, isEn: true, code: 'blockListItemTooLong'));
    }
  }
  if (style.isNotEmpty && !ListStyles.all.contains(style)) {
    issues.add((itemIndex: null, isEn: false, code: 'invalid'));
  }
  return issues;
}

/// One validation issue inside a [BlockTypes.details] block.
typedef DetailsBlockIssue = ({String? field, bool isEn, String code});

String _cleanDetailsText(String raw) =>
    raw.replaceAll(PageBlock.separator, '').replaceAll(PageBlock.listSeparator, '').trim();

/// Validates a [BlockTypes.details] block's summary and body against the limits
/// mirrored in `firestore.rules` (`validDetailsBlock`).
List<DetailsBlockIssue> validateDetailsBlock({
  required String summaryAr,
  required String bodyAr,
  String summaryEn = '',
  String bodyEn = '',
}) {
  final issues = <DetailsBlockIssue>[];
  final sAr = _cleanDetailsText(summaryAr);
  final bAr = _cleanDetailsText(bodyAr);
  final sEn = _cleanDetailsText(summaryEn);
  final bEn = _cleanDetailsText(bodyEn);
  if (sAr.isEmpty) {
    issues.add((field: 'summary', isEn: false, code: 'blockDetailsSummaryRequired'));
  } else if (sAr.length > detailsSummaryMax) {
    issues.add((field: 'summary', isEn: false, code: 'blockDetailsSummaryTooLong'));
  }
  if (bAr.isEmpty) {
    issues.add((field: 'body', isEn: false, code: 'blockDetailsBodyRequired'));
  } else if (bAr.length > detailsBodyMax) {
    issues.add((field: 'body', isEn: false, code: 'blockDetailsBodyTooLong'));
  }
  if (sEn.length > detailsSummaryMax) {
    issues.add((field: 'summary', isEn: true, code: 'blockDetailsSummaryTooLong'));
  }
  if (bEn.length > detailsBodyMax) {
    issues.add((field: 'body', isEn: true, code: 'blockDetailsBodyTooLong'));
  }
  return issues;
}

/// The stored image map's URL when it is set but not a usable image link
/// (e.g. an old doc saved before validation), or null when there is no
/// image or the link is fine. A bad link must block the save with a clear
/// error, never be dropped silently.
String? invalidImageUrl(Object? image) {
  if (image is! Map) return null;
  final source = image['source'];
  if (source != MediaSource.url && source != MediaSource.storage) return null;
  final url = image['url'];
  if (url is! String || url.trim().isEmpty) return null;
  return isValidImageUrl(url) ? null : url.trim();
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
  // https picture link; a heading block requires Arabic heading text; a list
  // block requires 1..20 non-blank AR items (<=200 chars), optional EN items
  // (<=200 chars), a valid style, and empty url/instapay/wallet slots; a
  // details block requires AR summary (1..200) and AR body (1..3500) plus
  // optional EN summary/body and empty url/account/instapay/wallet slots.
  final blocks = data['blocks'];
  if (blocks is List) {
    for (final raw in blocks) {
      final b = PageBlock.fromStored(raw);
      if (b != null) {
        if (b.type == BlockTypes.heading && b.textAr.trim().isEmpty) return 'blockHeadingRequired';
        if (b.type == BlockTypes.image && !b.url.startsWith('https://')) return 'blockImageUrl';
        if (b.type == BlockTypes.list) {
          if (b.url.isNotEmpty || b.instapay.isNotEmpty || b.wallet.isNotEmpty) return 'invalid';
          final rawAr = b.textAr.isEmpty ? const <String>[] : b.textAr.split(PageBlock.listSeparator);
          final rawEn = b.textEn.isEmpty ? const <String>[] : b.textEn.split(PageBlock.listSeparator);
          final issues = validateListBlock(arItems: rawAr, enItems: rawEn, style: b.account);
          if (issues.isNotEmpty) return issues.first.code;
        }
        if (b.type == BlockTypes.details) {
          if (b.url.isNotEmpty || b.account.isNotEmpty || b.instapay.isNotEmpty || b.wallet.isNotEmpty) {
            return 'invalid';
          }
          if (b.textAr.split(PageBlock.listSeparator).length != 2) return 'invalid';
          if (b.textEn.isNotEmpty && b.textEn.split(PageBlock.listSeparator).length != 2) return 'invalid';
          final d = b.details;
          final issues = validateDetailsBlock(
            summaryAr: d.summaryAr,
            bodyAr: d.bodyAr,
            summaryEn: d.summaryEn,
            bodyEn: d.bodyEn,
          );
          if (issues.isNotEmpty) return issues.first.code;
        }
      }
    }
  }
  // A cover image with a bad link blocks the save (old docs may carry one);
  // it is never dropped silently.
  if (invalidImageUrl(data['image']) != null) return 'invalidCoverImage';
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

/// Validates a scheduled notification draft per field, mapping field IDs
/// (`titleAr`, `bodyAr`, `titleEn`, `bodyEn`, `link`, `targets`, `id`) to l10n
/// error keys. Mirrors `validNotifyRow` in `firestore.rules` and
/// `parseScheduleRow` in `tool/push_sender.js`.
Map<String, String> validateScheduledNotificationFields(ScheduledNotification n) {
  bool sep(String s) => s.contains('\u001f');
  final errors = <String, String>{};
  if (n.titleAr.trim().isEmpty) {
    errors['titleAr'] = 'err_title_required';
  } else if (n.titleAr.length > 120) {
    errors['titleAr'] = 'err_title_length';
  } else if (sep(n.titleAr)) {
    errors['titleAr'] = 'err_bad_char';
  }

  if (n.bodyAr.trim().isEmpty) {
    errors['bodyAr'] = 'err_body_required';
  } else if (n.bodyAr.length > 300) {
    errors['bodyAr'] = 'err_body_length';
  } else if (sep(n.bodyAr)) {
    errors['bodyAr'] = 'err_bad_char';
  }

  if (n.titleEn.length > 120) {
    errors['titleEn'] = 'err_title_length';
  } else if (sep(n.titleEn)) {
    errors['titleEn'] = 'err_bad_char';
  }

  if (n.bodyEn.length > 300) {
    errors['bodyEn'] = 'err_body_length';
  } else if (sep(n.bodyEn)) {
    errors['bodyEn'] = 'err_bad_char';
  }

  if (!validNotificationLink(n.link)) {
    errors['link'] = 'err_bad_link';
  } else if (n.eventKey.isNotEmpty && !isValidPushEventKey(n.eventKey)) {
    errors['link'] = 'err_invalid_event_key';
  }

  if (!const ['all', 'web', 'app'].contains(n.targets)) {
    errors['targets'] = 'err_invalid_targets';
  }
  if (!RegExp(r'^[a-z0-9_-]{1,24}$').hasMatch(n.id)) {
    errors['id'] = 'err_invalid_id';
  }
  return errors;
}

/// Validates a scheduled notification draft before saving: the same limits
/// as `validNotifyRow` in firestore.rules and `parseScheduleRow` in
/// tool/push_sender.js (Arabic title AND body are required by both).
/// Returns an l10n key, or null.
String? validateScheduledNotification(ScheduledNotification n) {
  final errors = validateScheduledNotificationFields(n);
  if (errors.isEmpty) return null;
  // Preserve legacy single-key precedence across callers.
  for (final key in const [
    'err_title_required',
    'err_body_required',
    'err_title_length',
    'err_body_length',
    'err_bad_char',
  ]) {
    if (errors.values.contains(key)) return key;
  }
  return errors['link'] ?? errors['targets'] ?? errors['id'];
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
bool isValidVapidKey(String s) => s.isEmpty || RegExp(r'^[A-Za-z0-9_-]{80,100}$').hasMatch(s);

/// Formats an error for administrative error displays, surfacing structured
/// Firebase error codes (e.g. `[permission-denied]`) instead of raw/opaque strings.
String formatAdminError(Object error) {
  if (error is FirebaseException) {
    final code = error.code.trim();
    final message = (error.message ?? '').trim();
    if (code.isNotEmpty && message.isNotEmpty) {
      return '[$code] $message';
    }
    if (code.isNotEmpty) {
      return '[$code]';
    }
    if (message.isNotEmpty) {
      return message;
    }
    final plugin = error.plugin.trim();
    return plugin.isNotEmpty ? '[$plugin]' : '[firebase_error]';
  }
  return '$error';
}
