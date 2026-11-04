// Programme details of services, meetings and seasons (ADR-041): speaker,
// topic, choir, venue (hall), target audience and a PDF link (Google Drive
// or any https page — no upload, owner 4 Nov 2026). Venues and audiences
// are admin-defined lists in settings/features (defaults below). Pure Dart.

String _str(Object? v) => v is String ? v.trim() : '';

/// One admin-defined choice (a venue or an audience).
class ProgramOption {
  final String key, labelAr, labelEn;
  const ProgramOption(this.key, this.labelAr, this.labelEn);

  static final keyRe = RegExp(r'^[a-z0-9_-]{1,30}$');
  static const sep = '\u001f';

  /// Stored as `key␟labelAr␟labelEn`.
  static ProgramOption? fromStored(Object? v) {
    if (v is! String) return null;
    final p = v.split(sep);
    if (p.length < 2 || !keyRe.hasMatch(p[0]) || p[1].trim().isEmpty) return null;
    return ProgramOption(p[0], p[1].trim(), p.length > 2 ? p[2].trim() : '');
  }

  String encode() => [key, labelAr, labelEn].join(sep);

  @override
  bool operator ==(Object other) =>
      other is ProgramOption && other.key == key && other.labelAr == labelAr && other.labelEn == labelEn;

  @override
  int get hashCode => Object.hash(key, labelAr, labelEn);
}

/// `settings/features.venues` / `.audiences` (≤ 12 each). Missing / empty
/// list = the defaults, so a fresh site already offers the usual choices.
class ProgramOptions {
  static const max = 12;

  static const defaultVenues = [
    ProgramOption('main', 'الكنيسة الكبرى', 'Main church'),
    ProgramOption('lower', 'القاعة السفلية', 'Lower hall'),
    ProgramOption('services', 'مبنى الخدمات', 'Services building'),
  ];
  static const defaultAudiences = [
    ProgramOption('general', 'عام', 'Everyone'),
    ProgramOption('youth', 'شباب', 'Youth'),
    ProgramOption('children', 'أطفال', 'Children'),
  ];

  final List<ProgramOption> venues, audiences;
  const ProgramOptions({this.venues = defaultVenues, this.audiences = defaultAudiences});

  static const defaults = ProgramOptions();

  static List<ProgramOption> _list(Object? raw, List<ProgramOption> fallback) {
    if (raw is! List) return fallback;
    final out = <ProgramOption>[];
    final seen = <String>{};
    for (final v in raw) {
      final o = ProgramOption.fromStored(v);
      if (o != null && seen.add(o.key) && out.length < max) out.add(o);
    }
    return out.isEmpty ? fallback : out;
  }

  factory ProgramOptions.fromMap(Map<String, dynamic> m) => ProgramOptions(
        venues: _list(m['venues'], defaultVenues),
        audiences: _list(m['audiences'], defaultAudiences),
      );

  /// The venue / audience named [key]: the admin list first, then the
  /// built-in defaults, so an item saved with a default key (main, youth…)
  /// keeps its label after the admin replaces the list (Sentry review).
  ProgramOption? venue(String key) => _find(venues, key) ?? _find(defaultVenues, key);
  ProgramOption? audience(String key) => _find(audiences, key) ?? _find(defaultAudiences, key);

  /// [list] followed by the options of [keys] it does not hold (resolved
  /// through [find]), for chips / dropdowns that must show every used key.
  static List<ProgramOption> withUsed(
      List<ProgramOption> list, Iterable<String> keys, ProgramOption? Function(String) find) {
    final out = [...list];
    for (final k in keys) {
      if (out.any((o) => o.key == k)) continue;
      final o = find(k);
      if (o != null) out.add(o);
    }
    return out;
  }

  static ProgramOption? _find(List<ProgramOption> l, String key) {
    if (key.isEmpty) return null;
    for (final o in l) {
      if (o.key == key) return o;
    }
    return null;
  }
}

final _httpsRe = RegExp(r'^https://[^/\s]+\.[^/\s]+(\S*)$', caseSensitive: false);

/// The optional programme details of a liturgy, meeting or season. All keys
/// are optional; missing = '' (nothing shown, exactly as before).
class ProgramInfo {
  final String speakerAr, speakerEn, topicAr, topicEn, choirAr, choirEn;

  /// Keys of [ProgramOptions.venues] / [ProgramOptions.audiences] ('' = none).
  final String venue, audience;

  /// PDF / programme / prayer booklet link (Google Drive or any https URL).
  final String attachmentUrl, attachmentLabelAr, attachmentLabelEn;

  const ProgramInfo({
    this.speakerAr = '',
    this.speakerEn = '',
    this.topicAr = '',
    this.topicEn = '',
    this.choirAr = '',
    this.choirEn = '',
    this.venue = '',
    this.audience = '',
    this.attachmentUrl = '',
    this.attachmentLabelAr = '',
    this.attachmentLabelEn = '',
  });

  static const none = ProgramInfo();

  /// Stored keys (shared allow-list `programKeys()` in firestore.rules).
  static const keys = [
    'speakerAr', 'speakerEn', 'topicAr', 'topicEn', 'choirAr', 'choirEn', 'venue', 'audience', //
    'attachmentUrl', 'attachmentLabelAr', 'attachmentLabelEn',
  ];

  factory ProgramInfo.fromMap(Map<String, dynamic> m) {
    final url = _str(m['attachmentUrl']);
    return ProgramInfo(
      speakerAr: _str(m['speakerAr']),
      speakerEn: _str(m['speakerEn']),
      topicAr: _str(m['topicAr']),
      topicEn: _str(m['topicEn']),
      choirAr: _str(m['choirAr']),
      choirEn: _str(m['choirEn']),
      venue: ProgramOption.keyRe.hasMatch(_str(m['venue'])) ? _str(m['venue']) : '',
      audience: ProgramOption.keyRe.hasMatch(_str(m['audience'])) ? _str(m['audience']) : '',
      attachmentUrl: _httpsRe.hasMatch(url) ? url : '',
      attachmentLabelAr: _str(m['attachmentLabelAr']),
      attachmentLabelEn: _str(m['attachmentLabelEn']),
    );
  }

  bool get hasAttachment => attachmentUrl.isNotEmpty;

  bool get isEmpty =>
      speakerAr.isEmpty &&
      speakerEn.isEmpty &&
      topicAr.isEmpty &&
      topicEn.isEmpty &&
      choirAr.isEmpty &&
      choirEn.isEmpty &&
      venue.isEmpty &&
      audience.isEmpty &&
      attachmentUrl.isEmpty;
}
