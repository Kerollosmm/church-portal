// "Today" layer of the home page (ADR-039 / ADR-040): settings/today, the
// admin's church events of the day (`dayEvents`), the daily Katameros
// commemoration published by a scheduled GitHub Action
// (`calendar/synaxarium`) and the live-stream banner. Pure Dart.

import 'cairo_time.dart';
import 'coptic_calendar.dart';
import 'coptic_feasts.dart';
import 'media.dart';
import 'features.dart' show Hideable;
import 'models.dart' show parseDate, parseHm;

String _str(Object? v) => v is String ? v : (v == null ? '' : v.toString());
bool _bool(Object? v, bool def) => v is bool ? v : def;

/// `YYYY-MM-DD` of a date-only value.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Where the Coptic date strip shows.
class CopticStripModes {
  static const all = 'all';
  static const home = 'home';
  static const off = 'off';
  static const values = [all, home, off];
}

/// `settings/today` (public read, admin write). Missing doc / key = the
/// defaults below; nothing is seeded.
class TodaySettings {
  /// Coptic date strip: on every page (default), home only, or off.
  final String copticStrip;

  /// How the liturgical day starts: at the fixed [dayStartsAt] (default,
  /// 18:00) or at sunset at the church in Alexandria.
  final String dayStartMode;

  /// Fixed start ("HH:mm") for [DayStartModes.fixed]; blank
  /// = 18:00, "00:00" = civil midnight.
  final String dayStartsAt;

  /// The "top event of the day" card on the home page.
  final bool topEvent;

  /// When no church event is set: show the day's commemoration (Katameros /
  /// the computed feast list). Off = only church events.
  final bool commemoration;

  /// Live-stream banner.
  final bool liveEnabled;
  final String liveUrl, liveLabelAr, liveLabelEn;

  /// Optional automatic switch-off instant (null = until switched off).
  final DateTime? liveEndsAt;

  const TodaySettings({
    this.copticStrip = CopticStripModes.all,
    this.dayStartMode = DayStartModes.fixed,
    this.dayStartsAt = '',
    this.topEvent = true,
    this.commemoration = true,
    this.liveEnabled = false,
    this.liveUrl = '',
    this.liveLabelAr = '',
    this.liveLabelEn = '',
    this.liveEndsAt,
  });

  static const defaults = TodaySettings();

