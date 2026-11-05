// ADR-043: the Holy Week simulation findings (work/sim-holy-week/report.md).
// B1 the next-service card counts every service of a season that replaces
// the regular schedule; B4 an owner's dated Holy Week is not mixed with the
// seed's undated weekday templates (per day, replacing seasons only); B2 the
// "happening now" line falls back to the venue and never ends in a dash; B3
// the assistant's service lines name the venue and audience; the `kids` /
// `children` audience alias; the season picker shows the year.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/season_preset_admin.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart' show audienceMatches;
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

Liturgy lit(String id, {int? weekday, DateTime? date, required String start, required String end,
        String type = 'other', String? season, String venue = '', String audience = '', String placeAr = ''}) =>
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
      program: ProgramInfo(venue: venue, audience: audience),
    );

// The simulation's week: Holy Week 3 Nov 2026 00:00 → 9 Nov 18:00 Cairo.
final hw2026 = Season(
    id: 'holy-week-2026',
    key: 'holy_week',
    nameAr: 'أسبوع الآلام',
    nameEn: 'Holy Week',
    startsAt: cairo(2026, 11, 3),
    endsAt: cairo(2026, 11, 9, 18));

final regular = [
  lit('fri', weekday: 5, start: '06:30', end: '09:00', type: 'mass'),
  lit('sun', weekday: 7, start: '07:00', end: '09:30', type: 'mass'),
];

// The owner's dated services (type other, like the seed's Holy Week hours).
final owner = [
  lit('s1', date: DateTime.utc(2026, 11, 4), start: '06:00', end: '12:00', season: 'holy_week', venue: 'main'),
  lit('s2', date: DateTime.utc(2026, 11, 4), start: '08:00', end: '11:30', season: 'holy_week', venue: 'lower', audience: 'youth'),
  lit('s4', date: DateTime.utc(2026, 11, 4), start: '17:30', end: '21:00', season: 'holy_week', venue: 'main'),
  lit('s5', date: DateTime.utc(2026, 11, 5), start: '06:00', end: '12:00', season: 'holy_week', venue: 'main'),
];

