// "Golden hour" identity (ADR-022, branch design/coptic-identity): poster
// fonts, seal tab, poster headings, patrons band, footer signature, hero
// motion gating (reduced motion, admin switch) and art assets.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/golden.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
    final video = File(ArtAssets.heroVideo);
    expect(video.existsSync(), isTrue);
    expect(video.lengthSync(), lessThan(1024 * 1024), reason: 'hero loop under 1 MB');
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
}
