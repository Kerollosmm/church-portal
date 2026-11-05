import 'package:timezone/timezone.dart' as tz;

import 'cairo_time.dart';
import 'models.dart';

/// A concrete liturgy occurrence on a given Cairo day.
class LiturgyOccurrence {
  final Liturgy liturgy;
  final tz.TZDateTime start;
  final tz.TZDateTime end;

  /// 0 = today, 1 = tomorrow, ...
  final int dayOffset;
  const LiturgyOccurrence(this.liturgy, this.start, this.end, this.dayOffset);

  bool isHappeningAt(DateTime instant) => !instant.isBefore(start) && instant.isBefore(end);

  @override
  String toString() => 'LiturgyOccurrence(${liturgy.id}, $start-$end, +$dayOffset)';
}

class NextMassResult {
  /// Liturgy currently in progress (now within [start, end)).
  final LiturgyOccurrence? happeningNow;

  /// Next liturgy whose start is after now (today, else tomorrow, else the
  /// next day that has one within a week).
  final LiturgyOccurrence? next;

  /// Seasons that are overriding the regular schedule right now.
  final List<Season> activeSeasons;
  const NextMassResult({this.happeningNow, this.next, this.activeSeasons = const []});

  bool get isEmpty => happeningNow == null && next == null;
}

/// Is [s] active at [instant]? (flag on and instant within [startsAt, endsAt]).
bool isSeasonActiveAt(Season s, DateTime instant) {
  if (!s.active) return false;
  if (s.startsAt != null && instant.isBefore(s.startsAt!)) return false;
  if (s.endsAt != null && instant.isAfter(s.endsAt!)) return false;
  return true;
}

/// Is [s] active at any moment during the Cairo calendar day starting at
/// [dayStart]?
bool isSeasonActiveOnDay(Season s, tz.TZDateTime dayStart) {
  if (!s.active) return false;
  final dayEnd = CairoTime.at(dayStart.year, dayStart.month, dayStart.day + 1);
  if (s.startsAt != null && !s.startsAt!.isBefore(dayEnd)) return false;
  if (s.endsAt != null && s.endsAt!.isBefore(dayStart)) return false;
  return true;
}

List<Season> activeSeasonsAt(Iterable<Season> seasons, DateTime instant) =>
    seasons.where((s) => isSeasonActiveAt(s, instant)).toList();

bool _matchesDay(Liturgy l, tz.TZDateTime day) {
  if (l.date != null) {
    final d = CairoTime.calendarDate(l.date!);
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }
  return l.weekday != null && l.weekday == day.weekday;
}

/// Effective liturgies for a Cairo day, sorted by start time then order.
///
/// Delegates to [occurrencesForDay] so the two can never disagree (e.g. on a
/// season that starts or ends mid-day, or an additive revival season).
List<Liturgy> effectiveLiturgiesForDay({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
  Set<String>? types,
}) =>
    [
      for (final o in occurrencesForDay(liturgies: liturgies, seasons: seasons, day: day, dayOffset: 0, types: types))
        o.liturgy,
    ];

LiturgyOccurrence? _occurrence(Liturgy l, tz.TZDateTime day, int dayOffset) {
  final s = l.startMinutes;
  if (s == null) return null;
  var e = l.endMinutes ?? (s + 120);
  if (e <= s) e += 24 * 60; // crosses midnight (e.g. Easter night liturgy)
  return LiturgyOccurrence(
    l,
    CairoTime.at(day.year, day.month, day.day, s),
    CairoTime.at(day.year, day.month, day.day, e),
    dayOffset,
  );
}

