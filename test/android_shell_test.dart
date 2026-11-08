import 'package:church_portal/core/locale_storage.dart';
import 'package:church_portal/core/locale_storage_io.dart' as io;
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/assistant_page.dart';
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime cairo(int y, int m, int d, int h, [int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CairoTime.ensureInitialized);

  group('locale_storage_io unit tests', () {
    test('preloaded cache returns saved language code', () async {
      SharedPreferences.setMockInitialValues({'church_portal_lang': 'en'});
      await io.initLanguageStore();

      expect(io.readLanguage('church_portal_lang'), 'en');
      const store = PlatformLanguageStore();
      expect(store.read(), 'en');
    });

    test('write updates cache immediately and writes through', () async {
      SharedPreferences.setMockInitialValues({'church_portal_lang': 'en'});
      await io.initLanguageStore();

      const store = PlatformLanguageStore();
      expect(store.read(), 'en');

      store.write('ar');
      expect(io.readLanguage('church_portal_lang'), 'ar');
      expect(store.read(), 'ar');
    });

    test('fallback returns null for unknown language codes or missing store', () async {
      SharedPreferences.setMockInitialValues({});
      await io.initLanguageStore();

      const store = PlatformLanguageStore();
      expect(store.read(), isNull);

      // Invalid language code should be rejected by PlatformLanguageStore.read
      store.write('fr');
      expect(store.read(), isNull);
    });
  });

  group('parentRouteOf route hierarchy', () {
    test('detail route navigates to listing section', () {
      expect(parentRouteOf('/clinics/c1'), '/clinics');
      expect(parentRouteOf('/about/priests/p1'), '/about');
      expect(parentRouteOf('/about/saints/s1'), '/about');
      expect(parentRouteOf('/public-services/f1'), '/public-services');
    });

    test('battery route navigates to notifications (INV-NAV-01)', () {
      expect(parentRouteOf('/notifications/battery'), '/notifications');
      expect(parentRouteOf('/notifications/battery/'), '/notifications');
      expect(parentRouteOf('/notifications/battery?brand=xiaomi'), '/notifications');
    });

    test('subpages navigate to root home route', () {
      expect(parentRouteOf('/about'), '/');
      expect(parentRouteOf('/mass-schedule'), '/');
      expect(parentRouteOf('/clinics'), '/');
      expect(parentRouteOf('/church-education'), '/');
      expect(parentRouteOf('/contact'), '/');
      expect(parentRouteOf('/'), '/');
    });
  });

  group('AppShell Android back navigation (PopScope)', () {
    late GoRouter testRouter;

    Widget buildTestApp({required String initialLocation}) {
      testRouter = GoRouter(
        initialLocation: initialLocation,
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppShell(
              location: state.uri.toString(),
              child: child,
            ),
            routes: [
              GoRoute(path: '/', builder: (context, state) => const Text('HomeScreen')),
              GoRoute(path: '/about', builder: (context, state) => const Text('AboutScreen')),
              GoRoute(path: '/clinics', builder: (context, state) => const Text('ClinicsScreen')),
              GoRoute(path: '/clinics/:id', builder: (context, state) => const Text('ClinicDetailScreen')),
              GoRoute(path: '/notifications', builder: (context, state) => const Text('NotificationsScreen')),
              GoRoute(path: '/notifications/battery', builder: (context, state) => const Text('BatteryScreen')),
            ],
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          featuresReadyProvider.overrideWithValue(true),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 7, 10))),
        ],
        child: MaterialApp.router(
          routerConfig: testRouter,
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      );
    }

    testWidgets('detail route navigates to parent route on back press', (tester) async {
      await tester.pumpWidget(buildTestApp(initialLocation: '/clinics/c1'));
      await tester.pumpAndSettle();

      expect(find.text('ClinicDetailScreen'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('ClinicsScreen'), findsOneWidget);
    });

    testWidgets('battery route navigates to notifications on back press and shows tooltip', (tester) async {
      await tester.pumpWidget(buildTestApp(initialLocation: '/notifications/battery'));
      await tester.pumpAndSettle();

      expect(find.text('BatteryScreen'), findsOneWidget);
      expect(find.byTooltip('العودة إلى الإشعارات'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('NotificationsScreen'), findsOneWidget);
    });

    testWidgets('subpage route navigates to / on back press', (tester) async {
      await tester.pumpWidget(buildTestApp(initialLocation: '/about'));
      await tester.pumpAndSettle();

      expect(find.text('AboutScreen'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('HomeScreen'), findsOneWidget);
    });

    testWidgets('home route shows exit toast on single back and exits on double back within 2s', (tester) async {
      bool didSystemExit = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'SystemNavigator.pop') {
            didSystemExit = true;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildTestApp(initialLocation: '/'));
      await tester.pumpAndSettle();

      expect(find.text('HomeScreen'), findsOneWidget);

      // First back press shows confirmation SnackBar
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('اضغط مرة أخرى للخروج من التطبيق'), findsOneWidget);
      expect(didSystemExit, isFalse);

      // Second back press within 2s invokes SystemNavigator.pop()
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(didSystemExit, isTrue);
    });

    testWidgets('back press closes end drawer if open', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestApp(initialLocation: '/about'));
      await tester.pumpAndSettle();

      // Open drawer using the menu button
      final menuBtn = find.byIcon(Icons.menu_rounded);
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Drawer is open
      expect(find.byType(Drawer), findsOneWidget);

      // Back press closes drawer, stays on /about
      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);
      expect(find.text('AboutScreen'), findsOneWidget);
    });
  });

  group('AssistantPage on non-web platforms', () {
    testWidgets('displays external web redirect card and button', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          featuresReadyProvider.overrideWithValue(true),
          assistantVisibleProvider.overrideWithValue(true),
          settingsProvider.overrideWith((ref) => Stream.value(const ChurchSettings(
                nameAr: 'كنيسة',
                nameEn: 'Church',
                addressAr: 'الإسكندرية',
                addressEn: 'Alexandria',
              ))),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: AssistantPage(isWeb: false)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('مساعد الكنيسة الذكي'), findsOneWidget);
      expect(
        find.text('مساعد الكنيسة متاح عبر البوابة الإلكترونية على الإنترنت مع الحماية الكاملة.'),
        findsOneWidget,
      );
      expect(find.text('فتح المساعد في المتصفح'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser_rounded), findsOneWidget);

      // Interactive chat textfield should not be rendered
      expect(find.byType(TextField), findsNothing);
    });
  });
}
