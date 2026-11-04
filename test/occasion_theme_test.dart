// Occasion themes (ADR-025) and the hero video library (ADR-026): presets
// and their contrast on every ground (incl. the dark Holy Week scene),
// auto-correction of admin colour edits, the legacy `burgundy` key, the
// Coptic Easter computus, the Cairo-date schedule, YouTube link validation,
// and a rendered-text contrast walk over the public pages of every preset.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_portal/app.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

SeedData _seed(Map<String, dynamic> features) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  f['sections'] = {...(f['sections'] as Map), 'clinics': true};
  f.addAll(features);
  raw['settings']['features'] = f;
  return SeedData(raw);
}

/// The seed plus an admin-defined category with items and a custom page
/// with every text block type (ADR-027), for the contrast walk.
class _CustomRepo extends SeedRepository {
  _CustomRepo(super.seed);
  @override
  Stream<List<CustomCategory>> categories() => Stream.value(const [
        CustomCategory(id: 'k1', slug: 'youth-trips', nameAr: 'رحلات', nameEn: 'Youth trips', introEn: 'Trips for youth'),
      ]);
  @override
  Stream<List<CategoryEntry>> entries() => Stream.value(const [
        CategoryEntry(id: 'e1', categoryId: 'k1', titleAr: 'رحلة', titleEn: 'Alexandria trip', descEn: 'A day by the sea',
            contactPhone: '01012345678', externalUrl: '/page/donate', externalLabelEn: 'Register', sample: true),
      ]);
  @override
  Stream<List<CustomPage>> pages() => Stream.value(const [
        CustomPage(id: 'p1', slug: 'donate', titleAr: 'تبرع', titleEn: 'Building donations', subtitleEn: 'Help us', blocks: [
          PageBlock(type: BlockTypes.heading, textEn: 'The new building'),
          PageBlock(type: BlockTypes.paragraph, textEn: 'Every gift helps.'),
          PageBlock(type: BlockTypes.button, textEn: 'Contact us', url: '/contact'),
          PageBlock(type: BlockTypes.link, textEn: 'Diocese site', url: 'https://example.org'),
          PageBlock(type: BlockTypes.donation, account: 'CIB 100', instapay: 'church@instapay', wallet: '010', textEn: 'Notes'),
        ]),
      ]);
}

class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

final _nov1 = CairoTime.at(2026, 11, 1, 12 * 60).toUtc();

/// The resolved theme once settings/features and the clock have arrived.
Future<ActiveTheme> _active(ProviderContainer c) async {
  c.listen(activeThemeProvider, (_, _) {});
  await c.listen(featuresStreamProvider.future, (_, _) {}).read();
  await c.listen(nowProvider.future, (_, _) {}).read();
  return c.read(activeThemeProvider);
}

Future<ProviderContainer> _pumpApp(WidgetTester tester, Map<String, dynamic> features,
    {Size size = const Size(390, 6000), DateTime? now}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(_CustomRepo(_seed(features))),
    nowProvider.overrideWith((ref) => Stream.value(now ?? _nov1)),
    localeProvider.overrideWith(_English.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ChurchPortalApp()));
  await tester.pumpAndSettle();
  return container;
}

