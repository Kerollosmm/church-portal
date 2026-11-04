// ADR-043: occasion sub-themes. Every surface reads its colours from the
// palette roles and scene accents (no hard-coded colour in lib/ui), no
// built-in palette or accent is violet, Holy Week reads black / charcoal with
// ashen silver and deep crimson, the fasts are ash / stone with oxblood, the
// legacy `purple` key reads as the sober oxblood accent, and the theme
// follows the active church season (precedence: admin range > season >
// Coptic Easter > selected theme).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/domain/season_preset.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Every colour of a preset: its ten roles and its scene accents.
List<int> _allColours(String key) {
  final p = ThemePresets.palettes[key]!;
  return [for (final r in ThemePalette.keys) p[r], ...SceneAccents.of(key, p).all];
}

/// Every role of the Material scheme the site builds for [key].
List<Color> _schemeColours(String key) {
  final s = buildTheme(const Locale('ar'), palette: ThemePresets.palettes[key]!, key: key).colorScheme;
  return [
    s.primary, s.onPrimary, s.primaryContainer, s.onPrimaryContainer, s.secondary, s.onSecondary, //
    s.secondaryContainer, s.onSecondaryContainer, s.tertiary, s.onTertiary, s.tertiaryContainer,
    s.onTertiaryContainer, s.error, s.errorContainer, s.surface, s.onSurface, s.onSurfaceVariant,
    s.surfaceContainerLowest, s.surfaceContainerLow, s.surfaceContainer, s.surfaceContainerHigh,
    s.surfaceContainerHighest, s.surfaceDim, s.surfaceBright, s.outline, s.outlineVariant, s.inversePrimary,
    s.inverseSurface, s.onInverseSurface,
  ];
}

Season _season(String key, DateTime start, DateTime end, {bool active = true, bool replaces = true}) => Season(
    id: '$key-${start.year}',
    key: key,
    nameAr: key,
    nameEn: key,
    startsAt: start,
    endsAt: end,
    active: active,
    replacesRegular: replaces);

class _SeasonRepo extends SeedRepository {
  _SeasonRepo(super.seed, this._seasons);
  final Stream<List<Season>> _seasons;
  @override
  Stream<List<Season>> seasons() => _seasons;
}

