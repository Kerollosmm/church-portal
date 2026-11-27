import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeInstallEnv implements InstallEnv {
  @override
  String userAgent;
  @override
  String platform;
  @override
  bool isStandalone;

  _FakeInstallEnv({
    this.userAgent = 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36',
    this.platform = 'Linux armv8l',
    this.isStandalone = false,
  });

  @override
  int get maxTouchPoints => 5;

  @override
  bool get hasDeferredPrompt => false;

  @override
  bool get installedEventReceived => false;

  @override
  void clearInstalledSessionFlag() {}

  @override
  Future<bool> promptInstall() async => true;

  @override
  Map<String, dynamic>? readJson(String key) => null;

  @override
  void writeJson(String key, Map<String, dynamic> data) {}

  @override
  void remove(String key) {}

  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};
}

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  group('shouldShowInstallEntry', () {
    const enabled = InstallSettings(enabled: true);
    const disabled = InstallSettings(enabled: false);

    test('true only on non-standalone browser when enabled', () {
      expect(
        shouldShowInstallEntry(
          settings: enabled,
          isStandalone: false,
          installedEventReceived: false,
          isWeb: true,
        ),
        isTrue,
      );
      expect(
        shouldShowInstallEntry(
          settings: enabled,
          isStandalone: false,
          installedEventReceived: false,
          isWeb: false,
        ),
        isFalse,
      );
      expect(
        shouldShowInstallEntry(
          settings: disabled,
          isStandalone: false,
          installedEventReceived: false,
          isWeb: true,
        ),
        isFalse,
      );
      expect(
        shouldShowInstallEntry(
          settings: enabled,
          isStandalone: true,
          installedEventReceived: false,
          isWeb: true,
        ),
        isFalse,
      );
      expect(
        shouldShowInstallEntry(
          settings: enabled,
          isStandalone: false,
          installedEventReceived: true,
          isWeb: true,
        ),
        isFalse,
      );
    });
  });

  Widget wrapScope({
    required Widget child,
    required _FakeInstallEnv env,
    InstallSettings settings = const InstallSettings(enabled: true),
    Locale locale = const Locale('ar'),
  }) {
    final featuresMap = {
      'installPrompt': settings.enabled,
      'installAndroidUrl': settings.androidUrl,
      'installApkSizeMb': settings.apkSizeMb,
    };
    final features = FeatureSettings.fromMap(featuresMap);
    final seed = SeedData({
      'settings': {
        'church': const <String, dynamic>{},
        'features': featuresMap,
      },
    });
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(seed)),
        installEnvProvider.overrideWithValue(env),
        installSettingsProvider.overrideWithValue(settings),
        featuresProvider.overrideWithValue(features),
        featuresReadyProvider.overrideWithValue(true),
        settingsProvider.overrideWith((_) => Stream.value(ChurchSettings.fromMap(const {}))),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(locale),
        home: child,
      ),
    );
  }

  group('Footer permanent install entry', () {
    testWidgets('shows حمّل التطبيق on web when enabled and hides when disabled/standalone/native', (tester) async {
      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('footerInstallApp')), findsOneWidget);
      expect(find.text('حمّل التطبيق'), findsOneWidget);

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(isStandalone: true),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('footerInstallApp')), findsNothing);

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(),
          settings: const InstallSettings(enabled: false),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('footerInstallApp')), findsNothing);

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: false))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('footerInstallApp')), findsNothing);
    });

    testWidgets('tapping footer entry on Android with androidUrl launches APK and opens guide sheet', (tester) async {
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments;
        if (args is Map && args['url'] is String) launched.add(args['url'] as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(),
          settings: const InstallSettings(
            enabled: true,
            androidUrl: 'https://github.com/Kerollosmm/church-portal/releases/download/v1.0.0/app.apk',
            apkSizeMb: 18.4,
          ),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('footerInstallApp')));
      await tester.tap(find.byKey(const Key('footerInstallApp')));
      await tester.pumpAndSettle();

      expect(launched, ['https://github.com/Kerollosmm/church-portal/releases/download/v1.0.0/app.apk']);
      expect(find.text('دليل تثبيت تطبيق الكنيسة (APK)'), findsOneWidget);
    });

    testWidgets('tapping footer entry on iOS opens iOS install steps sheet', (tester) async {
      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(
            userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1',
            platform: 'iPhone',
          ),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('footerInstallApp')));
      await tester.tap(find.byKey(const Key('footerInstallApp')));
      await tester.pumpAndSettle();

      expect(find.text('إضافة الموقع للشاشة الرئيسية'), findsOneWidget);
    });

    testWidgets('tapping footer entry on Android without APK or prompt opens browser steps sheet', (tester) async {
      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(),
          child: const Scaffold(body: SingleChildScrollView(child: Footer(isWeb: true))),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('footerInstallApp')));
      await tester.tap(find.byKey(const Key('footerInstallApp')));
      await tester.pumpAndSettle();

      expect(find.text('تثبيت التطبيق من المتصفح'), findsOneWidget);
    });
  });

  group('AppShell drawer permanent install entry', () {
    testWidgets('shows حمّل التطبيق in drawer at 320px and opens deferred sheet cleanly', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(
            userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1',
            platform: 'iPhone',
          ),
          child: const AppShell(
            location: '/',
            isWeb: true,
            child: SizedBox(height: 400),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menuBtn = find.byTooltip('القائمة');
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      final drawerItem = find.byKey(const Key('drawerInstallApp'));
      expect(drawerItem, findsOneWidget);
      expect(find.text('حمّل التطبيق'), findsOneWidget);

      await tester.ensureVisible(drawerItem);
      await tester.tap(drawerItem);
      await tester.pumpAndSettle();

      expect(find.text('إضافة الموقع للشاشة الرئيسية'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides drawer entry when standalone', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrapScope(
          env: _FakeInstallEnv(isStandalone: true),
          child: const AppShell(
            location: '/',
            isWeb: true,
            child: SizedBox(height: 400),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('drawerInstallApp')), findsNothing);
    });
  });
}
