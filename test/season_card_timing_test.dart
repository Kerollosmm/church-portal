// ADR-048: findings of the Phase 1 seasons simulation
// (work/seasons-sim/phase1/report.md) and the owner's follow-ups.
// 1. The «يُقام الآن» box names every other service running at that moment
//    in another hall («وفي نفس الوقت: …»), not only the first one.
// 2. Overnight services (end at or before the start: Easter night 22:30–03:30,
//    Kiahk 21:00–05:30, the Apocalypse night) run into the next morning: never
//    finished before they start, still «يُقام الآن» after midnight (the
//    previous day's record), across the 18:00 liturgical-day shift and both
//    Egypt DST changes.
// 3. The /mass-schedule seasonal switch: ON and OFF clearly apart on every
//    theme (Holy Week's charcoal included), palette roles only, ≥ 3:1.
// 4. Additive seasons: morning mass → evening revival → next morning's mass,
//    minute by minute, nothing drops or cancels anything.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

Liturgy lit(String id,
        {int? weekday,
        DateTime? date,
        required String start,
        required String end,
        String type = 'other',
        String? season,
        String venue = '',
        String audience = '',
        String speaker = ''}) =>
    Liturgy(
      id: id,
      type: type,
      nameAr: 'خدمة $id',
      nameEn: 'Service $id',
      weekday: weekday,
      date: date,
      start: start,
      end: end,
      seasonKey: season,
      program: ProgramInfo(venue: venue, audience: audience, speakerAr: speaker),
    );

Season season(String key, tz.TZDateTime from, tz.TZDateTime to, {bool replaces = true}) => Season(
    id: '$key-${from.year}',
    key: key,
    nameAr: 'موسم $key',
    nameEn: 'Season $key',
    startsAt: from,
    endsAt: to,
    replacesRegular: replaces);

// ── Phase 1 data: Holy Thursday 29 Apr 2027 (Good Friday = DST start day).
final holyWeek27 = season('holy_week', cairo(2027, 4, 25), cairo(2027, 5, 1, 18));
final hwLits = [
  lit('morning', date: DateTime(2027, 4, 29), start: '07:00', end: '12:30', season: 'holy_week', venue: 'main', audience: 'general'),
  lit('evening', date: DateTime(2027, 4, 29), start: '18:00', end: '23:00', season: 'holy_week', venue: 'main', audience: 'general', speaker: 'متكلم'),
  lit('youth', date: DateTime(2027, 4, 29), start: '18:30', end: '21:30', season: 'holy_week', venue: 'lower', audience: 'youth'),
  lit('kids', date: DateTime(2027, 4, 29), start: '18:30', end: '20:30', season: 'holy_week', venue: 'services', audience: 'kids'),
  lit('elders', date: DateTime(2027, 4, 29), start: '19:00', end: '22:00', season: 'holy_week', venue: 'services', audience: 'general'),
  lit('friday', date: DateTime(2027, 4, 30), start: '08:00', end: '17:00', season: 'holy_week', venue: 'main', audience: 'general'),
  // Regular weekly masses the season replaces.
  lit('reg-thu', weekday: 4, start: '07:00', end: '09:00', type: 'mass'),
  lit('reg-fri', weekday: 5, start: '07:00', end: '09:00', type: 'mass'),
  lit('reg-sat', weekday: 6, start: '07:00', end: '09:00', type: 'mass'),
  lit('reg-sun', weekday: 7, start: '07:00', end: '09:30', type: 'mass'),
];

class _Repo extends SeedRepository {
  _Repo(super.seed, this._lits, this._seasons);
  final List<Liturgy> _lits;
  final List<Season> _seasons;
  @override
  Stream<List<Liturgy>> liturgies() => Stream.value(_lits);
  @override
  Stream<List<Season>> seasons() => Stream.value(_seasons);
}

List<String> ids(Iterable<Liturgy> l) => [for (final x in l) x.id];

