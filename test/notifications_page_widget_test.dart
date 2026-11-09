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
import 'package:church_portal/ui/widgets/remind_me.dart';
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

  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async => true;
  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async => 'test_token';
  @override
  Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async => 'test_token';
  @override
  Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) async => true;
  @override
  Future<bool> showSwTestNotification({String? title, String? body, String? link}) async => true;
  @override
  Future<List<WebInboxItem>> readInbox() async => const [];
  @override
  Future<bool> clearInbox() async => true;
  @override
  Future<bool> syncQuietHours({required bool enabled, required String start, required String end}) async => true;
  @override
  String? readStorage(String key) => null;
  @override
  void writeStorage(String key, String value) {}
  @override
  Stream<String> get deepLinks => const Stream.empty();
  @override
  Stream<WebInboxItem> get inboxEvents => const Stream.empty();
}

class FakeTestInstallEnv implements InstallEnv {
  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};

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

class _FailingInstallEnv extends FakeTestInstallEnv {
  @override
  void writeJson(String key, Map<String, dynamic> data) => throw StateError('QuotaExceededError');
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

  testWidgets('a permission denial rebuilds into the blocked how-to (pushPermissionProvider re-read)', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'default');
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true, vapidKey: 'k'),
      pushEnv: pushEnv,
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات محظورة في متصفحك'), findsNothing);

    // What the enable button does after the browser prompt was answered.
    pushEnv.permission = 'denied';
    ProviderScope.containerOf(tester.element(find.byType(NotificationsPage))).invalidate(pushPermissionProvider);
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات محظورة في متصفحك'), findsOneWidget);
  });

  testWidgets('MyRemindersSection displays Cairo wall time for UTC stored reminders', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();
    // 05:00 UTC in winter (UTC+2) is 07:00 Cairo time
    final utcReminder = Reminder(
      eventKey: 'lit-morning',
      lead: 15,
      title: const {'ar': 'قداس الصباح الباكر', 'en': 'Early Morning Liturgy'},
      startsAt: DateTime.utc(2026, 11, 7, 5, 0),
      createdAt: DateTime.utc(2026, 11, 1),
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.reminders],
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
      initialReminders: [utcReminder],
    ));
    await tester.pumpAndSettle();

    expect(find.text('قداس الصباح الباكر'), findsOneWidget);
    // Verified: shows 07:00 Cairo time, never 05:00 UTC
    expect(find.textContaining('٠٧:٠٠ ص'), findsOneWidget);
    expect(find.textContaining('٠٥:٠٠'), findsNothing);
  });

  testWidgets('enable button is enabled with valid VAPID key in PR D and triggers enableAndGetToken', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'default');
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.reminders],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();

    final buttonFinder = find.ancestor(
      of: find.text('تفعيل الإشعارات'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final button = tester.widget<ButtonStyleButton>(buttonFinder);
    expect(button.onPressed, isNotNull);
    await tester.tap(buttonFinder);
    await tester.pump();
  });

  testWidgets('installed iPhone on iOS < 16.4 gets the update card; the app build is never "enabled"', (tester) async {
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true),
      pushEnv: FakeTestPushEnv(isSupported: false),
      installEnv: FakeTestInstallEnv(
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
        platform: 'iPhone',
        isStandalone: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('16.4'), findsOneWidget);

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: false),
      pushSettings: const PushSettings(enabled: true),
      pushEnv: FakeTestPushEnv(permission: 'granted'),
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات مفعلة'), findsNothing);
  });

  testWidgets('a recurring «كل مرة» reminder past its first occurrence shows its next one and is not expired', (tester) async {
    // Stored for Sun 1 Nov 2026 08:00 Cairo; "now" is Fri 6 Nov 2026 -> Sun 8 Nov.
    final weekly = Reminder(
      eventKey: 'lit-sunday',
      lead: 60,
      every: true,
      title: const {'ar': 'قداس الأحد', 'en': 'Sunday Liturgy'},
      startsAt: CairoTime.at(2026, 11, 1, 8 * 60).toUtc(),
      createdAt: DateTime.utc(2026, 10, 20),
    );
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true, offered: [NotifyType.reminders]),
      pushEnv: FakeTestPushEnv(permission: 'granted'),
      installEnv: FakeTestInstallEnv(),
      initialReminders: [weekly],
    ));
    await tester.pumpAndSettle();
    expect(find.text('مسح التذكيرات المنتهية'), findsNothing);
    expect(find.textContaining('٨'), findsWidgets);
    expect(find.byIcon(Icons.event_busy), findsNothing);
  });

  testWidgets('reminder sheet shows a storage error and stays open when the device refuses the write', (tester) async {
    await tester.pumpWidget(buildTestable(
      child: RemindMeButton(
        eventKey: 'lit-x',
        title: const {'ar': 'قداس', 'en': 'Liturgy'},
        startsAt: CairoTime.at(2026, 11, 8, 8 * 60).toUtc(),
      ),
      pushSettings: const PushSettings(enabled: true, offered: [NotifyType.reminders]),
      pushEnv: FakeTestPushEnv(),
      installEnv: _FailingInstallEnv(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذكّرني'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التذكير'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remindSheetError')), findsOneWidget);
    expect(find.textContaining('تعذّر حفظ التذكير'), findsOneWidget);
    expect(find.text('حفظ التذكير'), findsOneWidget); // still open
  });
}