// The seed's undated sample templates (Wednesday = 3, Thursday = 4).
final templates = [
  lit('hw-day-3', weekday: 3, start: '09:00', end: '13:00', season: 'holy_week', placeAr: 'الكنيسة'),
  lit('hw-eve-3', weekday: 3, start: '18:00', end: '21:00', season: 'holy_week', placeAr: 'الكنيسة'),
  lit('hw-day-1', weekday: 1, start: '09:00', end: '13:00', season: 'holy_week', placeAr: 'الكنيسة'),
];

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('B1: the next-service card during a season that replaces the schedule', () {
    test('Holy Week services stored as `other` are the next service (not a regular mass days later)', () {
      final all = [...regular, ...owner];
      for (final (h, m, now, next) in [
        (7, 0, 's1', 's2'),
        (11, 45, 's1', 's4'),
        (17, 0, null, 's4'),
        (21, 45, null, 's5'),
      ]) {
        final r = computeNextMass(liturgies: all, seasons: [hw2026], now: cairo(2026, 11, 4, h, m));
        expect((r.happeningNow?.liturgy.id, r.next?.liturgy.id), (now, next), reason: '$h:$m');
      }
    });

    test('outside the season only masses count; in an additive revival its night counts too (ADR-045)', () {
      final rev = Season(
          id: 'rev', key: 'revival_moses', nameAr: '', nameEn: '', startsAt: cairo(2026, 11, 3), endsAt: cairo(2026, 11, 9),
          replacesRegular: false);
      final eve = lit('revEve', weekday: 4, start: '18:30', end: '21:00', season: 'revival_moses');
      final r = computeNextMass(liturgies: [...regular, eve], seasons: [rev], now: cairo(2026, 11, 5, 12));
      expect(r.next?.liturgy.id, 'revEve');
      // After the night the regular Friday mass is next again.
      expect(computeNextMass(liturgies: [...regular, eve], seasons: [rev], now: cairo(2026, 11, 5, 21, 30)).next?.liturgy.id,
          'fri');
      final after = computeNextMass(liturgies: [...regular, ...owner], seasons: [hw2026], now: cairo(2026, 11, 10, 12));
      expect(after.next?.liturgy.type, 'mass');
    });
  });

  group('B4: undated weekday templates vs an owner\'s dated programme', () {
    test('on a day with dated services the templates of that weekday do not occur', () {
      final occ = occurrencesForDay(
          liturgies: [...regular, ...owner, ...templates], seasons: [hw2026], day: cairo(2026, 11, 4), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['s1', 's2', 's4']);
    });

    test('the season list drops a template whose every weekday in the window has dated services', () {
      final list = seasonalSchedule([hw2026], [...owner, ...templates])[hw2026]!.map((l) => l.id).toList();
      expect(list, isNot(contains('hw-day-3')));
      expect(list, isNot(contains('hw-eve-3')));
      // Monday 9 Nov has no dated service yet: its sample template still shows.
      expect(list, contains('hw-day-1'));
    });

    test('a season of templates only (the seed\'s Holy Week 2027) keeps every template', () {
      final hw2027 = Season(
          id: 'hw27', key: 'holy_week', nameAr: '', nameEn: '', startsAt: cairo(2027, 4, 25), endsAt: cairo(2027, 5, 1, 18));
      final palm = lit('palm', date: DateTime.utc(2027, 4, 25), start: '07:00', end: '11:00', season: 'holy_week');
      final list = seasonalSchedule([hw2027], [...templates, palm])[hw2027]!.map((l) => l.id).toSet();
      expect(list, {'hw-day-3', 'hw-eve-3', 'hw-day-1', 'palm'});
      final wed = occurrencesForDay(liturgies: [...templates, palm], seasons: [hw2027], day: cairo(2027, 4, 28), dayOffset: 0);
      expect(wed.map((o) => o.liturgy.id), ['hw-day-3', 'hw-eve-3']);
    });

    test('additive revivals keep their nightly service on the dated feast day', () {
      final rev = Season(
          id: 'rev', key: 'revival_moses', nameAr: '', nameEn: '', startsAt: cairo(2027, 6, 22), endsAt: cairo(2027, 7, 1, 23, 59),
          replacesRegular: false);
      final eve = lit('revEve4', weekday: 4, start: '18:30', end: '21:00', season: 'revival_moses');
      final feast = lit('feast', date: DateTime.utc(2027, 7, 1), start: '06:30', end: '10:30', season: 'revival_moses', type: 'mass');
      final occ = occurrencesForDay(liturgies: [eve, feast], seasons: [rev], day: cairo(2027, 7, 1), dayOffset: 0);
      expect(occ.map((o) => o.liturgy.id), ['feast', 'revEve4']);
    });

    test('the page and the card agree: no template pairs with S4 as a parallel service', () {
      final all = [...owner, ...templates];
      final s4 = occurrencesForDay(liturgies: all, seasons: [hw2026], day: cairo(2026, 11, 4), dayOffset: 0)
          .firstWhere((o) => o.liturgy.id == 's4');
      final day = occurrencesForDay(liturgies: all, seasons: [hw2026], day: cairo(2026, 11, 4), dayOffset: 0);
      expect(parallelOccurrences(s4, day, ProgramOptions.defaults), isEmpty);
    });
  });

  group('B3: the assistant names venue and audience', () {
    test('each service line carries the venue and audience names', () {
      final text = buildAssistantInstruction(
        settings: const ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: ''),
        liturgies: owner,
        seasons: [hw2026],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        now: cairo(2026, 11, 4, 7),
      );
      final line = text.split('\n').firstWhere((l) => l.contains('Service s2'));
      expect(line, contains('Lower hall (القاعة السفلية)'));
      expect(line, contains('Youth (شباب)'));
      expect(text.split('\n').firstWhere((l) => l.contains('Service s1')), contains('Main church (الكنيسة الكبرى)'));
    });
  });

  group('audience alias: kids = children', () {
    test('items saved with `kids` share the children label, chip and filter with `children`', () {
      const defaults = ProgramOptions.defaults;
      expect(defaults.audience('kids')?.labelAr, 'أطفال');
      expect(defaults.audienceKey('kids'), 'children');
      final custom = ProgramOptions.fromMap({
        'audiences': ['general\u001fعام\u001fEveryone', 'kids\u001fأطفال\u001fChildren'],
      });
      expect(custom.audienceKey('children'), 'kids');
      expect(custom.audience('children')?.labelAr, 'أطفال');
      final a = lit('a', weekday: 1, start: '08:00', end: '09:00', audience: 'children');
      final b = lit('b', weekday: 1, start: '08:00', end: '09:00', audience: 'kids');
      for (final o in [defaults, custom]) {
        final chip = o.audienceKey('kids');
        expect(audienceMatches(a, chip, o) && audienceMatches(b, chip, o), isTrue);
      }
      expect(audienceMatches(a, 'youth', defaults), isFalse);
    });
  });

  group('B2: the "happening now" line', () {
    Future<String> line(WidgetTester tester, Liturgy l) async {
      final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_Repo(SeedData(raw), [l])),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 4, 7))),
        ],
        child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: SingleChildScrollView(child: NextMassCard()))),
      ));
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.byKey(const Key('happeningNowLine'))).data!;
    }

    final morning = DateTime.utc(2026, 11, 4);
    testWidgets('venue only → the venue name', (tester) async {
      expect(await line(tester, lit('v', date: morning, start: '06:00', end: '12:00', season: 'holy_week', venue: 'main')),
          'خدمة v — الكنيسة الكبرى');
    });
    testWidgets('free-text place wins over the venue', (tester) async {
      expect(
          await line(tester,
              lit('p', date: morning, start: '06:00', end: '12:00', season: 'holy_week', venue: 'main', placeAr: 'المذبح')),
          'خدمة p — المذبح');
    });
    testWidgets('neither → the name alone, no dangling dash', (tester) async {
      expect(await line(tester, lit('n', date: morning, start: '06:00', end: '12:00', season: 'holy_week')), 'خدمة n');
    });
  });

  group('season picker: two seasons with the same name are told apart by the year', () {
    testWidgets('labels carry the year', (tester) async {
      final b = _Backend([
        AdminDoc('hw26', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'nameEn': 'Holy Week', 'startsAt': cairo(2026, 11, 3), 'endsAt': cairo(2026, 11, 9)}),
        AdminDoc('hw27', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'nameEn': 'Holy Week', 'startsAt': cairo(2027, 4, 25), 'endsAt': cairo(2027, 5, 1)}),
      ]);
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: SeasonPresetScreen(repo: b, now: () => cairo(2026, 11, 1))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      final t26 = tester.widget<Text>(find.byKey(const ValueKey('presetSeasonItem-hw26')).last).data!;
      final t27 = tester.widget<Text>(find.byKey(const ValueKey('presetSeasonItem-hw27')).last).data!;
      expect(t26, startsWith('Holy Week 2026'));
      expect(t27, startsWith('Holy Week 2027'));
    });
  });
}

class _Repo extends SeedRepository {
  _Repo(super.seed, this._lits);
  final List<Liturgy> _lits;
  @override
  Stream<List<Liturgy>> liturgies() => Stream.value(_lits);
  @override
  Stream<List<Season>> seasons() => Stream.value([hw2026]);
}

class _Backend extends AdminBackend {
  _Backend(this.seasons);
  final List<AdminDoc> seasons;
  @override
  String get actor => 'owner@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(collection == 'seasons' ? seasons : const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}
  @override
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) async {}
  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {}
  @override
  Future<void> delete(String collection, String id) async {}
  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}
  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}
  @override
  Future<void> removeAdmin(String uid) async {}
}