/// The colour painted behind [e]: the nearest ancestor that paints one
/// (translucent ones composited over the page background), else the page
/// background itself.
Color _groundOf(Element e, OccasionColors pal, ThemeData theme) {
  Color? found;
  Color? pick(Color? c) => c != null && c.a > 0 ? c : null;
  Color? fromDecoration(Decoration? d) {
    if (d is! BoxDecoration) return null;
    final g = d.gradient?.colors;
    return pick(d.color) ?? (g == null || g.isEmpty ? null : pick(g[g.length ~/ 2]));
  }

  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Container) {
      c = pick(w.color) ?? fromDecoration(w.decoration);
    } else if (w is DecoratedBox) {
      c = fromDecoration(w.decoration);
    } else if (w is ColoredBox) {
      c = pick(w.color);
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = pick(w.color);
    } else if (w is Card) {
      c = pick(w.color) ?? pick(theme.cardTheme.color);
    } else if (w is ChoiceChip) {
      c = w.selected ? (w.selectedColor ?? theme.chipTheme.selectedColor) : (w.backgroundColor ?? theme.chipTheme.backgroundColor);
    } else if (w is FilterChip) {
      c = w.selected ? (w.selectedColor ?? theme.chipTheme.selectedColor) : (w.backgroundColor ?? theme.chipTheme.backgroundColor);
    } else if (w is ActionChip || w is Chip) {
      c = theme.chipTheme.backgroundColor;
    }
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  final g = found ?? pal.background;
  return g.a < 1 ? Color.alphaBlend(g, pal.background) : g;
}

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every visible paragraph's colour against its ground: ≥ 4.5:1, or ≥ 3:1
/// for large text (≥ 24 px, or ≥ 18.66 px bold).
List<String> _contrastFailures(WidgetTester tester, String where) {
  final failures = <String>[];
  for (final el in find.byType(RichText).evaluate()) {
    final ro = el.renderObject;
    if (ro is! RenderParagraph || !ro.attached || ro.size.isEmpty) continue;
    final style = ro.text.style;
    final color = style?.color;
    if (color == null || color.a == 0) continue;
    final text = ro.text.toPlainText().trim();
    if (text.isEmpty) continue;
    final theme = Theme.of(el);
    final pal = el.pal;
    final ground = _groundOf(el, pal, theme);
    final fg = color.a < 1 ? Color.alphaBlend(color, ground) : color;
    final size = (style?.fontSize ?? 14);
    final bold = (style?.fontWeight?.value ?? 400) >= 700;
    final large = size >= 24 || (bold && size >= 18.66);
    final min = large ? 3.0 : 4.5;
    final r = _ratio(fg, ground);
    if (r < min) failures.add('$where "${text.length > 30 ? text.substring(0, 30) : text}" ${r.toStringAsFixed(2)} < $min');
  }
  return failures;
}

const _routes = [
  '/', '/about', '/mass-schedule', '/church-education', '/church-activities', '/clinics', '/public-services', //
  '/contact', '/about/saints/moses-black',
];

