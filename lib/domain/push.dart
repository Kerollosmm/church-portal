// Domain logic for notification types, channels, topics, preferences, and safety (ADR-057).
// Pure Dart: no Flutter / web imports, so it is fully unit-tested.

import 'features.dart' show FeatureSettings;

/// Notification category offered to users.
enum NotifyType {
  announcements,
  // ignore: constant_identifier_names
  verse_daily,
  // ignore: constant_identifier_names
  katameros_daily,
  seasons,
  feasts,
  reminders;

  /// Arabic display label.
  String get labelAr {
    switch (this) {
      case NotifyType.announcements:
        return 'تنويهات وأخبار';
      case NotifyType.verse_daily:
        return 'آية اليوم';
      case NotifyType.katameros_daily:
        return 'قراءات القطمارس';
      case NotifyType.seasons:
        return 'مواسم وأعياد خاصة';
      case NotifyType.feasts:
        return 'أعياد وتذكارات';
      case NotifyType.reminders:
        return 'تذكيراتي';
    }
  }

  /// English display label.
  String get labelEn {
    switch (this) {
      case NotifyType.announcements:
        return 'Announcements & news';
      case NotifyType.verse_daily:
        return 'Daily verse';
      case NotifyType.katameros_daily:
        return 'Katameros readings';
      case NotifyType.seasons:
        return 'Seasons & special occasions';
      case NotifyType.feasts:
        return 'Feasts & commemorations';
      case NotifyType.reminders:
        return 'My reminders';
    }
  }

  /// Arabic one-line description.
  String get descriptionAr {
    switch (this) {
      case NotifyType.announcements:
        return 'إعلانات وتنبيهات هامة من الكنيسة';
      case NotifyType.verse_daily:
        return 'آية يومية مشجعة مع قراءات اليوم';
      case NotifyType.katameros_daily:
        return 'قراءات القداس اليومية بحسب طقس الكنيسة القبطية';
      case NotifyType.seasons:
        return 'تنبيهات مواسم الصوم وأسبوع الآلام والنهضات والمناسبات الكنسية';
      case NotifyType.feasts:
        return 'أعياد وتذكارات القديسين وشفعاء الكنيسة';
      case NotifyType.reminders:
        return 'تذكيرات للقداسات والخدمات والاجتماعات التي تختارها بنفسك';
    }
  }

  /// English one-line description.
  String get descriptionEn {
    switch (this) {
      case NotifyType.announcements:
        return 'Important church announcements & updates';
      case NotifyType.verse_daily:
        return 'Encouraging daily verse with scripture reference';
      case NotifyType.katameros_daily:
        return 'Daily Coptic liturgical readings';
      case NotifyType.seasons:
        return 'Fasting seasons, Holy Week, revivals and special church seasons';
      case NotifyType.feasts:
        return 'Feasts and commemorations of patron saints';
      case NotifyType.reminders:
        return 'Custom reminders for liturgies and meetings chosen by you';
    }
  }

  /// Identifier used for Material icon glyphs.
  String get iconKey {
    switch (this) {
      case NotifyType.announcements:
        return 'campaign_outlined';
      case NotifyType.verse_daily:
        return 'menu_book_outlined';
      case NotifyType.katameros_daily:
        return 'auto_stories_outlined';
      case NotifyType.seasons:
        return 'church_outlined';
      case NotifyType.feasts:
        return 'celebration_outlined';
      case NotifyType.reminders:
        return 'notifications_active_outlined';
    }
  }

