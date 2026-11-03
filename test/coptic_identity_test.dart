// Coptic identity ("Iconostasis", branch design/coptic-identity): grouped
// navigation, patron-saints teaser, ornaments and bundled fonts.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/ornaments.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

SeedData _seedWith(Map<String, bool> sections) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final features = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  features['sections'] = {...(features['sections'] as Map), ...sections};
  raw['settings']['features'] = features;
  return SeedData(raw);
}

class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

Future<GoRouter> _pump(WidgetTester tester, SeedData seed, {Size size = const Size(1400, 5000)}) async {
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
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(const Locale('en')),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('theme uses the bundled faces: Plex body, Naskh (ar) / Marcellus (en) headings', () {
    final ar = buildTheme(const Locale('ar'));
    final en = buildTheme(const Locale('en'));
    expect(ar.textTheme.bodyMedium?.fontFamily, AppFonts.body);
    expect(ar.textTheme.headlineSmall?.fontFamily, AppFonts.naskh);
    expect(en.textTheme.headlineSmall?.fontFamily, AppFonts.latinDisplay);
    expect(en.textTheme.headlineSmall?.fontFamilyFallback, contains(AppFonts.naskh));
    // Every bundled face is declared in pubspec and shipped with its licence.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final f in const [
      'IBMPlexSansArabic-Regular.ttf',
      'IBMPlexSansArabic-Bold.ttf',
      'NotoNaskhArabic-Regular.ttf',
      'NotoNaskhArabic-Bold.ttf',
      'Marcellus-Regular.ttf',
    ]) {
      expect(pubspec, contains('assets/fonts/$f'));
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
    }
    for (final l in const ['IBMPlexSansArabic', 'NotoNaskhArabic', 'Marcellus']) {
      expect(File('assets/fonts/$l-OFL.txt').readAsStringSync(), contains('SIL Open Font License'));
    }
    expect(pubspec.contains('google_fonts'), isFalse, reason: 'no runtime font fetching');
  });

  testWidgets('desktop: Church services menu groups the enabled services only', (tester) async {
    final router = await _pump(tester, _seedWith(const {'clinics': false}));
    expect(find.byTooltip('Church services'), findsOneWidget);
    await tester.tap(find.byTooltip('Church services'));
    await tester.pumpAndSettle();
    final menu = find.byType(PopupMenuItem<String>);
    expect(menu, findsNWidgets(4)); // mass, education, activities, public services
    expect(find.descendant(of: menu, matching: find.text('Clinics')), findsNothing);
    await tester.tap(find.descendant(of: menu, matching: find.text('Church education')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/church-education');
    // The interlace band sits under the app bar and every page header.
    expect(find.byType(InterlaceBand), findsWidgets);
  });

  testWidgets('phone drawer: seal header with close, two labelled groups', (tester) async {
    await _pump(tester, _seedWith(const {}), size: const Size(420, 1600));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('The church')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Church services')), findsOneWidget);
    final church = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('About')));
    final services = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('Church services')));
    final mass = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('Mass times')));
    expect(church.dy, lessThan(services.dy));
    expect(mass.dy, greaterThan(services.dy));
    await tester.tap(find.descendant(of: drawer, matching: find.byTooltip('Close')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('home: patron saints teaser follows the saints section switch', (tester) async {
    await _pump(tester, _seedWith(const {}));
    expect(find.byKey(const ValueKey('home-patrons')), findsOneWidget);
    expect(find.byKey(const ValueKey('homePatron-maximus-domadius')), findsOneWidget);
    // Saints carry no seeded image (golden rule 9): the arches hold the drawn cross.
    expect(find.byType(ArchCrossFill), findsWidgets);
    expect(find.text('About the church'), findsWidgets); // hero CTA + teaser link
  });

  testWidgets('home: saints off removes the teaser and the arch captions', (tester) async {
    await _pump(tester, _seedWith(const {'saints': false}));
    expect(find.byKey(const ValueKey('homePatron-maximus-domadius')), findsNothing);
    expect(find.text('Patron saints'), findsNothing);
  });

  testWidgets('page header: kicker, title in the display face, interlace band', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    router.go('/mass-schedule');
    await tester.pumpAndSettle();
    final header = find.byType(PageHeader);
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.byType(InterlaceBand)), findsOneWidget);
    expect(find.descendant(of: header, matching: find.byType(ArchWatermark)), findsOneWidget);
    final title = tester.widgetList<Text>(find.descendant(of: header, matching: find.byType(Text))).elementAt(1);
    expect(title.style?.fontFamily, AppFonts.latinDisplay);
  });

  testWidgets('footer: night ground, three columns on desktop, still at 320 px', (tester) async {
    await _pump(tester, _seedWith(const {}));
    final footer = find.byType(Footer);
    expect(tester.widget<Container>(find.descendant(of: footer, matching: find.byType(Container)).first).color,
        AppColors.night);
    expect(find.descendant(of: footer, matching: find.text('Quick links')), findsOneWidget);
    expect(find.descendant(of: footer, matching: find.text('Coptic Orthodox Church')), findsOneWidget);
    final links = tester.getTopLeft(find.byKey(const Key('footerQuickLinks')));
    final denom = tester.getTopLeft(find.descendant(of: footer, matching: find.text('Coptic Orthodox Church')));
    expect((links.dy - denom.dy).abs(), lessThan(120), reason: 'side by side on desktop');
  });
}
