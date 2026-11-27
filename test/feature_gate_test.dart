import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/common.dart';
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

/// settings/features never arrives (slow network): pages must wait.
class _PendingFeaturesRepository extends SeedRepository {
  _PendingFeaturesRepository(super.seed);
  final _never = StreamController<FeatureSettings>();
  @override
  Stream<FeatureSettings> features() => _never.stream;
}

Future<GoRouter> _pump(WidgetTester tester, SeedData seed,
    {Size size = const Size(1400, 2400),
    ContentRepository? repo,
    bool settle = true,
    Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo ?? SeedRepository(seed)),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    localeProvider.overrideWith(locale.languageCode == 'ar' ? _ArabicLocale.new : _EnglishLocale.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return router;
}

class _EnglishLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

class _ArabicLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('ar');
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  testWidgets('all sections on: meetings page and nav entries are shown', (tester) async {
    final router = await _pump(tester, _seedWith(const {'meetings': true}));
    expect(find.text('Church education'), findsWidgets);
    router.go('/church-education');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsNothing);
  });

  testWidgets('meetings off: hidden from home + nav, route shows "not available"', (tester) async {
    final router = await _pump(tester, _seedWith(const {'meetings': false}));
    expect(find.text('Church education'), findsNothing);
    expect(find.text('Mass times'), findsWidgets);

    router.go('/church-education');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sectionUnavailable')), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('old /clinics route redirects to home', (tester) async {
    final router = await _pump(tester, _seedWith(const {}));
    router.go('/clinics');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    router.go('/clinics/c1');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('mobile drawer lists only enabled sections', (tester) async {
    await _pump(tester, _seedWith(const {'meetings': false, 'activities': false}), size: const Size(420, 1600));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Church education')), findsNothing);
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

  testWidgets('first frame: gated pages wait for settings/features instead of flashing content', (tester) async {
    final seed = _seedWith(const {});
    await _pump(tester, seed, repo: _PendingFeaturesRepository(seed), settle: false);
    expect(find.byKey(const Key('featuresLoading')), findsOneWidget);
    expect(find.text('Next liturgy'), findsNothing);
    expect(find.byKey(const Key('sectionUnavailable')), findsNothing);
  });

  testWidgets('banner link to a switched-off section is not offered', (tester) async {
    await _pump(
        tester,
        _seedWith(const {'meetings': false}, extra: {
          'bannerEnabled': true,
          'bannerEn': 'Meetings paused',
          'bannerLink': '/church-education',
        }));
    expect(find.text('Meetings paused'), findsOneWidget);
    final banner = find.ancestor(of: find.text('Meetings paused'), matching: find.byType(Row)).first;
    expect(find.descendant(of: banner, matching: find.text('Learn more')), findsNothing);
  });

  testWidgets('phone width: header seal + short name fit without overflow', (tester) async {
    for (final width in [360.0, 1400.0]) {
      await _pump(tester, _seedWith(const {}), size: Size(width, 2400));
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('St. Maximus & Domadius Church'), findsOneWidget, reason: 'width $width');
    }
  });

  testWidgets('daily readings entry stays reachable in desktop nav, drawer, and footer when topEvent/commemoration are off',
      (tester) async {
    final seed = _seedWith(const {}, extra: {'topEvent': false, 'commemoration': false});
    final router = await _pump(tester, seed, size: const Size(1400, 2400));

    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: find.text('Daily readings')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(Footer),
      500,
      scrollable: find.descendant(of: find.byType(PageBody), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    final footer = find.byType(Footer);
    expect(find.descendant(of: footer, matching: find.text('Daily readings')), findsOneWidget);

    await tester.tap(find.descendant(of: appBar, matching: find.text('Daily readings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path, startsWith('/readings/'));

    await _pump(tester, seed, size: const Size(420, 1600));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Daily readings')), findsOneWidget);
  });

  testWidgets('desktop nav shows Notifications only when push is enabled', (tester) async {
    await _pump(tester, _seedWith(const {}, extra: {'push': false}), size: const Size(1400, 2400));
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Notifications')), findsNothing);

    final router = await _pump(tester, _seedWith(const {}, extra: {'push': true}), size: const Size(1400, 2400));
    final navBtn = find.descendant(of: find.byType(AppBar), matching: find.text('Notifications'));
    expect(navBtn, findsOneWidget);
    await tester.tap(navBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/notifications');
  });
}
