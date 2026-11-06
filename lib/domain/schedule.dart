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
  /// Liturgy currently in progress (now within [start, end)): the first of
  /// [runningNow].
  final LiturgyOccurrence? happeningNow;

  /// EVERY counted service in progress at now, in start order (yesterday's
  /// overnight ones first), so services held at the same moment in other
  /// halls are not dropped (ADR-049 item 1). [happeningNow] is its first.
  final List<LiturgyOccurrence> runningNow;

  /// Next liturgy whose start is after now (today, else tomorrow, else the
  /// next day that has one within a week).
  final LiturgyOccurrence? next;

  /// Seasons that are overriding the regular schedule right now.
  final List<Season> activeSeasons;
  const NextMassResult({this.happeningNow, this.next, this.activeSeasons = const [], this.runningNow = const []});

  /// The other services running now in ANOTHER venue / hall than
  /// [happeningNow] (ADR-041 rule: both must name a place), for the
  /// «وفي نفس الوقت» line of the «يُقام الآن» box (ADR-049). Same-venue
  /// services and ones without a place are left out, as on the schedule.
  ///
  /// Every entry of [runningNow] is in progress now by construction (a
  /// service without an end time runs its default 120 minutes, as in
  /// [computeNextMass]), so only the place is compared here — not the
  /// 1-minute overlap rule of [parallelOccurrences] (Sentry review on PR #42).
  List<Liturgy> alsoRunning([ProgramOptions? opts]) {
    final h = happeningNow;
    if (h == null) return const [];
    final key = _placeKey(h.liturgy, opts);
    if (key.isEmpty) return const [];
    return [
      for (final o in runningNow)
        if (o.liturgy.id != h.liturgy.id && _placeKey(o.liturgy, opts).isNotEmpty && _placeKey(o.liturgy, opts) != key)
          o.liturgy,
    ];
  }

  /// Is [o] already named in the «يُقام الآن» box: [happeningNow] itself, or
  /// one of its «وفي نفس الوقت» services ([alsoRunning])? The next-service
  /// card's parallel lines leave such a service out, so the card never names
  /// it twice (ADR-054, sims r3 P7 12:30: «وفي نفس الوقت: الكنيسة الكبرى
  /// (عام)» under the youth liturgy while the main one was the now box).
  bool shownInNowBox(LiturgyOccurrence o, [ProgramOptions? opts]) {
    final h = happeningNow;
    if (h == null) return false;
    bool same(LiturgyOccurrence a) => a.liturgy.id == o.liturgy.id && a.start.isAtSameMomentAs(o.start);
    if (same(h)) return true;
    final also = {for (final l in alsoRunning(opts)) l.id};
    return runningNow.any((a) => also.contains(a.liturgy.id) && same(a));
  }

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