  factory TodaySettings.fromMap(Map<String, dynamic> m) => TodaySettings(
        copticStrip: CopticStripModes.values.contains(m['copticStrip']) ? m['copticStrip'] as String : CopticStripModes.all,
        dayStartMode: DayStartModes.values.contains(m['dayStartMode']) ? m['dayStartMode'] as String : DayStartModes.fixed,
        dayStartsAt: _str(m['dayStartsAt']),
        topEvent: _bool(m['topEvent'], true),
        commemoration: _bool(m['commemoration'], true),
        liveEnabled: _bool(m['liveEnabled'], false),
        liveUrl: _str(m['liveUrl']).trim(),
        liveLabelAr: _str(m['liveLabelAr']),
        liveLabelEn: _str(m['liveLabelEn']),
        liveEndsAt: parseDate(m['liveEndsAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is TodaySettings &&
      other.copticStrip == copticStrip &&
      other.dayStartMode == dayStartMode &&
      other.dayStartsAt == dayStartsAt &&
      other.topEvent == topEvent &&
      other.commemoration == commemoration &&
      other.liveEnabled == liveEnabled &&
      other.liveUrl == liveUrl &&
      other.liveLabelAr == liveLabelAr &&
      other.liveLabelEn == liveLabelEn &&
      other.liveEndsAt == liveEndsAt;

  @override
  int get hashCode => Object.hash(copticStrip, dayStartMode, dayStartsAt, topEvent, commemoration, liveEnabled, liveUrl,
      liveLabelAr, liveLabelEn, liveEndsAt);

  /// Is a service starting at [start] on the eve of the next liturgical day
  /// (at or after the day's start, e.g. 18:00)?
  bool isEveService(DateTime start, {double? lat, double? lng}) => liturgicalDay(start, lat: lat, lng: lng).isEve;

  /// The liturgical day at [now] with these settings (church coordinates
  /// [lat] / [lng], default the church in Alexandria).
  LiturgicalDay liturgicalDay(DateTime now, {double? lat, double? lng}) =>
      liturgicalDayAt(now, mode: dayStartMode, fixedAt: dayStartsAt, lat: lat, lng: lng);

  /// Is the live banner on at [now]? Needs the switch, an http(s) link and
  /// (when set) a switch-off time still ahead.
  bool liveOn(DateTime now) =>
      liveEnabled && isLiveUrl(liveUrl) && (liveEndsAt == null || now.isBefore(liveEndsAt!));
}

final _liveUrlRe = RegExp(r'^https?://[^/\s]+\.[^/\s]+(\S*)$', caseSensitive: false);

/// A usable stream link (YouTube, Facebook or any http(s) page).
bool isLiveUrl(String url) => _liveUrlRe.hasMatch(url.trim());

/// An admin-set church event for a date (`dayEvents/{id}`), e.g. «الليلة
/// الرابعة من نهضة الشفعاء» or «بصخة ليلة الأربعاء». It takes the top of the
/// home page on its day(s).
class DayEvent implements Hideable {
  final String id;
  final String titleAr, titleEn;

  /// First day (local calendar date) and optional last day (inclusive).
  final DateTime? date, endDate;

  /// Optional "HH:mm" times; after [end] on the last day the event yields.
  final String start, end;
  final String speakerAr, speakerEn, topicAr, topicEn, noteAr, noteEn;

  /// "Details" link: in-app path or http(s) URL.
  final String link;
  final MediaImage? image;
  @override
  final bool visible;
  @override
  final int order;

  const DayEvent({
    required this.id,
    required this.titleAr,
    this.titleEn = '',
    this.date,
    this.endDate,
    this.start = '',
    this.end = '',
    this.speakerAr = '',
    this.speakerEn = '',
    this.topicAr = '',
    this.topicEn = '',
    this.noteAr = '',
    this.noteEn = '',
    this.link = '',
    this.image,
    this.visible = true,
    this.order = 0,
  });

  factory DayEvent.fromMap(String id, Map<String, dynamic> m) => DayEvent(
        id: id,
        titleAr: _str(m['titleAr']),
        titleEn: _str(m['titleEn']),
        date: parseDate(m['date']),
        endDate: parseDate(m['endDate']),
        start: _str(m['start']),
        end: _str(m['end']),
        speakerAr: _str(m['speakerAr']),
        speakerEn: _str(m['speakerEn']),
        topicAr: _str(m['topicAr']),
        topicEn: _str(m['topicEn']),
        noteAr: _str(m['noteAr']),
        noteEn: _str(m['noteEn']),
        link: _str(m['link']).trim(),
        image: MediaImage.fromMap(m['image']),
        visible: _bool(m['visible'], true),
        order: m['order'] is num ? (m['order'] as num).toInt() : 0,
      );

  /// Stored field order of one event string (U+001F separated, ADR-040).
  static const storedKeys = [
    'date', 'endDate', 'start', 'end', 'titleAr', 'titleEn', 'speakerAr', 'speakerEn', //
    'topicAr', 'topicEn', 'noteAr', 'noteEn', 'link',
  ];
  static const sep = '\u001f';

  /// Max events in `settings/features.dayEvents` (firestore.rules).
  static const maxEvents = 20;

  /// One event of `settings/features.dayEvents`: an encoded string (or,
  /// tolerantly, a map). Invalid entries return null.
  static DayEvent? fromStored(int index, Object? v) {
    Map<String, dynamic>? m;
    if (v is String) {
      final parts = v.split(sep);
      m = {for (var i = 0; i < storedKeys.length; i++) storedKeys[i]: i < parts.length ? parts[i] : ''};
      final d = DateTime.tryParse(m['date'] as String);
      if (d == null) return null;
      m['date'] = DateTime(d.year, d.month, d.day);
      final e = DateTime.tryParse(m['endDate'] as String);
      m['endDate'] = e == null ? null : DateTime(e.year, e.month, e.day);
    } else if (v is Map) {
      m = v.cast<String, dynamic>();
    }
    if (m == null) return null;
    final e = DayEvent.fromMap('e$index', {...m, 'order': index});
    return e.titleAr.trim().isEmpty || e.firstDay == null ? null : e;
  }

  static List<DayEvent> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <DayEvent>[];
    for (var i = 0; i < raw.length && out.length < maxEvents; i++) {
      final e = fromStored(i, raw[i]);
      if (e != null) out.add(e);
    }
    return out;
  }

  DateTime? get firstDay {
    final d = date;
    if (d == null) return null;
    final c = CairoTime.calendarDate(d);
    return DateTime.utc(c.year, c.month, c.day);
  }

  DateTime? get lastDay {
    final f = firstDay;
    if (f == null) return null;
    final e = endDate;
    if (e == null) return f;
    final c = CairoTime.calendarDate(e);
    final l = DateTime.utc(c.year, c.month, c.day);
    return l.isBefore(f) ? f : l;
  }

  /// Does the event cover the calendar date [day] (date-only)?
  bool covers(DateTime day) {
    final f = firstDay, l = lastDay;
    if (f == null || l == null || titleAr.trim().isEmpty) return false;
    return !day.isBefore(f) && !day.isAfter(l);
  }

  /// Has it finished at [now] on its last day ([end] passed; an end at or
  /// before [start] runs past midnight and counts as the end of the day)?
  bool endedAt(DateTime now) {
    final l = lastDay;
    if (l == null) return true;
    final s = parseHm(start), e = parseHm(end);
    var endMin = 24 * 60;
    if (e != null && (s == null || e > s)) endMin = e;
    return !now.isBefore(CairoTime.at(l.year, l.month, l.day, endMin));
  }
}

/// One day of the Katameros commemoration document.
class SynaxariumDay {
  /// Feast title (e.g. «عيد الميلاد»), empty on ordinary days.
  final String feastAr, feastEn;

  /// Synaxarium entries (commemorations) in order.
  final List<String> ar, en;

  /// Coptic date as published ("25/2/1743"), informational.
  final String coptic;

  const SynaxariumDay({this.feastAr = '', this.feastEn = '', this.ar = const [], this.en = const [], this.coptic = ''});

  static List<String> _list(Object? v) =>
      v is List ? [for (final x in v) if (x is String && x.trim().isNotEmpty) x.trim()] : const [];

  factory SynaxariumDay.fromMap(Map m) => SynaxariumDay(
        feastAr: _str(m['feastAr']).trim(),
        feastEn: _str(m['feastEn']).trim(),
        ar: _list(m['ar']),
        en: _list(m['en']),
        coptic: _str(m['coptic']),
      );

  bool get isEmpty => feastAr.isEmpty && feastEn.isEmpty && ar.isEmpty && en.isEmpty;
}

/// `calendar/synaxarium`: written only by the scheduled workflow
/// (tool/fetch_synaxarium.js) with the service account; public read.
class SynaxariumData {
  final Map<String, SynaxariumDay> days;
  final DateTime? fetchedAt;
  const SynaxariumData({this.days = const {}, this.fetchedAt});

  static const empty = SynaxariumData();

  factory SynaxariumData.fromMap(Map<String, dynamic> m) {
    final raw = m['days'];
    final days = <String, SynaxariumDay>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is Map) {
          final d = SynaxariumDay.fromMap(e.value as Map);
          if (!d.isEmpty) days[e.key as String] = d;
        }
      }
    }
    return SynaxariumData(days: days, fetchedAt: parseDate(m['fetchedAt']));
  }

  SynaxariumDay? dayOf(DateTime date) => days[dayKey(date)];
}

