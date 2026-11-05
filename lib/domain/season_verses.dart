// Season verse sets (ADR-042, owner plan §2.6 / §3): while a season is
// active, "verse of the day" rotates through the verses the admin chose for
// it (e.g. Holy Week verses) instead of the general list. Stored in
// `settings/features.seasonVerses` (no new document or listener) as up to
// [SeasonVerses.max] strings `seasonKey␟textAr␟refAr`, optionally followed by
// `␟textEn␟refEn` (ADR-047). Pure Dart.

import 'daily_verse.dart';
import 'models.dart' show Season;
import 'schedule.dart' show isSeasonActiveAt;

class SeasonVerses {
  /// At most this many verses in all (firestore.rules validSeasonVerses).
  static const max = 40;
  static const maxText = DailyVerseConfig.maxText, maxRef = DailyVerseConfig.maxRef;
  static const sep = '\u001f';

  /// The season keys a set can belong to (validSeason's `key` list).
  static const seasonKeys = [
    'holy_week', 'pascha', 'nativity', 'epiphany', 'marian', 'fast', 'revival_maximus', 'revival_moses', 'summer', //
  ];

  /// Season key → its verses, in the admin's order.
  final Map<String, List<Verse>> bySeason;
  const SeasonVerses([this.bySeason = const {}]);
  static const none = SeasonVerses();

  bool get isEmpty => bySeason.isEmpty;

  static SeasonVerses fromList(Object? raw) {
    if (raw is! List) return none;
    final out = <String, List<Verse>>{};
    var n = 0;
    for (final v in raw) {
      if (v is! String || n >= max) continue;
      final p = v.split(sep);
      if (p.length < 2 || !seasonKeys.contains(p[0])) continue;
      final text = p[1].trim();
      if (text.isEmpty) continue;
      String at(int i) => p.length > i ? p[i].trim() : '';
      (out[p[0]] ??= []).add(Verse(textAr: text, refAr: at(2), textEn: at(3), refEn: at(4)));
      n++;
    }
    return out.isEmpty ? none : SeasonVerses(out);
  }

  /// The set of the active season at [instant] that has verses: when
  /// several are active, the one that started last (the more specific one,
  /// e.g. Holy Week inside a longer season). Empty = no season set applies.
  List<Verse> activeSet(Iterable<Season> seasons, DateTime instant) {
    if (isEmpty) return const [];
    Season? best;
    for (final s in seasons) {
      if (!(bySeason[s.key]?.isNotEmpty ?? false) || !isSeasonActiveAt(s, instant)) continue;
      final a = s.startsAt, b = best?.startsAt;
      if (best == null || (a != null && (b == null || a.isAfter(b)))) best = s;
    }
    return best == null ? const [] : bySeason[best.key]!;
  }
}

/// The verse for the home page: a fixed admin verse wins; else, while a
/// season with its own verse set is active, that set rotates by day; else
/// the general daily rotation ([resolveDailyVerse]).
Verse? resolveSeasonalVerse(
  DailyVerseConfig config,
  List<Verse> verses,
  DateTime instant, {
  DateTime? day,
  List<Verse> seasonSet = const [],
}) {
  final fixed = config.mode == DailyVerseConfig.fixed && config.textAr.trim().isNotEmpty;
  if (!fixed && seasonSet.isNotEmpty) {
    return day != null ? verseForDate(seasonSet, day) : verseForDay(seasonSet, instant);
  }
  return resolveDailyVerse(config, verses, instant, day: day);
}
