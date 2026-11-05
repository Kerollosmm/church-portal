// ADR-050: findings of the seasons v2 simulation, phases 1–7
// (work/seasons-v2/ISSUES.md 1, 2, 3, 8, 15, 16, 17, 18, 19, 20).
// 1   An additive season's mass hides only the regular masses it overlaps in
//     time; a feast liturgy marked `replacesDay` hides the day's regulars.
// 2/3 A `sample: true` service never replaces or outranks a real one: once a
//     season has real services its samples (dated ones too) give way; a
//     sample gives way to a real service of ANY season at the same time; a
//     real service sorts before a sample at the same start.
// 8   The assistant's season label says what the schedule really shows, and
//     the prompt lists today's / tomorrow's services from the same function.
// 15  The «يُقام الآن» box shows when the service ends («حتى …»).
// 16  «في انتظار تأكيد الكنيسة» seed placeholders are treated as empty.
// 18  The pope-visit gallery image is a same-origin WebP on Hosting.
// 19  The hero gets the season theme's colour wash (Golden hour: none).
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/pending_text.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/golden.dart';
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
        bool replacesDay = false,
        int order = 0,
        String venue = 'main',
        String speaker = '',
        String topic = ''}) =>
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
      replacesDay: replacesDay,
      order: order,
      program: ProgramInfo(venue: venue, speakerAr: speaker, topicAr: topic),
    );

Season season(String id, String key, tz.TZDateTime from, tz.TZDateTime to, {bool replaces = false}) => Season(
    id: id, key: key, nameAr: 'موسم $id', nameEn: 'Season $id', startsAt: from, endsAt: to, replacesRegular: replaces);

List<String> ids(Iterable<Liturgy> l) => [for (final x in l) x.id];
List<String> occIds(List<Liturgy> lits, List<Season> seasons, tz.TZDateTime day) =>
    ids(occurrencesForDay(liturgies: lits, seasons: seasons, day: day, dayOffset: 0).map((o) => o.liturgy));
NextMassResult at(DateTime now, List<Liturgy> lits, List<Season> seasons) =>
    computeNextMass(liturgies: lits, seasons: seasons, now: now);

// ── Phase 2 (B1): Easter 2 May 2027, Holy 50 Days additive.
final pascha27 = season('pascha-2027', 'pascha', cairo(2027, 5, 1, 18), cairo(2027, 6, 20, 23, 59));
final p2 = [
  lit('main', date: DateTime(2027, 5, 1), start: '22:30', end: '03:30', season: 'pascha', speaker: 'متكلم'),
  lit('kids', date: DateTime(2027, 5, 1), start: '23:00', end: '02:30', season: 'pascha', venue: 'services'),
  lit('sun-real', weekday: 7, start: '07:00', end: '09:00'),
  // The seed samples of the season (dated).
  lit('pascha-eve', date: DateTime(2027, 5, 1), start: '21:00', end: '01:00', season: 'pascha', sample: true),
  lit('pascha-day', date: DateTime(2027, 5, 2), start: '08:00', end: '10:00', season: 'pascha', sample: true),
];

// ── Phase 3 (item 1 + B2): Wed 23 Jun 2027, Apostles' fast + the seed's
// sample-only St Moses revival, both additive.
final apostles27 = season('apostles-fast-2027', 'fast', cairo(2027, 6, 21), cairo(2027, 7, 11, 23, 59));
final moses27 = season('revival-moses-2027', 'revival_moses', cairo(2027, 6, 22), cairo(2027, 7, 1, 23));
final p3 = [
  lit('wed-am', weekday: 3, start: '06:30', end: '09:00', order: 1),
  lit('fast-pm', weekday: 3, start: '12:00', end: '15:00', season: 'fast', order: 10),
  lit('revival', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other', season: 'fast', order: 20,
      speaker: 'القمص أنطونيوس', topic: 'الرسل: شهود القيامة'),
  lit('rev-moses-3', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true,
      order: 2, venue: ''),
  lit('thu-1', weekday: 4, start: '07:00', end: '09:00'),
];

