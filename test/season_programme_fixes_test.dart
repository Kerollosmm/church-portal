// ADR-045: findings of the revival-night and Holy Week simulations
// (work/sim-revival/report.md, work/sim-holy-week/report.md and the ADR-043
// re-run). B1 the next-service card counts every service of any ACTIVE
// season (additive revivals too) whatever its type; B2 «يُقام الآن» keeps the
// programme; B3 the assistant grounds speaker / topic / choir / PDF, the
// church events of the day and the live link; B4 the assistant says wedding
// bookings are paused while condolences stay open; B5 the seed's undated
// sample templates never mix into an owner's season (additive or replacing);
// the top event falls back to today's / tonight's programme service, and a
// church event's PDF gets its own labelled button.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/today_widgets.dart';
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
        bool sample = false,
        ProgramInfo program = ProgramInfo.none,
        String placeAr = ''}) =>
    Liturgy(
      id: id,
      type: type,
      nameAr: 'خدمة $id',
      nameEn: 'Service $id',
      weekday: weekday,
      date: date,
      start: start,
      end: end,
      placeAr: placeAr,
      seasonKey: season,
      sample: sample,
      program: program,
    );

// The revival simulation: Mon 2 Nov 00:00 → Sat 7 Nov 23:00, additive.
final revival = Season(
    id: 'revival-2026',
    key: 'revival_maximus',
    nameAr: 'نهضة الشفعاء',
    nameEn: 'Revival',
    startsAt: cairo(2026, 11, 2),
    endsAt: cairo(2026, 11, 7, 23),
    replacesRegular: false);

final holyWeek = Season(
    id: 'holy-week-2026',
    key: 'holy_week',
    nameAr: 'أسبوع الآلام',
    nameEn: 'Holy Week',
    startsAt: cairo(2026, 11, 2),
    endsAt: cairo(2026, 11, 8, 19));

const programme = ProgramInfo(
  speakerAr: 'نيافة الأنبا بافلي',
  topicAr: 'الجهاد والرجاء',
  choirAr: 'كورال كيتارا',
  venue: 'main',
  audience: 'general',
  attachmentUrl: 'https://drive.google.com/file/d/abc/view',
  attachmentLabelAr: 'تحميل برنامج النهضة (PDF)',
);

final night4 = lit('night4',
    date: DateTime.utc(2026, 11, 5), start: '18:30', end: '21:30', type: 'vespers', season: 'revival_maximus', program: programme);

final regular = [
  lit('fri', weekday: 5, start: '06:30', end: '09:00', type: 'mass'),
  lit('sun', weekday: 7, start: '07:00', end: '09:30', type: 'mass'),
];

