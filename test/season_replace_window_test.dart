// ADR-053: findings of the seasons v2 round-2 simulation.
// N1 (P1)  A full-override season (`replacesRegular`) with an exact window
//          replaces every regular service starting inside it, also on a day
//          with no service of its own (Good Friday with only the owner's
//          Thursday service fell back to the regular Divine Liturgy), with
//          or without the seed's sample docs.
// P3 low   A sample of one season is left out of the season lists (and the
//          prompt's weekly list) when a real service of another active
//          season overlaps it on every day of its weekday in the window.
// P2 O-a   The card names a parallel service that starts later with its own
//          time («وبعدها ٠٧:٠٠ ص: …»), not «وفي نفس الوقت».
// P7 O3    The seasonal switch subtitle mentions the fasts.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
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
        String type = 'mass',
        String? season,
        bool sample = false,
        int order = 0,
        String venue = 'main',
        String audience = ''}) =>
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
      sample: sample,
      order: order,
      program: ProgramInfo(venue: venue, audience: audience),
    );

Season season(String id, String key, tz.TZDateTime? from, tz.TZDateTime? to, {bool replaces = false}) => Season(
    id: id, key: key, nameAr: 'موسم $id', nameEn: 'Season $id', startsAt: from, endsAt: to, replacesRegular: replaces);

List<String> ids(Iterable<Liturgy> l) => [for (final x in l) x.id];
List<String> occIds(List<Liturgy> lits, List<Season> seasons, tz.TZDateTime day) =>
    ids(occurrencesForDay(liturgies: lits, seasons: seasons, day: day, dayOffset: 0).map((o) => o.liturgy));

// ── P1 N1: Holy Week 2027, full override, Sun 25 Apr 00:00 → Sat 1 May 18:00.
final hw27 = season('holy-week-2027', 'holy_week', cairo(2027, 4, 25), cairo(2027, 5, 1, 18), replaces: true);
final regular = [
  lit('thu-1', weekday: 4, start: '07:00', end: '09:00'),
  lit('fri-1', weekday: 5, start: '06:30', end: '08:30', sample: true),
  lit('fri-2', weekday: 5, start: '08:30', end: '10:30', order: 1),
  lit('fri-kids', weekday: 5, start: '08:30', end: '10:30', order: 2, venue: 'services'),
  lit('sat-1', weekday: 6, start: '07:00', end: '09:00'),
  lit('sat-vespers', weekday: 6, start: '18:30', end: '19:15', type: 'vespers'),
  lit('sun-1', weekday: 7, start: '06:00', end: '08:00'),
];
final hwThu = lit('hw-thu', date: DateTime(2027, 4, 29), start: '18:30', end: '23:00', type: 'other', season: 'holy_week');
final hwFriSample =
    lit('hw-friday', date: DateTime(2027, 4, 30), start: '08:00', end: '18:00', type: 'other', season: 'holy_week', sample: true);
final p1 = [...regular, hwThu, hwFriSample];
final p1NoSamples = [...regular, hwThu];

class _Repo extends SeedRepository {
  _Repo(super.seed, this._lits, this._seasons);
  final List<Liturgy> _lits;
  final List<Season> _seasons;
  @override
  Stream<List<Liturgy>> liturgies() => Stream.value(_lits);
  @override
  Stream<List<Season>> seasons() => Stream.value(_seasons);
}

Future<void> pump(WidgetTester tester, Widget child, DateTime now, List<Liturgy> lits, List<Season> seasons,
    {String theme = ThemePresets.goldenHour, Locale locale = const Locale('ar'), bool scroll = true}) async {
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
        theme: buildTheme(locale, palette: ThemePresets.palettes[theme]!.normalized(), key: theme),
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child)),
  ));
  await tester.pumpAndSettle();
}