// ── Phase 6 (B6-1): Kiahk Sunday 20 Dec 2026, Nativity fast additive.
final kiahk26 = season('fast-nativity-2026', 'fast', cairo(2026, 11, 25), cairo(2027, 1, 5, 23, 59));
final p6 = [
  lit('sahra', date: DateTime(2026, 12, 19), start: '21:00', end: '05:30', type: 'praise', season: 'fast'),
  lit('early', date: DateTime(2026, 12, 20), start: '05:30', end: '07:30', season: 'fast'),
  lit('sun-1', weekday: 7, start: '06:00', end: '08:00', sample: true),
  lit('sun-2', weekday: 7, start: '08:00', end: '10:00', sample: true, order: 1),
  lit('sun-youth', weekday: 7, start: '08:00', end: '10:00', sample: true, order: 2, venue: 'lower'),
  lit('mon-1', weekday: 1, start: '07:00', end: '09:00', sample: true),
];

// ── Phase 7 (O2): Tue 16 Mar 2027, Great Lent additive, liturgies 12:00/13:00.
final lent27 = season('great-lent-2027', 'fast', cairo(2027, 3, 8), cairo(2027, 4, 23, 23, 59));
final p7 = [
  lit('tue-real', weekday: 2, start: '07:00', end: '09:00'),
  lit('lent-main', weekday: 2, start: '12:00', end: '15:00', season: 'fast'),
  lit('lent-youth', weekday: 2, start: '13:00', end: '16:00', season: 'fast', venue: 'lower'),
];

