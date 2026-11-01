import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Seed data with `settings/features` replaced by [sections] (+ extras).
SeedData _seedWith(Map<String, bool> sections, {Map<String, Object?> extra = const {}}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final features = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  features['sections'] = {...(features['sections'] as Map), ...sections};
  features.addAll(extra);
  raw['settings']['features'] = features;
  return SeedData(raw);
}

Future<GoRouter> _pump(WidgetTester tester, SeedData seed, {Size size = const Size(1400, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(seed)),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    localeProvider.overrideWith(_EnglishLocale.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

class _EnglishLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  testWidgets('all sections on: clinics page and nav entries are shown', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    expect(find.text('Clinics'), findsWidgets); // app bar highlight + hero + directory
    router.go('/clinics');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsNothing);
    expect(find.text('Charity specialty clinics'), findsWidgets);
  });

  testWidgets('clinics off: hidden from home + nav, route shows "not available"', (tester) async {
    final router = await _pump(tester, _seedWith(const {'clinics': false}));
    expect(find.text('Clinics'), findsNothing);
    expect(find.text('Specialties and booking'), findsNothing); // directory card subtitle
    expect(find.text('Mass times'), findsWidgets); // others still there

    router.go('/clinics?specialty=dental');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('mobile drawer lists only enabled sections', (tester) async {
    await _pump(tester, _seedWith(const {'clinics': false, 'activities': false}), size: const Size(420, 1600));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Clinics')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Activities')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Mass times')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Contact us')), findsOneWidget);
  });

  testWidgets('schedule off removes the next-liturgy card and guards /mass-schedule', (tester) async {
    final router = await _pump(tester, _seedWith(const {'schedule': false}));
    expect(find.text('Next liturgy'), findsNothing);
    router.go('/mass-schedule');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsOneWidget);
  });

  testWidgets('about page hides switched-off parts but stays up', (tester) async {
    final router = await _pump(tester, _seedWith(const {'saints': false, 'departedPriests': false}));
    router.go('/about');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsNothing);
    expect(find.text('Patron saints'), findsNothing);
    expect(find.text('Departed fathers'), findsNothing);
    expect(find.text('Our priests'), findsOneWidget);
  });

  testWidgets('home banner and custom hero title from settings/features', (tester) async {
    await _pump(
        tester,
        _seedWith(const {}, extra: {
          'bannerEnabled': true,
          'bannerEn': 'Nativity schedule published',
          'heroTitleEn': 'Welcome to our parish',
          'homeHidden': ['milestones'],
        }));
    expect(find.text('Nativity schedule published'), findsOneWidget);
    expect(find.text('Welcome to our parish'), findsOneWidget);
    expect(find.text('Our story'), findsNothing);
  });
}