// The seed's undated sample templates.
final revTemplates = [
  for (var wd = 1; wd <= 7; wd++)
    lit('rev-max-$wd', weekday: wd, start: '18:00', end: '20:30', season: 'revival_maximus', sample: true, placeAr: 'الكنيسة'),
];
final hwTemplates = [
  lit('hw-day-1', weekday: 1, start: '09:00', end: '13:00', season: 'holy_week', sample: true),
  lit('hw-eve-2', weekday: 2, start: '18:00', end: '21:00', season: 'holy_week', sample: true),
  lit('hw-day-3', weekday: 3, start: '09:00', end: '13:00', season: 'holy_week', sample: true),
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

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('B1: the next-service card in an additive revival', () {
    final all = [...regular, night4];
    test('at 18:00 tonight\'s revival (vespers) is next, not tomorrow\'s mass', () {
      final r = computeNextMass(liturgies: all, seasons: [revival], now: cairo(2026, 11, 5, 18));
      expect(r.next?.liturgy.id, 'night4');
    });
    test('at 18:30 it is happening now; the regular Friday mass is next', () {
      final r = computeNextMass(liturgies: all, seasons: [revival], now: cairo(2026, 11, 5, 18, 30));
      expect(r.happeningNow?.liturgy.id, 'night4');
      expect(r.next?.liturgy.id, 'fri');
    });
    test('regular masses continue around the revival', () {
      expect(computeNextMass(liturgies: all, seasons: [revival], now: cairo(2026, 11, 6, 5)).next?.liturgy.id, 'fri');
      expect(computeNextMass(liturgies: all, seasons: [revival], now: cairo(2026, 11, 5, 12)).next?.liturgy.id, 'night4');
    });
    test('with Holy Week also active the revival still counts', () {
      final r = computeNextMass(liturgies: all, seasons: [revival, holyWeek], now: cairo(2026, 11, 5, 18));
      expect(r.next?.liturgy.id, 'night4');
    });
    test('an inactive season\'s service does not count', () {
      final off = Season(
          id: 'x', key: 'revival_maximus', nameAr: '', nameEn: '', startsAt: cairo(2026, 11, 2), endsAt: cairo(2026, 11, 7),
          active: false, replacesRegular: false);
      final r = computeNextMass(liturgies: all, seasons: [off], now: cairo(2026, 11, 5, 18));
      expect(r.next?.liturgy.id, 'fri');
    });
  });

  group('B5: the seed\'s undated sample templates', () {
    test('an additive revival with a real night drops the sample rev-max templates', () {
      final list = seasonalSchedule([revival], [...revTemplates, night4])[revival]!.map((l) => l.id).toList();
      expect(list, ['night4']);
      final occ = occurrencesForDay(liturgies: [...revTemplates, night4], seasons: [revival], day: cairo(2026, 11, 5), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['night4']);
      final fri = occurrencesForDay(liturgies: [...revTemplates, night4], seasons: [revival], day: cairo(2026, 11, 6), dayOffset: 0);
      expect(fri, isEmpty);
    });
    test('a replacing season with real data drops the sample templates of days not entered yet', () {
      final owner = lit('s1', date: DateTime.utc(2026, 11, 4), start: '06:00', end: '12:00', season: 'holy_week');
      final list = seasonalSchedule([holyWeek], [...hwTemplates, owner])[holyWeek]!.map((l) => l.id).toList();
      expect(list, ['s1']);
      final mon = occurrencesForDay(liturgies: [...hwTemplates, owner], seasons: [holyWeek], day: cairo(2026, 11, 2), dayOffset: 0);
      expect(mon, isEmpty);
    });
    test('a season made only of samples (the bundled seed) keeps every template', () {
      final samplePalm =
          lit('palm', date: DateTime.utc(2026, 11, 8), start: '07:00', end: '11:00', season: 'holy_week', sample: true);
      final list = seasonalSchedule([holyWeek], [...hwTemplates, samplePalm])[holyWeek]!.map((l) => l.id).toSet();
      expect(list, {'hw-day-1', 'hw-eve-2', 'hw-day-3', 'palm'});
      final occ = occurrencesForDay(liturgies: [...revTemplates], seasons: [revival], day: cairo(2026, 11, 5), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['rev-max-4']);
    });
    test('the real seed: the 2027 seasons keep their sample programme (templates and dated)', () {
      final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      final seed = SeedData(raw);
      final grouped = {for (final e in seasonalSchedule(seed.seasons, seed.liturgies).entries) e.key.id: e.value.map((l) => l.id).toSet()};
      expect(grouped['revival-maximus-2027'], containsAll(['rev-max-1', 'rev-max-7', 'rev-max-feast']));
      expect(grouped['holy-week-2027'], containsAll(['hw-day-1', 'hw-eve-3', 'hw-palm', 'hw-friday']));
      expect(grouped['revival-moses-2027'], containsAll(['rev-moses-1', 'rev-moses-feast']));
    });
    test('a real undated nightly service stays on its dated feast-morning (additive, no overlap)', () {
      final eve = lit('eve', weekday: 4, start: '18:30', end: '21:00', season: 'revival_maximus');
      final feast =
          lit('feast', date: DateTime.utc(2026, 11, 5), start: '06:30', end: '10:00', season: 'revival_maximus', type: 'mass');
      final occ = occurrencesForDay(liturgies: [eve, feast], seasons: [revival], day: cairo(2026, 11, 5), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['feast', 'eve']);
      // …but gives way to a dated real night that overlaps it.
      final occ2 = occurrencesForDay(liturgies: [eve, night4], seasons: [revival], day: cairo(2026, 11, 5), dayOffset: 0);
      expect(occ2.map((o) => o.liturgy.id), ['night4']);
    });
  });

  group('review fixes (PR #38)', () {
    test('a dated service before the season starts does not suppress the season\'s weekday service', () {
      // Replacing season from Thu 5 Nov 18:00; a dated real morning service that day is outside it.
      final evening = Season(
          id: 'e', key: 'holy_week', nameAr: '', nameEn: '', startsAt: cairo(2026, 11, 5, 18), endsAt: cairo(2026, 11, 8, 19));
      final morning = lit('morning', date: DateTime.utc(2026, 11, 5), start: '08:00', end: '10:00', season: 'holy_week');
      final eve = lit('eve', weekday: 4, start: '19:00', end: '21:00', season: 'holy_week');
      final occ = occurrencesForDay(liturgies: [morning, eve], seasons: [evening], day: cairo(2026, 11, 5), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['eve']);
    });

    // ADR-050 (seasons v2 P2 B1): once the season has a real service, its DATED
    // samples give way on every day too, not only on the real one's day.
    test('a dated sample service gives way to a real dated one (on every day of the season)', () {
      final samplePalm =
          lit('palm', date: DateTime.utc(2026, 11, 8), start: '07:00', end: '11:00', season: 'holy_week', sample: true);
      final sampleThu =
          lit('thu', date: DateTime.utc(2026, 11, 5), start: '07:00', end: '11:00', season: 'holy_week', sample: true);
      final real = lit('realPalm', date: DateTime.utc(2026, 11, 8), start: '06:00', end: '10:00', season: 'holy_week');
      final all = [samplePalm, sampleThu, real];
      expect(seasonalSchedule([holyWeek], all)[holyWeek]!.map((l) => l.id), ['realPalm']);
      expect(occurrencesForDay(liturgies: all, seasons: [holyWeek], day: cairo(2026, 11, 5), dayOffset: 0), isEmpty);
      expect(occurrencesForDay(liturgies: all, seasons: [holyWeek], day: cairo(2026, 11, 8), dayOffset: 0).map((o) => o.liturgy.id),
          ['realPalm']);
      expect(computeNextMass(liturgies: all, seasons: [holyWeek], now: cairo(2026, 11, 8, 5)).next?.liturgy.id, 'realPalm');
    });

    test('wedding pause is announced even when the booking category had only the wedding choice', () {
      const weddingOnly = ContactSettings([
        ContactCategory(slot: 'c1', labelAr: 'استفسار عام', labelEn: 'General inquiry'),
        ContactCategory(
            slot: 'c2', labelAr: 'حجز قاعة', labelEn: 'Hall booking', kind: ContactKinds.booking,
            subtypes: [ContactSubtype('wedding', 'فرح', 'Wedding')]),
      ]);
      final text = buildAssistantInstruction(
        settings: const ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: ''),
        liturgies: const [],
        seasons: const [],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        now: cairo(2026, 11, 5, 12),
        features: FeatureSettings.fromMap(const {'weddingBookingOff': true}),
        contact: weddingOnly.withoutWedding(),
      );
      expect(text, contains('Wedding (فرح) hall bookings are NOT accepted'));
      expect(text, isNot(contains('Hall booking (حجز قاعة)')));
    });

    test('the programme signature changes with a speaker, a church event or the live link', () {
      final now = cairo(2026, 11, 5, 18, 30);
      final base = assistantProgrammeSignature(features: FeatureSettings.defaults, now: now, liturgies: [night4]);
      final otherSpeaker = lit('night4',
          date: DateTime.utc(2026, 11, 5), start: '18:30', end: '21:30', type: 'vespers', season: 'revival_maximus',
          program: const ProgramInfo(speakerAr: 'متكلم آخر'));
      expect(assistantProgrammeSignature(features: FeatureSettings.defaults, now: now, liturgies: [otherSpeaker]), isNot(base));
      final live = FeatureSettings.fromMap(const {'liveEnabled': true, 'liveUrl': 'https://youtube.com/live/x'});
      expect(assistantProgrammeSignature(features: live, now: now, liturgies: [night4]), isNot(base));
      final ev = FeatureSettings.fromMap(const {
        'dayEvents': ['2026-11-05\u001f\u001f\u001f\u001fحدث\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f'],
      });
      expect(assistantProgrammeSignature(features: ev, now: now, liturgies: [night4]), isNot(base));
    });
  });

  group('B3 / B4: the assistant instruction', () {
    String build({FeatureSettings f = FeatureSettings.defaults, DateTime? now, List<Liturgy>? lits}) =>
        buildAssistantInstruction(
          settings: const ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: ''),
          liturgies: lits ?? [...regular, night4],
          seasons: [revival],
          clinics: const [],
          meetings: const [],
          activities: const [],
          facilities: const [],
          now: now ?? cairo(2026, 11, 5, 18, 30),
          features: f,
          contact: f.weddingBookingOff ? ContactSettings.defaults.withoutWedding() : ContactSettings.defaults,
        );

    test('a service line carries speaker, topic, choir and the labelled PDF link', () {
      final line = build().split('\n').firstWhere((l) => l.contains('Service night4'));
      expect(line, contains('speaker: نيافة الأنبا بافلي'));
      expect(line, contains('topic: الجهاد والرجاء'));
      expect(line, contains('choir: كورال كيتارا'));
      expect(line, contains('تحميل برنامج النهضة (PDF): https://drive.google.com/file/d/abc/view'));
    });

    test('church events of the day (and the next week) are grounded with their PDF', () {
      final f = FeatureSettings.fromMap({
        'dayEvents': [
          '2026-11-05\u001f\u001f18:30\u001f21:30\u001fالليلة الرابعة\u001f\u001fأبونا يوحنا\u001f\u001fالرجاء\u001f\u001f\u001f\u001f'
              '\u001fhttps://drive.google.com/x\u001fبرنامج الليلة\u001f',
          '2026-12-30\u001f\u001f\u001f\u001fحدث بعيد\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f',
        ],
      });
      final text = build(f: f);
      expect(text, contains('## Church events (today and the next 7 days)'));
      final line = text.split('\n').firstWhere((l) => l.contains('الليلة الرابعة'));
      expect(line, contains('2026-11-05'));
      expect(line, contains('speaker: أبونا يوحنا'));
      expect(line, contains('برنامج الليلة: https://drive.google.com/x'));
      expect(text, isNot(contains('حدث بعيد')));
      // The home card switched off: the events are not public, not grounded.
      final off = FeatureSettings.fromMap({
        'topEvent': false,
        'dayEvents': ['2026-11-05\u001f\u001f18:30\u001f21:30\u001fالليلة الرابعة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f'],
      });
      expect(build(f: off), isNot(contains('Church events')));
    });

    test('the live link is grounded only while live', () {
      final live = FeatureSettings.fromMap(const {
        'liveEnabled': true,
        'liveUrl': 'https://youtube.com/live/xyz',
        'liveLabelAr': 'صلوات العشية والنهضة بث مباشر',
      });
      final text = build(f: live);
      expect(text, contains('## Live stream now'));
      expect(text, contains('صلوات العشية والنهضة بث مباشر: https://youtube.com/live/xyz'));
      expect(build(), isNot(contains('Live stream now')));
      final ended = FeatureSettings.fromMap({
        'liveEnabled': true,
        'liveUrl': 'https://youtube.com/live/xyz',
        'liveEndsAt': cairo(2026, 11, 5, 18),
      });
      expect(build(f: ended), isNot(contains('Live stream now')));
    });

    test('wedding bookings paused: an explicit line, condolence still open', () {
      final text = build(f: FeatureSettings.fromMap(const {'weddingBookingOff': true}));
      final line = text.split('\n').firstWhere((l) => l.contains('Wedding (فرح) hall bookings'));
      expect(line, contains('NOT accepted'));
      expect(line, contains('Condolence (عزاء)'));
      expect(build(), isNot(contains('Wedding (فرح) hall bookings')));
    });
  });

  group('top event: today\'s / tonight\'s programme service', () {
    test('falls back to tonight\'s revival night (with programme) when no church event is set', () {
      final e = resolveTopEvent(
          now: cairo(2026, 11, 5, 12),
          settings: TodaySettings.defaults,
          events: const [],
          liturgies: [...regular, night4],
          seasons: [revival]);
      expect(e?.kind, TopEventKind.service);
      expect(e?.service?.liturgy.id, 'night4');
      expect(e?.tonight, isTrue);
      // Still while it runs; gone after it ended.
      expect(
          resolveTopEvent(now: cairo(2026, 11, 5, 20), settings: TodaySettings.defaults, events: const [],
                  liturgies: [night4], seasons: [revival])
              ?.kind,
          TopEventKind.service);
      expect(
          resolveTopEvent(now: cairo(2026, 11, 5, 22), settings: TodaySettings.defaults, events: const [],
                  liturgies: [night4], seasons: [revival])
              ?.kind,
          isNot(TopEventKind.service));
    });

    test('an admin church event keeps precedence; the switch turns the fallback off', () {
      final ev = DayEvent(id: 'e', titleAr: 'حدث الكنيسة', date: DateTime(2026, 11, 5));
      final e = resolveTopEvent(
          now: cairo(2026, 11, 5, 12), settings: TodaySettings.defaults, events: [ev], liturgies: [night4], seasons: [revival]);
      expect(e?.kind, TopEventKind.church);
      final off = TodaySettings.fromMap(const {'topEventServices': false});
      expect(off.topEventServices, isFalse);
      expect(TodaySettings.defaults.topEventServices, isTrue);
      final e2 = resolveTopEvent(now: cairo(2026, 11, 5, 12), settings: off, events: const [], liturgies: [night4], seasons: [revival]);
      expect(e2?.kind, isNot(TopEventKind.service));
    });

    test('a service without speaker or topic, or a regular one, is not used', () {
      final plain = lit('plain', date: DateTime.utc(2026, 11, 5), start: '18:30', end: '21:30', season: 'revival_maximus');
      final reg = lit('reg', weekday: 4, start: '18:30', end: '21:30', program: programme);
      final e = resolveTopEvent(
          now: cairo(2026, 11, 5, 12), settings: TodaySettings.defaults, events: const [], liturgies: [plain, reg], seasons: [revival]);
      expect(e?.kind, isNot(TopEventKind.service));
    });

    test('day event encoded string: 13 fields (before) and 16 fields (with a PDF)', () {
      final old = DayEvent.fromStored(0, '2026-11-05\u001f\u001f\u001f\u001fحدث\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f');
      expect(old?.attachmentUrl, '');
      final pdf = DayEvent.fromStored(
          0, '2026-11-05\u001f\u001f\u001f\u001fحدث\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001fhttps://drive.google.com/x\u001fالبرنامج\u001fProgramme');
      expect(pdf?.attachmentUrl, 'https://drive.google.com/x');
      expect(pdf?.attachmentLabelAr, 'البرنامج');
      expect(pdf?.attachmentLabelEn, 'Programme');
      final http = DayEvent.fromStored(0, '2026-11-05\u001f\u001f\u001f\u001fحدث\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001fhttp://x.com/a\u001f\u001f');
      expect(http?.attachmentUrl, '', reason: 'https only');
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child, DateTime now, {List<Liturgy>? lits, Map<String, dynamic>? features}) async {
      final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_Repo(SeedData(raw), lits ?? [...regular, night4], [revival])),
          nowProvider.overrideWith((ref) => Stream.value(now)),
          if (features != null) featuresProvider.overrideWithValue(FeatureSettings.fromMap(features)),
        ],
        child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: SingleChildScrollView(child: child))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('B1: at 18:00 the card shows tonight\'s revival with its programme, titled «الصلاة القادمة»', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2026, 11, 5, 18));
      expect(find.text('خدمة night4'), findsOneWidget);
      expect(find.text('الصلاة القادمة'), findsOneWidget);
      expect(find.textContaining('نيافة الأنبا بافلي'), findsOneWidget);
      expect(find.text('تحميل برنامج النهضة (PDF)'), findsOneWidget);
    });

    testWidgets('B2: at 18:30 «يُقام الآن» keeps speaker, topic, choir and the PDF button', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2026, 11, 5, 18, 30));
      final box = find.byKey(const Key('happeningNowBox'));
      expect(box, findsOneWidget);
      for (final t in ['نيافة الأنبا بافلي', 'الجهاد والرجاء', 'كورال كيتارا']) {
        expect(find.descendant(of: box, matching: find.textContaining(t)), findsOneWidget, reason: t);
      }
      expect(find.descendant(of: box, matching: find.text('تحميل برنامج النهضة (PDF)')), findsOneWidget);
      // The line already names the venue: no duplicate venue pill.
      expect(find.descendant(of: box, matching: find.text('الكنيسة الكبرى')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('top event: tonight\'s revival with speaker, topic and the labelled PDF button', (tester) async {
      await pump(tester, const TopEventCard(), cairo(2026, 11, 5, 18, 30));
      expect(find.text('الليلة في الكنيسة'), findsOneWidget);
      expect(find.byKey(const Key('topEventTitle')), findsOneWidget);
      expect(find.textContaining('نيافة الأنبا بافلي'), findsOneWidget);
      expect(find.textContaining('الجهاد والرجاء'), findsOneWidget);
      expect(find.text('تحميل برنامج النهضة (PDF)'), findsOneWidget);
    });

    testWidgets('top event: a sample (unconfirmed) programme service shows its programme, no «times pending» note (ADR-046)', (tester) async {
      final sampleNight = lit('sampleNight',
          date: DateTime.utc(2026, 11, 5), start: '18:30', end: '21:30', season: 'revival_maximus', sample: true, program: programme);
      await pump(tester, const TopEventCard(), cairo(2026, 11, 5, 12), lits: [sampleNight]);
      expect(find.byKey(const Key('topEventProgramme')), findsOneWidget);
      expect(find.byKey(const Key('topEventTimesPending')), findsNothing);
      expect(find.textContaining('مواعيد تقريبية'), findsNothing);
    });

    testWidgets('top event: a church event\'s PDF has its own labelled button', (tester) async {
      await pump(tester, const TopEventCard(), cairo(2026, 11, 5, 12), features: {
        'dayEvents': [
          '2026-11-05\u001f\u001f18:30\u001f21:30\u001fالليلة الرابعة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f'
              '\u001fhttps://drive.google.com/x\u001fبرنامج الليلة\u001f',
        ],
      });
      expect(find.text('حدث اليوم'), findsOneWidget);
      expect(find.byKey(const Key('topEventPdf')), findsOneWidget);
      expect(find.text('برنامج الليلة'), findsOneWidget);
    });
  });
}