// ── Feast liturgy with `replacesDay` in an additive season.
final marian27 = season('marian-2027', 'marian', cairo(2027, 8, 7), cairo(2027, 8, 22, 23, 59));
List<Liturgy> feast({bool replacesDay = true, bool sample = false}) => [
      lit('reg-sun-1', weekday: 7, start: '07:00', end: '09:00'),
      lit('reg-sun-2', weekday: 7, start: '18:00', end: '19:30'),
      lit('reg-vespers', weekday: 7, start: '20:00', end: '21:00', type: 'vespers'),
      lit('feast', date: DateTime(2027, 8, 22), start: '10:00', end: '12:30', season: 'marian',
          replacesDay: replacesDay, sample: sample),
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

  group('issue 2 (P2 B1): the dated seed sample gives way to the real programme', () {
    test('Sun 2 May: the real 07:00 regular mass stays, the 08:00 sample is gone', () {
      expect(occIds(p2, [pascha27], cairo(2027, 5, 2)), ['sun-real']);
      expect(occIds(p2, [pascha27], cairo(2027, 5, 1)), containsAllInOrder(['main', 'kids']));
      expect(occIds(p2, [pascha27], cairo(2027, 5, 1)), isNot(contains('pascha-eve')));
    });

    test('03:31: no «يُقام الآن», the hand-over is the real 07:00 mass', () {
      final r = at(cairo(2027, 5, 2, 3, 31), p2, [pascha27]);
      expect(r.happeningNow, isNull);
      expect((r.next?.liturgy.id, r.next?.dayOffset), ('sun-real', 0));
      // 03:29: the overnight liturgy is still on.
      expect(at(cairo(2027, 5, 2, 3, 29), p2, [pascha27]).happeningNow?.liturgy.id, 'main');
    });

    test('the season lists and the assistant prompt drop the sample too', () {
      expect(ids(seasonalSchedule([pascha27], p2)[pascha27]!), ['main', 'kids']);
      final p = prompt(p2, [pascha27], cairo(2027, 5, 2, 3, 31));
      expect(p, isNot(contains('خدمة pascha-day')));
      expect(p, isNot(contains('خدمة pascha-eve')));
      expect(p, contains('Service sun-real'));
    });

    test('a season made only of samples (the bundled seed) is unchanged', () {
      final seedOnly = [for (final l in p2) if (l.sample) l];
      expect(occIds(seedOnly, [pascha27], cairo(2027, 5, 2)), ['pascha-day']);
    });

    test('a sample seasonal mass never supersedes a real regular mass', () {
      final lits = [
        lit('reg', weekday: 7, start: '08:00', end: '10:00'),
        lit('s', date: DateTime(2027, 5, 9), start: '08:00', end: '10:00', season: 'pascha', sample: true),
      ];
      expect(occIds(lits, [pascha27], cairo(2027, 5, 9)), ['reg', 's'], reason: 'real first, sample kept beside it');
    });
  });

  group('issue 3 (P3 B2): a real service of any season beats a seed sample at the same time', () {
    test('15:01 the next service is the real revival; 18:45 it is «يُقام الآن» alone', () {
      final r1 = at(cairo(2027, 6, 23, 15, 1), p3, [apostles27, moses27]);
      expect(r1.next?.liturgy.id, 'revival');
      final r2 = at(cairo(2027, 6, 23, 18, 45), p3, [apostles27, moses27]);
      expect(r2.happeningNow?.liturgy.id, 'revival');
      expect(ids(r2.runningNow.map((o) => o.liturgy)), ['revival'], reason: 'the sample is not even a parallel line');
      expect(r2.happeningNow?.liturgy.program.speakerAr, 'القمص أنطونيوس');
    });

    test('a sample-only season still shows on days without a real service at that time', () {
      // Thu 24 Jun: no real 18:30 service, nothing to give way to.
      final lits = [...p3, lit('rev-moses-4', weekday: 4, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true)];
      expect(occIds(lits, [apostles27, moses27], cairo(2027, 6, 24)), ['thu-1', 'rev-moses-4']);
    });

    test('at the same start a real service sorts before a sample (order no longer decides)', () {
      final lits = [
        lit('a-sample', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true, order: 1),
        lit('b-real', weekday: 3, start: '18:30', end: '19:00', type: 'other', venue: 'lower', order: 9),
      ];
      final occ = occurrencesForDay(liturgies: lits, seasons: [moses27], day: cairo(2027, 6, 23), dayOffset: 0);
      expect(ids(occ.map((o) => o.liturgy)), ['b-real', 'a-sample']);
    });
  });

  group('issue 1: an additive season hides only the regular masses it overlaps', () {
    test('P3: the real 06:30 regular mass stays when the fasting liturgy is at 12:00', () {
      expect(occIds(p3, [apostles27, moses27], cairo(2027, 6, 23)), ['wed-am', 'fast-pm', 'revival']);
      expect(at(cairo(2027, 6, 23, 6, 45), p3, [apostles27, moses27]).happeningNow?.liturgy.id, 'wed-am');
      final r = at(cairo(2027, 6, 23, 11, 30), p3, [apostles27, moses27]);
      expect((r.happeningNow, r.next?.liturgy.id), (null, 'fast-pm'));
    });

    test('P6: 07:31 hands over to the Sunday 08:00 regular masses, not Monday', () {
      expect(occIds(p6, [kiahk26], cairo(2026, 12, 20)), ['early', 'sun-2', 'sun-youth'],
          reason: 'sun-1 06:00–08:00 overlaps the 05:30–07:30 early liturgy and gives way; 08:00 stays');
      final r = at(cairo(2026, 12, 20, 7, 31), p6, [kiahk26]);
      expect(r.happeningNow, isNull);
      expect((r.next?.liturgy.id, r.next?.dayOffset), ('sun-2', 0));
      expect(at(cairo(2026, 12, 20, 5, 29), p6, [kiahk26]).happeningNow?.liturgy.id, 'sahra');
      expect(at(cairo(2026, 12, 20, 5, 31), p6, [kiahk26]).happeningNow?.liturgy.id, 'early');
    });

    test('P7: the Tuesday 07:00 regular mass stays when the Lent masses are 12:00 / 13:00', () {
      expect(occIds(p7, [lent27], cairo(2027, 3, 16)), ['tue-real', 'lent-main', 'lent-youth']);
      expect(at(cairo(2027, 3, 16, 7, 30), p7, [lent27]).happeningNow?.liturgy.id, 'tue-real');
      expect(regularSupersededOn(liturgies: p7, seasons: [lent27], day: cairo(2027, 3, 16)), isEmpty);
    });

    test('a feast liturgy with replacesDay hides every regular mass of its day (not vespers)', () {
      expect(occIds(feast(), [marian27], cairo(2027, 8, 22)), ['feast', 'reg-vespers']);
      expect(ids(regularSupersededOn(liturgies: feast(), seasons: [marian27], day: cairo(2027, 8, 22))),
          ['reg-sun-1', 'reg-sun-2']);
      // The Sunday before: not the feast day, nothing hidden.
      expect(occIds(feast(), [marian27], cairo(2027, 8, 15)), ['reg-sun-1', 'reg-sun-2', 'reg-vespers']);
      final r = at(cairo(2027, 8, 22, 6), feast(), [marian27]);
      expect(r.next?.liturgy.id, 'feast');
    });

    test('without replacesDay the same feast liturgy hides only an overlapping mass', () {
      expect(occIds(feast(replacesDay: false), [marian27], cairo(2027, 8, 22)),
          ['reg-sun-1', 'feast', 'reg-sun-2', 'reg-vespers']);
    });

    test('a SAMPLE feast liturgy with replacesDay never hides the real regular masses', () {
      expect(occIds(feast(sample: true), [marian27], cairo(2027, 8, 22)),
          ['reg-sun-1', 'feast', 'reg-sun-2', 'reg-vespers']);
    });

    test('replacesDay is read from Firestore (absent = false)', () {
      expect(Liturgy.fromMap('x', {'nameAr': 'x', 'start': '07:00', 'replacesDay': true}).replacesDay, isTrue);
      expect(Liturgy.fromMap('x', {'nameAr': 'x', 'start': '07:00'}).replacesDay, isFalse);
      expect(Liturgy.fromMap('x', {'nameAr': 'x', 'start': '07:00', 'replacesDay': 'yes'}).replacesDay, isFalse);
    });

    test('the liturgy editor offers the replacesDay checkbox (admin schema)', () {
      final def = collectionById('liturgies')!;
      final f = def.fields.firstWhere((f) => f.key == 'replacesDay');
      expect(f.type, FieldType.boolean);
      expect(f.labelAr, contains('يحل محل قداسات اليوم المعتادة'));
    });
  });

  group('issue 8: the assistant label follows what the schedule shows', () {
    test('P7 Lent: «regular services continue» and today lists the 07:00 mass', () {
      final p = prompt(p7, [lent27], cairo(2027, 3, 16, 7, 30));
      expect(p, contains('[ADDITIVE — regular services continue]'));
      expect(p, isNot(contains('regular morning masses continue')));
      expect(p, contains('## Services today and tomorrow (exactly as the website shows them)'));
      expect(p, contains('- Today 2027-03-16 (Tuesday): Service tue-real'));
      expect(p, isNot(contains('NOT held')));
    });

    test('feast day with replacesDay: the label and today say the regular masses are not held', () {
      final p = prompt(feast(), [marian27], cairo(2027, 8, 22, 6));
      expect(p, contains('[ADDITIVE — some regular services are NOT held today'));
      expect(p, contains("[REPLACES the day's regular masses]"));
      expect(p, contains('- Today 2027-08-22 (Sunday), NOT held (the season replaces them): '));
      expect(p, contains('Service reg-sun-1 (خدمة reg-sun-1) 07:00 AM – 09:00 AM'));
      expect(p, isNot(contains('- Today 2027-08-22 (Sunday): Service reg-sun-1')));
    });

    test('P3: the prompt lists the real revival today, not the seed sample', () {
      final p = prompt(p3, [apostles27, moses27], cairo(2027, 6, 23, 11, 30));
      expect(p, contains('- Today 2027-06-23 (Wednesday): Service revival'));
      expect(p, isNot(contains('- Today 2027-06-23 (Wednesday): [UNCONFIRMED] Service rev-moses-3')));
      expect(p, contains('- Today 2027-06-23 (Wednesday): Service wed-am'));
      expect(p, contains('- Tomorrow 2027-06-24 (Thursday): Service thu-1'));
    });
  });

  group('issue 15: the «يُقام الآن» box shows the end time', () {
    testWidgets('Easter night 00:30: «حتى ٠٣:٣٠ ص» (12-hour ص/م, next morning)', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 5, 2, 0, 30), p2, [pascha27],
          theme: ThemePresets.resurrection);
      expect(find.byKey(const Key('happeningNowBox')), findsOneWidget);
      expect(find.text('حتى ٠٣:٣٠ ص'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('English: "Until 03:00 PM"', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 3, 16, 12, 30), p7, [lent27],
          theme: ThemePresets.fasting, locale: const Locale('en'));
      expect(find.text('Until 03:00 PM'), findsOneWidget);
    });

    testWidgets('a service without an end runs its 120 minutes: «حتى ٠٩:٠٠ ص»', (tester) async {
      final noEnd = [lit('x', weekday: 2, start: '07:00', end: '')];
      await pump(tester, const NextMassCard(), cairo(2027, 3, 16, 7, 30), noEnd, const []);
      expect(find.text('حتى ٠٩:٠٠ ص'), findsOneWidget);
    });

    testWidgets('P3 18:45: the now box leads with the real revival, its speaker and topic', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 6, 23, 18, 45), p3, [apostles27, moses27],
          theme: ThemePresets.fasting);
      final box = find.byKey(const Key('happeningNowBox'));
      expect(find.descendant(of: box, matching: find.textContaining('خدمة revival')), findsOneWidget);
      expect(find.descendant(of: box, matching: find.textContaining('القمص أنطونيوس')), findsOneWidget);
      expect(find.descendant(of: box, matching: find.textContaining('خدمة rev-moses-3')), findsNothing);
      expect(find.descendant(of: box, matching: find.text('حتى ٠٩:٠٠ م')), findsOneWidget);
    });
  });

  group('/mass-schedule marks the regular masses a season supersedes today', () {
    testWidgets('feast day: «لا يُقام اليوم» on the Sunday masses, not on vespers', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 8, 22, 6), feast(), [marian27],
          theme: ThemePresets.marian, scroll: false);
      final sunday = find.widgetWithText(ChoiceChip, 'الأحد');
      await tester.ensureVisible(sunday);
      await tester.tap(sunday);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notHeldToday')), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Lent Tuesday: nothing is marked', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 3, 16, 7, 30), p7, [lent27],
          theme: ThemePresets.fasting, scroll: false);
      final other = find.widgetWithText(ChoiceChip, 'باقي الأيام');
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(find.text('خدمة tue-real'), findsOneWidget);
      expect(find.byKey(const Key('notHeldToday')), findsNothing);
    });
  });

  group('issue 16: «في انتظار تأكيد الكنيسة» placeholders are empty on public pages', () {
    test('strip removes the placeholder sentence / aside and keeps real facts', () {
      expect(stripPendingPlaceholders('حضانة للأطفال — التفاصيل في انتظار تأكيد الكنيسة.'), '');
      expect(
          stripPendingPlaceholders(
              'نال رتبة القمصية في 10 نوفمبر 2022. آخر تأكيد علني لخدمته بالكنيسة كان في 2022 — في انتظار تأكيد الكنيسة.'),
          'نال رتبة القمصية في 10 نوفمبر 2022.');
      // An affiliation caveat is a fact, not a placeholder: it stays.
      expect(stripPendingPlaceholders('كورال ترانيم (لم يُؤكَّد أنه تابع للكنيسة).'), 'كورال ترانيم (لم يُؤكَّد أنه تابع للكنيسة).');
      // Tashkeel does not hide a marker (CodeRabbit on PR #45).
      expect(stripPendingPlaceholders('مكتبة للكتب. تفاصيل غير مُؤكَّدة.'), 'مكتبة للكتب.');
      expect(hasPendingPlaceholder('تفاصيل غير مُؤكَّدة'), isTrue);
      // A link inside a placeholder sentence goes with it, no fragment left.
      const url = 'Library. Details pending church confirmation: https://example.org/contact.';
      expect(stripPendingPlaceholders(url), 'Library.');
      expect(stripPendingPlaceholders('Call us. Details: https://example.org/contact. Times pending church confirmation.'),
          'Call us. Details: https://example.org/contact.');
      expect(stripPendingPlaceholders("Children's nursery — details pending church confirmation."), '');
      expect(stripPendingPlaceholders('A choir (not confirmed as a church ministry).'), 'A choir (not confirmed as a church ministry).');
      const clean = 'يخدم مشروع تطوير خدمة الأنبا أبرآم.';
      expect(stripPendingPlaceholders(clean), clean);
      expect(hasPendingPlaceholder(clean), isFalse);
    });

    test('models clean priests, facilities, activities, milestones and saints', () {
      expect(Priest.fromMap('p', {'name': 'x', 'bioAr': 'ورد اسمه — في انتظار تأكيد الكنيسة.'}).bioAr, '');
      expect(Facility.fromMap('f', {'nameAr': 'x', 'descEn': 'Books — details pending church confirmation.'}).descEn, '');
    });

    test('the repo seed has no placeholder text left (its sample flags stay)', () {
      final raw = File('assets/seed/seed.json').readAsStringSync();
      for (final m in ['في انتظار تأكيد', 'pending church confirmation', 'شريك', 'partner']) {
        expect(raw, isNot(contains(m)), reason: m);
      }
      // The activities' affiliation caveats stay (CodeRabbit on PR #45).
      expect(raw, contains('not confirmed as a church ministry'));
      final seed = jsonDecode(raw) as Map<String, dynamic>;
      expect((seed['priests'] as Map)['saleeb']['sample'], isTrue);
      expect((seed['facilities'] as Map)['nursery']['sample'], isTrue);
    });

    test('the assistant prompt carries no placeholder text', () {
      final p = prompt(p7, [lent27], cairo(2027, 3, 16, 7, 30));
      expect(p, isNot(contains('انتظار تأكيد')));
      expect(p, isNot(contains('pending church confirmation')));
      // Placeholders inside live documents are cleaned on read as well.
      expect(stripPendingPlaceholders('مكتب — التفاصيل في انتظار تأكيد الكنيسة.'), '');
    });
  });

  group('issue 18: pope-visit gallery image on Hosting', () {
    test('web/media/milestones/pope-visit-gallery5.webp is a WebP ≤ 200 KB', () {
      final f = File('web/media/milestones/pope-visit-gallery5.webp');
      expect(f.existsSync(), isTrue);
      final b = f.readAsBytesSync();
      expect(b.length, lessThanOrEqualTo(200 * 1024));
      expect(ascii.decode(b.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(b.sublist(8, 12)), 'WEBP');
    });
  });

  group('issue 19: hero season tint', () {
    test('occasion themes tint; Golden hour, its colour presets and dark themes do not', () {
      OccasionColors oc(String k) => OccasionColors(ThemePresets.palettes[k]!.normalized(), key: k);
      for (final k in [ThemePresets.marian, ThemePresets.fasting, ThemePresets.resurrection, ThemePresets.nativity]) {
        final t = oc(k).heroTint;
        expect(t, isNotNull, reason: k);
        expect(t!.first.toARGB32() & 0xFFFFFF, oc(k).primary.toARGB32() & 0xFFFFFF, reason: 'palette role, $k');
        expect(t.last.a, 0, reason: 'fades out before the bottom');
        expect(t.first.a, lessThanOrEqualTo(0.25), reason: 'a gentle wash: the painting stays visible, $k');
      }
      expect(oc(ThemePresets.goldenHour).heroTint, isNull);
      expect(oc(ThemePresets.holyWeek).heroTint, isNull, reason: 'dark: the art is already dimmed');
    });

    testWidgets('HeroStage paints the tint layer only for a season theme and the admin switch', (tester) async {
      Future<void> stage(String theme, {bool tint = true}) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Locale('ar'), palette: ThemePresets.palettes[theme]!.normalized(), key: theme),
          home: SizedBox(width: 390, height: 600, child: HeroStage(image: ArtAssets.heroTall, tint: tint)),
        ));
        await tester.pumpAndSettle(); // the theme cross-fade finishes
      }

      await stage(ThemePresets.marian);
      expect(find.byKey(const Key('heroSeasonTint')), findsOneWidget);
      expect(find.byKey(const Key('heroStill')), findsOneWidget, reason: 'the painting is unchanged');
      await stage(ThemePresets.marian, tint: false);
      expect(find.byKey(const Key('heroSeasonTint')), findsNothing);
      await stage(ThemePresets.goldenHour);
      expect(find.byKey(const Key('heroSeasonTint')), findsNothing);
    });

    test('settings/features.heroSeasonTint: default on, read and written', () {
      expect(FeatureSettings.defaults.heroSeasonTint, isTrue);
      expect(FeatureSettings.fromMap({'heroSeasonTint': false}).heroSeasonTint, isFalse);
      expect(FeatureSettings.fromMap(const {}).copyWith(heroSeasonTint: false).toMap()['heroSeasonTint'], isFalse);
    });
  });

  group('CodeRabbit on PR #45', () {
    test('the prompt lists an overnight service of the evening before as ongoing', () {
      final p = prompt(p2, [pascha27], cairo(2027, 5, 2, 0, 30));
      expect(p, contains('- Today 2027-05-02 (Sunday): [ONGOING since the evening before, until 03:30 AM] Service main'));
      expect(p, isNot(contains('- Today 2027-05-02 (Sunday): no services listed.')));
    });

    test('a full-override season replaces the regulars even when its only service is a hidden sample', () {
      final hw = season('hw', 'holy_week', cairo(2027, 4, 26), cairo(2027, 4, 30, 23, 59), replaces: true);
      final rev = season('rev', 'revival_moses', cairo(2027, 4, 26), cairo(2027, 4, 30, 23, 59));
      final lits = [
        lit('mon-am', weekday: 1, start: '07:00', end: '09:00'),
        lit('hw-sample', weekday: 1, start: '18:00', end: '21:00', type: 'other', season: 'holy_week', sample: true),
        lit('rev-real', date: DateTime(2027, 4, 26), start: '18:00', end: '21:00', type: 'other', season: 'revival_moses'),
      ];
      expect(occIds(lits, [hw, rev], cairo(2027, 4, 26)), ['rev-real']);
    });

    test('a real service that cannot take place does not hide the samples', () {
      final s = season('rev', 'revival_moses', cairo(2027, 6, 22, 18), cairo(2027, 7, 1, 23));
      final sample = lit('rev-s', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other',
          season: 'revival_moses', sample: true);
      final noStart = lit('rev-x', date: DateTime(2027, 6, 24), start: '', end: '', type: 'other', season: 'revival_moses');
      final early = lit('rev-y', date: DateTime(2027, 6, 22), start: '08:00', end: '09:00', season: 'revival_moses');
      expect(seasonHasRealServices(s, [sample, noStart, early]), isFalse);
      expect(occIds([sample, noStart, early], [s], cairo(2027, 6, 23)), ['rev-s']);
      final real = lit('rev-z', date: DateTime(2027, 6, 24), start: '18:30', end: '21:00', type: 'other',
          season: 'revival_moses');
      expect(seasonHasRealServices(s, [sample, real]), isTrue);
      expect(occIds([sample, real], [s], cairo(2027, 6, 23)), isEmpty);
    });

    test('after a preset expires heroSeasonTint keeps its stored value', () {
      final end = DateTime.utc(2027, 5, 1, 22);
      final f = FeatureSettings.fromMap({
        'theme': ThemePresets.marian,
        'heroSeasonTint': false,
        'seasonPreset': {
          'seasonId': 'm',
          'seasonKey': 'marian',
          'endsAt': end,
          'options': ['heroMotionOff'],
          'previous': {'heroMotion': true},
        },
      });
      expect(f.effectiveAt(end).heroSeasonTint, isFalse);
      expect(f.effectiveAt(end).heroMotion, isTrue);
    });
  });
}