SeedData _seed([Map<String, dynamic> features = const {}]) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  raw['settings']['features'] = {...(raw['settings']['features'] as Map), ...features};
  return SeedData(raw);
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('no violet anywhere (owner: "not violet AI slop")', () {
    test('the hue rule: hue 260–320° with saturation > 0.25 is violet; greys never are', () {
      expect(isVioletPurple(0xFF4A235A), isTrue, reason: 'the old fasting violet');
      expect(isVioletPurple(0xFF7B1FA2), isTrue);
      expect(isVioletPurple(0xFF6E1C1C), isFalse, reason: 'poster maroon');
      expect(isVioletPurple(0xFF8A8590), isFalse, reason: 'a grey with a violet cast but no saturation');
      expect(isVioletPurple(0xFF1C3566), isFalse, reason: 'nativity night blue');
    });

    for (final key in ThemePresets.keys) {
      test('$key: no palette role or scene accent is violet', () {
        final bad = [for (final c in _allColours(key)) if (isVioletPurple(c)) colorToHex(c)];
        expect(bad, isEmpty);
      });
      test('$key: no Material scheme role is violet (no seeded drift, no M3 baseline #6750A4)', () {
        final cs = _schemeColours(key);
        expect([for (final c in cs) if (isVioletPurple(c.toARGB32() | 0xFF000000)) c], isEmpty);
        expect(cs.map((c) => c.toARGB32()), isNot(contains(0xFF6750A4)));
      });
    }

    test('the fasts are ash / stone with a deep oxblood, not violet', () {
      final f = ThemePresets.palettes[ThemePresets.fasting]!;
      expect(f.primary, 0xFF4F2420);
      expect(f.background, 0xFFF0EEEA);
      expect(f.dark, isFalse);
      expect(hueSat(f.primary).$1, lessThan(20), reason: 'a red-brown hue');
    });

    test('legacy `purple` stays a valid stored key but reads as the sober oxblood accent and is not offered', () {
      expect(ThemePresets.normalize('purple'), ThemePresets.legacyPurple);
      expect(ThemePresets.palettes['purple']!.primary, 0xFF4F2420);
      expect(ThemePresets.pickable, isNot(contains('purple')));
      expect(ThemePresets.keys, contains('purple'));
      expect(FeatureSettings.fromMap(const {'theme': 'purple'}).theme, 'purple');
    });
  });

  group('scene accents (sub-themes)', () {
    for (final key in ThemePresets.keys) {
      test('$key: every text-bearing accent pair passes 4.5:1', () {
        final p = ThemePresets.palettes[key]!;
        expect([for (final c in SceneAccents.of(key, p).checks(p)) if (!c.passes) '$c'], isEmpty);
        expect(p.failures, isEmpty);
      });
    }

    test('admin colour edits: derived accents stay readable on random palettes', () {
      final rnd = math.Random(43);
      int c() => 0xFF000000 | rnd.nextInt(0xFFFFFF);
      for (var i = 0; i < 150; i++) {
        final p = ThemePalette.withOverrides(ThemePresets.palettes[i.isEven ? 'goldenHour' : 'holyWeek']!, {
          for (final k in ThemePalette.keys)
            if (rnd.nextBool()) k: colorToHex(c()),
        }).normalized();
        final a = SceneAccents.derive(p);
        expect([for (final x in a.checks(p)) if (!x.passes) '$x'], isEmpty, reason: 'palette $i');
      }
    });

    test('Golden hour keeps its approved look exactly (the pre-ADR-043 colours)', () {
      final a = SceneAccents.of(ThemePresets.goldenHour, ThemePresets.goldenHourPalette);
      expect(a.ornament, 0xFFC9963F);
      expect(a.bar, 0xFF6E1C1C);
      expect(a.onBar, 0xFFFFFFFF);
      expect(a.onBarAccent, 0xFFE7C27A);
      expect(a.barEdge, isNull);
      expect(a.ribbon, 0xFF7A4530);
      expect(a.ribbonText, 0xFFFFF3DC);
      expect(a.notice, 0xFFFFF3CD);
      expect(a.alertGround, 0xFFFFF4E0);
      expect(a.live, 0xFFB3261E);
    });

    test('Holy Week: black cloth, charcoal bands with ash-white text, crimson edge, ash ornaments, no gold', () {
      final p = ThemePresets.palettes[ThemePresets.holyWeek]!;
      final a = SceneAccents.of(ThemePresets.holyWeek, p);
      expect(p.dark, isTrue);
      expect(relativeLuminance(p.background), lessThan(0.01), reason: 'black');
      expect(relativeLuminance(a.bar), lessThan(0.03), reason: 'the bands are charcoal, not the silver primary');
      expect(relativeLuminance(a.barDeep), lessThan(0.02));
      expect(a.barEdge, SceneAccents.crimson);
      expect(a.live, SceneAccents.crimson);
      expect(hueSat(SceneAccents.crimson).$1, lessThan(10), reason: 'crimson');
      expect(hueSat(p.primary).$2, lessThan(0.15), reason: 'ashen silver, not gold');
      // The golden art is dimmed: halos, ornaments and the cross are grey.
      for (final c in [a.ornament, a.haloInner, a.haloMid, a.haloOuter, a.cross, a.sepiaEdge]) {
        expect(hueSat(c).$2, lessThan(0.12), reason: colorToHex(c));
      }
    });
  });

  group('the theme follows the active season (precedence)', () {
    final day = DateTime.utc(2027, 4, 27);
    const off = OccasionConfig();

    test('defaults: Holy Week → holyWeek, Pascha → resurrection, fasts → fasting, revivals → none', () {
      expect(off.followSeason, isTrue);
      expect(off.themeForSeason('holy_week'), ThemePresets.holyWeek);
      expect(off.themeForSeason('pascha'), ThemePresets.resurrection);
      expect(off.themeForSeason('nativity'), ThemePresets.nativity);
      expect(off.themeForSeason('epiphany'), ThemePresets.epiphany);
      expect(off.themeForSeason('marian'), ThemePresets.marian);
      expect(off.themeForSeason('fast'), ThemePresets.fasting);
      expect(off.themeForSeason('revival_moses'), isNull);
      expect(off.themeForSeason('summer'), isNull);
      expect(off.themeForSeason('unknown'), isNull);
    });

    test('manual mode (auto off): an active season still brings its theme; none = the selected theme', () {
      final r = off.resolve('goldenHour', day, activeSeasonKeys: ['holy_week']);
      expect((r.theme, r.source, r.seasonKey), (ThemePresets.holyWeek, ThemeSource.season, 'holy_week'));
      expect(off.resolve('navy', day).theme, 'navy');
      expect(off.resolve('navy', day, activeSeasonKeys: ['revival_moses']).source, ThemeSource.manual);
    });

    test('followSeason off: the season never changes the theme', () {
      final r = off.copyWith(followSeason: false).resolve('goldenHour', day, activeSeasonKeys: ['holy_week']);
      expect((r.theme, r.source), (ThemePresets.goldenHour, ThemeSource.manual));
    });

    test('an admin range wins over the season; the season wins over the Easter dates', () {
      final auto = off.copyWith(auto: true, schedule: [
        const ThemeRange(theme: 'nativity', start: '2027-04-26', end: '2027-04-26'),
      ]);
      expect(auto.resolve('goldenHour', DateTime.utc(2027, 4, 26), activeSeasonKeys: ['holy_week']).source,
          ThemeSource.schedule);
      // Coptic Easter 2027 is 2 May: 27 April is Holy Week by the computus too,
      // but an active Pascha season document is explicit and wins.
      final r = auto.resolve('goldenHour', day, activeSeasonKeys: ['pascha']);
      expect((r.theme, r.source), (ThemePresets.resurrection, ThemeSource.season));
      expect(auto.resolve('goldenHour', day).source, ThemeSource.easter);
    });

    test('two seasons at once: the first in priority order (Holy Week over a fast); admin map overrides', () {
      expect(off.resolve('goldenHour', day, activeSeasonKeys: ['fast', 'holy_week']).theme, ThemePresets.holyWeek);
      final mapped = off.copyWith(seasonThemes: {'holy_week': SeasonThemes.none, 'revival_moses': 'brown'});
      expect(mapped.resolve('goldenHour', day, activeSeasonKeys: ['fast', 'holy_week']).theme, ThemePresets.fasting);
      expect(mapped.resolve('goldenHour', day, activeSeasonKeys: ['revival_moses']).theme, 'brown');
    });

    test('settings round-trip: only differences are stored; bad values are dropped', () {
      final c = OccasionConfig.fromMap({
        'followSeason': false,
        'seasonThemes': {'holy_week': 'holyWeek', 'pascha': 'none', 'fast': 'violetNeon', 'bogus': 'navy', 'summer': 'green'},
      });
      expect(c.followSeason, isFalse);
      expect(c.seasonThemes, {'pascha': 'none', 'summer': 'green'});
      expect(c.toMap()['seasonThemes'], {'pascha': 'none', 'summer': 'green'});
      expect(c.toMap()['followSeason'], isFalse);
      expect(OccasionConfig.fromMap(c.toMap()), c);
      expect(OccasionConfig.fromMap(null).followSeason, isTrue, reason: 'missing = on');
      expect(SeasonThemes.seasonKeys.toSet(), SeasonThemes.defaults.keys.toSet());
    });
  });

  group('season preset: optional theme item (reversible)', () {
    final start = DateTime.utc(2027, 4, 24, 22), end = DateTime.utc(2027, 5, 1, 15);
    final hw = _season('holy_week', start, end, active: false);
    PresetWrites apply({String? seasonTheme = 'holyWeek', String stored = 'burgundy'}) => planApply(
          r: const PresetRequest(options: {PresetOption.theme, PresetOption.heroMotionOff}),
          season: hw,
          sections: const {},
          sectionKeys: Sections.all,
          heroMotion: true,
          weddingBookingOff: false,
          liveUrl: '',
          liveEndsAt: null,
          now: start.subtract(const Duration(days: 2)),
          storedTheme: stored,
          seasonTheme: seasonTheme,
        );

    test('apply sets the theme and keeps the stored one; restore puts it back; startsAt is kept', () {
      final w = apply();
      expect(w.features['theme'], 'holyWeek');
      final p = SeasonPreset.fromMap(w.features['seasonPreset'])!;
      expect(p.has(PresetOption.theme), isTrue);
      expect(p.prevString(PresetPrev.theme), 'burgundy');
      expect(p.startsAt, start);
      expect(planRestore(p, sections: const {}, sectionKeys: Sections.all).features['theme'], 'burgundy');
    });

    test('a season key with no theme: the item is dropped, nothing written', () {
      final w = apply(seasonTheme: null);
      expect(w.features.containsKey('theme'), isFalse);
      expect(SeasonPreset.fromMap(w.features['seasonPreset'])!.has(PresetOption.theme), isFalse);
    });

    test('after the season end visitors read the previous theme (no write)', () {
      final f = FeatureSettings.fromMap({'theme': 'holyWeek', 'seasonPreset': apply().features['seasonPreset']});
      expect(f.theme, 'holyWeek');
      expect(f.effectiveAt(end).theme, ThemePresets.goldenHour, reason: 'burgundy reads as Golden hour');
    });

    test('no stored theme before the preset: after the end visitors get the default, like restore (Sentry #37)', () {
      final w = apply(stored: '');
      final f = FeatureSettings.fromMap({'theme': 'holyWeek', 'seasonPreset': w.features['seasonPreset']});
      expect(f.effectiveAt(end.subtract(const Duration(minutes: 1))).theme, 'holyWeek');
      expect(f.effectiveAt(end).theme, ThemePresets.goldenHour);
      final p = SeasonPreset.fromMap(w.features['seasonPreset'])!;
      expect(planRestore(p, sections: const {}, sectionKeys: Sections.all).features['theme'], ThemePresets.goldenHour);
    });

    test('seasonRunningAt: from the season start (or the apply for older presets) to its end', () {
      final p = SeasonPreset.fromMap(apply().features['seasonPreset'])!;
      expect(p.seasonRunningAt(start.subtract(const Duration(minutes: 1))), isFalse);
      expect(p.seasonRunningAt(start.add(const Duration(days: 1))), isTrue);
      expect(p.seasonRunningAt(end), isFalse);
      final old = SeasonPreset(seasonId: 'x', seasonKey: 'holy_week', appliedAt: start, endsAt: end);
      expect(old.seasonRunningAt(start.add(const Duration(hours: 1))), isTrue);
    });
  });

  group('activeThemeProvider follows the season (the seasons stream; the applied preset until it loads)', () {
    final start = DateTime.utc(2027, 4, 24, 22), end = DateTime.utc(2027, 5, 1, 15);
    final during = DateTime.utc(2027, 4, 27, 9);

    ProviderContainer container(Stream<List<Season>> seasons, {Map<String, dynamic> features = const {}}) {
      final c = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(_SeasonRepo(_seed(features), seasons)),
        nowProvider.overrideWith((ref) => Stream.value(during)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    // Listen first: Riverpod pauses providers nobody listens to.
    Future<ActiveTheme> read(ProviderContainer c) async {
      final sub = c.listen(activeThemeProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return sub.read();
    }

    test('an active Holy Week season document → the Holy Week theme', () async {
      final c = container(Stream.value([_season('holy_week', start, end)]));
      final t = await read(c);
      expect((t.key, t.source), (ThemePresets.holyWeek, ThemeSource.season));
    });

    test('an inactive season, or one outside its window → the selected theme', () async {
      final c = container(Stream.value([
        _season('holy_week', start, end, active: false),
        _season('nativity', DateTime.utc(2027, 1, 5, 22), DateTime.utc(2027, 1, 7, 21)),
      ]));
      expect((await read(c)).key, ThemePresets.goldenHour);
    });

    test('before the seasons list loads, the applied preset paints the season theme from the first frame', () async {
      final preset = SeasonPreset(
              seasonId: 'holy_week-2027', seasonKey: 'holy_week', appliedAt: start, startsAt: start, endsAt: end)
          .toMap();
      final c = container(const Stream<List<Season>>.empty(), features: {'seasonPreset': preset});
      expect((await read(c)).key, ThemePresets.holyWeek);
    });

    test('followSeason off: the season is ignored', () async {
      final c = container(Stream.value([_season('holy_week', start, end)]), features: {
        'occasions': {'followSeason': false},
      });
      expect((await read(c)).key, ThemePresets.goldenHour);
    });
  });

  group('widgets take their colours from the theme', () {
    test('selected chips have a distinct edge on every preset (Holy Week: crimson) — Sentry review on PR #37', () {
      for (final key in ThemePresets.keys) {
        final side = buildTheme(const Locale('ar'), palette: ThemePresets.palettes[key]!, key: key).chipTheme.side!;
        final on = WidgetStateProperty.resolveAs<BorderSide?>(side, {WidgetState.selected})!;
        final off = WidgetStateProperty.resolveAs<BorderSide?>(side, <WidgetState>{})!;
        expect(on.color, isNot(off.color), reason: key);
        expect(on.width, greaterThan(off.width), reason: key);
      }
      final hw = buildTheme(const Locale('ar'), palette: ThemePresets.palettes['holyWeek']!, key: 'holyWeek');
      final edge = WidgetStateProperty.resolveAs<BorderSide?>(hw.chipTheme.side!, {WidgetState.selected})!.color;
      expect(HSVColor.fromColor(edge).hue, anyOf(lessThan(20), greaterThan(340)), reason: 'crimson edge');
    });

    test('no hard-coded colour in lib/ui (Color(0x…), Colors.*, AppColors.*) outside marked exemptions', () {
      final bad = <String>[];
      final re = RegExp(r'Color\(0x|Colors\.(?!transparent)[a-zA-Z]|AppColors\.');
      for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//') || !re.hasMatch(l)) continue;
          if (l.contains('palette-exempt')) continue;
          bad.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }
      expect(bad, isEmpty);
    });

    testWidgets('next-service band: charcoal with a crimson edge on Holy Week, maroon on Golden hour', (tester) async {
      Future<BoxDecoration> band(String key) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(_seed())),
            nowProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 11, 4, 8))),
          ],
          child: MaterialApp(
            theme: buildTheme(const Locale('ar'), palette: ThemePresets.palettes[key]!, key: key),
            home: const Scaffold(body: SingleChildScrollView(child: NextMassCard())),
          ),
        ));
        await tester.pumpAndSettle();
        return tester.widget<Container>(find.byKey(const Key('nextMassBand'))).decoration! as BoxDecoration;
      }

      final hw = await band(ThemePresets.holyWeek);
      final hwA = SceneAccents.of(ThemePresets.holyWeek, ThemePresets.palettes[ThemePresets.holyWeek]!);
      expect((hw.gradient! as LinearGradient).colors, [Color(hwA.bar), Color(hwA.barDeep)]);
      expect((hw.border! as Border).bottom.color, const Color(SceneAccents.crimson));
      final gh = await band(ThemePresets.goldenHour);
      expect((gh.gradient! as LinearGradient).colors.first, const Color(0xFF6E1C1C));
      expect(gh.border, isNull);
    });

    testWidgets('a host without the site theme still gets the Golden hour palette, never Material violet',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(_seed())),
          nowProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 11, 4, 8))),
        ],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: NextMassCard()))),
      ));
      await tester.pumpAndSettle();
      final d = tester.widget<Container>(find.byKey(const Key('nextMassBand'))).decoration! as BoxDecoration;
      final colors = (d.gradient! as LinearGradient).colors;
      expect(colors.first, const Color(0xFF6E1C1C));
      for (final c in colors) {
        expect(isVioletPurple(c.toARGB32()), isFalse);
      }
    });
  });
}