/// Concrete occurrences for a Cairo day, honouring each season's exact time
/// window: a seasonal service counts only if it starts inside its season's
/// [startsAt, endsAt].
///
/// * A full-override season (`replacesRegular == true`: Holy Week, Pascha,
///   Nativity) that has any service on the day replaces every regular service
///   starting inside its window (so e.g. morning masses before a season
///   starting at 18:00 keep the regular schedule).
/// * An additive season (`replacesRegular == false`: the evening revivals)
///   keeps the regular schedule: a regular `mass` is superseded only when the
///   season also schedules a `mass` that day (e.g. the feast liturgy), and a
///   regular `vespers` / `praise` only when it overlaps in time with one of
///   the season's services that day.
///
/// Sorted by start time then order.
List<LiturgyOccurrence> occurrencesForDay({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
  required int dayOffset,
  Set<String>? types,
}) {
  final dayStart = CairoTime.startOfDay(day);
  final active = seasons.where((s) => isSeasonActiveOnDay(s, dayStart)).toList();
  bool typeOk(Liturgy l) => types == null || types.contains(l.type);

  final seasonal = <LiturgyOccurrence>[];
  final replacing = <Season>{};
  final additive = <Season, List<LiturgyOccurrence>>{};
  for (final l in liturgies) {
    if (l.seasonKey == null || !_matchesDay(l, dayStart)) continue;
    final o = _occurrence(l, dayStart, dayOffset);
    if (o == null) continue;
    final windows = active
        .where((s) =>
            s.key == l.seasonKey &&
            isSeasonActiveAt(s, o.start) &&
            (l.date != null || !undatedSuppressedOn(s, l, liturgies, dayStart)))
        .toList();
    if (windows.isEmpty) continue;
    seasonal.add(o);
    // Replacement is decided on ALL seasonal services (so e.g. Holy Week
    // Pascha hours also suspend the regular weekday masses), then filtered.
    for (final s in windows) {
      if (s.replacesRegular) {
        replacing.add(s);
      } else {
        (additive[s] ??= []).add(o);
      }
    }
  }

  bool superseded(LiturgyOccurrence o) {
    if (replacing.any((s) => isSeasonActiveAt(s, o.start))) return true;
    for (final MapEntry(key: s, value: services) in additive.entries) {
      switch (o.liturgy.type) {
        case 'mass':
          if (isSeasonActiveAt(s, o.start) && services.any((x) => x.liturgy.type == 'mass')) return true;
        case 'vespers' || 'praise':
          if (services.any((x) => o.start.isBefore(x.end) && x.start.isBefore(o.end))) return true;
      }
    }
    return false;
  }

  final result = <LiturgyOccurrence>[
    for (final o in seasonal)
      if (typeOk(o.liturgy)) o,
    for (final l in liturgies)
      if (l.seasonKey == null && _matchesDay(l, dayStart) && typeOk(l))
        if (_occurrence(l, dayStart, dayOffset) case final o?)
          if (!superseded(o)) o,
  ];
  result.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.liturgy.order.compareTo(b.liturgy.order);
  });
  return result;
}

/// Next-mass smart card logic (see SPEC "Business rules").
///
/// [now] is any instant; it is converted to Africa/Cairo. By default only
/// `type == 'mass'` is considered; pass [types] to include vespers etc.
/// While a season is active (Holy Week, Pascha, Nativity, and the additive
/// revivals too), EVERY service of that season counts whatever its type (the
/// Holy Week hours and revival nights are `other` / `vespers`; ADR-043 and
/// ADR-045, sims B1) — otherwise the card skipped them and showed a regular
/// mass hours or days later.
NextMassResult computeNextMass({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required DateTime now,
  Set<String> types = const {'mass'},
  int lookAheadDays = 7,
}) {
  final cairoNow = CairoTime.fromInstant(now);
  final today = CairoTime.startOfDay(cairoNow);
  LiturgyOccurrence? happening;
  LiturgyOccurrence? next;
  // Every service of an ACTIVE season counts whatever its type, additive
  // seasons included (ADR-045, revival sim B1: a revival night stored as
  // `vespers` / `other` is the evening's service). Regular services keep the
  // type filter; [occurrencesForDay] already merges an additive season with
  // the regular schedule.
  bool counts(LiturgyOccurrence o) =>
      types.contains(o.liturgy.type) ||
      (o.liturgy.seasonKey != null &&
          seasons.any((s) => s.key == o.liturgy.seasonKey && isSeasonActiveAt(s, o.start)));
  // Every type is read (the suppression of regular services is the same),
  // then filtered by [counts].
  List<LiturgyOccurrence> day(tz.TZDateTime d, int offset) => [
        for (final o in occurrencesForDay(liturgies: liturgies, seasons: seasons, day: d, dayOffset: offset))
          if (counts(o)) o,
      ];

  // Yesterday's occurrences may still be running past midnight.
  final yesterday = CairoTime.at(today.year, today.month, today.day - 1);
  for (final o in day(yesterday, -1)) {
    if (o.isHappeningAt(cairoNow)) happening ??= o;
  }

  for (var offset = 0; offset <= lookAheadDays && next == null; offset++) {
    final d = CairoTime.at(today.year, today.month, today.day + offset);
    for (final o in day(d, offset)) {
      if (offset == 0 && o.isHappeningAt(cairoNow)) {
        happening ??= o;
        continue;
      }
      if (o.start.isAfter(cairoNow)) {
        next = o;
        break;
      }
    }
  }
  return NextMassResult(
    happeningNow: happening,
    next: next,
    activeSeasons: activeSeasonsAt(seasons, cairoNow),
  );
}