  static NotifyType? tryParse(String? name) {
    if (name == null) return null;
    for (final t in NotifyType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Channel owner per platform.
enum PlatformOwnerChannel {
  local,
  remote,
  none,
}

/// Identifies the delivery channel owner for a notification type on the target platform.
///
/// [platform] is either 'app' (the native Android APK) or 'web' (Web browser / iPhone PWA).
PlatformOwnerChannel channelOf(NotifyType type, String platform) {
  if (platform == 'app') {
    switch (type) {
      case NotifyType.verse_daily:
      case NotifyType.katameros_daily:
      case NotifyType.feasts:
      case NotifyType.reminders:
        return PlatformOwnerChannel.local;
      case NotifyType.announcements:
      case NotifyType.seasons:
        return PlatformOwnerChannel.remote;
    }
  } else {
    // web / iPhone PWA
    switch (type) {
      case NotifyType.verse_daily:
      case NotifyType.katameros_daily:
      case NotifyType.feasts:
        // Presented on the Home page, not via Web Push.
        return PlatformOwnerChannel.none;
      case NotifyType.announcements:
      case NotifyType.seasons:
      case NotifyType.reminders:
        return PlatformOwnerChannel.remote;
    }
  }
}

/// Whether the notification type is locally managed on this platform.
bool isLocalOwned(NotifyType type, String platform) =>
    channelOf(type, platform) == PlatformOwnerChannel.local;

/// Computes the fixed FCM topic name for remote topic subscriptions.
///
/// Throws [ArgumentError] for local-owned types, unowned types, or dynamic types
/// such as [NotifyType.reminders] which require [reminderTopic].
String topicFor(NotifyType type, String lang, String platform) {
  final channel = channelOf(type, platform);
  if (channel == PlatformOwnerChannel.local || channel == PlatformOwnerChannel.none) {
    throw ArgumentError('Local-owned or unowned type has no fixed FCM topic: $type on $platform');
  }
  if (type == NotifyType.reminders) {
    throw ArgumentError('Reminders use dynamic per-event topics via reminderTopic(); not a fixed topic');
  }
  final prefix = platform == 'app' ? 'app' : 'web';
  final normalizedLang = lang.trim().toLowerCase() == 'en' ? 'en' : 'ar';
  return '${prefix}_${type.name}_$normalizedLang';
}

/// Generates the dynamic per-event topic name for user event reminders on the web.
///
/// Format:
/// - Single occurrence: `web_rem_<eventKey>_<YYYYMMDD>_<lead>_<lang>`
/// - Every time (recurring): `web_rem_<eventKey>_<lead>_<lang>`
///
/// Guaranteed to match FCM topic naming constraints: `[a-zA-Z0-9-_.~%]+`.
String reminderTopic({
  required String eventKey,
  String? occurrence,
  required int lead,
  required String lang,
  bool every = false,
}) {
  final cleanKey = eventKey.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '-');
  final normalizedLang = lang.trim().toLowerCase() == 'en' ? 'en' : 'ar';

  if (every || occurrence == null || occurrence.trim().isEmpty) {
    return 'web_rem_${cleanKey}_${lead}_$normalizedLang';
  }

  // FCM topics allow [a-zA-Z0-9-_.~%]; occurrences are ISO dates
  // (2027-04-30 -> 20270430). Anything else (slashes, ':' of a timestamp)
  // is dropped so the topic stays valid.
  final cleanOcc = occurrence.replaceAll(RegExp(r'[^a-zA-Z0-9_.~%]'), '');
  return 'web_rem_${cleanKey}_${cleanOcc}_${lead}_$normalizedLang';
}

/// Allowed lead choices in minutes before an event.
const allowedReminderLeads = [0, 5, 10, 15, 30, 60, 120, 180, 1440];

/// Admin push & notifications settings (settings/features).
class PushSettings {
  final bool enabled;
  final String vapidKey;
  final List<NotifyType> offered;
  final List<int> reminderLeads;
  final int defaultLead;

  /// Event sources that show «ذكّرني» (README §6): `lit` (liturgies and
  /// season services), `mtg` (meetings), `day` (today's events). Written by
  /// the admin from PR C; absent = all three.
  final Set<String> reminderSources;

  static const allReminderSources = {'lit', 'mtg', 'day'};

  const PushSettings({
    this.enabled = false,
    this.vapidKey = '',
    this.offered = NotifyType.values,
    this.reminderLeads = const [0, 15, 60, 1440],
    this.defaultLead = 60,
    this.reminderSources = allReminderSources,
  });

  /// Source of an [EventKey] (`lit-…` / `meeting-…` / `day-…`), else its prefix.
  static String sourceOf(String eventKey) {
    final prefix = eventKey.split('-').first;
    return switch (prefix) { 'meeting' => 'mtg', 'season' => 'lit', _ => prefix };
  }

  /// Whether «ذكّرني» is offered for [eventKey].
  bool remindsFor(String eventKey) =>
      enabled && offered.contains(NotifyType.reminders) && reminderSources.contains(sourceOf(eventKey));

  static const defaults = PushSettings();

  bool get webReady => enabled && vapidKey.trim().isNotEmpty;

  /// Whether the «فعّل الإشعارات» button may ask the browser for permission.
  /// False until a delivery path ships (PR D web push), whatever the VAPID
  /// key: asking for a permission nothing uses yet would burn the one-time
  /// browser prompt. The button stays disabled with «قريبًا» until then.
  bool get canRequestPermission => kPushDeliveryShipped && webReady;

  factory PushSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;

    final enabled = m['push'] == true;
    final rawVapid = m['pushVapidKey'];
    final vapidKey = rawVapid is String ? rawVapid.trim() : '';

    List<NotifyType> offered = List.of(NotifyType.values);
    final rawTypes = m['pushTypes'];
    if (rawTypes is List) {
      final parsed = <NotifyType>[];
      for (final e in rawTypes) {
        final t = NotifyType.tryParse(e?.toString());
        if (t != null && !parsed.contains(t)) {
          parsed.add(t);
        }
      }
      // An explicitly empty list = the admin offers none; a non-empty list
      // with nothing valid falls back to all types.
      if (parsed.isNotEmpty || rawTypes.isEmpty) {
        offered = parsed;
      }
    }

    List<int> reminderLeads = const [0, 15, 60, 1440];
    final rawLeads = m['reminderLeads'];
    if (rawLeads is List) {
      final parsed = <int>[];
      for (final e in rawLeads) {
        if (e is int && allowedReminderLeads.contains(e) && !parsed.contains(e)) {
          parsed.add(e);
        }
      }
      if (parsed.isNotEmpty && parsed.length <= 4) {
        reminderLeads = parsed;
      }
    }

    int defaultLead = 60;
    final rawDef = m['reminderDefaultLead'];
    if (rawDef is int && reminderLeads.contains(rawDef)) {
      defaultLead = rawDef;
    } else if (!reminderLeads.contains(defaultLead)) {
      defaultLead = reminderLeads.first;
    }

    // 'lit,mtg,day' (README §6) or a list; unknown values dropped; absent or
    // nothing valid = all sources.
    var reminderSources = allReminderSources;
    final rawSources = m['reminderSources'];
    final srcList = rawSources is String ? rawSources.split(',') : (rawSources is List ? rawSources : const []);
    final parsedSources = {
      for (final e in srcList)
        if (allReminderSources.contains(e?.toString().trim())) e.toString().trim(),
    };
    if (rawSources != null && (parsedSources.isNotEmpty || (rawSources is String && rawSources.trim().isEmpty) || (rawSources is List && rawSources.isEmpty))) {
      reminderSources = parsedSources;
    }

    return PushSettings(
      enabled: enabled,
      vapidKey: vapidKey,
      offered: offered,
      reminderLeads: reminderLeads,
      defaultLead: defaultLead,
      reminderSources: reminderSources,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushSettings &&
          other.enabled == enabled &&
          other.vapidKey == vapidKey &&
          _listEquals(other.offered, offered) &&
          _listEquals(other.reminderLeads, reminderLeads) &&
          other.defaultLead == defaultLead &&
          other.reminderSources.length == reminderSources.length &&
          other.reminderSources.containsAll(reminderSources);

  @override
  int get hashCode => Object.hash(
        enabled,
        vapidKey,
        Object.hashAll(offered),
        Object.hashAll(reminderLeads),
        Object.hashAllUnordered(reminderSources),
        defaultLead,
      );
}

/// Flipped to `true` by PR D (web push delivery). Until then no permission
/// prompt is shown (ADR-057).
const bool kPushDeliveryShipped = false;

/// Visitor's quiet hours specification. Stored with the visitor's prefs so
/// PR B / PR D can honour it; there is no quiet-hours UI in PR A (plan: it
/// needs a delivery path).
class QuietHours {
  final String from;
  final String to;

  const QuietHours({this.from = '22:00', this.to = '07:00'});

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  factory QuietHours.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const QuietHours();
    final f = m['from'] is String ? m['from'] as String : '22:00';
    final t = m['to'] is String ? m['to'] as String : '07:00';
    return QuietHours(from: f, to: t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuietHours && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Built-in defaults for notification scheduling (PR B / ADR-058 §5).
class NotifyTypeConfig {
  NotifyTypeConfig._();

  static const defaultVerseTime = '07:00';
  static const defaultKatamerosTime = '06:30';
  static const defaultFeastsTime = '07:30';
}

/// Device-stored push notification preferences (`church_portal_push`).
class PushPrefs {
  final Set<NotifyType> types;
  final String lang;
  final QuietHours quiet;
  final DateTime updatedAt;
  final String? verseTime;
  final String? katamerosTime;
  final bool quietHoursEnabled;
  final bool remindersRespectQuietHours;

  static const defaultTypes = <NotifyType>{};
  static const firstOptInTypes = {
    NotifyType.announcements,
    NotifyType.seasons,
    NotifyType.reminders,
  };

  const PushPrefs({
    this.types = defaultTypes,
    this.lang = 'ar',
    this.quiet = const QuietHours(),
    required this.updatedAt,
    this.verseTime,
    this.katamerosTime,
    this.quietHoursEnabled = true,
    this.remindersRespectQuietHours = false,
  });

  Map<String, dynamic> toJson() => {
        'types': types.map((t) => t.name).toList(),
        'lang': lang,
        'quiet': quiet.toJson(),
        'updatedAt': updatedAt.toIso8601String(),
        if (verseTime != null) 'verseTime': verseTime,
        if (katamerosTime != null) 'katamerosTime': katamerosTime,
        'quietHoursEnabled': quietHoursEnabled,
        'remindersRespectQuietHours': remindersRespectQuietHours,
      };

  factory PushPrefs.fromJson(Map<String, dynamic>? json, {List<NotifyType>? offered}) {
    if (json == null || json.isEmpty) {
      return PushPrefs(updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    }

    final rawTypes = json['types'];
    final parsedTypes = <NotifyType>{};
    if (rawTypes is List) {
      for (final item in rawTypes) {
        final t = NotifyType.tryParse(item?.toString());
        if (t != null) {
          if (offered == null || offered.contains(t)) {
            parsedTypes.add(t);
          }
        }
      }
    }

    final lang = json['lang'] == 'en' ? 'en' : 'ar';
    final quiet = json['quiet'] is Map
        ? QuietHours.fromJson(Map<String, dynamic>.from(json['quiet'] as Map))
        : const QuietHours();

    DateTime updatedAt;
    try {
      final rawDate = json['updatedAt'];
      updatedAt = rawDate is String
          ? DateTime.parse(rawDate)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    } catch (_) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final verseTime = json['verseTime'] is String ? json['verseTime'] as String : null;
    final katamerosTime = json['katamerosTime'] is String ? json['katamerosTime'] as String : null;
    final quietHoursEnabled = json['quietHoursEnabled'] is bool ? json['quietHoursEnabled'] as bool : true;
    final remindersRespectQuietHours = json['remindersRespectQuietHours'] == true;

    return PushPrefs(
      types: parsedTypes,
      lang: lang,
      quiet: quiet,
      updatedAt: updatedAt,
      verseTime: verseTime,
      katamerosTime: katamerosTime,
      quietHoursEnabled: quietHoursEnabled,
      remindersRespectQuietHours: remindersRespectQuietHours,
    );
  }

  PushPrefs copyWith({
    Set<NotifyType>? types,
    String? lang,
    QuietHours? quiet,
    DateTime? updatedAt,
    String? verseTime,
    String? katamerosTime,
    bool? quietHoursEnabled,
    bool? remindersRespectQuietHours,
  }) {
    return PushPrefs(
      types: types ?? this.types,
      lang: lang ?? this.lang,
      quiet: quiet ?? this.quiet,
      updatedAt: updatedAt ?? this.updatedAt,
      verseTime: verseTime ?? this.verseTime,
      katamerosTime: katamerosTime ?? this.katamerosTime,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      remindersRespectQuietHours: remindersRespectQuietHours ?? this.remindersRespectQuietHours,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushPrefs &&
          _setEquals(other.types, types) &&
          other.lang == lang &&
          other.quiet == quiet &&
          other.updatedAt == updatedAt &&
          other.verseTime == verseTime &&
          other.katamerosTime == katamerosTime &&
          other.quietHoursEnabled == quietHoursEnabled &&
          other.remindersRespectQuietHours == remindersRespectQuietHours;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(types),
        lang,
        quiet,
        updatedAt,
        verseTime,
        katamerosTime,
        quietHoursEnabled,
        remindersRespectQuietHours,
      );
}

/// Browser / device permission state for push notifications.
enum PushPermissionState {
  /// Not supported (no ServiceWorker / PushManager / Notification API).
  unsupported,

  /// iOS device not yet running as standalone PWA.
  iosNeedsInstall,

  /// iOS standalone PWA but version < 16.4.
  iosTooOld,

  /// In-app browser (e.g. Facebook, Instagram, WhatsApp) unable to install or push.
  inAppBrowser,

  /// Supported and promptable.
  defaultState,

  /// Permission granted.
  granted,

  /// Permission denied / blocked.
  denied,
}

/// Sanitizes deep links received from notifications.
///
/// Allows relative in-app paths starting with `/`.
/// Defends against open redirects, external protocols (`javascript:`, `https:`),
/// scheme-relative `//` URLs, or malformed strings by returning `/`.
String safeNotificationLink(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '/';
  final trimmed = raw.trim();

  // Reject scheme-relative or protocol URIs
  if (trimmed.startsWith('//') || trimmed.contains(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:'))) {
    return '/';
  }

  // Must begin with single /
  if (trimmed.startsWith('/')) {
    return trimmed;
  }

  return '/';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

/// Specification for a notification category including templates and defaults.
class NotifyTypeSpec {
  final NotifyType type;
  final String time;
  final int daysBefore;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String defaultLink;
  final List<String> allowedPlaceholders;

  const NotifyTypeSpec({
    required this.type,
    this.time = '',
    this.daysBefore = 0,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.defaultLink,
    required this.allowedPlaceholders,
  });

  static const builtInDefaults = <NotifyType, NotifyTypeSpec>{
    NotifyType.announcements: NotifyTypeSpec(
      type: NotifyType.announcements,
      time: '',
      daysBefore: 0,
      titleAr: '{event}',
      titleEn: '{event}',
      bodyAr: '{lead}',
      bodyEn: '{lead}',
      defaultLink: '/',
      allowedPlaceholders: ['{event}', '{time}', '{place}', '{lead}', '{date}'],
    ),
    NotifyType.verse_daily: NotifyTypeSpec(
      type: NotifyType.verse_daily,
      time: '07:00',
      daysBefore: 0,
      titleAr: 'آية اليوم',
      titleEn: 'Daily Verse',
      bodyAr: '{verse}\n({ref})',
      bodyEn: '{verse}\n({ref})',
      defaultLink: '/',
      allowedPlaceholders: ['{verse}', '{ref}'],
    ),
    NotifyType.katameros_daily: NotifyTypeSpec(
      type: NotifyType.katameros_daily,
      time: '06:30',
      daysBefore: 0,
      titleAr: 'قراءات اليوم',
      titleEn: 'Daily Readings',
      bodyAr: '{reading}',
      bodyEn: '{reading}',
      defaultLink: '/today',
      allowedPlaceholders: ['{reading}'],
    ),
    NotifyType.seasons: NotifyTypeSpec(
      type: NotifyType.seasons,
      time: '20:00',
      daysBefore: 3,
      titleAr: 'موسم {season}',
      titleEn: '{season} Season',
      bodyAr: 'يبدأ خلال {days} أيام',
      bodyEn: 'Begins in {days} days',
      defaultLink: '/seasons',
      allowedPlaceholders: ['{season}', '{days}'],
    ),
    NotifyType.feasts: NotifyTypeSpec(
      type: NotifyType.feasts,
      time: '07:30',
      daysBefore: 0,
      titleAr: 'عيد اليوم: {feast}',
      titleEn: "Today's Feast: {feast}",
      bodyAr: 'بركة شفاعته تشملنا',
      bodyEn: 'May their prayers be with us',
      defaultLink: '/',
      allowedPlaceholders: ['{feast}'],
    ),
    NotifyType.reminders: NotifyTypeSpec(
      type: NotifyType.reminders,
      time: '',
      daysBefore: 0,
      titleAr: 'تذكير: {event}',
      titleEn: 'Reminder: {event}',
      bodyAr: 'يبدأ الساعة {time} {place}',
      bodyEn: 'Starts at {time} {place}',
      defaultLink: '/mass-schedule',
      allowedPlaceholders: ['{event}', '{time}', '{place}', '{lead}', '{date}'],
    ),
  };
}

/// Admin configuration parsed from settings/features.
class NotifyConfig {
  final Map<NotifyType, NotifyTypeSpec> specs;
  final Set<String> reminderSources;

  const NotifyConfig({
    required this.specs,
    this.reminderSources = PushSettings.allReminderSources,
  });

  NotifyTypeSpec specFor(NotifyType type) => specs[type] ?? NotifyTypeSpec.builtInDefaults[type]!;

  factory NotifyConfig.fromFeatures(FeatureSettings f) {
    final parsedSpecs = Map<NotifyType, NotifyTypeSpec>.from(NotifyTypeSpec.builtInDefaults);
    for (final row in f.notifyTypes) {
      final parts = row.split('\u001f');
      if (parts.isEmpty) continue;
      final type = NotifyType.tryParse(parts[0]);
      if (type == null) continue;
      final def = NotifyTypeSpec.builtInDefaults[type]!;
      final time = parts.length > 1 && parts[1].trim().isNotEmpty ? parts[1].trim() : def.time;
      final daysBefore = parts.length > 2 && parts[2].trim().isNotEmpty
          ? (int.tryParse(parts[2].trim()) ?? def.daysBefore)
          : def.daysBefore;
      final titleAr = parts.length > 3 && parts[3].trim().isNotEmpty ? parts[3].trim() : def.titleAr;
      final titleEn = parts.length > 4 && parts[4].trim().isNotEmpty ? parts[4].trim() : def.titleEn;
      final bodyAr = parts.length > 5 && parts[5].trim().isNotEmpty ? parts[5].trim() : def.bodyAr;
      final bodyEn = parts.length > 6 && parts[6].trim().isNotEmpty ? parts[6].trim() : def.bodyEn;

      parsedSpecs[type] = NotifyTypeSpec(
        type: type,
        time: time,
        daysBefore: daysBefore,
        titleAr: titleAr,
        titleEn: titleEn,
        bodyAr: bodyAr,
        bodyEn: bodyEn,
        defaultLink: def.defaultLink,
        allowedPlaceholders: def.allowedPlaceholders,
      );
    }

    final rawSources = f.reminderSources.trim();
    final sources = rawSources.isEmpty
        ? <String>{}
        : rawSources.split(',').map((s) => s.trim()).where(PushSettings.allReminderSources.contains).toSet();

    return NotifyConfig(
      specs: parsedSpecs,
      reminderSources: sources.isEmpty && rawSources.isEmpty ? <String>{} : (sources.isEmpty ? PushSettings.allReminderSources : sources),
    );
  }

  bool isReminderSourceEnabled(String eventKey) {
    final prefix = eventKey.split('-').first;
    final source = switch (prefix) {
      'meeting' || 'mtg' => 'mtg',
      'season' || 'lit' => 'lit',
      'day' => 'day',
      _ => prefix,
    };
    return reminderSources.contains(source);
  }
}

/// Renders a template string by replacing `{key}` with values from [vars].
String renderTemplate(String template, Map<String, String> vars) {
  var result = template;
  vars.forEach((k, v) {
    final key = k.startsWith('{') && k.endsWith('}') ? k : '{$k}';
    result = result.replaceAll(key, v);
  });
  return result;
}

/// Returns a list of placeholders in [text] that are not allowed for [typeId].
List<String> unknownPlaceholders(String typeId, String text) {
  final type = NotifyType.tryParse(typeId);
  final allowed = type != null
      ? (NotifyTypeSpec.builtInDefaults[type]?.allowedPlaceholders ?? const [])
      : const <String>[];
  final matches = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(text);
  final unknown = <String>[];
  for (final m in matches) {
    final ph = m.group(0)!;
    if (!allowed.contains(ph) && !unknown.contains(ph)) {
      unknown.add(ph);
    }
  }
  return unknown;
}

/// One scheduled event push entry in settings/notifications.schedule.
class ScheduledNotification {
  final String id;
  final DateTime atUtc;
  final String targets; // 'all', 'web', 'app'
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String link;
  final String eventKey;

  static const sep = '\u001f';

  const ScheduledNotification({
    required this.id,
    required this.atUtc,
    this.targets = 'all',
    required this.titleAr,
    this.titleEn = '',
    required this.bodyAr,
    this.bodyEn = '',
    this.link = '/',
    this.eventKey = '',
  });

  String toRow() {
    final iso = atUtc.toUtc().toIso8601String();
    return [
      id,
      iso,
      targets,
      titleAr,
      titleEn,
      bodyAr,
      bodyEn,
      link,
      eventKey,
    ].join(sep);
  }

  static ScheduledNotification? fromRow(String row) {
    final parts = row.split(sep);
    if (parts.length < 9) return null;
    final id = parts[0].trim();
    final atUtc = DateTime.tryParse(parts[1].trim())?.toUtc();
    if (id.isEmpty || atUtc == null) return null;
    final targets = parts[2].trim();
    final titleAr = parts[3];
    final titleEn = parts[4];
    final bodyAr = parts[5];
    final bodyEn = parts[6];
    final link = safeNotificationLink(parts[7]);
    final eventKey = parts[8].trim();

    return ScheduledNotification(
      id: id,
      atUtc: atUtc,
      targets: targets.isEmpty ? 'all' : targets,
      titleAr: titleAr,
      titleEn: titleEn,
      bodyAr: bodyAr,
      bodyEn: bodyEn,
      link: link,
      eventKey: eventKey,
    );
  }
}

/// Per-platform send state for a scheduled notification row.
class TopicSendState {
  final String state; // 'ok', 'partial', 'error', 'unconfirmed'
  final String? fcmMessageId;
  final String? error;

  const TopicSendState({
    required this.state,
    this.fcmMessageId,
    this.error,
  });

  factory TopicSendState.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const TopicSendState(state: 'pending');
    return TopicSendState(
      state: m['state']?.toString() ?? 'pending',
      fcmMessageId: m['fcmMessageId']?.toString(),
      error: m['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'state': state,
    if (fcmMessageId != null) 'fcmMessageId': fcmMessageId,
    if (error != null) 'error': error,
  };
}

/// Status of a scheduled notification row.
class RowSendStatus {
  final String state; // 'pending', 'sending', 'ok', 'partial', 'error', 'unconfirmed', 'expired'
  final DateTime? claimedAt;
  final String? claimedBy;
  final TopicSendState? web;
  final TopicSendState? app;
  final String? lastError;
  final int retryCount;

  const RowSendStatus({
    required this.state,
    this.claimedAt,
    this.claimedBy,
    this.web,
    this.app,
    this.lastError,
    this.retryCount = 0,
  });

  factory RowSendStatus.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RowSendStatus(state: 'pending');
    DateTime? claimed;
    if (m['claimedAt'] is String) {
      claimed = DateTime.tryParse(m['claimedAt'] as String);
    }
    return RowSendStatus(
      state: m['state']?.toString() ?? 'pending',
      claimedAt: claimed,
      claimedBy: m['claimedBy']?.toString(),
      web: m['web'] is Map ? TopicSendState.fromMap(Map<String, dynamic>.from(m['web'] as Map)) : null,
      app: m['app'] is Map ? TopicSendState.fromMap(Map<String, dynamic>.from(m['app'] as Map)) : null,
      lastError: m['lastError']?.toString(),
      retryCount: m['retryCount'] is num ? (m['retryCount'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'state': state,
    if (claimedAt != null) 'claimedAt': claimedAt!.toUtc().toIso8601String(),
    if (claimedBy != null) 'claimedBy': claimedBy,
    if (web != null) 'web': web!.toMap(),
    if (app != null) 'app': app!.toMap(),
    if (lastError != null) 'lastError': lastError,
    if (retryCount > 0) 'retryCount': retryCount,
  };
}

/// Logged sent entry in settings/notifications.sentLog.
class SentEntry {
  final String id;
  final DateTime sentAt;
  final String titleAr;
  final String titleEn;
  final String targets;
  final String webState;
  final String appState;
  final String eventKey;
  final String link;

  const SentEntry({
    required this.id,
    required this.sentAt,
    required this.titleAr,
    this.titleEn = '',
    this.targets = 'all',
    this.webState = '',
    this.appState = '',
    this.eventKey = '',
    this.link = '/',
  });

  factory SentEntry.fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      return SentEntry(id: '', sentAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), titleAr: '');
    }
    DateTime sent;
    try {
      sent = m['sentAt'] is String
          ? DateTime.parse(m['sentAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    } catch (_) {
      sent = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return SentEntry(
      id: m['id']?.toString() ?? '',
      sentAt: sent,
      titleAr: m['titleAr']?.toString() ?? '',
      titleEn: m['titleEn']?.toString() ?? '',
      targets: m['targets']?.toString() ?? 'all',
      webState: m['webState']?.toString() ?? '',
      appState: m['appState']?.toString() ?? '',
      eventKey: m['eventKey']?.toString() ?? '',
      link: safeNotificationLink(m['link']?.toString()),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'titleAr': titleAr,
    'titleEn': titleEn,
    'targets': targets,
    'webState': webState,
    'appState': appState,
    'eventKey': eventKey,
    'link': link,
  };
}

/// Hourly health stamp written by the push sender.
class SenderHealth {
  final DateTime? lastRunAt;
  final String status; // 'ok', 'error', 'degraded'
  final String? lastError;
  final int subrequestsUsed;
  final int fcmSentCount;

  const SenderHealth({
    this.lastRunAt,
    this.status = 'ok',
    this.lastError,
    this.subrequestsUsed = 0,
    this.fcmSentCount = 0,
  });

  factory SenderHealth.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const SenderHealth();
    DateTime? lastRun;
    if (m['lastRunAt'] is String) {
      lastRun = DateTime.tryParse(m['lastRunAt'] as String);
    }
    return SenderHealth(
      lastRunAt: lastRun,
      status: m['status']?.toString() ?? 'ok',
      lastError: m['lastError']?.toString(),
      subrequestsUsed: m['subrequestsUsed'] is num ? (m['subrequestsUsed'] as num).toInt() : 0,
      fcmSentCount: m['fcmSentCount'] is num ? (m['fcmSentCount'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() => {
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toUtc().toIso8601String(),
    'status': status,
    if (lastError != null) 'lastError': lastError,
    'subrequestsUsed': subrequestsUsed,
    'fcmSentCount': fcmSentCount,
  };
}

/// In-memory representation of settings/notifications doc.
class NotifySchedule {
  final List<ScheduledNotification> schedule;
  final Map<String, RowSendStatus> status;
  final List<SentEntry> sentLog;
  final SenderHealth health;
  final DateTime? updatedAt;
  final String? updatedBy;

  const NotifySchedule({
    this.schedule = const [],
    this.status = const {},
    this.sentLog = const [],
    this.health = const SenderHealth(),
    this.updatedAt,
    this.updatedBy,
  });

  factory NotifySchedule.fromDoc(Map<String, dynamic>? doc) {
    if (doc == null || doc.isEmpty) return const NotifySchedule();
    final rawSchedule = doc['schedule'];
    final schedule = <ScheduledNotification>[];
    if (rawSchedule is List) {
      for (final r in rawSchedule) {
        if (r is String) {
          final s = ScheduledNotification.fromRow(r);
          if (s != null) schedule.add(s);
        }
      }
    }

    final rawStatus = doc['status'];
    final status = <String, RowSendStatus>{};
    if (rawStatus is Map) {
      rawStatus.forEach((k, v) {
        if (v is Map) {
          status[k.toString()] = RowSendStatus.fromMap(Map<String, dynamic>.from(v));
        }
      });
    }

    final rawSentLog = doc['sentLog'];
    final sentLog = <SentEntry>[];
    if (rawSentLog is List) {
      for (final entry in rawSentLog) {
        if (entry is Map) {
          sentLog.add(SentEntry.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    }

    final health = SenderHealth.fromMap(doc['health'] is Map ? Map<String, dynamic>.from(doc['health'] as Map) : null);

    DateTime? updatedAt;
    if (doc['updatedAt'] is String) {
      updatedAt = DateTime.tryParse(doc['updatedAt'] as String);
    }

    return NotifySchedule(
      schedule: schedule,
      status: status,
      sentLog: sentLog,
      health: health,
      updatedAt: updatedAt,
      updatedBy: doc['updatedBy']?.toString(),
    );
  }

  bool isExpiredAt(String id, DateTime nowUtc) {
    final row = schedule.where((r) => r.id == id).firstOrNull;
    if (row == null) return false;
    final rowStatus = status[id]?.state;
    if (rowStatus == 'ok') return false;
    return nowUtc.difference(row.atUtc) > const Duration(hours: 24);
  }

  List<ScheduledNotification> dueNow(DateTime nowUtc) {
    final list = <ScheduledNotification>[];
    for (final r in schedule) {
      if (r.atUtc.isAfter(nowUtc)) continue;
      if (isExpiredAt(r.id, nowUtc)) continue;
      final st = status[r.id]?.state;
      if (st == 'ok' || st == 'sending') continue;
      list.add(r);
    }
    return list;
  }

  bool canDeleteRow(String id) {
    final st = status[id]?.state;
    return st != 'sending';
  }

  ScheduledNotification cloneDraftForRetry(ScheduledNotification src, String newId, DateTime defaultAtUtc) {
    final st = status[src.id];
    var targets = src.targets;
    if (st != null) {
      if (st.web?.state == 'ok' && st.app?.state != 'ok') {
        targets = 'app';
      } else if (st.app?.state == 'ok' && st.web?.state != 'ok') {
        targets = 'web';
      }
    }
    return ScheduledNotification(
      id: newId,
      atUtc: defaultAtUtc,
      targets: targets,
      titleAr: src.titleAr,
      titleEn: src.titleEn,
      bodyAr: src.bodyAr,
      bodyEn: src.bodyEn,
      link: src.link,
      eventKey: src.eventKey,
    );
  }
}