String prompt(List<Liturgy> lits, List<Season> seasons, DateTime now) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final seed = SeedData(raw);
  return buildAssistantInstruction(
    settings: seed.settings,
    liturgies: lits,
    seasons: seasons,
    clinics: const [],
    meetings: const [],
    activities: const [],
    facilities: seed.facilities,
    priests: seed.priests,
    now: now,
  );
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('N1: a full-override season replaces the regular schedule on every day of its window', () {
    for (final (label, lits) in [('with the seed sample', p1), ('sample docs deleted', p1NoSamples)]) {
      test('Good Friday ($label): no regular masses', () {
        expect(occIds(lits, [hw27], cairo(2027, 4, 30)), isEmpty);
        expect(ids(regularSupersededOn(liturgies: lits, seasons: [hw27], day: cairo(2027, 4, 30))),
            ['fri-1', 'fri-2', 'fri-kids']);
      });

      test('Thu 23:00 ($label): the next service is not a regular mass inside Holy Week', () {
        final r = computeNextMass(liturgies: lits, seasons: [hw27], now: cairo(2027, 4, 29, 23));
        expect(r.next?.liturgy.id, 'sun-1');
        expect(r.next!.start, cairo(2027, 5, 2, 6));
      });

      test('Holy Thursday ($label): its own service stays, the morning regular mass is replaced', () {
        expect(occIds(lits, [hw27], cairo(2027, 4, 29)), ['hw-thu']);
      });

      test('Sat 1 May ($label): the 07:00 mass is replaced, vespers after the 18:00 end stays', () {
        expect(occIds(lits, [hw27], cairo(2027, 5, 1)), ['sat-vespers']);
      });
    }

    test('the prompt lists no Friday regular masses and names them not held', () {
      final p = prompt(p1, [hw27], cairo(2027, 4, 29, 18, 30));
      expect(p, contains('- Tomorrow 2027-04-30 (Friday): no services listed.'));
      expect(p, isNot(contains('- Tomorrow 2027-04-30 (Friday): Service fri-')));
      expect(p, isNot(contains('- Tomorrow 2027-04-30 (Friday): [UNCONFIRMED] Service fri-')));
      expect(p, contains('- Tomorrow 2027-04-30 (Friday), NOT held (the season replaces them): '));
      expect(p, contains('even on a day with no season service listed'));
    });

    test('Nativity: 7 Jan without its own service still replaces; 8 Jan is regular again', () {
      final nat = season('nativity-2027', 'nativity', cairo(2027, 1, 6), cairo(2027, 1, 7, 23, 59), replaces: true);
      final lits = [
        ...regular,
        lit('nat-eve', date: DateTime(2027, 1, 6), start: '20:00', end: '00:30', season: 'nativity'),
      ];
      expect(occIds(lits, [nat], cairo(2027, 1, 7)), isEmpty); // Thursday: thu-1 replaced
      expect(occIds(lits, [nat], cairo(2027, 1, 8)), ['fri-1', 'fri-2', 'fri-kids']);
      final r = computeNextMass(liturgies: lits, seasons: [nat], now: cairo(2027, 1, 7, 1));
      expect(r.next?.liturgy.id, 'fri-1');
    });

    test('Pascha from Sat 18:00: Saturday morning stays regular, Sunday is replaced without a Sunday service', () {
      final pascha = season('pascha-2027', 'pascha', cairo(2027, 5, 1, 18), cairo(2027, 5, 2, 23, 59), replaces: true);
      final lits = [
        ...regular,
        lit('pascha-eve', date: DateTime(2027, 5, 1), start: '21:00', end: '01:00', season: 'pascha'),
      ];
      expect(occIds(lits, [pascha], cairo(2027, 5, 1)), ['sat-1', 'pascha-eve']);
      expect(occIds(lits, [pascha], cairo(2027, 5, 2)), isEmpty);
    });

    test('an open-ended full-override season still replaces only on its service days (unchanged)', () {
      final open = season('open', 'holy_week', null, null, replaces: true);
      final lits = [...regular, lit('x', weekday: 4, start: '18:00', end: '20:00', season: 'holy_week')];
      expect(occIds(lits, [open], cairo(2027, 4, 29)), ['x']);
      expect(occIds(lits, [open], cairo(2027, 4, 30)), ['fri-1', 'fri-2', 'fri-kids']);
    });

    test('an additive season without a service that day keeps the regular schedule (unchanged)', () {
      final add = season('lent', 'great_lent', cairo(2027, 4, 25), cairo(2027, 5, 1, 18));
      final lits = [...regular, lit('l', date: DateTime(2027, 4, 29), start: '18:30', end: '20:00', season: 'great_lent')];
      expect(occIds(lits, [add], cairo(2027, 4, 30)), ['fri-1', 'fri-2', 'fri-kids']);
    });

    testWidgets('home card Thu 23:00: no Friday regular mass', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 4, 29, 23), p1, [hw27], theme: ThemePresets.holyWeek);
      expect(find.textContaining('خدمة fri-'), findsNothing);
      expect(find.text('خدمة sun-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('/mass-schedule Thu 23:00: the card shows no Friday regular mass', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 4, 29, 23), p1, [hw27],
          theme: ThemePresets.holyWeek, scroll: false);
      final card = find.byType(NextMassCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('خدمة fri-')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('P3: a sample hidden behind another season\'s real service leaves the season lists', () {
    final apostles = season('apostles-2027', 'apostles', cairo(2027, 6, 21), cairo(2027, 7, 11, 23, 59));
    final moses = season('revival-moses-2027', 'revival_moses', cairo(2027, 6, 22), cairo(2027, 7, 1, 23));
    final samples = [
      lit('rev-moses-3', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true),
      lit('rev-moses-4', weekday: 4, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true),
    ];
    final weekly = [
      ...samples,
      lit('revival', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'apostles'),
    ];
    final datedOnce = [
      ...samples,
      lit('revival', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other', season: 'apostles'),
    ];

    test('a weekly real revival hides the Wednesday sample in the list; Thursday stays', () {
      final g = seasonalSchedule([apostles, moses], weekly);
      expect(ids(g[moses]!), ['rev-moses-4']);
      expect(ids(g[apostles]!), ['revival']);
      // The day views agree: on both Wednesdays only the real revival.
      expect(occIds(weekly, [apostles, moses], cairo(2027, 6, 23)), ['revival']);
      expect(occIds(weekly, [apostles, moses], cairo(2027, 6, 30)), ['revival']);
    });

    test('the prompt\'s weekly list leaves the hidden sample out', () {
      final p = prompt(weekly, [apostles, moses], cairo(2027, 6, 23, 11, 30));
      expect(p, isNot(contains('Service rev-moses-3')));
      expect(p, contains('Service rev-moses-4'));
    });

    test('a real revival on one Wednesday only: the sample is still held on the next, so it stays listed', () {
      expect(ids(seasonalSchedule([apostles, moses], datedOnce)[moses]!), ['rev-moses-3', 'rev-moses-4']);
      expect(occIds(datedOnce, [apostles, moses], cairo(2027, 6, 23)), ['revival']);
      expect(occIds(datedOnce, [apostles, moses], cairo(2027, 6, 30)), ['rev-moses-3']);
    });

    test('a dated sample on the day of another season\'s real service is left out', () {
      final lits = [
        lit('s', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other', season: 'revival_moses',
            sample: true),
        lit('revival', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other', season: 'apostles'),
      ];
      expect(seasonalSchedule([apostles, moses], lits)[moses], isNull);
    });

    test('a view listing only some seasons still reads the others (context)', () {
      final g = seasonalSchedule([moses], weekly, context: [apostles, moses]);
      expect(ids(g[moses]!), ['rev-moses-4']);
      // Without context nothing hides it (the other season is unknown).
      expect(ids(seasonalSchedule([moses], weekly)[moses]!), ['rev-moses-3', 'rev-moses-4']);
    });

    test('a sample-only season beside another sample-only season is unchanged', () {
      final lits = [...samples, lit('other-sample', weekday: 3, start: '18:30', end: '21:00', season: 'apostles', sample: true)];
      expect(ids(seasonalSchedule([apostles, moses], lits)[moses]!), ['rev-moses-3', 'rev-moses-4']);
    });
  });

  group('P2 O-a: a parallel service starting later is named with its time', () {
    final lits = [
      lit('early', weekday: 7, start: '06:00', end: '08:00', venue: 'lower'),
      lit('same', weekday: 7, start: '06:00', end: '07:30', venue: 'services'),
      lit('late', weekday: 7, start: '07:00', end: '09:00', venue: 'main'),
    ];

    testWidgets('AR: «وفي نفس الوقت» for the same start, «وبعدها ٠٧:٠٠ ص: …» for the later one', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 5, 9, 5), lits, const []);
      expect(find.text('خدمة early'), findsOneWidget);
      final at = find.textContaining('وفي نفس الوقت: ');
      expect(at, findsOneWidget);
      expect((tester.widget<Text>(at)).data, isNot(contains('الكنيسة الكبرى')));
      final then = find.byKey(const Key('parallelThen0'));
      expect(then, findsOneWidget);
      expect(find.descendant(of: then, matching: find.textContaining('وبعدها ٠٧:٠٠ ص: خدمة late — ')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EN: "Then at 07:00 AM: Service late — …"', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 5, 9, 5), lits, const [], locale: const Locale('en'));
      expect(find.textContaining('Then at 07:00 AM: Service late — '), findsOneWidget);
      expect(find.textContaining('At the same time: '), findsOneWidget);
    });

    testWidgets('only a later service: no «وفي نفس الوقت» line at all', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 5, 9, 5), [lits[0], lits[2]], const []);
      expect(find.textContaining('وفي نفس الوقت'), findsNothing);
      expect(find.byKey(const Key('parallelThen0')), findsOneWidget);
    });
  });

  testWidgets('P7 O3: the seasonal switch subtitle mentions the fasts', (tester) async {
    await pump(tester, const MassSchedulePage(), cairo(2027, 3, 16, 13), regular, const [], scroll: false);
    expect(find.text('عرض مواعيد أسبوع الآلام والأعياد والأصوام والنهضات الروحية'), findsOneWidget);
  });
}