/// The enabled season that starts soonest after [instant] (ADR-055): the
/// «الموسم القادم» line of the seasonal view's empty state. Null when no
/// enabled season has a start in the future. Works on the seasons already
/// loaded: no extra read.
Season? nextUpcomingSeason(Iterable<Season> seasons, DateTime instant) {
  Season? best;
  for (final s in seasons) {
    final start = s.startsAt;
    if (!s.active || start == null || !instant.isBefore(start)) continue;
    if (best == null || start.isBefore(best.startsAt!)) best = s;
  }
  return best;
}

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
///   Nativity) with an exact window (both `startsAt` and `endsAt`) replaces
///   every regular service starting inside that window, whether or not it has
///   a service of its own that day (ADR-053, sims r2 P1 N1: Good Friday with
///   no owner service fell back to the regular Divine Liturgy once the seed
///   samples were hidden behind the owner's programme, and would again if the
///   sample docs were deleted). Morning masses before a season starting at
///   18:00 keep the regular schedule. An open-ended full-override season
///   (no start or no end) still replaces only on the days it has a service.
///   That is the owner's own choice for the season, so it applies whatever
///   the services' `sample`.
/// * An additive season (`replacesRegular == false`: fasts, revivals, the
///   Holy 50 Days) keeps the regular schedule (ADR-050): a regular `mass` is
///   superseded only by a seasonal `mass` that overlaps it in time, or by a
///   seasonal service marked [Liturgy.replacesDay] (the feast liturgy:
///   «يحل محل قداسات اليوم المعتادة») on that day; a regular `vespers` /
///   `praise` only when it overlaps one of the season's services in time.
/// * A `sample: true` service never supersedes, replaces or outranks a real
///   one (ADR-050, sims P2 B1 / P3 B2): it supersedes a regular service only
///   when that one is a sample too, it gives way to a real service of ANY
///   active season that overlaps it, and at the same start a real service
///   sorts before a sample.
///
/// Sorted by start time, then real before sample, then order. The home card,
/// /mass-schedule ([regularStatusOn]) and the assistant prompt all read this
/// one function, so they can never disagree.
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
  bool overlaps(LiturgyOccurrence a, LiturgyOccurrence b) => a.start.isBefore(b.end) && b.start.isBefore(a.end);
  // A sample never takes the place of a real service (ADR-050).
  bool mayReplace(LiturgyOccurrence by, LiturgyOccurrence o) => !by.liturgy.sample || o.liturgy.sample;

  final candidates = <(LiturgyOccurrence, List<Season>)>[];
  for (final l in liturgies) {
    if (l.seasonKey == null || !_matchesDay(l, dayStart)) continue;
    final o = _occurrence(l, dayStart, dayOffset);
    if (o == null) continue;
    final windows = active
        .where((s) =>
            s.key == l.seasonKey &&
            isSeasonActiveAt(s, o.start) &&
            !undatedSuppressedOn(s, l, liturgies, dayStart))
        .toList();
    if (windows.isEmpty) continue;
    candidates.add((o, windows));
  }
  // A seasonal sample gives way to a real seasonal service of any active
  // season held at the same time (P3 B2: the seed's St Moses revival night
  // beside the owner's own revival of the Apostles' fast).
  final seasonal = <LiturgyOccurrence>[];
  // A full-override season with an exact window replaces the regular
  // schedule inside it on every day, service or not (ADR-053, P1 N1).
  final replacing = <Season>{
    for (final s in active)
      if (s.replacesRegular && s.startsAt != null && s.endsAt != null) s,
  };
  final additive = <Season, List<LiturgyOccurrence>>{};
  for (final (o, windows) in candidates) {
    final hidden = o.liturgy.sample && candidates.any((c) => !c.$1.liturgy.sample && overlaps(c.$1, o));
    if (!hidden) seasonal.add(o);
    // Replacement is decided on ALL seasonal services (so e.g. Holy Week
    // Pascha hours also suspend the regular weekday masses), then filtered.
    // A full-override season counts even when its only service today is a
    // sample hidden by another season's real one (CodeRabbit on PR #45).
    for (final s in windows) {
      // ADR-051: an additive season replaces on its `replaceDates` (feast night).
      if (s.replacesOn(dayStart)) {
        replacing.add(s);
      } else if (!hidden) {
        (additive[s] ??= []).add(o);
      }
    }
  }

  bool superseded(LiturgyOccurrence o) {
    if (replacing.any((s) => isSeasonActiveAt(s, o.start))) return true;
    for (final MapEntry(key: s, value: services) in additive.entries) {
      switch (o.liturgy.type) {
        case 'mass':
          if (isSeasonActiveAt(s, o.start) &&
              services.any((x) =>
                  mayReplace(x, o) && (x.liturgy.replacesDay || (x.liturgy.type == 'mass' && overlaps(o, x))))) {
            return true;
          }
        case 'vespers' || 'praise':
          if (services.any((x) => mayReplace(x, o) && overlaps(o, x))) return true;
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
  result.sort(compareOccurrences);
  return result;
}

/// Start time, then a real service before a sample (ADR-050, P3 B2), then
/// the admin's order.
int compareOccurrences(LiturgyOccurrence a, LiturgyOccurrence b) {
  final c = a.start.compareTo(b.start);
  if (c != 0) return c;
  final s = (a.liturgy.sample ? 1 : 0).compareTo(b.liturgy.sample ? 1 : 0);
  return s != 0 ? s : a.liturgy.order.compareTo(b.liturgy.order);
}

/// The regular (non-seasonal) services that [occurrencesForDay] leaves out
/// on the Cairo day of [day] because a season supersedes them — what the
/// weekly tab of /mass-schedule marks «لا يُقام اليوم» and the assistant
/// prompt lists as not held today, so neither contradicts the home card
/// (ADR-050, issue 8). Empty when nothing is superseded.
List<Liturgy> regularSupersededOn({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
}) {
  final dayStart = CairoTime.startOfDay(day);
  final kept = {
    for (final o in occurrencesForDay(liturgies: liturgies, seasons: seasons, day: dayStart, dayOffset: 0))
      o.liturgy.id,
  };
  return [
    for (final l in liturgies)
      if (l.seasonKey == null && _matchesDay(l, dayStart) && l.startMinutes != null && !kept.contains(l.id)) l,
  ];
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
  final running = <LiturgyOccurrence>[];
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

  // Yesterday's occurrences may still be running past midnight (an end at
  // or before the start is the next morning: Easter night 22:30–03:30).
  final yesterday = CairoTime.at(today.year, today.month, today.day - 1);
  for (final o in day(yesterday, -1)) {
    if (o.isHappeningAt(cairoNow)) running.add(o);
  }

  for (var offset = 0; offset <= lookAheadDays && next == null; offset++) {
    final d = CairoTime.at(today.year, today.month, today.day + offset);
    for (final o in day(d, offset)) {
      if (offset == 0 && o.isHappeningAt(cairoNow)) {
        // Keep every running service, not only the first (ADR-049 item 1).
        running.add(o);
        continue;
      }
      if (o.start.isAfter(cairoNow)) {
        next = o;
        break;
      }
    }
  }
  return NextMassResult(
    happeningNow: running.isEmpty ? null : running.first,
    runningNow: List.unmodifiable(running),
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
///
/// Only a service that can take place counts (CodeRabbit on PR #45): it has
/// a start time, and a dated one starts inside the season's window.
bool seasonHasRealServices(Season s, Iterable<Liturgy> all) => all.any((l) {
      if (l.seasonKey != s.key || l.sample || l.startMinutes == null) return false;
      if (l.date == null) return true;
      if (!_dateInSeason(l.date!, s)) return false;
      final d = CairoTime.calendarDate(l.date!);
      final o = _occurrence(l, CairoTime.at(d.year, d.month, d.day), 0);
      return o != null && isSeasonActiveAt(s, o.start);
    });

/// Does the seasonal service [l] of [s] give way on the Cairo day
/// [dayStart]? (ADR-043 B4, widened in ADR-045 B5 and ADR-050)
/// * Any `sample: true` service, undated or dated, once [s] has any real
///   service ([seasonHasRealServices]) — the seed's samples never mix into
///   an owner's programme, Holy Week or revival alike.
/// * Any undated service, and a dated `sample: true` one (CodeRabbit on
///   PR #38), on a day where [s] has dated non-sample services of its own:
///   for a season that replaces the regular schedule any such service that
///   day (the dated programme is the plan for that day); for an additive
///   season one that overlaps it in time (a revival's nightly service still
///   runs on its dated feast-morning liturgy).
/// A dated real service never gives way. Seasons made only of sample data
/// (the bundled seed) are unchanged.
bool undatedSuppressedOn(Season s, Liturgy l, Iterable<Liturgy> all, tz.TZDateTime dayStart) {
  if (l.seasonKey != s.key) return false;
  if (l.date != null && !l.sample) return false;
  // Any sample of a season with a real programme, DATED ones too (ADR-050,
  // P2 B1: the seed's dated Easter-morning sample survived because the
  // owner's overnight liturgy is dated the evening before).
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
    if (s.replacesOn(dayStart)) return true;
    if (mine == null || (o.start.isBefore(mine.end) && mine.start.isBefore(o.end))) return true;
  }
  return false;
}

/// Is the `sample: true` service [l] of [s], on the Cairo day [dayStart],
/// hidden behind a real service of ANOTHER active season held at the same
/// time? The same rule as [occurrencesForDay] (ADR-050, P3 B2), so the
/// season lists never name a sample the day views leave out (ADR-053, sims
/// r2 P3: the seed's St Moses night beside the owner's own revival).
bool _sampleHiddenByOtherSeason(
        Liturgy l, Season s, Iterable<Liturgy> all, Iterable<Season> seasons, tz.TZDateTime dayStart) =>
    _otherSeasonServiceHiding(l, s, all, seasons, dayStart) != null;

/// The real service of another active season that hides the sample [l] of
/// [s] on [dayStart] ([_sampleHiddenByOtherSeason]), or null (ADR-054: the
/// lists name it beside the sample's exception date).
Liturgy? _otherSeasonServiceHiding(
    Liturgy l, Season s, Iterable<Liturgy> all, Iterable<Season> seasons, tz.TZDateTime dayStart) {
  if (!l.sample) return null;
  final mine = _occurrence(l, dayStart, 0);
  if (mine == null) return null;
  for (final d in all) {
    if (d.sample || d.seasonKey == null || d.seasonKey == s.key || !_matchesDay(d, dayStart)) continue;
    final o = _occurrence(d, dayStart, 0);
    if (o == null || !(o.start.isBefore(mine.end) && mine.start.isBefore(o.end))) continue;
    for (final s2 in seasons) {
      if (s2.key == d.seasonKey && isSeasonActiveAt(s2, o.start) && !undatedSuppressedOn(s2, d, all, dayStart)) {
        return d;
      }
    }
  }
  return null;
}

/// [l] is one of [s]'s services for the season lists: its key, and a dated
/// one inside the window, or an undated one that still applies on at least
/// one day of the window with its weekday ([undatedSuppressedOn]). An
/// undated service of an open-ended season is listed unless it is a sample
/// template of a season with real services.
///
/// With [seasons] (the seasons the lists are read against), a `sample` is
/// also left out on a day where a real service of another active season
/// overlaps it, as the day views do: a dated sample on its day, an undated
/// one when that holds on EVERY day of the window with its weekday (on a
/// week without such a real service it would still be held, so it stays
/// listed; ADR-053).
bool liturgyInSeason(Liturgy l, Season s, Iterable<Liturgy> all, [Iterable<Season> seasons = const []]) {
  if (l.seasonKey != s.key) return false;
  if (l.date != null) {
    if (!_dateInSeason(l.date!, s)) return false;
    if (l.sample && seasonHasRealServices(s, all)) return false;
    final d = CairoTime.calendarDate(l.date!);
    final day = CairoTime.at(d.year, d.month, d.day);
    return !undatedSuppressedOn(s, l, all, day) && !_sampleHiddenByOtherSeason(l, s, all, seasons, day);
  }
  if (l.sample && seasonHasRealServices(s, all)) return false;
  final from = s.startsAt, to = s.endsAt, wd = l.weekday;
  if (from == null || to == null || wd == null) return true;
  // Cheap common case (and long seasons such as summer): no dated real
  // service in the window at all, so no day can suppress it, and (for a
  // sample) no real service of another active season to hide behind.
  final ownDated = all.any((d) => d.seasonKey == s.key && d.date != null && !d.sample && _dateInSeason(d.date!, s));
  final crossCheck = _crossSeasonCheck(l, s, all, seasons);
  if (!ownDated && !crossCheck) return true;
  var sawWeekday = false;
  final first = CairoTime.calendarDate(from), last = CairoTime.calendarDate(to);
  final lastDay = CairoTime.at(last.year, last.month, last.day);
  var day = CairoTime.at(first.year, first.month, first.day);
  for (var i = 0; i < 400 && !day.isAfter(lastDay); i++) {
    // Only a day where the occurrence really starts inside the window counts
    // (a 07:00 service on an 18:00 start day is not part of the season, as in
    // [occurrencesForDay]; CodeRabbit on PR #47).
    // A service without a start time keeps the day check alone (unchanged).
    final o = day.weekday == wd ? _occurrence(l, day, 0) : null;
    if (day.weekday == wd && (l.startMinutes == null || (o != null && isSeasonActiveAt(s, o.start)))) {
      sawWeekday = true;
      if (!undatedSuppressedOn(s, l, all, day) &&
          !(crossCheck && _sampleHiddenByOtherSeason(l, s, all, seasons, day))) {
        return true;
      }
    }
    day = CairoTime.at(day.year, day.month, day.day + 1);
  }
  // A window longer than the scan: the rest is not checked, so it stays
  // listed (CodeRabbit on PR #47).
  if (!day.isAfter(lastDay)) return true;
  // No such weekday in the window at all: listed as before (unchanged).
  return !sawWeekday;
}

/// Can a real service of another active season hide the sample [l] of [s]?
bool _crossSeasonCheck(Liturgy l, Season s, Iterable<Liturgy> all, Iterable<Season> seasons) =>
    l.sample &&
    all.any((d) =>
        !d.sample &&
        d.seasonKey != null &&
        d.seasonKey != s.key &&
        seasons.any((s2) => s2.active && s2.key == d.seasonKey));

/// A day on which a listed undated sample is NOT held because a real
/// service of another season ([by]) takes its time (ADR-054).
class SeasonListException {
  /// The Cairo calendar date (year, month, day; time 00:00).
  final DateTime date;
  final Liturgy by;
  const SeasonListException(this.date, this.by);

  @override
  String toString() => 'SeasonListException(${date.year}-${date.month}-${date.day}, ${by.id})';
}

/// The days of [s]'s window on which the undated `sample` [l] is hidden
/// behind a real service of another active season ([_sampleHiddenByOtherSeason]),
/// in date order, from the Cairo day of [from] on when given (ADR-054, sims
/// r3 P3 item 9). [liturgyInSeason] keeps such a sample listed while any
/// other matching day still holds it; the lists then state these days
/// («لا يُقام ٢٣ يونيو», "(not on 2027-06-23: replaced by …)") so the list
/// never contradicts the day views. Empty for a dated or real service, an
/// open-ended season, or a sample no other season's real service can hide.
List<SeasonListException> seasonListExceptions(Liturgy l, Season s, Iterable<Liturgy> all,
    {Iterable<Season> seasons = const [], DateTime? from}) {
  if (l.seasonKey != s.key || l.date != null || !l.sample) return const [];
  final start = s.startsAt, end = s.endsAt, wd = l.weekday;
  if (start == null || end == null || wd == null || l.startMinutes == null) return const [];
  if (!_crossSeasonCheck(l, s, all, seasons)) return const [];
  final first = CairoTime.calendarDate(start), last = CairoTime.calendarDate(end);
  final lastDay = CairoTime.at(last.year, last.month, last.day);
  final fromDay = from == null ? null : CairoTime.startOfDay(CairoTime.fromInstant(from));
  final out = <SeasonListException>[];
  // The scan starts at today when that is later, so the 400 days checked are
  // the upcoming ones (CodeRabbit on PR #48).
  var day = CairoTime.at(first.year, first.month, first.day);
  if (fromDay != null && fromDay.isAfter(day)) day = fromDay;
  for (var i = 0; i < 400 && !day.isAfter(lastDay); i++) {
    if (day.weekday == wd) {
      final o = _occurrence(l, day, 0);
      if (o != null && isSeasonActiveAt(s, o.start) && !undatedSuppressedOn(s, l, all, day)) {
        final by = _otherSeasonServiceHiding(l, s, all, seasons, day);
        if (by != null) out.add(SeasonListException(DateTime(day.year, day.month, day.day), by));
      }
    }
    day = CairoTime.at(day.year, day.month, day.day + 1);
  }
  return out;
}

/// Has [s] ended before the Cairo day of [now] began? Such a season is no
/// longer listed on /mass-schedule or in the assistant prompt (ADR-054, sims
/// r3 P1 O-2: Nativity and the January revival listed on Good Friday). A
/// season ending later today stays listed until midnight.
bool seasonEndedBeforeToday(Season s, DateTime now) {
  final end = s.endsAt;
  if (end == null) return false;
  return end.isBefore(CairoTime.startOfDay(CairoTime.fromInstant(now)));
}

/// Seasonal liturgies grouped by season, for active seasons only, seasons
/// sorted by start date. A dated liturgy is attached only to the season
/// whose window covers its day, so e.g. 2027 and 2028 seasons sharing a key
/// never pick up each other's services; an undated one only when it still
/// falls on a day of the season without dated services ([liturgyInSeason]).
/// A sample hidden behind another active season's real service is left out
/// ([liturgyInSeason]); [context] are the seasons that check reads (default:
/// [seasons]), so a view listing only some seasons still sees the others.
///
/// With [now], a season that ended before the Cairo day of [now] is left out
/// ([seasonEndedBeforeToday], ADR-054); it still counts in [context].
Map<Season, List<Liturgy>> seasonalSchedule(Iterable<Season> seasons, Iterable<Liturgy> all,
    {Iterable<Season>? context, DateTime? now}) {
  final ctx = (context ?? seasons).where((s) => s.active).toList();
  final sorted = seasons.where((s) => s.active && (now == null || !seasonEndedBeforeToday(s, now))).toList()
    ..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
  final map = <Season, List<Liturgy>>{};
  for (final s in sorted) {
    final ls = all.where((l) => liturgyInSeason(l, s, all, ctx)).toList()
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

/// The day a service belongs to: `('d', days since epoch)` for a one-off
/// date, `('w', ISO weekday)` for a weekly one, null when it has neither.
(String, int)? _slotDay(Liturgy l) {
  final d = l.date;
  if (d != null) {
    final c = CairoTime.calendarDate(d);
    return ('d', DateTime.utc(c.year, c.month, c.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
  }
  final w = l.weekday;
  return w == null ? null : ('w', w);
}

/// [minutes] from the Cairo midnight of the one-off service [l]'s date as a
/// real instant (minutes past 24:00 roll into the next day).
DateTime _instant(Liturgy l, int minutes) {
  final c = CairoTime.calendarDate(l.date!);
  return CairoTime.at(c.year, c.month, c.day, minutes);
}

/// Whole days from [a]'s day to [b]'s day when they are the same day or
/// adjacent (-1, 0, 1; weekly days wrap Sunday → Monday), else null. Two
/// services on adjacent days can overlap when one crosses midnight
/// (ADR-049: Easter night 22:30–03:30 and a 00:00 service the next day).
int? _dayShift((String, int) a, (String, int) b) {
  if (a.$1 != b.$1) return null;
  var diff = b.$2 - a.$2;
  if (a.$1 == 'w') {
    diff = ((diff % 7) + 7) % 7;
    if (diff == 6) diff = -1;
  }
  return diff >= -1 && diff <= 1 ? diff : null;
}

/// Services of [list] held at the same time in ANOTHER venue / hall
/// (ADR-041: Holy Week prayers in the main church, the lower hall and the
/// services building for different age groups). Two services are parallel
/// when their times overlap on the same day or across midnight on adjacent
/// days (date, or weekday for weekly ones; a service without an end time
/// counts as one minute, an end at or before the start crosses midnight into
/// the next day, ADR-049) and
/// their venues (or places) differ — both must name one. Returns, for each
/// liturgy id that has any, the other services in start order.
Map<String, List<Liturgy>> parallelServices(Iterable<Liturgy> list, [ProgramOptions? opts]) {
  final items = [
    for (final l in list)
      if (l.startMinutes != null && _placeKey(l, opts).isNotEmpty && _slotDay(l) != null) l,
  ];
  // For each id: the other services with their start on its own clock.
  final found = <String, List<(Liturgy, int)>>{};
  for (var i = 0; i < items.length; i++) {
    final a = items[i];
    final aStart = a.startMinutes!;
    final aEnd = _endMinutes(a);
    for (var j = i + 1; j < items.length; j++) {
      final b = items[j];
      final shift = _dayShift(_slotDay(a)!, _slotDay(b)!);
      if (shift == null || _placeKey(a, opts) == _placeKey(b, opts)) continue;
      // b on a's clock: +24 h when it is the next day, -24 h the day before.
      final bStart = b.startMinutes! + shift * 24 * 60;
      final bEnd = _endMinutes(b) + shift * 24 * 60;
      // One-off dates compare real Cairo instants, so a wall time skipped by
      // the spring DST change (00:30 on the last Friday of April) cannot
      // fake an overlap (CodeRabbit on PR #42); weekly services have no date
      // and keep the nominal clock.
      final overlap = _slotDay(a)!.$1 == 'd'
          ? _instant(a, aStart).isBefore(_instant(b, _endMinutes(b))) &&
              _instant(b, b.startMinutes!).isBefore(_instant(a, aEnd))
          : aStart < bEnd && bStart < aEnd;
      if (overlap) {
        (found[a.id] ??= []).add((b, bStart));
        (found[b.id] ??= []).add((a, aStart - shift * 24 * 60));
      }
    }
  }
  return {
    for (final MapEntry(:key, :value) in found.entries)
      key: [for (final (l, _) in value..sort((x, y) => x.$2.compareTo(y.$2))) l],
  };
}

/// The occurrences of the Cairo day of [day] together with those of the day
/// before and the day after ([occurrencesForDay] each, with their own
/// season windows), so services overlapping across midnight compare
/// (ADR-049: the next-service card's «وفي نفس الوقت» line for a service at
/// 22:30 that runs into a 00:00 one, or the reverse).
List<LiturgyOccurrence> occurrencesAround({
  required Iterable<Liturgy> liturgies,
  required Iterable<Season> seasons,
  required tz.TZDateTime day,
  required int dayOffset,
}) {
  final d = CairoTime.fromInstant(day);
  return [
    for (final k in const [-1, 0, 1])
      ...occurrencesForDay(
          liturgies: liturgies,
          seasons: seasons,
          day: CairoTime.at(d.year, d.month, d.day + k),
          dayOffset: dayOffset + k),
  ];
}

/// The services held at the same time as [target] in ANOTHER venue / hall,
/// among [sameDay] = that day's real occurrences ([occurrencesForDay]: season
/// windows and suppression already applied), for the next-service card
/// (Sentry review on PR #32). Overlap uses the real instants (a service
/// without an end time counts as one minute), places compare as in
/// [parallelServices].
List<Liturgy> parallelOccurrences(LiturgyOccurrence target, Iterable<LiturgyOccurrence> sameDay,
        [ProgramOptions? opts]) =>
    [for (final o in parallelOccurrencesOf(target, sameDay, opts)) o.liturgy];

/// [parallelOccurrences] with each service's own occurrence, so the card
/// can tell one starting with [target] («وفي نفس الوقت») from one starting
/// later while [target] runs («وبعدها ٠٧:٠٠ ص: …», ADR-053, sims r2 P2 O-a).
List<LiturgyOccurrence> parallelOccurrencesOf(LiturgyOccurrence target, Iterable<LiturgyOccurrence> sameDay,
    [ProgramOptions? opts]) {
  final key = _placeKey(target.liturgy, opts);
  if (key.isEmpty) return const [];
  DateTime endOf(LiturgyOccurrence o) =>
      o.liturgy.endMinutes == null ? o.start.add(const Duration(minutes: 1)) : o.end;
  final tEnd = endOf(target);
  return [
    for (final o in sameDay)
      if (o.liturgy.id != target.liturgy.id &&
          _placeKey(o.liturgy, opts).isNotEmpty &&
          _placeKey(o.liturgy, opts) != key &&
          o.start.isBefore(tEnd) &&
          target.start.isBefore(endOf(o)))
        o,
  ]..sort((a, b) => a.start.compareTo(b.start));
}
