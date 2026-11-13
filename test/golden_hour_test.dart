// "Golden hour" identity (ADR-022, branch design/coptic-identity): poster
// fonts, seal tab, poster headings, patrons band, footer signature, hero
// motion gating (reduced motion, admin switch) and art assets.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/pages/home_page.dart' show HaloText;
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/golden.dart';
import 'package:church_portal/ui/widgets/hero_video.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

String _assetName(ImageProvider provider) {
  final image = provider is ResizeImage ? provider.imageProvider : provider;
  return (image as AssetImage).assetName;
}

SeedData _seedWith(Map<String, bool> sections, {Map<String, dynamic> features = const {}}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  f['sections'] = {...(f['sections'] as Map), ...sections};
  f.addAll(features);
  raw['settings']['features'] = f;
  return SeedData(raw);
}

class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

Future<GoRouter> _pump(WidgetTester tester, SeedData seed,
    {Size size = const Size(1400, 5000), bool reduceMotion = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(seed)),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    localeProvider.overrideWith(_English.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduceMotion),
      child: MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(const Locale('en')),
        routerConfig: router,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('theme: Plex body, Lalezar headings in both languages, Ruqaa accent; fonts bundled with licences', () {
    for (final l in const [Locale('ar'), Locale('en')]) {
      final t = buildTheme(l);
      expect(t.textTheme.bodyMedium?.fontFamily, AppFonts.body);
      expect(t.textTheme.headlineSmall?.fontFamily, AppFonts.display);
    }
    expect(AppFonts.script().fontFamily, AppFonts.accent);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final f in const ['IBMPlexSansArabic-Regular.ttf', 'IBMPlexSansArabic-Bold.ttf', 'Lalezar-Regular.ttf', 'ArefRuqaa-Bold.ttf']) {
      expect(pubspec, contains('assets/fonts/$f'));
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
    }
    for (final l in const ['IBMPlexSansArabic', 'Lalezar', 'ArefRuqaa']) {
      expect(File('assets/fonts/$l-OFL.txt').readAsStringSync(), contains('SIL Open Font License'));
    }
    expect(pubspec.contains('google_fonts'), isFalse, reason: 'no runtime font fetching');
  });

  test('art assets exist, are WebP, and stay light', () {
    const art = [
      ArtAssets.heroWide, ArtAssets.heroWideSmall, ArtAssets.heroTall, ArtAssets.nile, ArtAssets.clouds, //
      ArtAssets.saintMoses, ArtAssets.saintMaximusDomadius,
    ];
    var total = 0;
    for (final a in art) {
      final f = File(a);
      expect(f.existsSync(), isTrue, reason: a);
      final head = f.readAsBytesSync().sublist(0, 12);
      expect(String.fromCharCodes(head.sublist(8, 12)), 'WEBP', reason: a);
      total += f.lengthSync();
    }
    expect(total, lessThan(400 * 1024), reason: 'decorative art budget');
    for (final v in const [ArtAssets.heroVideo, ArtAssets.heroVideoTall]) {
      final video = File(v);
      expect(video.existsSync(), isTrue, reason: v);
      expect(video.lengthSync(), lessThan(1024 * 1024), reason: 'hero loop under 1 MB');
    }
    for (final p in const [ArtAssets.heroPoster, ArtAssets.heroPosterTall]) {
      final head = File(p).readAsBytesSync().sublist(0, 12);
      expect(String.fromCharCodes(head.sublist(8, 12)), 'WEBP', reason: p);
    }
    expect(ArtAssets.paintingForSaint('moses-black'), ArtAssets.saintMoses);
    expect(ArtAssets.paintingForSaint('unknown'), isNull);
  });

  test('heroMotion: default on, parsed, saved only when off or already stored', () {
    expect(FeatureSettings.defaults.heroMotion, isTrue);
    expect(FeatureSettings.fromMap(const {'heroMotion': false}).heroMotion, isFalse);
    expect(FeatureSettings.fromMap(const {'heroMotion': 'no'}).heroMotion, isTrue);
    final on = featuresSaveWrites(const FeatureSettings(), const {'theme': 'burgundy'}).first;
    expect(on.containsKey('heroMotion'), isFalse, reason: 'rules that predate the key keep accepting saves');
    final off = featuresSaveWrites(const FeatureSettings(heroMotion: false), const {}).first;
    expect(off['heroMotion'], isFalse);
    final back = featuresSaveWrites(const FeatureSettings(), const {'heroMotion': false}).first;
    expect(back['heroMotion'], isTrue);
  });

  test('heroShowAddress: default off, parsed, saved only when on or already stored; rules allow a bool', () {
    expect(FeatureSettings.defaults.heroShowAddress, isFalse);
    expect(FeatureSettings.fromMap(const {'heroShowAddress': true}).heroShowAddress, isTrue);
    expect(FeatureSettings.fromMap(const {'heroShowAddress': 'yes'}).heroShowAddress, isFalse);
    final off = featuresSaveWrites(const FeatureSettings(), const {'theme': 'burgundy'}).first;
    expect(off.containsKey('heroShowAddress'), isFalse, reason: 'rules that predate the key keep accepting saves');
    final on = featuresSaveWrites(const FeatureSettings(heroShowAddress: true), const {}).first;
    expect(on['heroShowAddress'], isTrue);
    final back = featuresSaveWrites(const FeatureSettings(), const {'heroShowAddress': true}).first;
    expect(back['heroShowAddress'], isFalse);
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules.substring(rules.indexOf('function validFeatures(')), contains("'heroShowAddress'"));
    expect(rules, contains("d.get('heroShowAddress', false) is bool"));
  });

  // The hero verse's colours are checked on the scene colour at verseScrimAlpha
  // (verseGrounds). The radial glow fades towards wide line ends, so the glyph
  // halo must give that ground next to every stroke on its own — over the
  // darkest and the lightest frame, for every theme.
  testWidgets('hero verse halo: the ground beside every stroke keeps ink and gold >= 4.5:1', (tester) async {
    final failures = <String>[];
    for (final entry in ThemePresets.palettes.entries) {
      final p = entry.value;
      for (final frame in const [Color(0xFF000000), Color(0xFFFFFFFF)]) {
        for (final fg in [p.ink, p.goldText]) {
          final key = GlobalKey();
          await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: frame,
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: HaloText('x x',
                        ground: Color(p.background), style: TextStyle(fontSize: 13, color: Color(fg))),
                  ),
                ),
              ),
            ),
          ));
          final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final w = ro.size.width.toInt(), h = ro.size.height.toInt();
          final bytes = (await tester.runAsync(() async {
            final img = await ro.toImage();
            return img.toByteData(format: ui.ImageByteFormat.rawRgba);
          }))!;
          int px(int x, int y) {
            final i = (y * w + x) * 4;
            return 0xFF000000 | bytes.getUint8(i) << 16 | bytes.getUint8(i + 1) << 8 | bytes.getUint8(i + 2);
          }

          // Glyph = exactly the text colour; ground = the pixels 2 px off a glyph
          // pixel that are not glyph and not anti-aliased (no glyph within 1 px).
          bool glyph(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && px(x, y) == (fg | 0xFF000000);
          var worst = 99.0, grounds = 0;
          for (var y = 2; y < h - 2; y++) {
            for (var x = 2; x < w - 2; x++) {
              if (glyph(x, y)) continue;
              var near = false, touching = false;
              for (var dy = -2; dy <= 2; dy++) {
                for (var dx = -2; dx <= 2; dx++) {
                  if (!glyph(x + dx, y + dy)) continue;
                  if (dx.abs() <= 1 && dy.abs() <= 1) touching = true;
                  near = true;
                }
              }
              if (!near || touching) continue;
              grounds++;
              final r = contrastRatio(fg, px(x, y));
              if (r < worst) worst = r;
            }
          }
          if (grounds == 0) failures.add('${entry.key}: no glyph found');
          if (worst < 4.5) {
            failures.add('${entry.key} ${colorToHex(fg)} over ${colorToHex(frame.toARGB32())}: ${worst.toStringAsFixed(2)}');
          }
        }
      }
    }
    expect(failures, isEmpty);
  });

  testWidgets('desktop: Church services menu groups the enabled services only', (tester) async {
    final router = await _pump(tester, _seedWith(const {'clinics': false}));
    await tester.tap(find.byTooltip('Church services'));
    await tester.pumpAndSettle();
    final menu = find.byType(PopupMenuItem<String>);
    expect(menu, findsNWidgets(4));
    expect(find.descendant(of: menu, matching: find.text('Clinics')), findsNothing);
    await tester.tap(find.descendant(of: menu, matching: find.text('Church education')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/church-education');
  });

  testWidgets('seal tab hangs from the bar, follows the preset and links Home', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    router.go('/about');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sealTab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sealTabHome')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('phone drawer: maroon seal header with close, two labelled groups; tab hidden while open', (tester) async {
    await _pump(tester, _seedWith(const {}), size: const Size(420, 1600));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sealTab')), findsNothing);
    final drawer = find.byType(Drawer);
    final services = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('Church services')));
    final about = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('About')));
    final mass = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('Mass times')));
    expect(about.dy, lessThan(services.dy));
    expect(mass.dy, greaterThan(services.dy));
    await tester.tap(find.descendant(of: drawer, matching: find.byTooltip('Close')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(const Key('sealTab')), findsOneWidget);
  });

  testWidgets('home: hero stage, accent + title, patrons band follows the saints switch', (tester) async {
    await _pump(tester, _seedWith(const {}));
    expect(find.byKey(const Key('homeHero')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('homeHero')), matching: find.byType(HeroStage)), findsOneWidget);
    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.byKey(const ValueKey('homePatron-maximus-domadius')), findsOneWidget);
    // No uploaded icon (golden rule 9): the painted patron fills the halo.
    expect(find.byType(HaloPortrait), findsNWidgets(2));
    expect(find.byKey(const Key('patronsBand')), findsOneWidget);
  });

  testWidgets('home: saints off removes the patrons band', (tester) async {
    await _pump(tester, _seedWith(const {'saints': false}));
    expect(find.byKey(const ValueKey('homePatron-maximus-domadius')), findsNothing);
    expect(find.byKey(const Key('patronsBand')), findsNothing);
  });

  testWidgets('page header: accent word, title in the display face (primary), subtitle ribbon', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    router.go('/mass-schedule');
    await tester.pumpAndSettle();
    final header = find.byType(PageHeader);
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Come, let us pray')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.byType(TitleRibbon)), findsOneWidget);
    final title = tester.widget<Text>(find.descendant(of: header, matching: find.text('Mass times')));
    expect(title.style?.fontFamily, AppFonts.display);
    expect(title.style?.color, AppColors.burgundy);
  });

  testWidgets('saint page: halo portrait over the Nile', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    router.go('/about/saints/moses-black');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saintHalo')), findsOneWidget);
    expect(find.text('Lives of the saints'), findsOneWidget);
  });

  testWidgets('footer: warm panel, signature line with Facebook / WhatsApp, three columns on desktop', (tester) async {
    await _pump(tester, _seedWith(const {}));
    final footer = find.byType(Footer);
    expect(find.descendant(of: footer, matching: find.byKey(const Key('footerPanel'))), findsOneWidget);
    expect(find.descendant(of: footer, matching: find.byKey(const Key('footerSignature'))), findsOneWidget);
    expect(find.text('Church of Sts Maximus & Domadius and the Strong Anba Moussa the Black – El-Asafra 45'), findsOneWidget);
    expect(find.byKey(const Key('footerSig-facebook')), findsOneWidget);
    expect(find.byKey(const Key('footerSig-whatsapp')), findsOneWidget);
    final links = tester.getTopLeft(find.byKey(const Key('footerQuickLinks')));
    final denom = tester.getTopLeft(find.descendant(of: footer, matching: find.text('Coptic Orthodox Church')));
    expect((links.dy - denom.dy).abs(), lessThan(160), reason: 'side by side on desktop');
  });

  testWidgets('footer: socials off hides the signature icons, keeps the line', (tester) async {
    await _pump(tester, _seedWith(const {'socials': false}));
    expect(find.byKey(const Key('footerSignature')), findsOneWidget);
    expect(find.byKey(const Key('footerSig-facebook')), findsNothing);
  });

  test('heroAmbientLoopAllowed truth table (INV-PERF-01)', () {
    expect(heroAmbientLoopAllowed(isWeb: false, platform: TargetPlatform.android), isFalse);
    expect(heroAmbientLoopAllowed(isWeb: true, platform: TargetPlatform.android), isFalse);
    expect(heroAmbientLoopAllowed(isWeb: false, platform: TargetPlatform.iOS), isFalse);
    expect(heroAmbientLoopAllowed(isWeb: true, platform: TargetPlatform.iOS), isFalse);
    expect(heroAmbientLoopAllowed(width: 320), isFalse);
    expect(heroAmbientLoopAllowed(width: 599), isFalse);
    expect(heroAmbientLoopAllowed(isWeb: false, platform: TargetPlatform.windows), isTrue);
    expect(heroAmbientLoopAllowed(isWeb: false, platform: TargetPlatform.macOS), isTrue);
    expect(heroAmbientLoopAllowed(isWeb: false, platform: TargetPlatform.linux), isTrue);
    expect(heroAmbientLoopAllowed(isWeb: true, platform: TargetPlatform.windows, width: 1024), isTrue);
    expect(heroAmbientLoopAllowed(isWeb: true, platform: TargetPlatform.macOS, width: 1440), isTrue);
  });

  test('heroVideoPlatformAllowed is desktop web only, so phones never fetch the clip', () {
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.windows, width: 1024), isTrue);
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.macOS, width: 1440), isTrue);
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.linux, width: 600), isTrue);
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.windows, width: 599), isFalse);
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.android, width: 1400), isFalse);
    expect(heroVideoPlatformAllowed(isWeb: true, platform: TargetPlatform.iOS, width: 390), isFalse);
    expect(heroVideoPlatformAllowed(isWeb: false, platform: TargetPlatform.android, width: 1400), isFalse);
    expect(heroVideoPlatformAllowed(isWeb: false, platform: TargetPlatform.iOS, width: 800), isFalse);
    expect(heroVideoPlatformAllowed(isWeb: false, platform: TargetPlatform.linux, width: 1400), isFalse);
  });

  test('heroStillAsset: poster on phones and under a playing clip; painting when desktop video is off', () {
    expect(
      heroStillAsset(image: ArtAssets.heroTall, poster: ArtAssets.heroPosterTall, videoPlaying: false, phoneLike: true),
      ArtAssets.heroPosterTall,
    );
    expect(
      heroStillAsset(image: ArtAssets.heroWide, poster: ArtAssets.heroPoster, videoPlaying: true, phoneLike: false),
      ArtAssets.heroPoster,
    );
    expect(
      heroStillAsset(image: ArtAssets.heroWide, poster: ArtAssets.heroPoster, videoPlaying: false, phoneLike: false),
      ArtAssets.heroWide,
    );
    expect(heroStillAsset(image: ArtAssets.heroTall, poster: null, videoPlaying: false, phoneLike: true), ArtAssets.heroTall);
  });

  test('reduced motion covers disableAnimations and accessibleNavigation', () {
    expect(reducedMotionRequested(const MediaQueryData(disableAnimations: true)), isTrue);
    expect(reducedMotionRequested(const MediaQueryData(accessibleNavigation: true)), isTrue);
    expect(reducedMotionRequested(const MediaQueryData()), isFalse);
  });

  testWidgets('motion gating: tests, reduced motion and the admin switch keep the stage still', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    expect(ambientMotionOn(ctx), isFalse);
    expect(heroVideoAllowed(ctx, adminOn: true), isFalse);
    await tester.pumpWidget(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    // Under flutter test ambient loops never run (pumpAndSettle must settle).
    expect(ambientMotionOn(ctx), isFalse);
    expect(heroVideoAllowed(ctx, adminOn: false), isFalse);
  });

  testWidgets('reduced motion: reveals render at full opacity at once', (tester) async {
    await _pump(tester, _seedWith(const {}), reduceMotion: true);
    for (final o in tester.widgetList<Opacity>(
        find.descendant(of: find.byType(Reveal), matching: find.byType(Opacity)))) {
      expect(o.opacity, 1);
    }
  });

  test('bottom feather: opaque at the top, fully transparent at the bottom edge (CSS mask matches)', () {
    expect(BottomFeather.alphas.first, 1);
    expect(BottomFeather.alphas.last, 0);
    expect(BottomFeather.stops.last, 1);
    expect(BottomFeather.stops.length, BottomFeather.alphas.length);
    for (var i = 1; i < BottomFeather.alphas.length; i++) {
      expect(BottomFeather.alphas[i], lessThanOrEqualTo(BottomFeather.alphas[i - 1]), reason: 'monotonic');
      expect(BottomFeather.stops[i], greaterThan(BottomFeather.stops[i - 1]));
    }
    // Smooth start: the first step of the ramp is tiny (no visible line).
    expect(1 - BottomFeather.alphas[2], lessThan(0.05));
    expect(BottomFeather.cssMask, startsWith('linear-gradient(to bottom, rgba(0,0,0,1.0) 0.0%, '));
    expect(BottomFeather.cssMask, endsWith('rgba(0,0,0,0.0) 100.0%)'));
  });

  testWidgets('hero seams: every stage layer is full-bleed (not capped at 1200), feathered, scrims bleed', (tester) async {
    await _pump(tester, _seedWith(const {}), size: const Size(1600, 5000));
    final hero = find.byKey(const Key('homeHero'));
    final heroRect = tester.getRect(hero);
    expect(heroRect.width, 1600, reason: 'full width, outside the content cap');
    final stage = find.descendant(of: hero, matching: find.byType(HeroStage));
    expect(tester.getRect(stage), heroRect);
    // Still + rays dissolve into the page (no line where the hero ends).
    final feathers = find.descendant(of: stage, matching: find.byKey(const Key('heroFeather')));
    expect(feathers, findsAtLeastNWidgets(2));
    for (final e in feathers.evaluate()) {
      expect(tester.getRect(find.byWidget(e.widget)), heroRect);
    }
    expect(tester.getRect(find.descendant(of: stage, matching: find.byKey(const Key('heroStill')))), heroRect);
    // The title glow is a radial bleed bigger than the text, not a box.
    final scrim = find.ancestor(
        of: find.descendant(of: hero, matching: find.byKey(const Key('heroTitle'))), matching: find.byType(TextScrim));
    final glow = tester.getRect(find.descendant(of: scrim, matching: find.byKey(const Key('textScrimGlow'))));
    final text = tester.getRect(find.descendant(of: scrim, matching: find.byKey(const Key('heroTitle'))));
    expect(glow.left, lessThan(text.left - 40));
    expect(glow.top, lessThan(text.top - 30));
    expect(glow.bottom, greaterThan(text.bottom + 30));
    // The verse of the day sits on the same kind of soft glow (no panel).
    final verse = find.descendant(of: hero, matching: find.byKey(const Key('heroVerse')));
    if (verse.evaluate().isNotEmpty) {
      final vGlow = tester.getRect(find.descendant(of: verse, matching: find.byKey(const Key('textScrimGlow'))));
      final vText = tester.getRect(find.descendant(of: verse, matching: find.byKey(const Key('dailyVerseText'))));
      expect(vGlow.left, lessThan(vText.left - 40));
      expect(vGlow.top, lessThan(vText.top - 20));
    }
  });

  testWidgets('phone home hero is a static poster: no video, haze, or blurred rays', (tester) async {
    await _pump(tester, _seedWith(const {}), size: const Size(390, 3000));
    final stage = tester.widget<HeroStage>(
        find.descendant(of: find.byKey(const Key('homeHero')), matching: find.byType(HeroStage)));
    expect(stage.video, ArtAssets.heroVideoTall, reason: 'the clip stays configured for desktop widths');
    expect(stage.poster, ArtAssets.heroPosterTall);
    expect(stage.image, ArtAssets.heroTall);
    expect(stage.motion, isTrue, reason: 'heroMotion defaults on');
    final still = tester.widget<Image>(find.descendant(of: find.byType(HeroStage), matching: find.byKey(const Key('heroStill'))));
    expect(_assetName(still.image), ArtAssets.heroPosterTall);
    expect(find.byType(HeroVideo), findsNothing);
    expect(find.byKey(const Key('heroHaze')), findsNothing);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightRaysPainter), findsNothing);
  });

  testWidgets('desktop home hero keeps the wide clip and the light rays', (tester) async {
    await _pump(tester, _seedWith(const {}), size: const Size(1400, 3000));
    final stage = tester.widget<HeroStage>(
        find.descendant(of: find.byKey(const Key('homeHero')), matching: find.byType(HeroStage)));
    expect(stage.video, ArtAssets.heroVideo);
    expect(stage.poster, ArtAssets.heroPoster);
    final still = tester.widget<Image>(find.descendant(of: find.byType(HeroStage), matching: find.byKey(const Key('heroStill'))));
    // flutter test freezes motion, so the painting shows instead of the poster-under-video.
    expect(_assetName(still.image), ArtAssets.heroWide);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightRaysPainter), findsOneWidget);
  });

  testWidgets('hero plays only the bundled clip, even with a stored YouTube library (ADR-036)', (tester) async {
    await _pump(
        tester,
        _seedWith(const {}, features: const {
          'heroVideos': {
            'items': {
              'v1': {'name': 'A', 'url': 'https://www.youtube.com/watch?v=aaaaaaaaaaa'},
            },
            'active': 'v1',
          },
        }),
        size: const Size(1280, 3000));
    final stage = tester.widget<HeroStage>(
        find.descendant(of: find.byKey(const Key('homeHero')), matching: find.byType(HeroStage)));
    expect(stage.video, ArtAssets.heroVideo);
    expect(stage.poster, ArtAssets.heroPoster);
    expect(stage.image, ArtAssets.heroWide);
  });

  testWidgets('seal tab: new seal on a gold ring with a soft shadow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SealTab()))));
    final img = tester.widget<Image>(find.descendant(of: find.byType(SealTab), matching: find.byType(Image)));
    expect((img.image as AssetImage).assetName, 'assets/branding/seal.png');
    final ring = tester
        .widgetList<Container>(find.descendant(of: find.byType(SealTab), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle);
    expect(ring.gradient, isA<SweepGradient>());
    expect(ring.boxShadow, isNotEmpty);
  });
}
