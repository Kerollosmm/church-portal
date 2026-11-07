import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/domain/app_install.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/apk_install_guide.dart';
import 'package:church_portal/ui/widgets/install_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeInstallEnv implements InstallEnv {
  @override
  String userAgent;
  @override
  String platform;
  @override
  int maxTouchPoints;
  @override
  bool isStandalone;
  @override
  bool hasDeferredPrompt;
  @override
  bool installedEventReceived;
  final Map<String, dynamic> storage;
  int promptCalls = 0;

  FakeInstallEnv({
    this.userAgent = 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36',
    this.platform = 'Linux armv8l',
    this.maxTouchPoints = 5,
    this.isStandalone = false,
    this.hasDeferredPrompt = false,
    this.installedEventReceived = false,
    Map<String, dynamic>? storage,
  }) : storage = storage ?? {};

  @override
  void clearInstalledSessionFlag() {
    installedEventReceived = false;
  }

  @override
  Future<bool> promptInstall() async {
    promptCalls++;
    return true;
  }

  @override
  Map<String, dynamic>? readJson(String key) => storage[key] as Map<String, dynamic>?;

  @override
  void writeJson(String key, Map<String, dynamic> data) {
    storage[key] = data;
  }

  @override
  void remove(String key) {
    storage.remove(key);
  }
}

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  Widget buildTestable({
    required Widget child,
    required FakeInstallEnv installEnv,
    InstallSettings? installSettings,
    Locale locale = const Locale('ar'),
    bool contentReady = true,
  }) {
    final settings = installSettings ??
        const InstallSettings(
          enabled: true,
          titleAr: 'تطبيق الكنيسة',
          titleEn: 'Church App',
          bodyAr: 'ثبّت التطبيق للمتابعة',
          bodyEn: 'Install the app',
          androidUrl: 'https://example.com/app.apk',
          apkVersion: '1.1.0',
          apkSizeMb: 18.4,
          reshowDays: 14,
          remindDays: 3,
        );

    return ProviderScope(
      overrides: [
        installEnvProvider.overrideWithValue(installEnv),
        installSettingsProvider.overrideWithValue(settings),
        contentReadyProvider.overrideWithValue(contentReady),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(locale),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('InstallBanner renders on Android with APK download button', (tester) async {
    final env = FakeInstallEnv();
    await tester.pumpWidget(buildTestable(
      child: const InstallBanner(currentPath: '/', delay: Duration.zero, isWeb: true),
      installEnv: env,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(InstallBanner), findsOneWidget);
    expect(find.text('تطبيق الكنيسة'), findsOneWidget);
    expect(find.text('تحميل التطبيق'), findsOneWidget);
    expect(find.text('لاحقًا'), findsOneWidget);
  });

  testWidgets('Close button ✕ writes dismissedUntil in storage', (tester) async {
    final env = FakeInstallEnv();
    await tester.pumpWidget(buildTestable(
      child: const InstallBanner(currentPath: '/', delay: Duration.zero, isWeb: true),
      installEnv: env,
    ));
    await tester.pumpAndSettle();

    final closeBtn = find.byTooltip('إغلاق');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(env.storage.containsKey(installStorageKey), isTrue);
    expect(find.text('تطبيق الكنيسة'), findsNothing);
  });

  testWidgets('Later button writes remindUntil in storage', (tester) async {
    final env = FakeInstallEnv();
    await tester.pumpWidget(buildTestable(
      child: const InstallBanner(currentPath: '/', delay: Duration.zero, isWeb: true),
      installEnv: env,
    ));
    await tester.pumpAndSettle();

    final laterBtn = find.text('لاحقًا');
    expect(laterBtn, findsOneWidget);
    await tester.tap(laterBtn);
    await tester.pumpAndSettle();

    expect(env.storage.containsKey(installStorageKey), isTrue);
    expect(find.text('تطبيق الكنيسة'), findsNothing);
  });

  testWidgets('InstallBanner on iOS shows how-to-install button and sheet', (tester) async {
    final env = FakeInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
      platform: 'iPhone',
    );
    await tester.pumpWidget(buildTestable(
      child: const InstallBanner(currentPath: '/', delay: Duration.zero, isWeb: true),
      installEnv: env,
    ));
    await tester.pumpAndSettle();

    final howToBtn = find.text('طريقة الإضافة');
    expect(howToBtn, findsOneWidget);

    await tester.tap(howToBtn);
    await tester.pumpAndSettle();

    expect(find.text('إضافة الموقع للشاشة الرئيسية'), findsOneWidget);
    expect(find.text('اضغط زر المشاركة في أسفل المتصفح'), findsOneWidget);
    expect(find.text('اختر «إضافة إلى الشاشة الرئيسية»'), findsOneWidget);
  });

  testWidgets('showApkInstallGuide modal renders 5 steps without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(const Locale('ar')),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showApkInstallGuide(context, apkSizeMb: 18.4),
              child: const Text('Open Guide'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Guide'));
    await tester.pumpAndSettle();

    expect(find.text('دليل تثبيت تطبيق الكنيسة (APK)'), findsOneWidget);
    expect(find.text('الخطوة ١ من ٥'), findsOneWidget);

    // Navigate to step 2
    final nextBtn = find.text('التالي');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();
    expect(find.text('الخطوة ٢ من ٥'), findsOneWidget);
  });
}