enum TopEventKind { church, feast, commemoration }

/// What the home page shows at the top for the day.
class TopEvent {
  final TopEventKind kind;
  final String titleAr, titleEn;

  /// Up to two further lines (e.g. the day's other commemorations).
  final List<String> linesAr, linesEn;

  /// The church event itself (speaker, topic, times, link) for [TopEventKind.church].
  final DayEvent? event;

  /// From the Katameros commemoration (/data/today.json): credit the source.
  final bool fromKatameros;

  const TopEvent({
    this.fromKatameros = false,
    required this.kind,
    required this.titleAr,
    this.titleEn = '',
    this.linesAr = const [],
    this.linesEn = const [],
    this.event,
  });
}

/// The top event at [now] (hierarchy, ADR-040):
/// 1. an admin church event covering today (not yet ended), else — on the
///    eve, after the liturgical day started — one covering the liturgical
///    day (lowest `order`, then earliest start);
/// 2. else (when [TodaySettings.commemoration]) the Katameros commemoration
///    of the liturgical day: its feast, else its first synaxarium entry;
/// 3. else the computed feast list for that day;
/// null when nothing applies or the card is switched off.
TopEvent? resolveTopEvent({
  required DateTime now,
  required TodaySettings settings,
  required Iterable<DayEvent> events,
  SynaxariumData synaxarium = SynaxariumData.empty,
  double? lat,
  double? lng,
}) {
  if (!settings.topEvent) return null;
  final day = settings.liturgicalDay(now, lat: lat, lng: lng);
  int byOrder(DayEvent a, DayEvent b) {
    final o = a.order.compareTo(b.order);
    return o != 0 ? o : (parseHm(a.start) ?? 0).compareTo(parseHm(b.start) ?? 0);
  }

  final visible = events.where((e) => e.visible).toList();
  final today = visible.where((e) => e.covers(day.civilDate) && !e.endedAt(now)).toList()..sort(byOrder);
  var pick = today.isEmpty ? null : today.first;
  if (pick == null && day.isEve) {
    final eve = visible.where((e) => e.covers(day.date)).toList()..sort(byOrder);
    if (eve.isNotEmpty) pick = eve.first;
  }
  if (pick != null) {
    return TopEvent(kind: TopEventKind.church, titleAr: pick.titleAr, titleEn: pick.titleEn, event: pick);
  }
  if (!settings.commemoration) return null;
  final s = synaxarium.dayOf(day.date);
  if (s != null) {
    if (s.feastAr.isNotEmpty || s.feastEn.isNotEmpty) {
      return TopEvent(
        fromKatameros: true,
        kind: TopEventKind.feast,
        titleAr: s.feastAr.isNotEmpty ? s.feastAr : (s.ar.isNotEmpty ? s.ar.first : ''),
        titleEn: s.feastEn,
        linesAr: s.ar.take(2).toList(),
        linesEn: s.en.take(2).toList(),
      );
    }
    if (s.ar.isNotEmpty || s.en.isNotEmpty) {
      return TopEvent(
        fromKatameros: true,
        kind: TopEventKind.commemoration,
        titleAr: s.ar.isNotEmpty ? s.ar.first : '',
        titleEn: s.en.isNotEmpty ? s.en.first : '',
        linesAr: s.ar.skip(1).take(2).toList(),
        linesEn: s.en.skip(1).take(2).toList(),
      );
    }
  }
  final feasts = copticFeastsOn(day.date);
  if (feasts.isEmpty) return null;
  return TopEvent(
    kind: TopEventKind.feast,
    titleAr: feasts.first.ar,
    titleEn: feasts.first.en,
    linesAr: [for (final f in feasts.skip(1)) f.ar],
    linesEn: [for (final f in feasts.skip(1)) f.en],
  );
}
