// Verse of the day: bundled public-domain list, Cairo-day rotation, admin
// options (settings/features.dailyVerse), the home card and its contrast.
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/pages/home_page.dart' show HaloText;
import 'package:church_portal/ui/widgets/golden.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:convert';

final _asset = File(dailyVersesAsset).readAsStringSync();
final _verses = parseDailyVerses(_asset);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

Future<void> _pumpHome(WidgetTester tester,
    {Map<String, dynamic>? dailyVerse,
    Map<String, bool> sections = const {},
    Map<String, dynamic> features = const {},
    required DateTime now}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = raw['settings']['features'] as Map;
  if (dailyVerse != null) f['dailyVerse'] = dailyVerse;
  (f['sections'] as Map).addAll(sections);
  f.addAll(features);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(SeedData(raw))),
    nowProvider.overrideWith((ref) => Stream.value(now)),
    dailyVersesProvider.overrideWith((ref) async => _verses),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(const Locale('ar')),
      routerConfig: container.read(routerProvider),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Primaries of the presets on the Golden hour scene (occasion presets with
/// their own scene are covered by test/occasion_theme_test.dart).
final goldenSceneAccents = [
  for (final p in ThemePresets.palettes.values)
    if (p.background == ThemePresets.goldenHourPalette.background) p.primary,
];

void main() {
  group('bundled verses', () {
    test('366 public-domain Van Dyck verses with source, licence and Arabic references', () {
      final meta = jsonDecode(_asset) as Map<String, dynamic>;
      expect(meta['license'], 'Public Domain');
      expect(meta['source'], 'https://ebible.org/Scriptures/arb-vd_vpl.zip');
      expect(meta['count'], 366);
      expect(_verses, hasLength(366));
      final refs = <String>{};
      for (final v in _verses) {
        expect(v.textAr.trim(), isNotEmpty);
        expect(v.refAr, matches(RegExp(r'^[\u0600-\u06FF ]+ [٠-٩]+: [٠-٩]+$')), reason: v.refAr);
        expect(v.refEn, matches(RegExp(r'^[1-3A-Za-z ]+ \d+:\d+$')), reason: v.refEn);
        expect(refs.add(v.refEn), isTrue, reason: 'duplicate ${v.refEn}');
      }
      final john = _verses.firstWhere((v) => v.refEn == 'John 3:16');
      expect(john.refAr, 'يوحنا ٣: ١٦');
      expect(File('pubspec.yaml').readAsStringSync(),
          matches(RegExp(r'^\s+- assets/verses/daily_verses\.json$', multiLine: true)), reason: 'active asset entry');
      // The asset was generated from the SHA-pinned archive the generator checks.
      final gen = File('tool/gen_daily_verses.py').readAsStringSync();
      expect(gen, contains("SRC_SHA256 = '${meta['sourceSha256']}'"));
    });

    test('the real provider loads the bundled asset (no override)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(dailyVersesProvider.future), hasLength(366));
    });

    test('malformed input parses to an empty / filtered list', () {
      expect(parseDailyVerses('[]'), isEmpty);
      expect(parseDailyVerses('{"verses": [{"textAr": 1}, {"textAr": "نص", "refAr": "مرجع"}]}'), hasLength(1));
    });
  });

  group('rotation follows the Cairo calendar day', () {
    test('day of year changes at Cairo midnight, not UTC midnight', () {
      // Winter (EET, UTC+2): Cairo midnight Jan 2 = 22:00 UTC Jan 1.
      expect(cairoDayOfYear(DateTime.utc(2026, 1, 1, 21, 59)), 1);
      expect(cairoDayOfYear(DateTime.utc(2026, 1, 1, 22, 0)), 2);
      expect(cairoDayOfYear(DateTime.utc(2026, 1, 1, 23, 59)), 2, reason: 'still Jan 1 in UTC');
      expect(cairoDayOfYear(DateTime.utc(2026, 1, 2, 0, 0)), 2, reason: 'UTC midnight changes nothing');
      // Summer (EEST, UTC+3): Cairo midnight Jul 2 = 21:00 UTC Jul 1.
      expect(cairoDayOfYear(DateTime.utc(2026, 7, 1, 20, 59)), 182);
      expect(cairoDayOfYear(DateTime.utc(2026, 7, 1, 21, 0)), 183);
      expect(cairoDayOfYear(DateTime.utc(2026, 7, 2, 0, 0)), 183);
      // New year: 22:00 UTC Dec 31 is already Jan 1 in Cairo.
      expect(cairoDayOfYear(DateTime.utc(2026, 12, 31, 21, 59)), 365);
      expect(cairoDayOfYear(DateTime.utc(2026, 12, 31, 22, 0)), 1);
      // Leap year reaches 366.
      expect(cairoDayOfYear(DateTime.utc(2028, 12, 31, 12)), 366);
    });

    test('verse N of the list on Cairo day N; the same verse all Cairo day', () {
      expect(verseForDay(_verses, DateTime.utc(2026, 1, 1, 21, 59)), same(_verses[0]));
      expect(verseForDay(_verses, DateTime.utc(2026, 1, 1, 22, 0)), same(_verses[1]));
      expect(verseForDay(_verses, DateTime.utc(2026, 1, 2, 0, 0)), same(_verses[1]));
      expect(verseForDay(_verses, DateTime.utc(2026, 1, 2, 21, 59)), same(_verses[1]));
      expect(verseForDay(_verses, DateTime.utc(2028, 12, 31, 12)), same(_verses[365]));
      expect(verseForDay(const [], DateTime.utc(2026)), isNull);
      const two = [Verse(textAr: 'أ', refAr: 'أ'), Verse(textAr: 'ب', refAr: 'ب')];
      expect(verseForDay(two, DateTime.utc(2026, 1, 3, 12)), same(two[0]), reason: 'wraps');
    });
  });

  group('admin options', () {
    test('missing fields default to on + daily; bad values fall back', () {
      expect(FeatureSettings.defaults.dailyVerse, DailyVerseConfig.defaults);
      expect(FeatureSettings.fromMap(const {'dailyVerse': {}}).dailyVerse.mode, DailyVerseConfig.daily);
      expect(FeatureSettings.defaults.enabled(Sections.dailyVerse), isTrue, reason: 'missing section = on');
      expect(FeatureSettings.fromMap(const {'sections': {'dailyVerse': false}}).enabled(Sections.dailyVerse), isFalse);
      final bad = DailyVerseConfig.fromMap(const {'mode': 'weekly', 'textAr': 3});
      expect(bad, DailyVerseConfig.defaults);
      final fixed = FeatureSettings.fromMap(const {
        'dailyVerse': {'mode': 'fixed', 'textAr': 'نص', 'refAr': 'مرجع'}
      }).dailyVerse;
      expect([fixed.mode, fixed.textAr, fixed.refAr], ['fixed', 'نص', 'مرجع']);
      expect(FeatureSettings(dailyVerse: fixed).toMap()['dailyVerse'], fixed.toMap());
    });

    test('resolve: fixed -> admin verse; empty fixed -> daily', () {
      final t = DateTime.utc(2026, 3, 1, 12);
      final f = resolveDailyVerse(const DailyVerseConfig(mode: 'fixed', textAr: ' نص ', refAr: ' مرجع '), _verses, t)!;
      expect([f.textAr, f.refAr, f.refEn], ['نص', 'مرجع', '']);
      expect(resolveDailyVerse(const DailyVerseConfig(mode: 'fixed'), _verses, t), same(verseForDay(_verses, t)));
    });

    test('saved only once it differs from the default or is already stored', () {
      expect(featuresSaveWrites(const FeatureSettings(), const {}).first.containsKey('dailyVerse'), isFalse);
      const fixed = FeatureSettings(dailyVerse: DailyVerseConfig(mode: 'fixed', textAr: 'نص'));
      expect(featuresSaveWrites(fixed, const {}).first['dailyVerse'], fixed.dailyVerse.toMap());
      final back = featuresSaveWrites(const FeatureSettings(), const {'dailyVerse': {'mode': 'fixed'}}).first;
      expect(back['dailyVerse'], DailyVerseConfig.defaults.toMap());
    });

    test('firestore.rules allow the key and validate it', () {
      final rules = File('firestore.rules').readAsStringSync();
      final block = rules.substring(rules.indexOf('function validFeatures('));
      expect(block, contains("'dailyVerse'"));
      expect(rules, contains('function validDailyVerse('));
      expect(rules.substring(rules.indexOf('function sectionKeys()')), contains("'dailyVerse'"));
      for (final k in DailyVerseConfig.defaults.toMap().keys) {
        expect(rules.substring(rules.indexOf('function validDailyVerse(')), contains("'$k'"));
      }
    });
  });

  group('hero verse (the hero panel shows the verse of the day)', () {
    testWidgets('shows today\'s Cairo verse with its reference in «»', (tester) async {
      // 23:30 UTC Jan 1 = 01:30 Jan 2 in Cairo -> entry 1.
      await _pumpHome(tester, now: DateTime.utc(2026, 1, 1, 23, 30));
      expect(find.byKey(const Key('heroVerse')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('homeHero')), matching: find.byKey(const Key('heroVerse'))),
          findsOneWidget);
      expect(find.text('« ${_verses[1].textAr} »'), findsOneWidget);
      expect(find.text(_verses[1].refAr), findsOneWidget); // Arabic UI: the Arabic reference
      // Shown once: the separate card under the hero is gone.
      expect(find.byKey(const Key('dailyVerseCard')), findsNothing);
      expect(find.byKey(const Key('dailyVerseText')), findsOneWidget);
    });

    testWidgets('fixed admin verse replaces the rotation', (tester) async {
      await _pumpHome(tester,
          now: DateTime.utc(2026, 5, 5, 9),
          dailyVerse: {'mode': 'fixed', 'textAr': 'نص الآية الثابتة', 'refAr': 'مزمور ٢٣: ١'});
      expect(find.text('« نص الآية الثابتة »'), findsOneWidget);
      expect(find.text('مزمور ٢٣: ١'), findsOneWidget);
    });

    testWidgets('admin: daily mode saves the hidden fixed-verse fields cleared', (tester) async {
      FeatureSettings? saved;
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: FeaturesEditor(
            initial: FeatureSettings(dailyVerse: DailyVerseConfig(mode: 'fixed', textAr: 'x' * 600, refAr: 'مرجع')),
            onSave: (f) async => saved = f,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dailyVerse-mode-daily')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('features-verseTextAr')), findsNothing);
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull, reason: 'the hidden over-long draft does not block the save');
      expect(saved!.dailyVerse, DailyVerseConfig.defaults);
    });

    testWidgets('set straight on the hero (no panel), old fixed-verse typography', (tester) async {
      await _pumpHome(tester, now: DateTime.utc(2026, 1, 1, 23, 30));
      final verse = find.byKey(const Key('heroVerse'));
      // The soft text scrim like the title's, not a cream/white card.
      expect(tester.widget(verse), isA<TextScrim>());
      expect(find.ancestor(of: verse, matching: find.byType(WarmPanel)), findsNothing);
      expect(find.descendant(of: verse, matching: find.byType(WarmPanel)), findsNothing);
      for (final w in tester.widgetList<Container>(find.descendant(of: verse, matching: find.byType(Container)))) {
        expect(w.decoration, isNull, reason: 'no box behind the verse');
      }
      final text = tester.widget<HaloText>(find.byKey(const Key('dailyVerseText')));
      expect(text.textAlign, TextAlign.center);
      expect(text.style.fontSize, 24); // Ruqaa 24 / 20 on phones, height 1.8 (pre-PR #17)
      expect(text.style.height, 1.8);
      final ref = tester.widget<HaloText>(find.byKey(const Key('dailyVerseRef')));
      expect([ref.style.fontSize, ref.style.fontWeight], [13, FontWeight.w700]);
    });

    testWidgets('no address ribbon in the hero by default; the admin switch brings it back', (tester) async {
      final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      final address = raw['settings']['church']['addressAr'] as String;
      await _pumpHome(tester, now: DateTime.utc(2026, 5, 5, 9));
      final hero = find.byKey(const Key('homeHero'));
      expect(find.descendant(of: hero, matching: find.byType(TitleRibbon)), findsNothing);
      expect(find.descendant(of: hero, matching: find.text(address)), findsNothing);
      expect(find.text(address), findsWidgets, reason: 'still in the footer');

      await _pumpHome(tester, now: DateTime.utc(2026, 5, 5, 9), features: const {'heroShowAddress': true});
      expect(find.descendant(of: hero, matching: find.byKey(const Key('heroRibbon'))), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text(address)), findsOneWidget);

      // An admin hero subtitle always shows (switch or not).
      await _pumpHome(tester, now: DateTime.utc(2026, 5, 5, 9), features: const {'heroSubtitleAr': 'أهلًا بكم'});
      expect(find.descendant(of: hero, matching: find.text('أهلًا بكم')), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text(address)), findsNothing);

      // The subtitle also wins with the address switch on.
      await _pumpHome(tester,
          now: DateTime.utc(2026, 5, 5, 9), features: const {'heroSubtitleAr': 'أهلًا بكم', 'heroShowAddress': true});
      expect(find.descendant(of: hero, matching: find.text('أهلًا بكم')), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text(address)), findsNothing);
    });

    testWidgets('section switched off: no hero verse', (tester) async {
      await _pumpHome(tester, now: DateTime.utc(2026, 5, 5, 9), sections: {'dailyVerse': false});
      expect(find.byKey(const Key('heroVerse')), findsNothing);
      expect(find.byKey(const Key('dailyVerseText')), findsNothing);
    });

    test('text colours (incl. every theme preset title) keep >= 4.5:1 on the panel, even over the gold backdrop', () {
      for (final under in const [AppColors.cream, AppColors.parchment, AppColors.gold]) {
        final bg = Color.alphaBlend(AppColors.panel, under);
        for (final fg in [AppColors.ink, AppColors.goldText, AppColors.script, for (final c in goldenSceneAccents) Color(c)]) {
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
        }
      }
    });
  });
}