void main() {
  group('presets: every text colour on every ground', () {
    test('all presets pass ≥ 4.5:1 body / ≥ 3:1 large on panels, cards, scene, hero scrim, bars and footer', () {
      for (final e in ThemePresets.palettes.entries) {
        expect(e.value.failures, isEmpty, reason: e.key);
        // Normalising a passing palette changes nothing (the presets are authored, not corrected).
        expect(e.value.normalized(), e.value, reason: e.key);
      }
    });

    test('Holy Week is a dark scene; the others are light', () {
      expect(ThemePresets.palettes[ThemePresets.holyWeek]!.dark, isTrue);
      for (final k in ThemePresets.keys.where((k) => k != ThemePresets.holyWeek)) {
        expect(ThemePresets.palettes[k]!.dark, isFalse, reason: k);
      }
      final hw = ThemePresets.palettes[ThemePresets.holyWeek]!;
      // Text on the dark scene (backdrop + texture), on dark panels and on the silver bar.
      for (final r in ['ink', 'muted', 'goldText', 'script', 'primary']) {
        for (final g in [...hw.sceneGrounds, ...hw.panelGrounds]) {
          expect(contrastRatio(hw[r], g), greaterThanOrEqualTo(4.5), reason: '$r on ${colorToHex(g)}');
        }
      }
      expect(contrastRatio(hw.onPrimary, hw.primary), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(hw.onPrimaryAccent, hw.primaryDeep), greaterThanOrEqualTo(4.5));
    });

    test('hero verse (Ruqaa verse in ink, reference in gold, no panel: on the hero verse scrim) on every theme', () {
      expect(ThemePresets.palettes.keys, contains(ThemePresets.holyWeek));
      for (final e in ThemePresets.palettes.entries) {
        final p = e.value;
        // The verse scrim over the darkest and the lightest video frame.
        expect(p.verseGrounds, hasLength(2));
        for (final g in p.verseGrounds) {
          expect(contrastRatio(p.ink, g), greaterThanOrEqualTo(4.5), reason: '${e.key} verse on scrim ${colorToHex(g)}');
          expect(contrastRatio(p.goldText, g), greaterThanOrEqualTo(4.5),
              reason: '${e.key} reference on scrim ${colorToHex(g)}');
        }
        // Part of the palette's own checks, so admin colours are corrected too.
        expect(p.checks.where((c) => c.ground.startsWith('verse')), hasLength(4), reason: e.key);
      }
    });

    test('custom colours: normalising keeps the hero verse readable on its scrim', () {
      final base = ThemePresets.palettes[ThemePresets.goldenHour]!;
      final hw = ThemePresets.palettes[ThemePresets.holyWeek]!;
      for (final bad in [base.withColor('goldText', 0xFFD8B070), hw.withColor('goldText', 0xFF6A5A30)]) {
        final n = bad.normalized();
        for (final g in n.verseGrounds) {
          expect(contrastRatio(n.ink, g), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(n.goldText, g), greaterThanOrEqualTo(4.5));
        }
      }
    });

    test('hero verse colours also hold on panels (fixed-verse previews) on every theme', () {
      for (final e in ThemePresets.palettes.entries) {
        final p = e.value;
        for (final g in p.panelGrounds) {
          expect(contrastRatio(p.ink, g), greaterThanOrEqualTo(4.5), reason: '${e.key} verse on ${colorToHex(g)}');
          expect(contrastRatio(p.goldText, g), greaterThanOrEqualTo(4.5), reason: '${e.key} reference on ${colorToHex(g)}');
        }
      }
    });

    test('Golden hour stays the default (maroon #6E1C1C); `burgundy` and unknown keys read as it', () {
      expect(const FeatureSettings().theme, ThemePresets.goldenHour);
      expect(FeatureSettings.fromMap(const {'theme': 'burgundy'}).theme, ThemePresets.goldenHour);
      expect(FeatureSettings.fromMap(const {'theme': 'nope'}).theme, ThemePresets.goldenHour);
      expect(FeatureSettings.fromMap(const {'theme': 'navy'}).theme, 'navy');
      expect(ThemePresets.palettes[ThemePresets.goldenHour]!.primary, 0xFF6E1C1C);
      final f = FeatureSettings.fromMap(const {'theme': 'burgundy'});
      expect(f.occasions.paletteFor(f.theme).primary, 0xFF6E1C1C);
    });
  });

  group('admin colour edits are auto-corrected', () {
    test('random palettes (light and dark) always come out readable', () {
      final rnd = math.Random(17);
      int c() => 0xFF000000 | rnd.nextInt(0xFFFFFF);
      for (var i = 0; i < 400; i++) {
        final p = ThemePalette(
          primary: c(),
          onPrimary: c(),
          onPrimaryAccent: c(),
          background: c(),
          surface: c(),
          surfaceAlt: c(),
          ink: c(),
          muted: c(),
          goldText: c(),
          script: c(),
        );
        final n = p.normalized();
        expect(n.failures, isEmpty, reason: 'palette $i: ${n.failures.take(2)}');
      }
    });

    test('an unreadable edit is nudged, a readable one kept as typed', () {
      final base = ThemePresets.palettes[ThemePresets.goldenHour]!;
      final cfg = OccasionConfig(custom: {
        ThemePresets.goldenHour: {'ink': '#F0E8D0', 'primary': '#1E3A6E'}, // light ink on cream: unreadable
      });
      final p = cfg.paletteFor(ThemePresets.goldenHour);
      expect(p.primary, 0xFF1E3A6E); // readable: kept
      expect(p.ink, isNot(0xFFF0E8D0)); // corrected
      expect(p.readable, isTrue);
      expect(p.background, base.background);
    });

    test('custom colours parse only #RRGGBB for known presets and keys', () {
      // primary|onPrimary|onPrimaryAccent|background|surface|surfaceAlt|ink|muted|goldText|script
      final cfg = OccasionConfig.fromMap(const {}, const {
        'holyWeek': '#aabbcc||||||red|||',
        'marian': '#aabbcc|', // wrong field count
        'nope': '#000000|||||||||',
      });
      expect(cfg.custom, {
        'holyWeek': {'primary': '#AABBCC'},
      });
      expect(cfg.colorsToMap(), {'holyWeek': '#AABBCC|||||||||'});
    });
  });

  group('Coptic (Orthodox) Easter', () {
    test('known years', () {
      const known = {
        2001: '2001-04-15', 2010: '2010-04-04', 2015: '2015-04-12', 2016: '2016-05-01', 2017: '2017-04-16', //
        2018: '2018-04-08', 2019: '2019-04-28', 2020: '2020-04-19', 2021: '2021-05-02', 2022: '2022-04-24',
        2023: '2023-04-16', 2024: '2024-05-05', 2025: '2025-04-20', 2026: '2026-04-12', 2027: '2027-05-02',
        2028: '2028-04-16', 2029: '2029-04-08', 2030: '2030-04-28',
      };
      known.forEach((y, d) => expect(formatDate(orthodoxEaster(y)), d, reason: '$y'));
    });

    test('always a Sunday between 4 April and 8 May (1900–2099)', () {
      for (var y = 1900; y <= 2099; y++) {
        final e = orthodoxEaster(y);
        expect(e.weekday, DateTime.sunday, reason: '$y');
        expect(e.isBefore(DateTime.utc(y, 4, 4)) || e.isAfter(DateTime.utc(y, 5, 8)), isFalse, reason: '$y');
      }
    });

    test('Holy Week = Palm Sunday → Holy Saturday; Resurrection = Easter + resurrectionDays', () {
      final r = const OccasionConfig(resurrectionDays: 50).easterRanges(2027);
      expect((r[0].theme, r[0].start, r[0].end), (ThemePresets.holyWeek, '2027-04-25', '2027-05-01'));
      expect((r[1].theme, r[1].start, r[1].end), (ThemePresets.resurrection, '2027-05-02', '2027-06-20'));
    });
  });

  group('schedule (Cairo dates) and the manual override', () {
    DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

    test('manual (auto off) always uses the selected theme', () {
      const c = OccasionConfig(auto: false);
      expect(c.resolve('marian', d(2027, 4, 28)).theme, 'marian');
      expect(c.resolve('marian', d(2027, 4, 28)).source, ThemeSource.manual);
    });

    test('auto: admin ranges first, then the Easter dates, else the selected theme', () {
      const c = OccasionConfig(auto: true, schedule: [
        ThemeRange(theme: 'nativity', start: '2026-12-25', end: '2027-01-08'),
        ThemeRange(theme: 'marian', start: '2027-04-30', end: '2027-04-30'), // inside Holy Week: wins
      ]);
      expect(c.resolve('goldenHour', d(2027, 1, 7)).theme, 'nativity');
      expect(c.resolve('goldenHour', d(2027, 1, 9)).theme, 'goldenHour');
      expect(c.resolve('goldenHour', d(2027, 4, 24)).theme, 'goldenHour');
      expect(c.resolve('goldenHour', d(2027, 4, 25)).theme, ThemePresets.holyWeek);
      expect(c.resolve('goldenHour', d(2027, 4, 30)).theme, 'marian');
      expect(c.resolve('goldenHour', d(2027, 5, 1)).source, ThemeSource.easter);
      expect(c.resolve('goldenHour', d(2027, 5, 2)).theme, ThemePresets.resurrection);
      expect(c.resolve('goldenHour', d(2027, 5, 8)).theme, ThemePresets.resurrection); // 7 days
      expect(c.resolve('goldenHour', d(2027, 5, 9)).theme, 'goldenHour');
      expect(c.copyWith(easter: false).resolve('goldenHour', d(2027, 4, 26)).theme, 'goldenHour');
    });

    test('invalid ranges are dropped when read', () {
      final c = OccasionConfig.fromMap(const {
        'auto': true,
        'schedule': {
          'r1': 'holyWeek|2027-05-01|2027-04-25', // reversed
          'r2': 'nope|2027-04-25|2027-05-01',
          'r3': 'fasting|2027-02-30|2027-03-01', // no 30 Feb
          'r4': 'fasting|2027-03-08|2027-04-24',
          'r5': {'theme': 'fasting', 'start': '2027-03-08', 'end': '2027-04-24'}, // not a string
          'r99': 'fasting|2027-03-08|2027-04-24',
        },
      });
      expect(c.schedule, const [ThemeRange(theme: 'fasting', start: '2027-03-08', end: '2027-04-24')]);
      expect(OccasionConfig.fromMap(c.toMap()), c);
    });

    test('the switch happens at Cairo midnight, not UTC midnight (winter and summer time)', () async {
      ProviderContainer at(DateTime utc) {
        final c = ProviderContainer(overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(_seed(const {
            'theme': 'goldenHour',
            'occasions': {'auto': true, 'easter': true, 'resurrectionDays': 7},
          }))),
          nowProvider.overrideWith((ref) => Stream.value(utc)),
        ]);
        addTearDown(c.dispose);
        return c;
      }

      Future<String> keyAt(DateTime utc) async {
        return (await _active(at(utc))).key;
      }

      // 25 Apr 2027 (EET, UTC+2): Holy Week starts at 22:00 UTC on the 24th.
      expect(await keyAt(DateTime.utc(2027, 4, 24, 21, 59)), ThemePresets.goldenHour);
      expect(await keyAt(DateTime.utc(2027, 4, 24, 22, 0)), ThemePresets.holyWeek);
      // 2 May 2027 (EEST, UTC+3 since 30 Apr): the Resurrection starts at 21:00 UTC on 1 May.
      expect(await keyAt(DateTime.utc(2027, 5, 1, 20, 59)), ThemePresets.holyWeek);
      expect(await keyAt(DateTime.utc(2027, 5, 1, 21, 0)), ThemePresets.resurrection);
    });
  });

  group('hero video library removed (ADR-036)', () {
    test('a stored library does not affect the theme in force', () async {
      final c = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(_seed(const {
          'theme': 'holyWeek',
          'heroVideos': {
            'items': {
              'v1': {'name': 'A', 'url': 'https://www.youtube.com/watch?v=aaaaaaaaaaa'},
            },
            'active': 'v1',
            'byTheme': {'holyWeek': 'v1'},
          },
        }))),
        nowProvider.overrideWith((ref) => Stream.value(_nov1)),
      ]);
      addTearDown(c.dispose);
      final t = await _active(c);
      expect(t.key, ThemePresets.holyWeek);
      expect(FeatureSettings.fromMap(const {'heroVideos': {'active': 'v1'}}).toMap().keys, isNot(contains('heroVideos')));
    });
  });

  group('rendered pages: every text readable on its ground', () {
    for (final key in ThemePresets.keys) {
      testWidgets('$key: home at 390 px (incl. the hero verse)', (tester) async {
        await _pumpApp(tester, {'theme': key});
        expect(find.byKey(const Key('dailyVerseText')), findsOneWidget);
        expect(_contrastFailures(tester, '$key /'), isEmpty);
      });
    }

    for (final key in const [ThemePresets.holyWeek, ThemePresets.resurrection]) {
      testWidgets('$key: every public page', (tester) async {
        final c = await _pumpApp(tester, {'theme': key}, size: const Size(1200, 6000));
        final failures = <String>[];
        for (final r in _routes) {
          c.read(routerProvider).go(r);
          await tester.pumpAndSettle();
          failures.addAll(_contrastFailures(tester, '$key $r'));
        }
        expect(failures, isEmpty);
      });
    }

    // ADR-027 / ADR-028: custom category and page, and the contact form's
    // booking and anonymous views, on every preset.
    for (final key in ThemePresets.keys) {
      testWidgets('$key: custom section, custom page and contact form variants', (tester) async {
        final c = await _pumpApp(tester, {'theme': key}, size: const Size(1200, 6000));
        final failures = <String>[];
        for (final r in ['/section/youth-trips', '/page/donate', '/contact']) {
          c.read(routerProvider).go(r);
          await tester.pumpAndSettle();
          failures.addAll(_contrastFailures(tester, '$key $r'));
        }
        expect(find.byKey(const Key('anonSwitch')), findsNothing);
        await tester.tap(find.byKey(const Key('contactCategory')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hall booking').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtype-wedding')));
        await tester.pumpAndSettle();
        failures.addAll(_contrastFailures(tester, '$key /contact booking'));
        await tester.tap(find.byKey(const Key('contactCategory')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complaint').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('anonSwitch')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('anonHint')), findsOneWidget);
        failures.addAll(_contrastFailures(tester, '$key /contact anonymous'));
        expect(failures, isEmpty);
      });
    }

    testWidgets('Holy Week: dark scene, silver accent, art dimmed', (tester) async {
      await _pumpApp(tester, const {'theme': 'holyWeek'});
      final el = tester.element(find.byKey(const Key('warmBackdrop')));
      final pal = el.pal;
      expect(pal.key, ThemePresets.holyWeek);
      expect(pal.dark, isTrue);
      expect(Theme.of(el).colorScheme.primary, Color(ThemePresets.palettes['holyWeek']!.primary));
      final box = tester.widget<DecoratedBox>(find.byKey(const Key('warmBackdrop')));
      expect((box.decoration as BoxDecoration).color, pal.background);
      expect(find.byType(ColorFiltered), findsWidgets);
    });

    testWidgets('admin dashboard keeps the Golden hour palette under Holy Week', (tester) async {
      final c = await _pumpApp(tester, const {'theme': 'holyWeek'}, size: const Size(1200, 900));
      c.read(routerProvider).go('/admin');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final el = tester.element(find.byType(Theme).last);
      expect(el.pal.key, ThemePresets.goldenHour);
    });
  });
}
