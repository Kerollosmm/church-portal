import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/push_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/notifications_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeTestPushEnv implements PushEnv {
  @override
  bool isSupported;
  @override
  String permission;
  int requestCalls = 0;

  FakeTestPushEnv({
    this.isSupported = true,
    this.permission = 'default',
  });

  @override
  Future<String> requestPermission() async {
    requestCalls++;
    permission = 'granted';
    return permission;
  }
}

class FakeTestInstallEnv implements InstallEnv {
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

  FakeTestInstallEnv({
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
  Future<bool> promptInstall() async => true;

  @override
  Map<String, dynamic>? readJson(String key) => storage[key] as Map<String, dynamic>?;

  @override
  void writeJson(String key, Map<String, dynamic> data) => storage[key] = data;

  @override
  void remove(String key) => storage.remove(key);
}

class _FakeRemindersNotifier extends UserRemindersNotifier {
  final List<Reminder> initial;
  _FakeRemindersNotifier(this.initial);

  @override
  List<Reminder> build() => initial;
}

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  Widget buildTestable({
    required Widget child,
    required PushSettings pushSettings,
    required PushEnv pushEnv,
    required InstallEnv installEnv,
    List<Reminder> initialReminders = const [],
    Locale locale = const Locale('ar'),
  }) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 6, 12 * 60).toUtc())),
        featuresStreamProvider.overrideWith((ref) => Stream.value(FeatureSettings.defaults)),
        pushSettingsProvider.overrideWithValue(pushSettings),
        pushEnvProvider.overrideWithValue(pushEnv),
        installEnvProvider.overrideWithValue(installEnv),
        userRemindersProvider.overrideWith(() => _FakeRemindersNotifier(initialReminders)),
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

  testWidgets('NotificationsPage renders unsupported state when push is off', (tester) async {
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: false),
      pushEnv: FakeTestPushEnv(),
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('هذا المتصفح لا يدعم تلقي الإشعارات.'), findsOneWidget);
  });

  testWidgets('NotificationsPage renders explainer, types, and reminders when push is on', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.seasons, NotifyType.reminders],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('إشعارات وتنبيهات الكنيسة'), findsOneWidget);
    expect(find.text('تنويهات وأخبار'), findsOneWidget);
    expect(find.text('مواسم وأعياد خاصة'), findsOneWidget);
    expect(find.text('تذكيراتي'), findsWidgets);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);

    // Toggle a type on: now "Turn off all notifications" appears
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();
    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);
  });

  testWidgets('NotificationsPage shows install-first card on iOS when not standalone', (tester) async {
    final pushEnv = FakeTestPushEnv();
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
      platform: 'iPhone',
      isStandalone: false,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('لتفعيل الإشعارات على iPhone'), findsOneWidget);
  });
}
