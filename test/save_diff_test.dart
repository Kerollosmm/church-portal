import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/admin/save_diff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeBackend implements AdminBackend {
  final Map<String, Map<String, dynamic>> docs;
  int saveCalls = 0;

  _FakeBackend({Map<String, Map<String, dynamic>>? docs})
      : docs = {
          for (final e in (docs ?? const {}).entries) e.key: Map<String, dynamic>.from(e.value),
        };

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(
        docs[path] == null ? null : AdminDoc(path.split('/').last, docs[path]!),
      );

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    saveCalls++;
    docs[path] = {...?docs[path], ...data};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('buildSaveDiffRows unit tests', () {
    test('formats booleans, short strings, numbers, dates, and long/complex fields using FieldDef labels', () {
      final initial = <String, dynamic>{
        'nameAr': 'كنيسة قديمة',
        'sample': true,
        'lat': 31.26,
        'historyAr': 'تاريخ قديم',
        'phones': <Map<String, dynamic>>[],
      };
      final current = <String, dynamic>{
        'nameAr': 'كنيسة جديدة',
        'sample': false,
        'lat': 31.30,
        'historyAr': 'تاريخ محدث',
        'phones': [
          {'labelAr': 'المكتب', 'number': '01012345678'},
        ],
      };

      final en = buildSaveDiffRows(churchInfoDoc.fields, initial, current, isAr: false);
      expect(en.overflowCount, 0);
      expect(en.rows.map((r) => r.label).toList(), [
        'Church name (Arabic)',
        'Unconfirmed data',
        'Latitude',
        'Phone numbers',
        'History (Arabic)',
      ]);
      expect(en.rows[0].oldValue, 'كنيسة قديمة');
      expect(en.rows[0].newValue, 'كنيسة جديدة');
      expect(en.rows[1].oldValue, adminStrings['switch_sample']![1]);
      expect(en.rows[1].newValue, adminStrings['switch_confirmed']![1]);
      expect(en.rows[2].oldValue, '31.26');
      expect(en.rows[2].newValue, '31.3');
      expect(en.rows[3].changedOnly, isTrue);
      expect(en.rows[4].changedOnly, isTrue);

      final ar = buildSaveDiffRows(churchInfoDoc.fields, initial, current, isAr: true);
      expect(ar.rows[0].label, 'اسم الكنيسة (عربي)');
      expect(ar.rows[1].oldValue, adminStrings['switch_sample']![0]);
      expect(ar.rows[1].newValue, adminStrings['switch_confirmed']![0]);
    });

    test('treats long single-line text (>36 chars) as changedOnly and resolves choices via tr', () {
      final initial = <String, dynamic>{
        'copticStrip': 'all',
        'liveUrl': '',
        'liveEndsAt': null,
      };
      final current = <String, dynamic>{
        'copticStrip': 'home',
        'liveUrl': 'https://youtube.com/watch?v=very-long-stream-identifier-12345',
        'liveEndsAt': DateTime.utc(2027, 4, 29, 18, 0),
      };
      String tr(String k) => switch (k) {
            'opt_all' => 'Every page',
            'opt_home' => 'Home only',
            _ => adminStrings[k]?[1] ?? k,
          };

      final diff = buildSaveDiffRows(todaySettingsDoc.fields, initial, current, isAr: false, tr: tr);
      expect(diff.rows.length, 3);
      expect(diff.rows[0].label, 'Coptic date strip');
      expect(diff.rows[0].oldValue, 'Every page');
      expect(diff.rows[0].newValue, 'Home only');
      expect(diff.rows[1].label, 'Stream link (YouTube / Facebook)');
      expect(diff.rows[1].changedOnly, isTrue);
      expect(diff.rows[2].label, 'Switch off automatically at (optional)');
      expect(diff.rows[2].oldValue, '—');
      expect(diff.rows[2].newValue, '2027-04-29 20:00');
    });

    test('caps rows at 12 and reports overflowCount', () {
      final fields = [
        for (var i = 0; i < 15; i++) FieldDef('f$i', 'حقل $i', 'Field $i', FieldType.text),
      ];
      final initial = {for (var i = 0; i < 15; i++) 'f$i': 'a$i'};
      final current = {for (var i = 0; i < 15; i++) 'f$i': 'b$i'};

      final diff = buildSaveDiffRows(fields, initial, current, isAr: false);
      expect(diff.rows.length, maxSaveDiffRows);
      expect(diff.overflowCount, 3);
      expect(diff.rows.first.label, 'Field 0');
      expect(diff.rows.last.label, 'Field 11');
    });
  });

  group('buildFeaturesSaveDiffRows unit tests', () {
    test('reports section toggles, home order/hidden, theme, and caps overflow', () {
      final before = FeatureSettings.defaults;
      final after = before.copyWith(
        sections: {
          ...before.sections,
          Sections.meetings: false,
        },
        homeOrder: [
          HomeBlocks.alerts,
          HomeBlocks.banner,
          ...HomeBlocks.defaultOrder.skip(2),
        ],
        homeHidden: {HomeBlocks.map},
        theme: 'navy',
        heroTitleEn: 'Welcome',
      );

      String tr(String k) => switch (k) {
            'heroTitleEn' => 'Hero title (English)',
            _ => adminStrings[k]?[1] ?? k,
          };
      final diff = buildFeaturesSaveDiffRows(before, after, isAr: false, tr: tr);
      final labels = diff.rows.map((r) => r.label).toList();
      expect(labels, contains('Sunday school & meetings'));
      expect(labels, contains('Home page layout'));
      expect(labels, contains('Home page layout — Church map'));
      expect(labels, contains('Hero title (English)'));
      expect(labels, contains('Site theme & occasions'));

      final meetingsRow = diff.rows.firstWhere((r) => r.label == 'Sunday school & meetings');
      expect(meetingsRow.oldValue, 'Enabled');
      expect(meetingsRow.newValue, 'Off');

      final mapRow = diff.rows.firstWhere((r) => r.label == 'Home page layout — Church map');
      expect(mapRow.oldValue, 'Visible');
      expect(mapRow.newValue, 'Hidden');

      final themeRow = diff.rows.firstWhere((r) => r.label == 'Site theme & occasions');
      expect(themeRow.newValue, 'Navy');
    });

    test('caps features diff at 12 rows when more than 12 sections change', () {
      final before = FeatureSettings.defaults;
      final after = before.copyWith(
        sections: {for (final s in Sections.all) s: false},
      );
      final diff = buildFeaturesSaveDiffRows(before, after, isAr: true);
      expect(diff.rows.length, maxSaveDiffRows);
      expect(diff.overflowCount, Sections.all.length - maxSaveDiffRows);
    });
  });

  group('Save diff confirmation dialog widget tests', () {
    testWidgets('dirty FeaturesEditor shows diff; Cancel does not save; Confirm saves', (tester) async {
      tester.view.physicalSize = const Size(1000, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FeatureSettings? saved;
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: FeaturesEditor(
            initial: FeatureSettings.defaults,
            onSave: (f) async => saved = f,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('theme-navy')));
      await tester.tap(find.byKey(const ValueKey('theme-navy')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();

      final diffList = find.byKey(const ValueKey('save-diff-list'));
      expect(diffList, findsOneWidget);
      expect(find.text('Confirm saving changes'), findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('Site theme & occasions')), findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('Golden hour (default) → Navy')), findsOneWidget);

      // Tap targets meet 48x48 dp accessibility minimum.
      expect(tester.getSize(find.byKey(const ValueKey('confirm-cancel'))).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('confirm-ok'))).height, greaterThanOrEqualTo(48));

      // Cancel must not write.
      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byKey(const ValueKey('save-diff-list')), findsNothing);

      // Re-open and confirm writes.
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();
      expect(saved?.theme, 'navy');
    });

    testWidgets('dirty Today DocEditor shows diff; Cancel does not write; Confirm saves', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _FakeBackend(docs: {
        'settings/features': {'copticStrip': 'all', 'liveEnabled': false},
      });
      await tester.pumpWidget(_wrap(ChurchInfoScreen(repo: repo, doc: todaySettingsDoc)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('field-liveEnabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      final diffList = find.byKey(const ValueKey('save-diff-list'));
      expect(diffList, findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('Live-stream banner')), findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('Off → Enabled')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 0);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 1);
      expect(repo.docs['settings/features']!['liveEnabled'], isTrue);
    });

    testWidgets('dirty Church DocEditor shows diff at 320px x 200% and Cancel does not write', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _FakeBackend(docs: {
        'settings/church': {
          'nameAr': 'كنيسة قديمة',
          'nameEn': 'Old Church',
          'addressAr': 'شارع ٤٥',
          'sample': true,
        },
      });
      await tester.pumpWidget(_wrap(ChurchInfoScreen(repo: repo, doc: churchInfoDoc)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'كنيسة جديدة');
      await tester.pump();
      final saveBtn = find.byKey(const ValueKey('unsaved-bar-save'));
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final diffList = find.byKey(const ValueKey('save-diff-list'));
      expect(diffList, findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('Church name (Arabic)')), findsOneWidget);
      expect(find.descendant(of: diffList, matching: find.text('كنيسة قديمة → كنيسة جديدة')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 0);
    });

    testWidgets('more than 12 changed fields shows capped list and "and N more" line', (tester) async {
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        Scaffold(
          body: FeaturesEditor(
            initial: FeatureSettings.defaults,
            onSave: (_) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Toggle 14 sections off (assistant is omitted from FeaturesEditor).
      for (final s in Sections.all.where((k) => k != Sections.assistant).take(14)) {
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('section-$s')),
          matching: find.byType(Switch),
        ));
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-diff-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-diff-more')), findsOneWidget);
      expect(find.text('and 2 more'), findsOneWidget);
    });
  });
}
