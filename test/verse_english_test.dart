// ADR-047: English text for the hero verse of the day — bundled World English
// Bible (British Edition) text for the 366 daily verses, optional English for
// the admin's fixed verse and season verses (inside settings/features), and
// the Arabic shown only when a verse has no English.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/season_verses.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _asset = File(dailyVersesAsset).readAsStringSync();
final _verses = parseDailyVerses(_asset);

Future<void> _pumpHome(WidgetTester tester, {required Locale locale, Map<String, dynamic>? dailyVerse, required DateTime now}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = raw['settings']['features'] as Map;
  if (dailyVerse != null) f['dailyVerse'] = dailyVerse;
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(SeedData(raw))),
    nowProvider.overrideWith((ref) => Stream.value(now)),
    dailyVersesProvider.overrideWith((ref) async => _verses),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      routerConfig: container.read(routerProvider),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('bundled English text', () {
    test('every one of the 366 verses has its WEBBE text; the Arabic and the rotation are unchanged', () {
      final meta = jsonDecode(_asset) as Map<String, dynamic>;
      expect(meta['licenseEn'], 'Public Domain');
      expect(meta['sourceEn'], 'https://ebible.org/Scriptures/eng-webbe_vpl.zip');
      expect(File('tool/gen_daily_verses.py').readAsStringSync(), contains("EN_SHA256 = '${meta['sourceEnSha256']}'"));
      expect(_verses, hasLength(366));
      for (final v in _verses) {
        expect(v.textEn.trim(), isNotEmpty, reason: v.refEn);
        expect(v.textEn, isNot(matches(RegExp(r'[\u0600-\u06FF]'))), reason: v.refEn);
        expect(v.textEn, isNot(contains('Yahweh')), reason: 'British Edition says "the LORD": ${v.refEn}');
      }
      final john = _verses.firstWhere((v) => v.refEn == 'John 3:16');
      expect(john.textEn, startsWith('For God so loved the world'));
      expect(john.refAr, 'يوحنا ٣: ١٦');
    });

    test('older lists without textEn still parse (English empty)', () {
      final v = parseDailyVerses('{"verses": [{"textAr": "نص", "refAr": "مرجع", "refEn": "John 1:1"}]}').single;
      expect(v.textEn, '');
    });
  });

  group('what the English site shows', () {
    const both = Verse(textAr: 'نص', refAr: 'يو ٣: ١٦', refEn: 'John 3:16', textEn: 'For God so loved');
    test('English text with its English reference, left to right', () {
      final d = both.display(english: true);
      expect([d.text, d.ref, d.rtl], ['For God so loved', 'John 3:16', false]);
    });
    test('no English text: the Arabic with the Arabic reference (never mixed)', () {
      const ar = Verse(textAr: 'نص', refAr: 'يو ٣: ١٦', refEn: 'John 3:16');
      final d = ar.display(english: true);
      expect([d.text, d.ref, d.rtl], ['نص', 'يو ٣: ١٦', true]);
    });
    test('English text without an English reference keeps the Arabic citation', () {
      const v = Verse(textAr: 'نص', refAr: 'يو ٣: ١٦', textEn: 'For God so loved');
      expect(v.display(english: true).ref, 'يو ٣: ١٦');
    });
    test('the Arabic site always shows the Arabic', () {
      final d = both.display(english: false);
      expect([d.text, d.ref, d.rtl], ['نص', 'يو ٣: ١٦', true]);
    });
  });

  group('admin verses keep their English', () {
    test('fixed verse: textEn / refEn read, written only when set, and carried to the hero', () {
      final c = DailyVerseConfig.fromMap(const {'mode': 'fixed', 'textAr': 'نص', 'refAr': 'م', 'textEn': 'Text', 'refEn': 'Ps 23:1'});
      expect([c.textEn, c.refEn], ['Text', 'Ps 23:1']);
      expect(c.toMap(), {'mode': 'fixed', 'textAr': 'نص', 'refAr': 'م', 'textEn': 'Text', 'refEn': 'Ps 23:1'});
      expect(const DailyVerseConfig(mode: 'fixed', textAr: 'نص').toMap().keys, ['mode', 'textAr', 'refAr']);
      final v = resolveDailyVerse(c, _verses, DateTime.utc(2026, 3, 1, 12))!;
      expect([v.textEn, v.refEn], ['Text', 'Ps 23:1']);
      expect(c, isNot(const DailyVerseConfig(mode: 'fixed', textAr: 'نص', refAr: 'م')));
    });

    test('season verses: the optional ␟textEn␟refEn tail', () {
      const s = SeasonVerses.sep;
      final set = SeasonVerses.fromList([
        ['holy_week', 'هوذا حمل الله', 'يو ١: ٢٩', 'Behold, the Lamb of God', 'John 1:29'].join(s),
        ['holy_week', 'المسيح قام', ''].join(s),
      ]).bySeason['holy_week']!;
      expect([set[0].textEn, set[0].refEn], ['Behold, the Lamb of God', 'John 1:29']);
      expect([set[1].textEn, set[1].refEn], ['', '']);
    });

    test('the season-verse editor stores the tail only when the English is set', () {
      final def = seasonSettingsDoc.fields.firstWhere((f) => f.key == 'seasonVerses');
      expect(def.subFields.map((f) => f.key), ['season', 'textAr', 'refAr', 'textEn', 'refEn']);
      expect(def.encodedOptionalTail, 2);
      const s = '\u001f';
      expect(encodeRowFields(def, {'season': 'pascha', 'textAr': 'المسيح قام', 'refAr': '', 'textEn': '', 'refEn': ''}),
          ['pascha', 'المسيح قام', ''].join(s));
      expect(encodeRowFields(def, {'season': 'pascha', 'textAr': 'ق', 'refAr': 'م', 'textEn': 'Christ is risen', 'refEn': ''}),
          ['pascha', 'ق', 'م', 'Christ is risen', ''].join(s));
      // Other encoded lists (day events: fixed 13 / 16 fields) keep every field.
      final events = [...seasonSettingsDoc.fields, ...todaySettingsDoc.fields].where((f) => f.encodedRows && f.key != 'seasonVerses');
      for (final f in events) {
        expect(f.encodedOptionalTail, 0, reason: f.key);
      }
    });

    test('firestore.rules accept the English keys and the season-verse tail', () {
      final rules = File('firestore.rules').readAsStringSync();
      final dv = rules.substring(rules.indexOf('function validDailyVerse('));
      for (final k in ['textEn', 'refEn']) {
        expect(dv.substring(0, dv.indexOf('\n    }')), contains("'$k'"));
      }
      final sv = rules.substring(rules.indexOf('function validSeasonVerses('));
      expect(sv.substring(0, sv.indexOf('\n    }')), contains(r'(\x1f[^\x1f\x1e]{0,500}\x1f[^\x1f\x1e]{0,60})?'));
    });
  });

  group('hero verse on Home', () {
    testWidgets('English site: the bundled verse in English, left to right, with the English reference', (tester) async {
      await _pumpHome(tester, locale: const Locale('en'), now: DateTime.utc(2026, 1, 1, 23, 30));
      final v = _verses[1];
      expect(find.text('“${v.textEn}”'), findsOneWidget);
      expect(find.text(v.refEn), findsOneWidget);
      expect(find.text('« ${v.textAr} »'), findsNothing);
    });

    testWidgets('Arabic site: unchanged Arabic verse and reference', (tester) async {
      await _pumpHome(tester, locale: const Locale('ar'), now: DateTime.utc(2026, 1, 1, 23, 30));
      final v = _verses[1];
      expect(find.text('« ${v.textAr} »'), findsOneWidget);
      expect(find.text(v.refAr), findsOneWidget);
      expect(find.text('“${v.textEn}”'), findsNothing);
    });

    testWidgets('English site: a fixed verse with English shows it; without English the Arabic stays', (tester) async {
      await _pumpHome(tester,
          locale: const Locale('en'),
          now: DateTime.utc(2026, 5, 5, 9),
          dailyVerse: {'mode': 'fixed', 'textAr': 'الرب راعيّ', 'refAr': 'مزمور ٢٣: ١', 'textEn': 'The LORD is my shepherd', 'refEn': 'Psalm 23:1'});
      expect(find.text('“The LORD is my shepherd”'), findsOneWidget);
      expect(find.text('Psalm 23:1'), findsOneWidget);
    });

    testWidgets('English site: a fixed verse without English falls back to Arabic + Arabic reference', (tester) async {
      await _pumpHome(tester,
          locale: const Locale('en'),
          now: DateTime.utc(2026, 5, 5, 9),
          dailyVerse: {'mode': 'fixed', 'textAr': 'الرب راعيّ', 'refAr': 'مزمور ٢٣: ١'});
      expect(find.text('« الرب راعيّ »'), findsOneWidget);
      expect(find.text('مزمور ٢٣: ١'), findsOneWidget);
    });
  });
}
