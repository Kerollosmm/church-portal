// ADR-055: seasonal list empty state. With the «المواسم والأعياد الكنسية»
// switch on and no season in effect now (all ended / none started yet),
// /mass-schedule shows «لا توجد مواسم حالية» ("No current seasons") and,
// when an enabled season starts later, «الموسم القادم: … — يبدأ ٢٥ نوفمبر»
// ("Next season: … — starts 25 Nov"), built from the seasons already loaded.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/occasion_theme.dart' show ThemePresets;
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

Season season(String id, String nameAr, String nameEn, tz.TZDateTime? from, tz.TZDateTime? to,
        {bool active = true}) =>
    Season(
        id: id, key: id, nameAr: nameAr, nameEn: nameEn, startsAt: from, endsAt: to, active: active);

Liturgy lit(String id, {required DateTime date, String? seasonKey}) => Liturgy(
      id: id,
      type: 'mass',
      nameAr: 'خدمة $id',
      nameEn: 'Service $id',
      date: date,
      start: '07:00',
      end: '09:00',
      seasonKey: seasonKey,
    );

class _Repo extends SeedRepository {
  _Repo(super.seed, this._lits, this._seasons);
  final List<Liturgy> _lits;
  final List<Season> _seasons;
  @override
  Stream<List<Liturgy>> liturgies() => Stream.value(_lits);
  @override
  Stream<List<Season>> seasons() => Stream.value(_seasons);
}

Future<void> pumpSeasonal(WidgetTester tester, DateTime now, List<Season> seasons,
    {List<Liturgy> lits = const [], Locale locale = const Locale('ar')}) async {
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
        theme: buildTheme(locale,
            palette: ThemePresets.palettes[ThemePresets.goldenHour]!.normalized(), key: ThemePresets.goldenHour),
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: MassSchedulePage())),
  ));
  await tester.pumpAndSettle();
  // Turn the seasonal switch on (a replacing season in effect opens it already).
  if (!tester.widget<Switch>(find.byType(Switch)).value) {
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
  }
  expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
}

void main() {
  final now = cairo(2026, 11, 6, 16, 17);
  final ended = season('apostles', 'صوم الرسل', 'Apostles Fast', cairo(2026, 6, 8), cairo(2026, 7, 11, 23, 59));
  final nayrouz = season('nayrouz', 'عيد النيروز', 'Nayrouz', cairo(2026, 9, 11), cairo(2026, 9, 27, 23, 59));
  final nativityFast =
      season('nativity_fast', 'صوم الميلاد', 'Nativity Fast', cairo(2026, 11, 25), cairo(2027, 1, 6, 23, 59));
  final kiahk = season('kiahk', 'شهر كيهك', 'Kiahk', cairo(2026, 12, 10), cairo(2027, 1, 8, 23, 59));
  final greatLent = season('great_lent', 'الصوم الكبير', 'Great Lent', cairo(2027, 2, 15), cairo(2027, 4, 3, 23, 59));

  group('nextUpcomingSeason', () {
    test('the enabled season that starts soonest after now', () {
      expect(nextUpcomingSeason([greatLent, ended, kiahk, nativityFast], now)?.id, 'nativity_fast');
    });
    test('disabled, started, ended and undated seasons are skipped', () {
      final off = season('off', 'م', 'Off', cairo(2026, 11, 10), cairo(2026, 11, 12), active: false);
      final undated = season('u', 'م', 'Undated', null, null);
      expect(nextUpcomingSeason([off, ended, nayrouz, undated, kiahk], now)?.id, 'kiahk');
      expect(nextUpcomingSeason([off, ended, nayrouz, undated], now), isNull);
    });
  });

  group('/mass-schedule seasonal view, no current season', () {
    testWidgets('AR: empty state + next season line', (tester) async {
      await pumpSeasonal(tester, now, [ended, nayrouz, kiahk, nativityFast]);
      expect(find.byKey(const Key('noCurrentSeasons')), findsOneWidget);
      expect(find.text('لا توجد مواسم حالية'), findsOneWidget);
      expect(find.text('الموسم القادم: صوم الميلاد — يبدأ ٢٥ نوفمبر'), findsOneWidget);
      expect(find.text('لا توجد بيانات حاليًا'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EN: empty state + next season line', (tester) async {
      await pumpSeasonal(tester, now, [ended, nayrouz, kiahk, nativityFast], locale: const Locale('en'));
      expect(find.text('No current seasons'), findsOneWidget);
      expect(find.text('Next season: Nativity Fast — starts 25 Nov'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AR: all ended, nothing upcoming — no next-season line', (tester) async {
      await pumpSeasonal(tester, now, [ended, nayrouz]);
      expect(find.text('لا توجد مواسم حالية'), findsOneWidget);
      expect(find.byKey(const Key('emptyStateDetail')), findsNothing);
      expect(find.textContaining('الموسم القادم'), findsNothing);
    });

    testWidgets('EN: all ended, nothing upcoming — no next-season line', (tester) async {
      await pumpSeasonal(tester, now, [ended, nayrouz], locale: const Locale('en'));
      expect(find.text('No current seasons'), findsOneWidget);
      expect(find.byKey(const Key('emptyStateDetail')), findsNothing);
      expect(find.textContaining('Next season'), findsNothing);
    });

    testWidgets('no seasons at all: the same empty state', (tester) async {
      await pumpSeasonal(tester, now, const []);
      expect(find.text('لا توجد مواسم حالية'), findsOneWidget);
      expect(find.byKey(const Key('emptyStateDetail')), findsNothing);
    });

    testWidgets('a next season in another year carries its year', (tester) async {
      await pumpSeasonal(tester, now, [ended, greatLent]);
      expect(find.text('الموسم القادم: الصوم الكبير — يبدأ ١٥ فبراير ٢٠٢٧'), findsOneWidget);
    });

    testWidgets('an upcoming season with services stays listed under the notice', (tester) async {
      await pumpSeasonal(tester, now, [ended, nativityFast],
          lits: [lit('nf1', date: cairo(2026, 11, 26), seasonKey: 'nativity_fast')]);
      expect(find.text('لا توجد مواسم حالية'), findsOneWidget);
      expect(find.text('الموسم القادم: صوم الميلاد — يبدأ ٢٥ نوفمبر'), findsOneWidget);
      expect(find.text('صوم الميلاد'), findsWidgets);
      expect(find.text('خدمة nf1'), findsOneWidget);
      final notice = tester.getTopLeft(find.byKey(const Key('noCurrentSeasons'))).dy;
      expect(notice, lessThan(tester.getTopLeft(find.text('خدمة nf1')).dy));
    });

    testWidgets('a season in effect now: no empty state', (tester) async {
      final current = season('now', 'نهضة', 'Revival', cairo(2026, 11, 1), cairo(2026, 11, 20, 23, 59));
      await pumpSeasonal(tester, now, [current, nativityFast],
          lits: [lit('r1', date: cairo(2026, 11, 7), seasonKey: 'now')]);
      expect(find.byKey(const Key('noCurrentSeasons')), findsNothing);
      expect(find.text('لا توجد مواسم حالية'), findsNothing);
    });
  });
}
