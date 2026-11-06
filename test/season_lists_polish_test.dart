// ADR-054: findings of the seasons v2 round-3 simulation.
// 1 (P3 item 9) An undated sample kept in the season lists while another
//   season's real service replaces it on one of its weekdays states that
//   day: «لا يُقام ٢٣ يونيو» on /mass-schedule, "(not on 2027-06-23:
//   replaced by …)" in the prompt; hidden on every day = dropped (ADR-053).
// 2 (O-1) «بعد يومين» / «بعد ٣ أيام» / «بعد ١١ يومًا», not «بعد ٢ أيام».
// 3 (O-2) Seasons that ended before today are not listed (/mass-schedule,
//   prompt).
// 4 (O-3) Preset dialog warns when the season replaces the weekly schedule
//   for more than 3 days; stored defaults unchanged.
// 5 (P7 12:30) The next card never repeats a service the «يُقام الآن» box
//   already names.
// 6 (P5 O-d) The active-season pill wraps with balanced lines.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/l10n.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/occasion_theme.dart' show ThemePresets;
import 'package:church_portal/domain/season_preset.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/time_format.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/season_preset_admin.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
      program: ProgramInfo(venue: venue, audience: audience),
    );

Season season(String id, String key, tz.TZDateTime? from, tz.TZDateTime? to,
        {bool replaces = false, String? nameAr}) =>
    Season(
        id: id,
        key: key,
        nameAr: nameAr ?? 'موسم $id',
        nameEn: 'Season $id',
        startsAt: from,
        endsAt: to,
        replacesRegular: replaces);

List<String> ids(Iterable<Liturgy> l) => [for (final x in l) x.id];

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
    {Locale locale = const Locale('ar'), bool scroll = true, double width = 390}) async {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  tester.view.physicalSize = Size(width, 2400);
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

class _Backend extends AdminBackend {
  _Backend(this.seasons);
  final List<AdminDoc> seasons;
  final batches = <Map<String, Map<String, dynamic>>>[];
  @override
  String get actor => 'owner@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(collection == 'seasons' ? seasons : const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(
      path == 'settings/features' ? AdminDoc('features', const {}) : seasons.where((d) => 'seasons/${d.id}' == path).firstOrNull);
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}
  @override
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) async => batches.add(writes);
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