NextMassResult at(DateTime now, List<Liturgy> lits, List<Season> seasons) =>
    computeNextMass(liturgies: lits, seasons: seasons, now: now);

  Future<void> pump(WidgetTester tester, Widget child, DateTime now, List<Liturgy> lits, List<Season> seasons,
      {String theme = ThemePresets.goldenHour, bool scroll = true}) async {
    final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(_Repo(SeedData(raw), lits, seasons)),
        nowProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: MaterialApp(
          theme: buildTheme(const Locale('ar'), palette: ThemePresets.palettes[theme]!.normalized(), key: theme),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child)),
    ));
    await tester.pumpAndSettle();
  }

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('1: parallel services in the «يُقام الآن» box', () {
    test('at 18:30 every running service is kept, the first one is shown', () {
      final r = at(cairo(2027, 4, 29, 18, 30), hwLits, [holyWeek27]);
      expect(r.happeningNow?.liturgy.id, 'evening');
      expect(ids(r.runningNow.map((o) => o.liturgy)), ['evening', 'youth', 'kids']);
      expect(ids(r.alsoRunning()), ['youth', 'kids']);
      expect(r.next?.liturgy.id, 'elders');
    });

    test('at 19:30 elders joins; at 21:45 only main is left, no line', () {
      expect(ids(at(cairo(2027, 4, 29, 19, 30), hwLits, [holyWeek27]).alsoRunning()), ['youth', 'kids', 'elders']);
      expect(ids(at(cairo(2027, 4, 29, 20, 30), hwLits, [holyWeek27]).alsoRunning()), ['youth', 'elders'],
          reason: 'kids ends at 20:30 (end exclusive)');
      final late = at(cairo(2027, 4, 29, 22, 30), hwLits, [holyWeek27]);
      expect(late.happeningNow?.liturgy.id, 'evening');
      expect(late.alsoRunning(), isEmpty);
    });

    test('a service in the same hall, or without a place, is not named (ADR-041 rule)', () {
      final lits = [
        lit('a', date: DateTime(2027, 4, 29), start: '18:00', end: '21:00', season: 'holy_week', venue: 'main'),
        lit('b', date: DateTime(2027, 4, 29), start: '18:30', end: '21:00', season: 'holy_week', venue: 'main'),
        lit('c', date: DateTime(2027, 4, 29), start: '18:30', end: '21:00', season: 'holy_week'),
      ];
      final r = at(cairo(2027, 4, 29, 19), lits, [holyWeek27]);
      expect(r.runningNow.length, 3);
      expect(r.alsoRunning(), isEmpty);
    });

    test('nothing running: no list', () {
      final r = at(cairo(2027, 4, 29, 13), hwLits, [holyWeek27]);
      expect(r.happeningNow, isNull);
      expect(r.runningNow, isEmpty);
      expect(r.alsoRunning(), isEmpty);
    });
  });

  group('2: overnight services', () {
    // Coptic Easter 2027 = Sun 2 May; the Easter night liturgy is on the
    // Saturday's record, 22:30 → 03:30 Sunday (after the DST change).
    final pascha = season('pascha', cairo(2027, 5, 1, 18), cairo(2027, 6, 10));
    final easter =
        lit('easter', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', type: 'mass', season: 'pascha', venue: 'main', speaker: 'الأب الكاهن');
    final sunMass = lit('reg-sun', weekday: 7, start: '07:00', end: '09:30', type: 'mass');
    final lits = [easter, sunMass];

    test('minute by minute Sat 18:00 → Sun 08:00: next, then «يُقام الآن» across midnight, then Sunday', () {
      final start = cairo(2027, 5, 1, 18), stop = cairo(2027, 5, 2, 8);
      final eStart = cairo(2027, 5, 1, 22, 30), eEnd = cairo(2027, 5, 2, 3, 30);
      for (var t = start; t.isBefore(stop); t = t.add(const Duration(minutes: 1))) {
        final r = at(t, lits, [pascha]);
        final running = !t.isBefore(eStart) && t.isBefore(eEnd);
        if (t.isBefore(eStart)) {
          expect(r.happeningNow, isNull, reason: '$t');
          expect(r.next?.liturgy.id, 'easter', reason: 'not finished before it starts: $t');
        } else if (running) {
          expect(r.happeningNow?.liturgy.id, 'easter', reason: '$t');
          expect(r.happeningNow?.dayOffset, t.day == 1 ? 0 : -1, reason: 'the Saturday record after midnight: $t');
          expect(r.next?.liturgy.id, 'reg-sun', reason: '$t');
        } else {
          expect(r.happeningNow?.liturgy.id, t.isBefore(cairo(2027, 5, 2, 7)) ? isNull : 'reg-sun', reason: '$t');
        }
      }
    });

    test('at 00:30 Sunday: still running, top event, dated list and duration', () {
      final t = cairo(2027, 5, 2, 0, 30);
      final r = at(t, lits, [pascha]);
      expect(r.happeningNow?.liturgy.id, 'easter');
      expect(r.happeningNow!.end, cairo(2027, 5, 2, 3, 30));
      expect(r.happeningNow!.end.difference(r.happeningNow!.start), const Duration(hours: 5));
      // Top event: the programme service is still on.
      final e = resolveTopEvent(now: t, settings: TodaySettings.defaults, events: const [], liturgies: lits, seasons: [pascha]);
      expect(e?.kind, TopEventKind.service);
      expect(e?.service?.liturgy.id, 'easter');
      // The dated one-off list keeps it while it runs, then drops it.
      final oneOff = lit('nye', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', type: 'mass');
      expect(isDatedLiturgyCurrent(oneOff, t), isTrue);
      expect(isDatedLiturgyCurrent(oneOff, cairo(2027, 5, 2, 3, 30)), isFalse);
      expect(isDatedLiturgyCurrent(oneOff, cairo(2027, 4, 30, 23)), isTrue, reason: 'upcoming');
    });

    test('the assistant line says it ends the next morning', () {
      final ctx = buildAssistantInstruction(
        settings: const ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: ''),
        liturgies: [lit('nye', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', type: 'mass')],
        seasons: const [],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        now: cairo(2027, 5, 2, 0, 30),
      );
      expect(ctx, contains('10:30 PM – 03:30 AM (ends the next morning, after midnight)'));
    });

    test('Kiahk 21:00–05:30 then the 05:30–07:30 liturgy (additive), across the 18:00 shift', () {
      final kiahk = season('kiahk', cairo(2026, 12, 10), cairo(2027, 1, 7, 23), replaces: false);
      final tasbeha = lit('tasbeha', weekday: 6, start: '21:00', end: '05:30', type: 'praise', season: 'kiahk', venue: 'main');
      final liturgy = lit('kiahk-mass', weekday: 7, start: '05:30', end: '07:30', type: 'mass', season: 'kiahk', venue: 'main');
      final satVespers = lit('sat-vespers', weekday: 6, start: '17:00', end: '18:00', type: 'vespers');
      final all = [tasbeha, liturgy, satVespers];
      final settings = TodaySettings.defaults;
      // Sat 19 Dec 2026, 18:00 → Sun 20 Dec 08:00.
      for (var t = cairo(2026, 12, 19, 18); t.isBefore(cairo(2026, 12, 20, 8)); t = t.add(const Duration(minutes: 1))) {
        final r = at(t, all, [kiahk]);
        final tStart = cairo(2026, 12, 19, 21), tEnd = cairo(2026, 12, 20, 5, 30), lEnd = cairo(2026, 12, 20, 7, 30);
        if (t.isBefore(tStart)) {
          expect(r.happeningNow, isNull, reason: '$t');
          expect(r.next?.liturgy.id, 'tasbeha', reason: '$t');
          expect(settings.isEveService(r.next!.start), isTrue, reason: 'after 18:00: «الليلة • ليلة الأحد»');
        } else if (t.isBefore(tEnd)) {
          expect(r.happeningNow?.liturgy.id, 'tasbeha', reason: '$t');
          expect(r.next?.liturgy.id, 'kiahk-mass', reason: 'the next liturgy follows without a gap: $t');
        } else if (t.isBefore(lEnd)) {
          expect(r.happeningNow?.liturgy.id, 'kiahk-mass', reason: 'the tasbeha ended at 05:30 sharp: $t');
          expect(r.runningNow.length, 1, reason: '$t');
        } else {
          expect(r.happeningNow, isNull, reason: '$t');
        }
      }
      // The Saturday 17:00 vespers does not overlap the tasbeha: it stays.
      final sat = occurrencesForDay(liturgies: all, seasons: [kiahk], day: cairo(2026, 12, 19), dayOffset: 0);
      expect(ids(sat.map((o) => o.liturgy)), ['sat-vespers', 'tasbeha']);
    });

    test('Apocalypse night Fri 23:00 → Sat 06:00 then the Saturday liturgy; Good Friday is the DST start day', () {
      final apoc = lit('apocalypse', date: DateTime(2027, 4, 30), start: '23:00', end: '06:00', season: 'holy_week', venue: 'main', speaker: 'متكلم');
      final joy = lit('joy-sat', date: DateTime(2027, 5, 1), start: '06:00', end: '09:00', type: 'mass', season: 'holy_week', venue: 'main');
      final all = [...hwLits, apoc, joy];
      final settings = TodaySettings.defaults;
      // Friday 20:00 (after the 18:00 shift): next is tonight's Apocalypse,
      // the eve of Saturday.
      final fri = at(cairo(2027, 4, 30, 20), all, [holyWeek27]);
      expect(fri.next?.liturgy.id, 'apocalypse');
      expect(fri.next?.dayOffset, 0);
      expect(settings.isEveService(fri.next!.start), isTrue);
      for (final (h, m) in [(23, 0), (23, 59)]) {
        expect(at(cairo(2027, 4, 30, h, m), all, [holyWeek27]).happeningNow?.liturgy.id, 'apocalypse');
      }
      for (final (h, m) in [(0, 0), (0, 30), (3, 0), (5, 59)]) {
        final r = at(cairo(2027, 5, 1, h, m), all, [holyWeek27]);
        expect(r.happeningNow?.liturgy.id, 'apocalypse', reason: '$h:$m');
        expect(r.happeningNow?.dayOffset, -1);
        expect(r.next?.liturgy.id, 'joy-sat');
        final e = resolveTopEvent(
            now: cairo(2027, 5, 1, h, m), settings: settings, events: const [], liturgies: all, seasons: [holyWeek27]);
        expect(e?.service?.liturgy.id, 'apocalypse', reason: 'top event after midnight $h:$m');
      }
      final six = at(cairo(2027, 5, 1, 6), all, [holyWeek27]);
      expect(six.happeningNow?.liturgy.id, 'joy-sat');
      expect(six.runningNow.length, 1);
      // The regular Saturday mass stays replaced (the season replaces it).
      expect(ids(occurrencesForDay(liturgies: all, seasons: [holyWeek27], day: cairo(2027, 5, 1), dayOffset: 0)
              .map((o) => o.liturgy)),
          ['joy-sat']);
    });

    test('DST start (Fri 30 Apr 2027 00:00 → 01:00): Thursday 22:30–03:30 lasts 4 real hours', () {
      final night = lit('thu-night', date: DateTime(2027, 4, 29), start: '22:30', end: '03:30', season: 'holy_week', venue: 'main');
      final all = [night];
      final r = at(cairo(2027, 4, 30, 1, 30), all, [holyWeek27]);
      expect(r.happeningNow?.liturgy.id, 'thu-night');
      expect(r.happeningNow!.end.difference(r.happeningNow!.start), const Duration(hours: 4));
      expect(r.happeningNow!.end.toUtc(), DateTime.utc(2027, 4, 30, 0, 30), reason: '03:30 EEST');
      expect(at(DateTime.utc(2027, 4, 29, 21, 59), all, [holyWeek27]).happeningNow?.liturgy.id, 'thu-night',
          reason: '23:59 EET');
      expect(at(DateTime.utc(2027, 4, 29, 22, 0), all, [holyWeek27]).happeningNow?.liturgy.id, 'thu-night',
          reason: '01:00 EEST, the first instant after the jump');
      expect(at(DateTime.utc(2027, 4, 30, 0, 30), all, [holyWeek27]).happeningNow, isNull, reason: 'ended at 03:30');
    });

    test('DST end (Thu 28 Oct 2027 24:00 → 23:00): Thursday 22:30–03:30 runs through both 23:30s', () {
      final rev = season('revival', cairo(2027, 10, 20), cairo(2027, 11, 5), replaces: false);
      final night = lit('night', date: DateTime(2027, 10, 28), start: '22:30', end: '03:30', season: 'revival', venue: 'main');
      final all = [night];
      final r0 = at(DateTime.utc(2027, 10, 28, 20, 30), all, [rev]); // 23:30 EEST
      final r1 = at(DateTime.utc(2027, 10, 28, 21, 30), all, [rev]); // 23:30 EET (repeated hour)
      final r2 = at(DateTime.utc(2027, 10, 29, 0, 30), all, [rev]); // 02:30 EET
      for (final r in [r0, r1, r2]) {
        expect(r.happeningNow?.liturgy.id, 'night');
      }
      expect(r1.happeningNow!.end.difference(r1.happeningNow!.start), const Duration(hours: 6));
      expect(at(DateTime.utc(2027, 10, 29, 1, 30), all, [rev]).happeningNow, isNull, reason: '03:30 EET');
    });

    test('parallel services across midnight (schedule lists and the card)', () {
      final a = lit('sat-night', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', venue: 'main', audience: 'general');
      final b = lit('sun-early', date: DateTime(2027, 5, 2), start: '00:00', end: '02:00', venue: 'lower', audience: 'youth');
      final c = lit('sun-late', date: DateTime(2027, 5, 2), start: '04:00', end: '05:00', venue: 'lower', audience: 'youth');
      final p = parallelServices([a, b, c]);
      expect(ids(p['sat-night'] ?? const []), ['sun-early']);
      expect(ids(p['sun-early'] ?? const []), ['sat-night']);
      expect(p['sun-late'], isNull);
      // Weekly wrap: Sunday 23:00–01:00 and Monday 00:00–00:30.
      final w = parallelServices([
        lit('sun', weekday: 7, start: '23:00', end: '01:00', venue: 'main'),
        lit('mon', weekday: 1, start: '00:00', end: '00:30', venue: 'lower'),
        lit('tue', weekday: 2, start: '00:00', end: '00:30', venue: 'lower'),
      ]);
      expect(ids(w['sun'] ?? const []), ['mon']);
      expect(w['tue'], isNull);
      // The card: the next service at 22:30 meets the 00:00 one.
      final s = season('pascha', cairo(2027, 5, 1), cairo(2027, 6, 1));
      final sa = lit('sat-night', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', season: 'pascha', venue: 'main');
      final sb = lit('sun-early', date: DateTime(2027, 5, 2), start: '00:00', end: '02:00', season: 'pascha', venue: 'lower');
      final r = at(cairo(2027, 5, 1, 20), [sa, sb], [s]);
      expect(r.next?.liturgy.id, 'sat-night');
      final around = occurrencesAround(liturgies: [sa, sb], seasons: [s], day: r.next!.start, dayOffset: r.next!.dayOffset);
      expect(ids(parallelOccurrences(r.next!, around)), ['sun-early']);
      // And at 00:30 both run: the box names the lower hall.
      final r2 = at(cairo(2027, 5, 2, 0, 30), [sa, sb], [s]);
      expect(r2.happeningNow?.liturgy.id, 'sat-night');
      expect(ids(r2.alsoRunning()), ['sun-early']);
    });
  });

  group('4: additive revival, day to night handover, minute by minute', () {
    // A summer revival (EEST): regular daily mass 07:00–09:00, revival nights
    // 19:00–21:30 on 10–13 Aug 2027 with a programme.
    final revival = season('revival_virgin', cairo(2027, 8, 7), cairo(2027, 8, 21, 23), replaces: false);
    final daily = [for (var wd = 1; wd <= 7; wd++) lit('mass-$wd', weekday: wd, start: '07:00', end: '09:00', type: 'mass', venue: 'main')];
    final nights = [
      for (var d = 10; d <= 13; d++)
        lit('night-$d', date: DateTime(2027, 8, d), start: '19:00', end: '21:30', type: 'vespers', season: 'revival_virgin', venue: 'main', speaker: 'متكلم'),
    ];
    final all = [...daily, ...nights];

    // Independent oracle: the expected intervals, built by hand.
    final expected = <(String, DateTime, DateTime)>[
      for (var d = 10; d <= 16; d++) ...[
        ('mass-${DateTime(2027, 8, d).weekday}', cairo(2027, 8, d, 7), cairo(2027, 8, d, 9)),
        if (d <= 13) ('night-$d', cairo(2027, 8, d, 19), cairo(2027, 8, d, 21, 30)),
      ],
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    test('Wed 11 → Thu 12 Aug, every minute: happening and next match the oracle', () {
      for (var t = cairo(2027, 8, 11); t.isBefore(cairo(2027, 8, 13)); t = t.add(const Duration(minutes: 1))) {
        final r = at(t, all, [revival]);
        final run = [for (final e in expected) if (!t.isBefore(e.$2) && t.isBefore(e.$3)) e.$1];
        final nxt = expected.firstWhere((e) => e.$2.isAfter(t)).$1;
        expect(r.happeningNow?.liturgy.id, run.isEmpty ? isNull : run.first, reason: 'happening at $t');
        expect(ids(r.runningNow.map((o) => o.liturgy)), run, reason: 'running at $t');
        expect(r.next?.liturgy.id, nxt, reason: 'next at $t');
      }
    });

    test('the handover points, with the 18:00 shift', () {
      final settings = TodaySettings.defaults;
      // 08:59 the mass runs and tonight's revival is next.
      final a = at(cairo(2027, 8, 11, 8, 59), all, [revival]);
      expect((a.happeningNow?.liturgy.id, a.next?.liturgy.id), ('mass-3', 'night-11'));
      // 09:00 sharp: the mass ended, the revival is «الصلاة القادمة».
      final b = at(cairo(2027, 8, 11, 9), all, [revival]);
      expect((b.happeningNow, b.next?.liturgy.id), (null, 'night-11'));
      expect(settings.isEveService(b.next!.start), isTrue, reason: '19:00 is after the 18:00 shift');
      // 19:00 it starts; tomorrow's mass is next.
      final c = at(cairo(2027, 8, 11, 19), all, [revival]);
      expect((c.happeningNow?.liturgy.id, c.next?.liturgy.id, c.next?.dayOffset), ('night-11', 'mass-4', 1));
      // 21:30 sharp: it ended; the next day's mass at once.
      final d = at(cairo(2027, 8, 11, 21, 30), all, [revival]);
      expect((d.happeningNow, d.next?.liturgy.id, d.next?.dayOffset), (null, 'mass-4', 1));
      // The revival never removes the regular morning mass.
      expect(ids(occurrencesForDay(liturgies: all, seasons: [revival], day: cairo(2027, 8, 11), dayOffset: 0)
              .map((o) => o.liturgy)),
          ['mass-3', 'night-11']);
    });
  });

  group('widgets', () {
    testWidgets('1: at 18:30 the «يُقام الآن» box names youth and children in the other halls', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 4, 29, 18, 30), hwLits, [holyWeek27], theme: ThemePresets.holyWeek);
      final box = find.byKey(const Key('happeningNowBox'));
      expect(box, findsOneWidget);
      expect(find.descendant(of: box, matching: find.text('وفي نفس الوقت: القاعة السفلية (شباب)، مبنى الخدمات (أطفال)')),
          findsOneWidget);
      // The next service (elders at 19:00) keeps its own line.
      expect(find.text('وفي نفس الوقت: الكنيسة الكبرى (عام)، القاعة السفلية (شباب)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2: at 00:30 the Easter night liturgy is still «يُقام الآن»', (tester) async {
      final pascha = season('pascha', cairo(2027, 5, 1, 18), cairo(2027, 6, 10));
      final easter = lit('easter', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', type: 'mass', season: 'pascha', venue: 'main');
      await pump(tester, const NextMassCard(), cairo(2027, 5, 2, 0, 30), [easter], [pascha]);
      final box = find.byKey(const Key('happeningNowBox'));
      expect(box, findsOneWidget);
      expect(find.descendant(of: box, matching: find.textContaining('خدمة easter')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4: 09:00 revival is «الصلاة القادمة» tonight; 21:30 tomorrow\'s mass at once', (tester) async {
      final revival = season('revival_virgin', cairo(2027, 8, 7), cairo(2027, 8, 21, 23), replaces: false);
      final lits = [
        lit('mass-3', weekday: 3, start: '07:00', end: '09:00', type: 'mass'),
        lit('mass-4', weekday: 4, start: '07:00', end: '09:00', type: 'mass'),
        lit('night', date: DateTime(2027, 8, 11), start: '19:00', end: '21:30', type: 'vespers', season: 'revival_virgin'),
      ];
      await pump(tester, const NextMassCard(), cairo(2027, 8, 11, 9), lits, [revival]);
      expect(find.text('الصلاة القادمة'), findsOneWidget);
      expect(find.text('خدمة night'), findsOneWidget);
      expect(find.text('الليلة • ليلة الخميس'), findsOneWidget);
      expect(find.byKey(const Key('happeningNowBox')), findsNothing);

    });
  });

  group('4: widgets (handover)', () {
    final revival = season('revival_virgin', cairo(2027, 8, 7), cairo(2027, 8, 21, 23), replaces: false);
    final lits = [
      lit('mass-3', weekday: 3, start: '07:00', end: '09:00', type: 'mass'),
      lit('mass-4', weekday: 4, start: '07:00', end: '09:00', type: 'mass'),
      lit('night', date: DateTime(2027, 8, 11), start: '19:00', end: '21:30', type: 'vespers', season: 'revival_virgin'),
    ];
    testWidgets('19:00 the revival is «يُقام الآن», tomorrow\'s mass next', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 8, 11, 19), lits, [revival]);
      final box = find.byKey(const Key('happeningNowBox'));
      expect(find.descendant(of: box, matching: find.textContaining('خدمة night')), findsOneWidget);
      expect(find.text('خدمة mass-4'), findsOneWidget);
    });
    testWidgets('21:30 sharp: tomorrow\'s mass at once, «القداس القادم»', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 8, 11, 21, 30), lits, [revival]);
      expect(find.byKey(const Key('happeningNowBox')), findsNothing);
      expect(find.text('خدمة mass-4'), findsOneWidget);
      expect(find.text('غدًا • الخميس'), findsOneWidget);
      expect(find.text('القداس القادم'), findsOneWidget);
    });
  });

  group('3: the seasonal switch on /mass-schedule', () {
    test('every theme: ON track, OFF thumb / outline ≥ 3:1 on the card; ON thumb ≥ 3:1 on its track', () {
      for (final k in ThemePresets.keys) {
        final oc = OccasionColors(ThemePresets.palettes[k]!.normalized(), key: k);
        final p = oc.palette;
        final grounds = [
          p.surface,
          blendOver(p.surface, ThemePalette.cardAlpha, kBlack),
          blendOver(p.surface, ThemePalette.cardAlpha, kWhite),
        ];
        int c(Color x) => x.toARGB32() | 0xFF000000;
        for (final g in grounds) {
          expect(contrastRatio(c(oc.switchOnTrack), g), greaterThanOrEqualTo(3), reason: '$k ON track');
          expect(contrastRatio(c(oc.switchOffThumb), g), greaterThanOrEqualTo(3), reason: '$k OFF thumb / outline');
        }
        expect(contrastRatio(c(oc.switchOnThumb), c(oc.switchOnTrack)), greaterThanOrEqualTo(3), reason: '$k ON thumb');
        expect(contrastRatio(c(oc.switchOffThumb), c(oc.switchOffTrack)), greaterThanOrEqualTo(3), reason: '$k OFF thumb');
        // ON and OFF never read alike: the tracks differ by ≥ 3:1.
        expect(contrastRatio(c(oc.switchOnTrack), c(oc.switchOffTrack)), greaterThanOrEqualTo(3), reason: '$k ON vs OFF');
      }
    });

    testWidgets('Holy Week: the switch uses the palette roles, ON and OFF distinct', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 4, 29, 18, 30), hwLits, [holyWeek27],
          theme: ThemePresets.holyWeek, scroll: false);
      final oc = OccasionColors(ThemePresets.palettes[ThemePresets.holyWeek]!.normalized(), key: ThemePresets.holyWeek);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isTrue, reason: 'Holy Week opens the seasonal view');
      expect(tile.activeTrackColor, oc.switchOnTrack);
      expect(tile.activeThumbColor, oc.switchOnThumb);
      expect(tile.inactiveTrackColor, oc.switchOffTrack);
      expect(tile.inactiveThumbColor, oc.switchOffThumb);
      expect(tile.trackOutlineColor?.resolve({WidgetState.selected}), oc.switchOnTrack);
      expect(tile.trackOutlineColor?.resolve({}), oc.switchOffThumb);
      // Holy Week: crimson thumb on the ash track; the old ash-on-ash is gone.
      expect(oc.switchOnThumb, isNot(oc.ornament));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
