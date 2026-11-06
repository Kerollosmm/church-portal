// ADR-051 widgets: Holy Week day name in the top bar, the EN live label,
// the admin exceptional-season chips and feast-night date chips, and the
// season preset's tonight live end / wedding default / replace dates.
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_settings.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/season_preset_admin.dart';
import 'package:church_portal/ui/widgets/today_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

DateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

/// In-memory admin backend: seasons + liturgies, recording batched writes.
class _Backend extends AdminBackend {
  _Backend({this.seasons = const [], this.liturgies = const [], this.features});
  final List<AdminDoc> seasons, liturgies;
  Map<String, dynamic>? features;
  final batches = <Map<String, Map<String, dynamic>>>[];
  int liturgyReads = 0;

  @override
  String get actor => 'owner@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) {
    if (collection == 'liturgies') liturgyReads++;
    return Stream.value(switch (collection) { 'seasons' => seasons, 'liturgies' => liturgies, _ => const <AdminDoc>[] });
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(path == 'settings/features'
      ? (features != null ? AdminDoc('features', features!) : null)
      : seasons.where((d) => 'seasons/${d.id}' == path).firstOrNull);
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

Widget _app(Widget child, {String lang = 'en'}) => MaterialApp(
      locale: Locale(lang),
      theme: buildTheme(Locale(lang)),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  Future<void> pumpPublic(WidgetTester tester, Widget child,
      {FeatureSettings features = FeatureSettings.defaults, required DateTime now, String lang = 'ar'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        featuresProvider.overrideWithValue(features),
        featuresReadyProvider.overrideWithValue(true),
        nowProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        theme: buildTheme(Locale(lang), palette: ThemePresets.palettes['holyWeek']!, key: 'holyWeek'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: Column(children: [child])),
      ),
    ));
    await tester.pump();
  }

  group('issue 13: Holy Week day name in the top bar', () {
    testWidgets('«ليلة الجمعة العظيمة» on Holy Thursday evening, Arabic and English', (tester) async {
      await pumpPublic(tester, const TopUtilityBar(location: '/'), now: cairo(2027, 4, 29, 18, 30));
      expect(find.text('ليلة الجمعة العظيمة ٢٢ برموده ١٧٤٣ ش'), findsOneWidget);
      await pumpPublic(tester, const TopUtilityBar(location: '/'), now: cairo(2027, 4, 29, 18, 30), lang: 'en');
      expect(find.text('Eve of Good Friday 22 Baramouda 1743 AM'), findsOneWidget);
    });

    testWidgets('Palm Sunday morning and an ordinary day', (tester) async {
      await pumpPublic(tester, const TopUtilityBar(location: '/'), now: cairo(2027, 4, 25, 9));
      expect(find.textContaining('أحد الشعانين'), findsOneWidget);
      await pumpPublic(tester, const TopUtilityBar(location: '/'), now: cairo(2027, 5, 12, 9));
      expect(find.textContaining('الأربعاء'), findsOneWidget);
    });
  });

  group('issue 14: live label on English pages', () {
    final live = {
      'liveEnabled': true,
      'liveUrl': 'https://www.youtube.com/@example/live',
      'liveLabelAr': 'بث مباشر: قداس عيد القيامة',
    };

    testWidgets('no English label → the generic "Live now", never the Arabic text', (tester) async {
      await pumpPublic(tester, const LiveStreamBanner(), features: FeatureSettings.fromMap(live), now: cairo(2027, 5, 2, 0, 30), lang: 'en');
      expect(find.text('Live now from the church'), findsOneWidget);
      expect(find.textContaining('بث مباشر'), findsNothing);
      await pumpPublic(tester, const TopUtilityBar(location: '/mass-schedule'),
          features: FeatureSettings.fromMap(live), now: cairo(2027, 5, 2, 0, 30), lang: 'en');
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('the English label on English pages, the Arabic one on Arabic pages', (tester) async {
      final both = FeatureSettings.fromMap({...live, 'liveLabelEn': 'Live: the Resurrection liturgy'});
      await pumpPublic(tester, const LiveStreamBanner(), features: both, now: cairo(2027, 5, 2, 0, 30), lang: 'en');
      expect(find.text('Live: the Resurrection liturgy'), findsOneWidget);
      await pumpPublic(tester, const LiveStreamBanner(), features: both, now: cairo(2027, 5, 2, 0, 30));
      expect(find.text('بث مباشر: قداس عيد القيامة'), findsOneWidget);
    });
  });

  group('issue 5 / 11: admin chips', () {
    testWidgets('exceptional seasons: defaults ticked when the field is missing; a change is saved as a list', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Assistant',
        fields: assistantSettingsDoc.fields,
        data: const {'perDay': 3},
        docId: 'assistant',
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.pumpAndSettle();
      FilterChip chip(String k) => tester.widget<FilterChip>(find.byKey(ValueKey('choice-exceptionalSeasons-$k')));
      for (final k in exceptionalSeasonKeys) {
        expect(chip(k).selected, isTrue, reason: k);
      }
      expect(chip('apostles').selected, isFalse);
      expect(chip('fast').selected, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('choice-exceptionalSeasons-apostles')));
      await tester.tap(find.byKey(const ValueKey('choice-exceptionalSeasons-apostles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved!['exceptionalSeasons'], [
        'holy_week', 'pascha', 'nativity', 'marian', 'revival_maximus', 'revival_moses', 'apostles', 'kiahk', 'great_lent', //
      ]);
    });

    testWidgets('season replace dates: stored dates as chips, × removes one', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('seasons')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Season',
        fields: def.fields,
        def: def,
        data: const {
          'key': 'apostles',
          'nameAr': 'صوم الرسل',
          'replacesRegular': false,
          'replaceDates': ['2027-07-12', '2027-07-11'],
        },
        docId: 'ap',
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('date-replaceDates-2027-07-12')), findsOneWidget);
      expect(find.text('12 Jul 2027'), findsOneWidget);
      expect(find.byKey(const ValueKey('dateAdd-replaceDates')), findsOneWidget);
      final del = find.descendant(
          of: find.byKey(const ValueKey('date-replaceDates-2027-07-11')), matching: find.byTooltip('Delete'));
      await tester.ensureVisible(del);
      await tester.tap(del);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('date-replaceDates-2027-07-11')), findsNothing);
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved!['replaceDates'], ['2027-07-12']);
    });
  });

  group('issue 10 / 11 / 12: season preset screen', () {
    final lentStart = DateTime.utc(2027, 3, 7, 22); // Mon 8 Mar 00:00 Cairo
    final lentEnd = DateTime.utc(2027, 4, 23, 21, 59);

    Future<void> pump(WidgetTester tester, _Backend b, DateTime now) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(SeasonPresetScreen(repo: b, now: () => now)));
      await tester.pumpAndSettle();
    }

    testWidgets('Great Lent: weddings off by default; live end = tonight\'s last service + 30 min; one apply',
        (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('gl', {
          'key': 'great_lent', 'nameAr': 'الصوم الكبير المقدس', 'nameEn': 'Great Lent', 'startsAt': lentStart,
          'endsAt': lentEnd, 'replacesRegular': false, 'replaceDates': ['2027-04-24'],
        }),
      ], liturgies: [
        AdminDoc('ves', {'type': 'vespers', 'nameAr': 'عشية الصوم', 'start': '18:00', 'end': '19:30', 'weekday': 2, 'seasonKey': 'great_lent'}),
        AdminDoc('reg', {'type': 'mass', 'nameAr': 'قداس', 'start': '07:00', 'end': '23:30', 'weekday': 2}),
      ], features: {'heroMotion': true});
      await pump(tester, b, cairo(2027, 3, 16, 13));
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Great Lent').last);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('presetOpt-weddingOff'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('presetOpt-replaceRegular'))).value, isFalse);
      expect(find.byKey(const Key('presetReplaceDates')), findsOneWidget);
      expect(find.text('24 Apr 2027'), findsOneWidget);
      expect(b.liturgyReads, 1, reason: 'one read of the services, no listener');

      await tester.tap(find.byKey(const Key('presetOpt-live')));
      await tester.pumpAndSettle();
      expect(find.text('The live banner ends: 08:00 PM — 16 Mar 2027'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('presetLiveUrl')), 'https://www.youtube.com/@example/live');
      await tester.tap(find.byKey(const Key('presetApply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('The live banner ends: 08:00 PM'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('presetConfirm')));
      await tester.pumpAndSettle();
      final f = b.batches.single['settings/features']!;
      expect(f['weddingBookingOff'], isTrue);
      expect((f['liveEndsAt'] as DateTime).millisecondsSinceEpoch, cairo(2027, 3, 16, 20).millisecondsSinceEpoch);
      expect((f['seasonPreset'] as Map)['endsAt'], lentEnd);
    });
  });
}
