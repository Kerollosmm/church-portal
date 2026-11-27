import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/notification_health_page.dart';
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    CairoTime.ensureInitialized();
    await preloadNotificationRoutesForTest();
  });

  const deviceChannel = MethodChannel('church_portal/device');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      (MethodCall call) async {
        if (call.method == 'getDiagnostics') {
          return <String, dynamic>{
            'manufacturer': 'Xiaomi',
            'brand': 'Redmi',
            'isIgnoringBatteryOptimizations': true,
            'canScheduleExactAlarms': true,
            'notificationsAllowed': true,
          };
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      null,
    );
  });

  Widget buildApp({
    required Size size,
    Locale locale = const Locale('ar'),
    double textScale = 1.0,
  }) {
    final router = GoRouter(
      initialLocation: '/notifications/battery',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(
            location: state.uri.toString(),
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/notifications',
              builder: (context, state) => const Text('NotificationsScreen'),
            ),
            GoRoute(
              path: '/notifications/battery',
              builder: (context, state) => const NotificationHealthPage(),
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        featuresProvider.overrideWithValue(FeatureSettings.defaults),
        featuresReadyProvider.overrideWithValue(true),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 8, 12 * 60).toUtc())),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp.router(
          routerConfig: router,
          locale: locale,
          theme: buildTheme(locale),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
  }

  testWidgets('NotificationHealthPage has exactly 1 Scaffold and 1 Back arrow on mobile (INV-NAV-01, INV-NAV-02)', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(size: const Size(400, 800)));
    await tester.pumpAndSettle();

    // Exactly one Scaffold belonging to AppShell; no nested Scaffold inside NotificationHealthPage (INV-NAV-01)
    expect(find.byType(Scaffold), findsOneWidget);

    // Exactly one back arrow icon (INV-NAV-02)
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // PageHeader contains localized Arabic title and subtitle from notificationHealthStrings
    expect(find.byType(PageHeader), findsOneWidget);
    expect(find.text('إذا لم تصلك الإشعارات'), findsOneWidget);
    expect(find.text('فحص البطارية وإعدادات النظام'), findsOneWidget);
  });

  testWidgets('NotificationHealthPage in English displays English title and subtitle', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(size: const Size(400, 800), locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('Notification Health & Battery'), findsOneWidget);
    expect(find.text('Battery saver & system diagnostics'), findsOneWidget);
  });

  testWidgets('NotificationHealthPage renders responsive layouts without overflow (320, 400, 1400 px)', (tester) async {
    for (final width in [320.0, 400.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildApp(size: Size(width, 1000)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'No layout exceptions at width $width');
      expect(find.byType(PageBody), findsOneWidget);
      expect(find.text('إذا لم تصلك الإشعارات'), findsOneWidget);
    }
    tester.view.reset();
  });

  testWidgets('NotificationHealthPage defaults permissions to neutral unknown when channel fails or returns null',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      (MethodCall call) async {
        if (call.method == 'getDiagnostics') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );

    await tester.pumpWidget(buildApp(size: const Size(400, 800)));
    await tester.pumpAndSettle();

    expect(find.text('غير معروف'), findsNWidgets(2));
    expect(find.byIcon(Icons.help_outline_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('مسموح به'), findsNothing);
    expect(find.text('مسموح به (دقيق)'), findsNothing);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceChannel,
      (MethodCall call) async => null,
    );

    await tester.pumpWidget(buildApp(size: const Size(400, 800), locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Unknown'), findsNWidgets(2));
    expect(find.byIcon(Icons.help_outline_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  group('/notifications/battery route platform gating', () {
    Future<GoRouter> pumpRoutedApp(
      WidgetTester tester, {
      required bool isWeb,
      required TargetPlatform platform,
    }) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = ProviderContainer(overrides: [
        isWebProvider.overrideWithValue(isWeb),
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        featuresProvider.overrideWithValue(FeatureSettings.fromMap({'push': true})),
        featuresReadyProvider.overrideWithValue(true),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 8, 12 * 60).toUtc())),
      ]);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('redirects /notifications/battery to /notifications on web (preserving query)', (tester) async {
      final router = await pumpRoutedApp(tester, isWeb: true, platform: TargetPlatform.android);
      router.go('/notifications/battery?lang=en');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(router.routerDelegate.currentConfiguration.uri.path, '/notifications');
      expect(router.routerDelegate.currentConfiguration.uri.queryParameters['lang'], 'en');
    });

    testWidgets('redirects /notifications/battery to /notifications on iOS', (tester) async {
      final router = await pumpRoutedApp(tester, isWeb: false, platform: TargetPlatform.iOS);
      router.go('/notifications/battery');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(router.routerDelegate.currentConfiguration.uri.path, '/notifications');
    });

    testWidgets('allows /notifications/battery on native Android', (tester) async {
      final router = await pumpRoutedApp(tester, isWeb: false, platform: TargetPlatform.android);
      router.go('/notifications/battery');
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(NotificationHealthPage).evaluate().isNotEmpty) break;
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(router.routerDelegate.currentConfiguration.uri.path, '/notifications/battery');
      expect(find.byType(NotificationHealthPage), findsOneWidget);
    });
  });
}