/// Day tabs on the mass-schedule page.
enum ScheduleTab { friday, sunday, wednesday, saturday, other }

const Map<ScheduleTab, Set<int>> scheduleTabWeekdays = {
  ScheduleTab.friday: {5},
  ScheduleTab.sunday: {7},
  ScheduleTab.wednesday: {3},
  ScheduleTab.saturday: {6},
  ScheduleTab.other: {1, 2, 4},
};

/// Regular liturgies for a tab (weekly schedule, no seasonal overrides),
/// excluding vespers/praise which have their own section.
List<Liturgy> regularLiturgiesForTab(Iterable<Liturgy> all, ScheduleTab tab) {
  final days = scheduleTabWeekdays[tab]!;
  final list = all
      .where((l) =>
          l.seasonKey == null &&
          l.date == null &&
          l.weekday != null &&
          days.contains(l.weekday) &&
          l.type != 'vespers' &&
          l.type != 'praise')
      .toList();
  list.sort((a, b) {
    final w = (a.weekday ?? 0).compareTo(b.weekday ?? 0);
    if (w != 0) return w;
    final c = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return list;
}

/// Regular vespers & praise services. Weekly ones (no date) are always
/// listed; with [now], a one-off dated one is listed from its Cairo day on
/// and, after that day, only while it is still running past midnight.
List<Liturgy> vespersAndPraise(Iterable<Liturgy> all, {DateTime? now}) {
  final list = all
      .where((l) =>
          l.seasonKey == null &&
          (l.type == 'vespers' || l.type == 'praise') &&
          (now == null || l.date == null || isDatedLiturgyCurrent(l, now)))
      .toList();
  list.sort((a, b) {
    final w = (a.weekday ?? 0).compareTo(b.weekday ?? 0);
    if (w != 0) return w;
    return (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
  });
  return list;
}

/// Cairo calendar day of [now] as a plain (non-UTC) date.
DateTime _cairoToday(DateTime now) {
  final t = CairoTime.startOfDay(CairoTime.fromInstant(now));
  return DateTime(t.year, t.month, t.day);
}

/// Is the dated one-off [l] still listed at [now]? From its Cairo day on;
/// before that day only while its occurrence (which may cross midnight, see
/// [_occurrence]) has not ended yet.
bool isDatedLiturgyCurrent(Liturgy l, DateTime now) {
  final d = CairoTime.calendarDate(l.date!);
  if (!d.isBefore(_cairoToday(now))) return true;
  final o = _occurrence(l, CairoTime.at(d.year, d.month, d.day), 0);
  return o != null && o.end.isAfter(now);
}

/// Standalone one-off services (a dated liturgy that belongs to no season,
/// e.g. New Year's Eve or a feast), excluding vespers / praise which have
/// their own section, from the Cairo day of [now] on (and a previous-day one
/// while it is still running past midnight). Sorted by date, start time,
/// then order.
List<Liturgy> upcomingSpecialLiturgies(Iterable<Liturgy> all, DateTime now) {
  final list = all
      .where((l) =>
          l.seasonKey == null &&
          l.date != null &&
          l.type != 'vespers' &&
          l.type != 'praise' &&
          isDatedLiturgyCurrent(l, now))
      .toList();
  list.sort((a, b) {
    final d = CairoTime.calendarDate(a.date!).compareTo(CairoTime.calendarDate(b.date!));
    if (d != 0) return d;
    final c = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return list;
}

/// Does the Cairo calendar day of the stored [date] overlap [s]'s
/// [startsAt, endsAt] window (open bounds match everything)?
bool _dateInSeason(DateTime date, Season s) {
  final d = CairoTime.calendarDate(date);
  final dayStart = CairoTime.at(d.year, d.month, d.day);
  final dayEnd = CairoTime.at(d.year, d.month, d.day + 1);
  if (s.startsAt != null && !s.startsAt!.isBefore(dayEnd)) return false;
  if (s.endsAt != null && s.endsAt!.isBefore(dayStart)) return false;
  return true;
}

/// Does [s] have a real (non-sample) service of its own: a dated one inside
/// its window, or an undated one of its key? Then the seed's undated
/// `sample: true` templates of that key are not part of it (ADR-045, sims
/// B5: the owner's programme replaces the sample one).
bool seasonHasRealServices(Season s, Iterable<Liturgy> all) => all.any(
    (l) => l.seasonKey == s.key && !l.sample && (l.date == null || _dateInSeason(l.date!, s)));

/// Does the undated (weekday) service [l] of [s] give way on the Cairo day
/// [dayStart]? (ADR-043 B4, widened in ADR-045 B5)
/// * A `sample: true` template, once [s] has any real service
///   ([seasonHasRealServices]) — the seed's templates never mix into an
///   owner's programme, Holy Week or revival alike.
/// * Any undated service, on a day where [s] has dated non-sample services
///   of its own: for a season that replaces the regular schedule any such
///   service that day (the dated programme is the plan for that day); for an
///   additive season one that overlaps it in time (a revival's nightly
///   service still runs on its dated feast-morning liturgy).
/// Seasons made only of sample data (the bundled seed) are unchanged.
bool undatedSuppressedOn(Season s, Liturgy l, Iterable<Liturgy> all, tz.TZDateTime dayStart) {
  if (l.date != null || l.seasonKey != s.key) return false;
  if (l.sample && seasonHasRealServices(s, all)) return true;
  final mine = _occurrence(l, dayStart, 0);
  for (final d in all) {
    if (d.seasonKey != s.key || d.date == null || d.sample || !_matchesDay(d, dayStart) || !_dateInSeason(d.date!, s)) {
      continue;
    }
    // Only a dated service that really occurs in the season counts: one
    // starting before the season's start (a morning service on an 18:00
    // start day) is not part of it (as in [occurrencesForDay]; CodeRabbit).
    final o = _occurrence(d, dayStart, 0);
    if (o == null || !isSeasonActiveAt(s, o.start)) continue;
    if (s.replacesRegular) return true;
    if (mine == null || (o.start.isBefore(mine.end) && mine.start.isBefore(o.end))) return true;
  }
  return false;
}

/// [l] is one of [s]'s services for the season lists: its key, and a dated
/// one inside the window, or an undated one that still applies on at least
/// one day of the window with its weekday ([undatedSuppressedOn]). An
/// undated service of an open-ended season is listed unless it is a sample
/// template of a season with real services.
bool liturgyInSeason(Liturgy l, Season s, Iterable<Liturgy> all) {
  if (l.seasonKey != s.key) return false;
  if (l.date != null) return _dateInSeason(l.date!, s);
  if (l.sample && seasonHasRealServices(s, all)) return false;
  final from = s.startsAt, to = s.endsAt, wd = l.weekday;
  if (from == null || to == null || wd == null) return true;
  // Cheap common case (and long seasons such as summer): no dated real
  // service in the window at all, so no day can suppress it.
  if (!all.any((d) => d.seasonKey == s.key && d.date != null && !d.sample && _dateInSeason(d.date!, s))) return true;
  var sawWeekday = false;
  final first = CairoTime.calendarDate(from), last = CairoTime.calendarDate(to);
  var day = CairoTime.at(first.year, first.month, first.day);
  for (var i = 0; i < 400 && !day.isAfter(CairoTime.at(last.year, last.month, last.day)); i++) {
    if (day.weekday == wd) {
      sawWeekday = true;
      if (!undatedSuppressedOn(s, l, all, day)) return true;
    }
    day = CairoTime.at(day.year, day.month, day.day + 1);
  }
  // No such weekday in the window at all: listed as before (unchanged).
  return !sawWeekday;
}

/// Seasonal liturgies grouped by season, for active seasons only, seasons
/// sorted by start date. A dated liturgy is attached only to the season
/// whose window covers its day, so e.g. 2027 and 2028 seasons sharing a key
/// never pick up each other's services; an undated one only when it still
/// falls on a day of the season without dated services ([liturgyInSeason]).
Map<Season, List<Liturgy>> seasonalSchedule(Iterable<Season> seasons, Iterable<Liturgy> all) {
  final sorted = seasons.where((s) => s.active).toList()
    ..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
  final map = <Season, List<Liturgy>>{};
  for (final s in sorted) {
    final ls = all.where((l) => liturgyInSeason(l, s, all)).toList()
      ..sort((a, b) {
        final da = a.date ?? DateTime(2000, 1, a.weekday ?? 0);
        final db = b.date ?? DateTime(2000, 1, b.weekday ?? 0);
        final c = da.compareTo(db);
        if (c != 0) return c;
        final t = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
        return t != 0 ? t : a.order.compareTo(b.order);
      });
    if (ls.isNotEmpty) map[s] = ls;
  }
  return map;
}

/// Where a service is held, for comparing parallel services (ADR-041): the
/// admin venue's Arabic name when [opts] knows the key (so the venue `main`
/// and the free text «الكنيسة الكبرى» are the same place), else the key,
/// else the free-text Arabic place, else the English one (compared only with
/// other English-only places; CodeRabbit review on PR #32).
String _placeKey(Liturgy l, ProgramOptions? opts) {
  final v = l.program.venue;
  if (v.isNotEmpty) {
    final name = opts?.venue(v)?.labelAr.trim() ?? '';
    return name.isNotEmpty ? 'n:$name' : 'v:$v';
  }
  if (l.placeAr.trim().isNotEmpty) return 'n:${l.placeAr.trim()}';
  return l.placeEn.trim().isEmpty ? '' : 'e:${l.placeEn.trim().toLowerCase()}';
}

/// A service's end in minutes from its day's midnight: no end = one minute,
/// an end at or before the start crosses midnight (as [_occurrence]).
int _endMinutes(Liturgy l) {
  final s = l.startMinutes!;
  final e = l.endMinutes;
  if (e == null) return s + 1;
  return e <= s ? e + 24 * 60 : e;
}

/// The day a service belongs to: its one-off date, else its weekday.
String _slotDay(Liturgy l) {
  final d = l.date;
  if (d != null) {
    final c = CairoTime.calendarDate(d);
    return 'd:${c.year}-${c.month}-${c.day}';
  }
  return l.weekday == null ? '' : 'w:${l.weekday}';
}

/// Services of [list] held at the same time in ANOTHER venue / hall
/// (ADR-041: Holy Week prayers in the main church, the lower hall and the
/// services building for different age groups). Two services are parallel
/// when they fall on the same day (date, or weekday for weekly ones), their
/// times overlap (a service without an end time counts as one minute, an end
/// at or before the start crosses midnight) and
/// their venues (or places) differ — both must name one. Returns, for each
/// liturgy id that has any, the other services in start order.
Map<String, List<Liturgy>> parallelServices(Iterable<Liturgy> list, [ProgramOptions? opts]) {
  final items = [
    for (final l in list)
      if (l.startMinutes != null && _placeKey(l, opts).isNotEmpty && _slotDay(l).isNotEmpty) l,
  ];
  final out = <String, List<Liturgy>>{};
  for (var i = 0; i < items.length; i++) {
    final a = items[i];
    final aStart = a.startMinutes!;
    final aEnd = _endMinutes(a);
    for (var j = i + 1; j < items.length; j++) {
      final b = items[j];
      if (_slotDay(a) != _slotDay(b) || _placeKey(a, opts) == _placeKey(b, opts)) continue;
      final bStart = b.startMinutes!;
      final bEnd = _endMinutes(b);
      if (aStart < bEnd && bStart < aEnd) {
        (out[a.id] ??= []).add(b);
        (out[b.id] ??= []).add(a);
      }
    }
  }
  for (final v in out.values) {
    v.sort((x, y) => x.startMinutes!.compareTo(y.startMinutes!));
  }
  return out;
}

/// The services held at the same time as [target] in ANOTHER venue / hall,
/// among [sameDay] = that day's real occurrences ([occurrencesForDay]: season
/// windows and suppression already applied), for the next-service card
/// (Sentry review on PR #32). Overlap uses the real instants (a service
/// without an end time counts as one minute), places compare as in
/// [parallelServices].
List<Liturgy> parallelOccurrences(LiturgyOccurrence target, Iterable<LiturgyOccurrence> sameDay,
    [ProgramOptions? opts]) {
  final key = _placeKey(target.liturgy, opts);
  if (key.isEmpty) return const [];
  DateTime endOf(LiturgyOccurrence o) =>
      o.liturgy.endMinutes == null ? o.start.add(const Duration(minutes: 1)) : o.end;
  final tEnd = endOf(target);
  final out = [
    for (final o in sameDay)
      if (o.liturgy.id != target.liturgy.id &&
          _placeKey(o.liturgy, opts).isNotEmpty &&
          _placeKey(o.liturgy, opts) != key &&
          o.start.isBefore(tEnd) &&
          target.start.isBefore(endOf(o)))
        o,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return [for (final o in out) o.liturgy];
}
