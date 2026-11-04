import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/clinics_page.dart';
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
    {Size size = const Size(1400, 2400), ContentRepository? repo, bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo ?? SeedRepository(seed)),
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

void main() {
  setUpAll(CairoTime.ensureInitialized);

  testWidgets('all sections on: clinics page and nav entries are shown', (tester) async {
    // The seed ships clinics switched off until the church confirms them.
    final router = await _pump(tester, _seedWith(const {'clinics': true}));
    expect(find.text('Clinics'), findsWidgets); // directory card + footer quick links (never the app bar)
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

  group('app bar never shows a Clinics shortcut (owner request, 4 Nov 2026)', () {
    final appBar = find.byType(AppBar);
    void expectNoClinicsAction(String reason) {
      expect(find.descendant(of: appBar, matching: find.byTooltip('Clinics')), findsNothing, reason: reason);
      expect(find.descendant(of: appBar, matching: find.byIcon(Icons.local_hospital_rounded)), findsNothing,
          reason: reason);
    }

    for (final on in [true, false]) {
      for (final size in const [Size(320, 800), Size(400, 800), Size(420, 1600), Size(1400, 2400)]) {
        testWidgets('clinics ${on ? 'on' : 'off'}, ${size.width.toInt()} px', (tester) async {
          final router = await _pump(tester, _seedWith({'clinics': on}), size: size);
          expectNoClinicsAction('home');
          router.go('/about');
          await tester.pumpAndSettle();
          expectNoClinicsAction('/about');
          router.go('/clinics');
          await tester.pumpAndSettle();
          expectNoClinicsAction('/clinics');
          // Phones keep the menu button (clinics are listed in the drawer).
          if (size.width < 1024) expect(find.descendant(of: appBar, matching: find.byTooltip('Menu')), findsOneWidget);
        });
      }
    }

    testWidgets('clinics on: still reachable from the drawer and from Home', (tester) async {
      final router = await _pump(tester, _seedWith(const {'clinics': true}), size: const Size(400, 1600));
      expectNoClinicsAction('home');
      expect(find.text('Specialties and booking'), findsOneWidget); // Home directory card
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      final entry = find.descendant(of: find.byType(Drawer), matching: find.text('Clinics'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/clinics');
      expect(find.text('Charity specialty clinics'), findsWidgets);
    });

    testWidgets('Arabic phone bar: no clinics icon either', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(_seedWith(const {'clinics': true}))),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: container.read(routerProvider),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.descendant(of: appBar, matching: find.byTooltip('العيادات')), findsNothing);
      expect(find.descendant(of: appBar, matching: find.byIcon(Icons.local_hospital_rounded)), findsNothing);
      expect(find.descendant(of: appBar, matching: find.byTooltip('مواعيد القداسات')), findsOneWidget);
    });
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
        _seedWith(const {'clinics': false}, extra: {
          'bannerEnabled': true,
          'bannerEn': 'New clinic hours',
          'bannerLink': '/clinics',
        }));
    expect(find.text('New clinic hours'), findsOneWidget);
    final banner = find.ancestor(of: find.text('New clinic hours'), matching: find.byType(Row)).first;
    expect(find.descendant(of: banner, matching: find.text('Learn more')), findsNothing);
  });

  testWidgets('phone width: header seal + short name fit without overflow', (tester) async {
    for (final width in [360.0, 1400.0]) {
      await _pump(tester, _seedWith(const {}), size: Size(width, 2400));
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('St. Maximus & Domadius Church'), findsOneWidget, reason: 'width $width');
    }
  });

  testWidgets('clinics without booking numbers offer "Call church office"', (tester) async {
    final router = await _pump(tester, _seedWith(const {'clinics': true}));
    router.go('/clinics');
    await tester.pumpAndSettle();
    // Every seeded clinic is a placeholder with no booking phone / WhatsApp.
    expect(find.byKey(const Key('callChurchOffice')), findsWidgets);
    expect(find.text('Call church office'), findsWidgets);
    // English UI shows a translated placeholder doctor title.
    expect(find.text('Internal medicine doctor — to be announced'), findsOneWidget);
    expect(find.textContaining('يُعلن لاحقًا'), findsNothing);
  });

  testWidgets('no office fallback while contact info is switched off', (tester) async {
    final router = await _pump(tester, _seedWith(const {'clinics': true, 'contactInfo': false}));
    router.go('/clinics');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('callChurchOffice')), findsNothing);
  });

  testWidgets('ClinicCard: booking numbers win over the office fallback', (tester) async {
    Future<void> pumpCard(Clinic c) => tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: ClinicCard(clinic: c, availableToday: false, fallbackOfficePhone: '035368888'),
          ),
        ));
    const base = Clinic(
        id: 'c', specialty: 'dental', specialtyAr: 'الأسنان', specialtyEn: 'Dental', doctorName: 'Dr Mina', days: [5]);
    await pumpCard(base);
    expect(find.byKey(const Key('callChurchOffice')), findsOneWidget);
    await pumpCard(const Clinic(
        id: 'c',
        specialty: 'dental',
        specialtyAr: 'الأسنان',
        specialtyEn: 'Dental',
        doctorName: 'Dr Mina',
        days: [5],
        bookingPhone: '01012345678'));
    expect(find.byKey(const Key('callChurchOffice')), findsNothing);
    expect(find.byKey(const Key('bookClinic')), findsOneWidget);
    expect(find.text('Call • Book'), findsOneWidget);
    expect(find.text('Dr Mina'), findsOneWidget);
  });
}
