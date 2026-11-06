// Season preset (ADR-042): the owner's pre-season checklist (SOP, owner plan
// §4) as ONE explicit, reversible action in /admin → «تجهيز الموسم».
//
// Apply writes the chosen changes AND a snapshot of the values they replace
// into `settings/features.seasonPreset`; «استرجاع الإعدادات السابقة» writes
// the snapshot back. When the season ends, every visitor's app already reads
// the snapshot values for the switches the preset turned off (see
// [FeatureSettings.effectiveAt]), so the site returns to normal at the end of
// the season with no write and no Cloud Function; the admin dashboard then
// offers the restore button to make the stored values match. Pure Dart.

import 'cairo_time.dart';
import 'models.dart' show Liturgy, Season;
import 'schedule.dart' show occurrencesForDay;
import 'season_keys.dart';

DateTime? _date(Object? v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  // Firestore Timestamp without importing cloud_firestore.
  try {
    final d = (v as dynamic)?.toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

/// The checklist items an admin can tick.
class PresetOption {
  PresetOption._();

  /// The season's services replace the regular weekly schedule
  /// (`seasons/{id}.replacesRegular` = true).
  static const replaceRegular = 'replaceRegular';

  /// Hide the meetings section (`sections.meetings` = false).
  static const hideMeetings = 'hideMeetings';

  /// Hide the clinics section (`sections.clinics` = false).
  static const hideClinics = 'hideClinics';

  /// Hero motion and video off (`heroMotion` = false).
  static const heroMotionOff = 'heroMotionOff';

  /// The wedding choice of hall-booking requests is hidden on the contact
  /// form (`weddingBookingOff` = true).
  static const weddingOff = 'weddingOff';

  /// Live-stream link (`liveUrl`, `liveEndsAt` = season end). The banner
  /// itself is still switched on by hand when the prayers start.
  static const live = 'live';

  /// Season programme PDF / Drive link (`seasons/{id}.attachmentUrl`).
  static const pdf = 'pdf';

  /// Pick the season's occasion theme by hand (`theme` = the season key's
  /// theme, ADR-043). Only needed when «اتّباع الموسم» is off: with it on,
  /// the theme already follows the active season.
  static const theme = 'theme';

  static const all = [replaceRegular, hideMeetings, hideClinics, heroMotionOff, weddingOff, live, pdf, theme];
}

/// Keys of [SeasonPreset.previous] (mirrored by firestore.rules
/// validSeasonPreset).
class PresetPrev {
  PresetPrev._();
  static const seasonActive = 'seasonActive';
  static const replacesRegular = 'replacesRegular';
  static const meetings = 'meetings';
  static const clinics = 'clinics';
  static const heroMotion = 'heroMotion';
  static const weddingBookingOff = 'weddingBookingOff';
  static const liveUrl = 'liveUrl';
  static const liveEndsAt = 'liveEndsAt';
  static const attachmentUrl = 'attachmentUrl';
  static const attachmentLabelAr = 'attachmentLabelAr';
  static const attachmentLabelEn = 'attachmentLabelEn';

  /// The stored `settings/features.theme` before the preset (ADR-043).
  static const theme = 'theme';
  static const all = [
    seasonActive, replacesRegular, meetings, clinics, heroMotion, weddingBookingOff, liveUrl, liveEndsAt, //
    attachmentUrl, attachmentLabelAr, attachmentLabelEn, theme,
  ];
}

/// `settings/features.seasonPreset` (null / missing = no preset applied).
class SeasonPreset {
  /// `seasons/{seasonId}` the preset was applied for.
  final String seasonId;

  /// The season's key (holy_week, revival_moses…), for labels.
  final String seasonKey;

  final DateTime? appliedAt;

  /// The season's start when applied (ADR-043; older presets: none). Lets
  /// the theme follow the season from the first paint, before the seasons
  /// list has loaded.
  final DateTime? startsAt;

  /// The season's end when applied; null = until restored by hand.
  final DateTime? endsAt;

  /// Ticked [PresetOption]s.
  final List<String> options;

  /// Values replaced by the apply, keyed by [PresetPrev] (bool / String /
  /// DateTime / null).
  final Map<String, Object?> previous;

  const SeasonPreset({
    required this.seasonId,
    this.seasonKey = '',
    this.appliedAt,
    this.startsAt,
    this.endsAt,
    this.options = const [],
    this.previous = const {},
  });

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

  static SeasonPreset? fromMap(Object? v) {
    if (v is! Map) return null;
    final id = v['seasonId'];
    if (id is! String || !_idRe.hasMatch(id)) return null;
    final opts = v['options'];
    final prev = v['previous'];
    return SeasonPreset(
      seasonId: id,
      seasonKey: v['seasonKey'] is String ? v['seasonKey'] as String : '',
      appliedAt: _date(v['appliedAt']),
      startsAt: _date(v['startsAt']),
      endsAt: _date(v['endsAt']),
      options: opts is List ? [for (final o in opts) if (o is String && PresetOption.all.contains(o)) o] : const [],
      previous: prev is Map
          ? {
              for (final e in prev.entries)
                if (PresetPrev.all.contains(e.key))
                  e.key as String: e.key == PresetPrev.liveEndsAt ? _date(e.value) : e.value,
            }
          : const {},
    );
  }

  Map<String, dynamic> toMap() => {
        'seasonId': seasonId,
        'seasonKey': seasonKey,
        'appliedAt': appliedAt,
        if (startsAt != null) 'startsAt': startsAt,
        'endsAt': endsAt,
        'options': options,
        'previous': previous,
      };

  bool has(String option) => options.contains(option);

  /// The season is over: visitors read the [previous] values again.
  bool expiredAt(DateTime instant) => endsAt != null && !instant.isBefore(endsAt!);

  /// The preset's season is running at [instant] (from its start, or from
  /// the apply when the preset predates ADR-043, until its end).
  bool seasonRunningAt(DateTime instant) {
    final from = startsAt ?? appliedAt;
    if (from != null && instant.isBefore(from)) return false;
    return !expiredAt(instant);
  }

  bool? prevBool(String key) => previous[key] is bool ? previous[key] as bool : null;
  String prevString(String key) => previous[key] is String ? previous[key] as String : '';
  DateTime? prevDate(String key) => previous[key] is DateTime ? previous[key] as DateTime : null;
}

/// What the admin ticked on the checklist.
class PresetRequest {
  final Set<String> options;
  final String liveUrl;
  final String attachmentUrl, attachmentLabelAr, attachmentLabelEn;
  const PresetRequest({
    this.options = const {},
    this.liveUrl = '',
    this.attachmentUrl = '',
    this.attachmentLabelAr = '',
    this.attachmentLabelEn = '',
  });

  /// The checklist defaults per season kind (owner SOP): Holy Week / Pascha /
  /// Nativity replace the weekly schedule, hide meetings and clinics, stop
  /// the hero motion and hide wedding bookings; revivals add evening prayers
  /// on top of the regular masses, so nothing is replaced or hidden. The
  /// fasts (`fast`, Great Lent, the Apostles' fast, Kiahk — the Nativity fast
  /// uses `fast` or `kiahk`) hide wedding bookings: no weddings in a fast
  /// (ADR-051, issue 12).
  static Set<String> defaultsFor(String seasonKey) => switch (seasonKey) {
        'holy_week' => {
            PresetOption.replaceRegular,
            PresetOption.hideMeetings,
            PresetOption.hideClinics,
            PresetOption.heroMotionOff,
            PresetOption.weddingOff,
          },
        'pascha' || 'nativity' => {PresetOption.replaceRegular},
        _ when SeasonKeys.isFast(seasonKey) => {PresetOption.weddingOff},
        _ => const {},
      };
}

/// The writes of one apply / restore: `settings/features` fields and the
/// `seasons/{id}` fields (empty map = no write to that doc).
/// Thrown inside a fresh apply / restore when the stored preset or season
/// changed since the screen read it (another admin): nothing is written.
class PresetConflict implements Exception {
  const PresetConflict();
}

class PresetWrites {
  final Map<String, dynamic> features;
  final String seasonId;
  final Map<String, dynamic> season;
  const PresetWrites(this.features, this.seasonId, this.season);
}

final _httpsRe = RegExp(r'^https://[^/\s]+\.[^/\s]+(\S*)$', caseSensitive: false);
final _httpRe = RegExp(r'^https?://[^/\s]+\.[^/\s]+(\S*)$', caseSensitive: false);

/// Longest live-stream / programme link the rules accept.
const presetMaxUrl = 500;

/// Why [planApply] refuses (null = fine).
String? presetProblem(PresetRequest r, Season? season) {
  if (season == null) return 'season';
  // Same 500-character cap as the rules (`liveUrl`, `attachmentUrl`; CodeRabbit review on PR #33).
  final live = r.liveUrl.trim(), pdf = r.attachmentUrl.trim();
  if (r.options.contains(PresetOption.live) && (live.length > presetMaxUrl || !_httpRe.hasMatch(live))) return 'liveUrl';
  if (r.options.contains(PresetOption.pdf) && (pdf.length > presetMaxUrl || !_httpsRe.hasMatch(pdf))) {
    return 'attachmentUrl';
  }
  return null;
}

/// The apply writes for [r] on [season], given the current stored
/// `settings/features` map [stored] (raw, not effective) and the current
/// liveUrl / liveEndsAt / sections / heroMotion values it replaces.
///
/// Always activates the season (stores its previous `active`). The sections
/// map is written whole (validSections), from [sections] (effective
/// switches, missing = on).
PresetWrites planApply({
  required PresetRequest r,
  required Season season,
  required Map<String, bool> sections,
  required List<String> sectionKeys,
  required bool heroMotion,
  required bool weddingBookingOff,
  required String liveUrl,
  required DateTime? liveEndsAt,
  required DateTime now,
  String storedTheme = '',
  String? seasonTheme,
  DateTime? liveEnd,
}) {
  final o = r.options;
  final prev = <String, Object?>{PresetPrev.seasonActive: season.active};
  final f = <String, dynamic>{};
  final s = <String, dynamic>{'active': true};

  if (o.contains(PresetOption.replaceRegular)) {
    prev[PresetPrev.replacesRegular] = season.replacesRegular;
    s['replacesRegular'] = true;
  }
  if (o.contains(PresetOption.hideMeetings) || o.contains(PresetOption.hideClinics)) {
    final next = {for (final k in sectionKeys) k: sections[k] ?? true};
    if (o.contains(PresetOption.hideMeetings)) {
      prev[PresetPrev.meetings] = next['meetings'];
      next['meetings'] = false;
    }
    if (o.contains(PresetOption.hideClinics)) {
      prev[PresetPrev.clinics] = next['clinics'];
      next['clinics'] = false;
    }
    f['sections'] = next;
  }
  if (o.contains(PresetOption.heroMotionOff)) {
    prev[PresetPrev.heroMotion] = heroMotion;
    f['heroMotion'] = false;
  }
  if (o.contains(PresetOption.weddingOff)) {
    prev[PresetPrev.weddingBookingOff] = weddingBookingOff;
    f['weddingBookingOff'] = true;
  }
  if (o.contains(PresetOption.live)) {
    prev[PresetPrev.liveUrl] = liveUrl;
    prev[PresetPrev.liveEndsAt] = liveEndsAt;
    f['liveUrl'] = r.liveUrl.trim();
    // ADR-051 (issue 10): tonight's end ([presetLiveEnd], editable on the
    // screen); null = the season's end (older callers).
    f['liveEndsAt'] = liveEnd ?? season.endsAt;
  }
  if (o.contains(PresetOption.pdf)) {
    prev[PresetPrev.attachmentUrl] = season.program.attachmentUrl;
    prev[PresetPrev.attachmentLabelAr] = season.program.attachmentLabelAr;
    prev[PresetPrev.attachmentLabelEn] = season.program.attachmentLabelEn;
    s['attachmentUrl'] = r.attachmentUrl.trim();
    s['attachmentLabelAr'] = r.attachmentLabelAr.trim();
    s['attachmentLabelEn'] = r.attachmentLabelEn.trim();
  }
  // The season's theme by hand (ADR-043); nothing to do when the key brings
  // no theme.
  if (o.contains(PresetOption.theme) && seasonTheme != null) {
    prev[PresetPrev.theme] = storedTheme;
    f['theme'] = seasonTheme;
  }
  f['seasonPreset'] = SeasonPreset(
    seasonId: season.id,
    seasonKey: season.key,
    appliedAt: now,
    startsAt: season.startsAt,
    endsAt: season.endsAt,
    options: [
      for (final k in PresetOption.all)
        if (o.contains(k) && (k != PresetOption.theme || seasonTheme != null)) k,
    ],
    previous: prev,
  ).toMap();
  return PresetWrites(f, season.id, s);
}

/// The default end of the live banner the preset sets (ADR-051, issue 10):
/// the end of the last of [season]'s visible evening services (starting at
/// [eveningFrom] or later) on its first evening — today, or the season's
/// first day when it has not started yet — plus 30 minutes (an overnight
/// service ends the next morning); 23:59 that day when it has none then, or
/// when they have all ended before [now]. A service of the season running
/// at [now] since yesterday (applied at 00:30 during an all-night praise)
/// gives its own end + 30 minutes. Never after the season's end. The admin
/// can change it before applying, and the live banner is still switched on
/// by hand every night.
DateTime presetLiveEnd({required Season season, required Iterable<Liturgy> liturgies, required DateTime now}) {
  // Hidden services never set the end (CodeRabbit on PR #44).
  final shown = [for (final l in liturgies) if (l.visible) l];
  final c = CairoTime.fromInstant(now);
  var day = CairoTime.at(c.year, c.month, c.day);
  final start = season.startsAt;
  if (start != null && !start.isBefore(CairoTime.at(c.year, c.month, c.day + 1))) {
    final s = CairoTime.fromInstant(start);
    day = CairoTime.at(s.year, s.month, s.day);
  }
  // The season as it will be once applied (the preset activates it).
  final active = Season(
    id: season.id,
    key: season.key,
    nameAr: season.nameAr,
    nameEn: season.nameEn,
    startsAt: season.startsAt,
    endsAt: season.endsAt,
    replacesRegular: season.replacesRegular,
    replaceDates: season.replaceDates,
  );
  // Last night's service still running now (an all-night praise at 00:30).
  final yesterday = CairoTime.at(c.year, c.month, c.day - 1);
  for (final o in occurrencesForDay(liturgies: shown, seasons: [active], day: yesterday, dayOffset: -1)) {
    if (o.liturgy.seasonKey == season.key && !o.start.isAfter(now) && o.end.isAfter(now)) {
      return _utc(o.end.add(const Duration(minutes: 30)));
    }
  }
  DateTime? last;
  for (final o in occurrencesForDay(liturgies: shown, seasons: [active], day: day, dayOffset: 0)) {
    if (o.liturgy.seasonKey != season.key) continue;
    // Evening services only, unless it is running now (CodeRabbit on PR #44).
    final evening = !o.start.isBefore(CairoTime.at(day.year, day.month, day.day, eveningFrom));
    final runningNow = !o.start.isAfter(now) && o.end.isAfter(now);
    if (!evening && !runningNow) continue;
    if (last == null || o.end.isAfter(last)) last = o.end;
  }
  final fallback = CairoTime.at(day.year, day.month, day.day, 23 * 60 + 59);
  var end = last == null ? fallback : last.add(const Duration(minutes: 30));
  if (!end.isAfter(now)) end = fallback;
  final seasonEnd = season.endsAt;
  if (seasonEnd != null && end.isAfter(seasonEnd) && seasonEnd.isAfter(now)) end = seasonEnd;
  return _utc(end);
}

/// Services starting at or after this minute of the day count as the
/// evening's for [presetLiveEnd] (12:00: Lent's afternoon liturgy and every
/// vespers, praise and revival night).
const eveningFrom = 12 * 60;

DateTime _utc(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true);

/// The restore writes: every value [p] replaced goes back, and the preset is
/// cleared (`seasonPreset` = null). [sections] = the current effective
/// switches (only the ones the preset turned off are put back).
PresetWrites planRestore(SeasonPreset p, {required Map<String, bool> sections, required List<String> sectionKeys}) {
  final f = <String, dynamic>{'seasonPreset': null};
  final s = <String, dynamic>{};
  final active = p.prevBool(PresetPrev.seasonActive);
  if (active != null) s['active'] = active;
  if (p.has(PresetOption.replaceRegular)) {
    s['replacesRegular'] = p.prevBool(PresetPrev.replacesRegular) ?? true;
  }
  if (p.has(PresetOption.hideMeetings) || p.has(PresetOption.hideClinics)) {
    final next = {for (final k in sectionKeys) k: sections[k] ?? true};
    if (p.has(PresetOption.hideMeetings)) next['meetings'] = p.prevBool(PresetPrev.meetings) ?? true;
    if (p.has(PresetOption.hideClinics)) next['clinics'] = p.prevBool(PresetPrev.clinics) ?? true;
    f['sections'] = next;
  }
  if (p.has(PresetOption.heroMotionOff)) f['heroMotion'] = p.prevBool(PresetPrev.heroMotion) ?? true;
  if (p.has(PresetOption.weddingOff)) f['weddingBookingOff'] = p.prevBool(PresetPrev.weddingBookingOff) ?? false;
  if (p.has(PresetOption.live)) {
    f['liveUrl'] = p.prevString(PresetPrev.liveUrl);
    f['liveEndsAt'] = p.prevDate(PresetPrev.liveEndsAt);
  }
  if (p.has(PresetOption.pdf)) {
    s['attachmentUrl'] = p.prevString(PresetPrev.attachmentUrl);
    s['attachmentLabelAr'] = p.prevString(PresetPrev.attachmentLabelAr);
    s['attachmentLabelEn'] = p.prevString(PresetPrev.attachmentLabelEn);
  }
  if (p.has(PresetOption.theme)) {
    final t = p.prevString(PresetPrev.theme);
    f['theme'] = t.isEmpty ? 'goldenHour' : t;
  }
  return PresetWrites(f, p.seasonId, s);
}

/// The `settings/features` write that moves an applied preset's end to the
/// season's current [seasonEnd] after the admin changed the season's dates
/// (Sentry review on PR #33): the auto-revert follows. When the preset set
/// the live link and its `liveEndsAt` still equals the preset's old end
/// ([storedLiveEndsAt]; not changed by hand since), the live end is pulled in
/// to a shortened season end — never pushed later: since ADR-051 the live end
/// is tonight's ([presetLiveEnd]), and extending it would keep a switched-on
/// banner for days (CodeRabbit on PR #44).
PresetWrites planSyncEnd(SeasonPreset p, DateTime seasonEnd, {DateTime? storedLiveEndsAt}) => PresetWrites({
      'seasonPreset': {...p.toMap(), 'endsAt': seasonEnd},
      if (p.has(PresetOption.live) &&
          storedLiveEndsAt != null &&
          storedLiveEndsAt == p.endsAt &&
          seasonEnd.isBefore(storedLiveEndsAt))
        'liveEndsAt': seasonEnd,
    }, p.seasonId, const {});

/// The days, rounded up, that applying a preset with [options] to [season]
/// at [now] would replace the whole weekly schedule, when that is more than
/// 3 days; null otherwise (ADR-054, sims r3 O-3: the Pascha preset's
/// default replaceRegular on a 50-day window). Counted from the later of the
/// season's start and [now] to its end; the season replaces when the preset
/// ticks [PresetOption.replaceRegular] or it already does.
int? presetReplaceDays(Season season, Set<String> options, DateTime now) {
  final replaces = options.contains(PresetOption.replaceRegular) || season.replacesRegular;
  final end = season.endsAt;
  if (!replaces || end == null) return null;
  final start = season.startsAt == null || season.startsAt!.isBefore(now) ? now : season.startsAt!;
  final minutes = end.difference(start).inMinutes;
  if (minutes <= 3 * 24 * 60) return null;
  return (minutes / (24 * 60)).ceil();
}