void main() {
  setUpAll(CairoTime.ensureInitialized);

  // ── 1: the rev-moses-3 case of sims r3 P3 item 9.
  group('1: a listed sample states the days another season replaces it', () {
    final apostles = season('apostles-2027', 'apostles', cairo(2027, 6, 21), cairo(2027, 7, 11, 23, 59));
    final moses = season('revival-moses-2027', 'revival_moses', cairo(2027, 6, 22), cairo(2027, 7, 1, 23));
    final samples = [
      lit('rev-moses-3', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true),
      lit('rev-moses-4', weekday: 4, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses', sample: true),
    ];
    final revival =
        lit('revival', date: DateTime(2027, 6, 23), start: '18:30', end: '21:00', type: 'other', season: 'apostles');
    final datedOnce = [...samples, revival];
    final both = [apostles, moses];

    test('the sample stays listed, with 23 Jun as its exception (and who replaces it)', () {
      expect(ids(seasonalSchedule(both, datedOnce)[moses]!), ['rev-moses-3', 'rev-moses-4']);
      final x = seasonListExceptions(samples[0], moses, datedOnce, seasons: both);
      expect(x, hasLength(1));
      expect(x.single.date, DateTime(2027, 6, 23));
      expect(x.single.by.id, 'revival');
      // Thursday's sample has no exception.
      expect(seasonListExceptions(samples[1], moses, datedOnce, seasons: both), isEmpty);
    });

    test('past exception days are not named; no other season = no exception', () {
      expect(seasonListExceptions(samples[0], moses, datedOnce, seasons: both, from: cairo(2027, 6, 24, 10)), isEmpty);
      expect(seasonListExceptions(samples[0], moses, datedOnce, seasons: [moses]), isEmpty);
      // A real (non-sample) service never gets one.
      final real = lit('r3', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'revival_moses');
      expect(seasonListExceptions(real, moses, [real, revival], seasons: both), isEmpty);
    });

    test('hidden on every Wednesday: dropped from the list (ADR-053), no exception line needed', () {
      final weekly = [
        ...samples,
        lit('revival', weekday: 3, start: '18:30', end: '21:00', type: 'other', season: 'apostles'),
      ];
      expect(ids(seasonalSchedule(both, weekly)[moses]!), ['rev-moses-4']);
    });

    test('prompt: "(not on 2027-06-23: replaced by …)" on the Wednesday line', () {
      final p = prompt(datedOnce, both, cairo(2027, 6, 22, 11));
      final line = p.split('\n').firstWhere((l) => l.contains('Service rev-moses-3'));
      expect(line, contains('(not on 2027-06-23: replaced by Service revival (خدمة revival))'));
      final thu = p.split('\n').firstWhere((l) => l.contains('Service rev-moses-4'));
      expect(thu, isNot(contains('not on')));
      // After 23 Jun the exception is gone from the line.
      final later = prompt(datedOnce, both, cairo(2027, 6, 25, 11));
      expect(later.split('\n').firstWhere((l) => l.contains('Service rev-moses-3')), isNot(contains('not on')));
    });

    for (final (loc, text) in [(const Locale('ar'), 'لا يُقام ٢٣ يونيو'), (const Locale('en'), 'Not held 23 Jun')]) {
      testWidgets('/mass-schedule seasonal view (${loc.languageCode}): «$text» on the sample card only',
          (tester) async {
        await pump(tester, const MassSchedulePage(), cairo(2027, 6, 22, 11), datedOnce, both,
            locale: loc, scroll: false);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        final pill = find.byKey(const Key('notHeldOn'));
        expect(pill, findsOneWidget);
        expect(find.descendant(of: pill, matching: find.text(text)), findsOneWidget);
        final card = find.ancestor(of: pill, matching: find.byType(LiturgyCard));
        expect(tester.widget<LiturgyCard>(card).liturgy.id, 'rev-moses-3');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('/mass-schedule weekly view: the active revival section carries the same note', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 6, 22, 11), datedOnce, both, scroll: false);
      expect(find.byKey(const Key('notHeldOn')), findsOneWidget);
      expect(find.text('لا يُقام ٢٣ يونيو'), findsOneWidget);
    });

    test('formatDayMonth', () {
      expect(formatDayMonth(DateTime(2027, 6, 23), arabic: true), '٢٣ يونيو');
      expect(formatDayMonth(DateTime(2027, 6, 23), arabic: false), '23 Jun');
    });
  });

  // ── 2: Arabic counts.
  group('2: «بعد يومين», «بعد ٣ أيام», «بعد ١١ يومًا»', () {
    Future<BuildContext> ctx(WidgetTester tester, Locale l) async {
      late BuildContext c;
      await tester.pumpWidget(MaterialApp(
        locale: l,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (b) {
          c = b;
          return const SizedBox();
        }),
      ));
      return c;
    }

    testWidgets('Arabic', (tester) async {
      final c = await ctx(tester, const Locale('ar'));
      expect(c.inDays(1), 'غدًا');
      expect(c.inDays(2), 'بعد يومين');
      expect(c.inDays(3), 'بعد ٣ أيام');
      expect(c.inDays(10), 'بعد ١٠ أيام');
      expect(c.inDays(11), 'بعد ١١ يومًا');
      expect(c.inDays(51), 'بعد ٥١ يومًا');
      expect(c.dayCount(2), 'يومين');
      expect(c.dayCount(7), '٧ أيام');
      expect(c.dayCount(51), '٥١ يومًا');
    });

    testWidgets('English unchanged', (tester) async {
      final c = await ctx(tester, const Locale('en'));
      expect(c.inDays(2), 'In 2 days');
      expect(c.inDays(11), 'In 11 days');
    });

    testWidgets('home card Thu 23:00 → Saturday 21:00: «بعد يومين»', (tester) async {
      final lits = [lit('sat-eve', weekday: 6, start: '21:00', end: '23:00')];
      await pump(tester, const NextMassCard(), cairo(2027, 4, 29, 23), lits, const []);
      expect(find.textContaining('بعد يومين'), findsOneWidget);
      expect(find.textContaining('بعد ٢ أيام'), findsNothing);
    });
  });

  // ── 3: past seasons.
  group('3: seasons that ended before today are not listed', () {
    final nat = season('nat', 'nativity', cairo(2027, 1, 6), cairo(2027, 1, 7, 23, 59), replaces: true, nameAr: 'الميلاد');
    final hw = season('hw', 'holy_week', cairo(2027, 4, 25), cairo(2027, 5, 1, 18), replaces: true, nameAr: 'البصخة');
    final lits = [
      lit('nat-eve', date: DateTime(2027, 1, 6), start: '20:00', end: '23:30', season: 'nativity'),
      lit('hw-thu', date: DateTime(2027, 4, 29), start: '18:30', end: '23:00', type: 'other', season: 'holy_week'),
    ];

    test('seasonalSchedule(now:) drops a season that ended before today; a season ending today stays', () {
      final g = seasonalSchedule([nat, hw], lits, now: cairo(2027, 4, 30, 10));
      expect(g.keys.map((s) => s.id), ['hw']);
      expect(seasonalSchedule([nat, hw], lits).keys.map((s) => s.id), ['nat', 'hw']); // without now: unchanged
      expect(seasonalSchedule([nat], lits, now: cairo(2027, 1, 7, 23, 30)).keys.map((s) => s.id), ['nat']);
      expect(seasonalSchedule([nat], lits, now: cairo(2027, 1, 8, 0, 1)), isEmpty);
      expect(seasonEndedBeforeToday(nat, cairo(2027, 1, 8)), isTrue);
      expect(seasonEndedBeforeToday(season('open', 'x', null, null), cairo(2030, 1, 1)), isFalse);
    });

    test('the prompt does not list the past season', () {
      final p = prompt(lits, [nat, hw], cairo(2027, 4, 30, 10));
      expect(p, contains('### Season hw (البصخة)'));
      expect(p, isNot(contains('### Season nat')));
    });

    testWidgets('/mass-schedule on Good Friday: no Nativity section', (tester) async {
      await pump(tester, const MassSchedulePage(), cairo(2027, 4, 30, 10), lits, [nat, hw], scroll: false);
      // A replacing season opens the seasonal view by default.
      expect(find.text('البصخة'), findsWidgets);
      expect(find.text('الميلاد'), findsNothing);
      expect(find.text('خدمة nat-eve'), findsNothing);
    });
  });

  // ── 4: preset warning.
  group('4: preset dialog warns about a long replace window', () {
    test('presetReplaceDays', () {
      final pascha = Season(
          id: 'p', key: 'pascha', nameAr: 'الخماسين', nameEn: 'Pascha', startsAt: cairo(2027, 5, 1, 18),
          endsAt: cairo(2027, 6, 20, 23, 59), replacesRegular: false);
      final before = cairo(2027, 5, 1, 17);
      expect(presetReplaceDays(pascha, {PresetOption.replaceRegular}, before), 51);
      expect(presetReplaceDays(pascha, const {}, before), isNull, reason: 'additive and unticked');
      // Already replacing in the doc: warned even unticked.
      final stored = Season(
          id: 'p', key: 'pascha', nameAr: '', nameEn: '', startsAt: pascha.startsAt, endsAt: pascha.endsAt);
      expect(presetReplaceDays(stored, const {}, before), 51);
      // Counted from now once the season has started.
      expect(presetReplaceDays(pascha, {PresetOption.replaceRegular}, cairo(2027, 6, 10, 23, 59)), 10);
      // 3 days or less: no warning (Nativity, Pascha night).
      final nat = Season(
          id: 'n', key: 'nativity', nameAr: '', nameEn: '', startsAt: cairo(2027, 1, 6), endsAt: cairo(2027, 1, 7, 23, 59));
      expect(presetReplaceDays(nat, {PresetOption.replaceRegular}, cairo(2027, 1, 5)), isNull);
      // Stored defaults unchanged.
      expect(PresetRequest.defaultsFor('pascha'), contains(PresetOption.replaceRegular));
    });

    for (final (loc, text) in [
      (const Locale('ar'), 'تنبيه: هذا الموسم سيُلغي كل القداسات المعتادة لمدة ٥١ يومًا'),
      (const Locale('en'), 'Warning: this season will cancel every regular service for 51 days'),
    ]) {
      testWidgets('the apply dialog shows it (${loc.languageCode})', (tester) async {
        final b = _Backend([
          AdminDoc('pascha-2027', {
            'key': 'pascha',
            'nameAr': 'الخماسين المقدسة',
            'nameEn': 'Holy Fifty Days',
            'startsAt': DateTime.utc(2027, 5, 1, 15),
            'endsAt': DateTime.utc(2027, 6, 20, 21, 59),
            'replacesRegular': false,
          }),
        ]);
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          locale: loc,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: SeasonPresetScreen(repo: b, now: () => DateTime.utc(2027, 5, 1, 14))),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('presetSeason')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('presetSeasonItem-pascha-2027')).last);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(find.byKey(const Key('presetOpt-replaceRegular'))).value, isTrue);
        await tester.ensureVisible(find.byKey(const Key('presetApply')));
        await tester.tap(find.byKey(const Key('presetApply')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('presetReplaceLongWarn')), findsOneWidget);
        expect(find.textContaining(text), findsOneWidget);
        // Unticked: no warning.
        await tester.tap(find.text(loc.languageCode == 'ar' ? 'إلغاء' : 'Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('presetOpt-replaceRegular')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('presetApply')));
        await tester.tap(find.byKey(const Key('presetApply')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('presetApplyDialog')), findsOneWidget);
        expect(find.byKey(const Key('presetReplaceLongWarn')), findsNothing);
        expect(b.batches, isEmpty);
      });
    }
  });

  // ── 5: the r3 P7 12:30 repro (Great Lent Tuesday).
  group('5: the next card does not repeat a service named in the now box', () {
    final lent = season('lent', 'great_lent', cairo(2027, 3, 1), cairo(2027, 4, 24), nameAr: 'الصوم الكبير المقدس');
    final lits = [
      lit('lent-main', weekday: 2, start: '12:00', end: '15:00', season: 'great_lent', venue: 'main'),
      lit('lent-youth', weekday: 2, start: '13:00', end: '16:00', season: 'great_lent', venue: 'lower', audience: 'youth'),
    ];

    test('shownInNowBox', () {
      final r = computeNextMass(liturgies: lits, seasons: [lent], now: cairo(2027, 3, 9, 12, 30));
      expect(r.happeningNow?.liturgy.id, 'lent-main');
      expect(r.next?.liturgy.id, 'lent-youth');
      expect(r.shownInNowBox(r.happeningNow!), isTrue);
      expect(r.shownInNowBox(r.next!), isFalse);
    });

    testWidgets('12:30: no «وفي نفس الوقت: الكنيسة الكبرى» under the youth liturgy', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 3, 9, 12, 30), lits, [lent]);
      expect(find.byKey(const Key('happeningNowBox')), findsOneWidget);
      expect(find.text('خدمة lent-youth'), findsOneWidget);
      expect(find.textContaining('وفي نفس الوقت'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11:00 (nothing running): the later youth liturgy is still «وبعدها»', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 3, 9, 11), lits, [lent]);
      expect(find.byKey(const Key('parallelThen0')), findsOneWidget);
    });

    testWidgets('a third service, not in the now box, is still named', (tester) async {
      final three = [
        ...lits,
        lit('lent-kids', weekday: 2, start: '13:00', end: '15:00', season: 'great_lent', venue: 'services', audience: 'kids'),
      ];
      await pump(tester, const NextMassCard(), cairo(2027, 3, 9, 12, 30), three, [lent]);
      final at = find.textContaining('وفي نفس الوقت: ');
      expect(at, findsOneWidget);
      expect(tester.widget<Text>(at).data, isNot(contains('الكنيسة الكبرى')));
    });
  });

  // ── 6: balanced season pill.
  group('6: the active-season pill wraps with balanced lines', () {
    const name = 'عيد النيروز (رأس السنة القبطية ١٧٤٤ ش)';
    final nay = season('nayrouz', 'nayrouz', cairo(2027, 9, 11, 18), cairo(2027, 9, 12, 23, 59), nameAr: name);
    final lits = [lit('nay', date: DateTime(2027, 9, 12), start: '08:00', end: '10:00', season: 'nayrouz')];

    testWidgets('390 px: two lines, the last one not a lone «ش)»', (tester) async {
      await pump(tester, const NextMassCard(), cairo(2027, 9, 12, 7), lits, [nay], width: 390);
      final pill = find.byKey(const Key('seasonActivePill'));
      expect(pill, findsOneWidget);
      final text = find.descendant(of: pill, matching: find.textContaining('النيروز'));
      final para = tester.renderObject<RenderParagraph>(text);
      final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: para.text.toPlainText().length));
      // Group the boxes by line (their top); the last line holds more than «ش)».
      final tops = <double, double>{};
      for (final b in lines) {
        tops.update(b.top.roundToDouble(), (w) => w + (b.right - b.left), ifAbsent: () => b.right - b.left);
      }
      if (tops.length > 1) {
        final widths = tops.values.toList();
        final ratio = widths.last / widths.reduce((a, b) => a > b ? a : b);
        expect(ratio, greaterThan(0.4), reason: 'balanced lines: $widths');
      }
      expect(tester.takeException(), isNull);
    });

    test('BalancedText.balancedWidth: same line count, narrower box; one line = null', () {
      const style = TextStyle(fontSize: 12);
      final w = BalancedText.balancedWidth(
          'aaaa bbbb cccc dddd eeee ffff gggg hhhh i', style, 200, TextDirection.ltr, TextScaler.noScaling);
      expect(w, isNotNull);
      expect(w!, lessThan(200));
      expect(BalancedText.balancedWidth('short', style, 200, TextDirection.ltr, TextScaler.noScaling), isNull);
    });

    testWidgets('a short pill keeps its own width (does not stretch)', (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(const Locale('en'),
              palette: ThemePresets.palettes[ThemePresets.goldenHour]!.normalized(), key: ThemePresets.goldenHour),
          home: const Scaffold(
              body: Align(alignment: Alignment.topLeft, child: Pill('Lent', balanced: true, maxLines: null)))));
      expect(tester.getSize(find.byType(Pill)).width, lessThan(120));
    });
  });
}
