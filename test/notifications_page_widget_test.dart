import 'dart:async';
import 'dart:convert';

import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/push_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/data/web_push_repository.dart' as web_push;
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/notifications_page.dart';
import 'package:church_portal/ui/widgets/remind_me.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall, PlatformException, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeTestPushEnv implements PushEnv {
  @override
  bool isSupported;
  @override
  String permission;
  int requestCalls = 0;
  int enableCalls = 0;
  final Map<String, String> storage;

  FakeTestPushEnv({
    this.isSupported = true,
    this.permission = 'default',
    Map<String, String>? storage,
  }) : storage = storage ?? {};

  @override
  Future<String> requestPermission() async {
    requestCalls++;
    permission = 'granted';
    return permission;
  }

  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async => true;
  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async {
    enableCalls++;
    return 'test_token';
  }
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
  Future<bool> syncQuietHours({
    required bool enabled,
    required String start,
    required String end,
    bool remindersRespectQuietHours = true,
  }) async =>
      true;
  @override
  String? readStorage(String key) => storage[key];
  @override
  void writeStorage(String key, String value) {
    storage[key] = value;
  }
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

class _DenyingPushEnv extends FakeTestPushEnv {
  _DenyingPushEnv() : super(permission: 'default');

  @override
  Future<String> requestPermission() async {
    requestCalls++;
    permission = 'denied';
    return 'denied';
  }
}

class _FakeRemindersNotifier extends UserRemindersNotifier {
  final List<Reminder> initial;
  _FakeRemindersNotifier(this.initial);

  @override
  List<Reminder> build() => initial;
}

void main() {
  setUpAll(() async {
    await NotificationsPage.preloadWebPushForTest();
    await RemindMeButton.preloadSheetForTest();
  });

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

    expect(find.text('تفعيل إشعارات المتصفح'), findsOneWidget);
    expect(
      find.text('اضغط على الزر أدناه للسماح للمتصفح بإرسال إشعارات وتنبيهات الكنيسة عند نشر التنبيهات ومواعيد القداسات.'),
      findsOneWidget,
    );

    final buttonFinder = find.ancestor(
      of: find.text('السماح بإشعارات المتصفح'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final button = tester.widget<ButtonStyleButton>(buttonFinder);
    expect(button.onPressed, isNotNull);
    expect(find.byIcon(Icons.notifications_active), findsWidgets);
    expect(pushEnv.requestCalls, 0);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(pushEnv.requestCalls, 1);
    expect(find.text('الإشعارات مفعلة'), findsOneWidget);
  });

  testWidgets('PushPermissionState.denied renders recheck button and clicking invokes onPermissionChanged', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'denied');
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true),
      pushEnv: pushEnv,
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('التحقق من الإذن مجددًا'), findsOneWidget);

    pushEnv.permission = 'granted';
    await tester.tap(find.text('التحقق من الإذن مجددًا'));
    await tester.pumpAndSettle();

    expect(find.text('الإشعارات مفعلة'), findsOneWidget);
  });

  testWidgets('PushPermissionState.iosNeedsInstall renders 3-step guide', (tester) async {
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
    expect(find.text('اضغط زر المشاركة (Share) في أسفل شاشة Safari'), findsOneWidget);
    expect(find.text('اختر «إضافة إلى الشاشة الرئيسية» (Add to Home Screen)'), findsOneWidget);
    expect(find.text('افتح التطبيق من الشاشة الرئيسية لتفعيل التنبيهات'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.byIcon(Icons.add_box_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
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

  testWidgets('OEM battery optimization card is not rendered on /notifications (Web & Android)', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    // 1. Web environment
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(enabled: true),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('حالة الإشعارات وتحسين البطارية'), findsNothing);
    expect(find.text('Notification Health & Battery Guide'), findsNothing);
    expect(find.text('دليل استثناء التطبيق من توفير الطاقة'), findsNothing);

    // 2. Android environment
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(buildTestable(
        child: const NotificationsPage(isWeb: false),
        pushSettings: const PushSettings(enabled: true),
        pushEnv: pushEnv,
        installEnv: installEnv,
      ));
      await tester.pumpAndSettle();

      expect(find.text('حالة الإشعارات وتحسين البطارية'), findsNothing);
      expect(find.text('Notification Health & Battery Guide'), findsNothing);
      expect(find.text('دليل استثناء التطبيق من توفير الطاقة'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('toggling switch when unpermitted invokes requestPermission and enables switch if granted', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'default');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap the switch
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 1);
    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);
  });

  testWidgets('toggling switch when unpermitted displays SnackBar and keeps switch off if denied', (tester) async {
    final pushEnv = _DenyingPushEnv();
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap the switch
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 1);
    expect(find.text('الإشعارات غير مفعلة. يُرجى السماح بالإشعارات من إعدادات المتصفح أو النظام.'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('toggling switch when iosNeedsInstall displays SnackBar without requesting permission', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv();
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
      platform: 'iPhone',
      isStandalone: false,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap switch
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(find.text('لتفعيل الإشعارات على iPhone، أضف الموقع أولاً إلى الشاشة الرئيسية.'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('toggling switch when inAppBrowser displays SnackBar without requesting permission', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv();
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148 [FBAN/FBIOS;FBDV/iPhone14,2;]',
      platform: 'iPhone',
      isStandalone: false,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap switch
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(find.text('أنت تفتح الموقع من داخل تطبيق. انسخ الرابط وافتحه في متصفحك الأساسي لتفعيل الإشعارات.'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('tapping unsubscribe all confirms all turned off and clears preferences', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.reminders],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    // Turn on a type
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);

    // Tap unsubscribe all
    await tester.tap(find.text('إيقاف كل الإشعارات'));
    await tester.pumpAndSettle();

    expect(find.text('تم إيقاف جميع الإشعارات'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('In-app browser displays copy link button and copies link to clipboard', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        copiedText = (methodCall.arguments as Map)['text'] as String?;
      }
      return null;
    });

    final pushEnv = FakeTestPushEnv();
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) Mobile/15E148 Telegram/10.9.1',
      platform: 'iPhone',
      isStandalone: false,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('نسخ الرابط للمتصفح'), findsOneWidget);

    await tester.tap(find.text('نسخ الرابط للمتصفح'));
    await tester.pumpAndSettle();

    expect(find.text('تم نسخ الرابط'), findsOneWidget);
    expect(copiedText, 'https://maximos-domadios-church.web.app/notifications');
  });

  testWidgets('iOS Safari installed PWA (isStandalone: true) exposes permission prompt card and switches', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv(permission: 'default', isSupported: true);
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
      platform: 'iPhone',
      isStandalone: true,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.reminders],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('لتفعيل الإشعارات على iPhone'), findsNothing);
    expect(find.text('السماح بإشعارات المتصفح'), findsOneWidget);
    expect(find.text('تنويهات وأخبار'), findsOneWidget);

    expect(pushEnv.requestCalls, 0);
    await tester.tap(find.text('السماح بإشعارات المتصفح'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 1);
    expect(find.text('الإشعارات مفعلة'), findsOneWidget);
  });

  testWidgets('NotificationsPage never requests permission automatically on load', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'default');
    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        vapidKey: 'test_vapid_key_0123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: FakeTestInstallEnv(),
    ));
    await tester.pumpAndSettle();

    // Crucial check: 0 permission calls on load
    expect(pushEnv.requestCalls, 0);
  });

  testWidgets('Switch toggling on native (isWeb: false) directly enables switch without permission gate', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv(permission: 'default');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: false),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap switch on native: toggles directly without permission gate
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);
  });

  testWidgets('Switch toggling on Web when canRequestPermission is false does not request permission and stays off', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv(permission: 'default');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: '', // canRequestPermission is false
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);

    // Tap switch when gate closed: does not call requestPermission, switch stays off
    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('Unsubscribe all does not trigger permission request when syncedToken is null', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pushEnv = FakeTestPushEnv(permission: 'default');
    final installEnv = FakeTestInstallEnv(
      storage: {
        'church_portal_push': {
          'types': ['announcements'],
          'lang': 'ar',
          'updatedAt': '2026-11-12T00:00:00.000Z',
        },
      },
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);
    expect(pushEnv.requestCalls, 0);
    expect(pushEnv.enableCalls, 0);

    // Tap unsubscribe all when syncedToken is null: must not request permission or enable
    await tester.tap(find.text('إيقاف كل الإشعارات'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(pushEnv.enableCalls, 0);
    expect(find.text('تم إيقاف جميع الإشعارات'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('Active locale language is passed into synced topics', (tester) async {
    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    final capturedBatches = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      capturedBatches.add(queueData);
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      locale: const Locale('en'),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    // Tap switch in English locale
    await tester.tap(find.text('Announcements & news'));
    await tester.pumpAndSettle();

    expect(capturedBatches.isNotEmpty, isTrue);
    final want = (capturedBatches.first['want'] as List).cast<String>();
    expect(want, contains('web_announcements_en'));
    expect(want.any((t) => t.endsWith('_ar')), isFalse);
  });

  testWidgets('clearAll reuses repository and shows confirmation SnackBar when web sync succeeds', (tester) async {
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();
    expect(writes.length, 1);
    expect((writes.last['want'] as List).cast<String>(), contains('web_announcements_ar'));

    await tester.tap(find.text('إيقاف كل الإشعارات'));
    await tester.pumpAndSettle();
    expect(writes.length, 2);
    expect(writes.last['want'], isEmpty);
    expect(find.text('تم إيقاف جميع الإشعارات'), findsOneWidget);
  });

  testWidgets('clearAll shows error SnackBar instead of confirmation when web sync fails', (tester) async {
    var failWrites = false;
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      if (failWrites) throw UnsupportedError('write refused');
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    failWrites = true;
    await tester.tap(find.text('إيقاف كل الإشعارات'));
    await tester.pumpAndSettle();

    expect(find.text('تم إيقاف جميع الإشعارات'), findsNothing);
    expect(find.text('تعذّر حفظ إيقاف الإشعارات على الخادم؛ ستتم إعادة المحاولة تلقائيًا.'), findsOneWidget);
  });

  testWidgets('primary permission button registers token and syncs opted-in topics', (tester) async {
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(permission: 'default');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('السماح بإشعارات المتصفح'));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 1);
    expect(pushEnv.enableCalls, 1);
    expect(writes, isNotEmpty);
    expect((writes.last['want'] as List).cast<String>(), contains('web_announcements_ar'));
  });

  testWidgets('concurrent clearAll while enable is pending reconciles to empty server topics', (tester) async {
    final enableCompleter = Completer<String?>();
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = _DelayedEnablePushEnv(enableCompleter);
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pump();

    expect(find.text('إيقاف كل الإشعارات'), findsOneWidget);
    await tester.tap(find.text('إيقاف كل الإشعارات'));
    await tester.pump();

    enableCompleter.complete('test_token');
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(writes, isEmpty);
    expect(find.text('تم إيقاف جميع الإشعارات'), findsOneWidget);
    expect(find.text('إيقاف كل الإشعارات'), findsNothing);
  });

  testWidgets('toggling switch shows sync error SnackBar when web sync fails', (tester) async {
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      throw UnsupportedError('write refused');
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(permission: 'granted');
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر مزامنة الإشعارات مع الخادم؛ ستتم إعادة المحاولة تلقائيًا.'), findsOneWidget);
  });

  testWidgets('iOS < 16.4 inside in-app browser resolves to iosTooOld instead of inAppBrowser', (tester) async {
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/19G71 [FBAN/FBIOS;WhatsApp]',
      isStandalone: false,
    );
    final pushEnv = FakeTestPushEnv(isSupported: false, permission: 'unsupported');

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(find.text('يتطلب تلقي الإشعارات على iPhone تحديث نظام iOS إلى الإصدار 16.4 أو أحدث.'), findsOneWidget);
    expect(find.text('نسخ الرابط للمتصفح'), findsNothing);
  });

  testWidgets('toggling switch while language changes mid-flight applies post-wait locale', (tester) async {
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final enableCompleter = Completer<String?>();
    final pushEnv = _DelayedEnablePushEnv(enableCompleter);
    final installEnv = FakeTestInstallEnv();
    final localeNotifier = ValueNotifier<Locale>(const Locale('ar'));
    addTearDown(localeNotifier.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 6, 12 * 60).toUtc())),
          featuresStreamProvider.overrideWith((ref) => Stream.value(FeatureSettings.defaults)),
          pushSettingsProvider.overrideWithValue(const PushSettings(
            enabled: true,
            offered: [NotifyType.announcements],
            vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
          )),
          pushEnvProvider.overrideWithValue(pushEnv),
          installEnvProvider.overrideWithValue(installEnv),
          userRemindersProvider.overrideWith(() => _FakeRemindersNotifier(const [])),
        ],
        child: ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (_, loc, _) => MaterialApp(
            locale: loc,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(loc),
            home: const Scaffold(body: NotificationsPage(isWeb: true)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pump();

    localeNotifier.value = const Locale('en');
    await tester.pump();

    enableCompleter.complete('test_token');
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single['want'], contains('web_announcements_en'));
    expect(writes.single['want'], isNot(contains('web_announcements_ar')));
  });

  testWidgets('unmounting NotificationsPage mid-sync still completes sync and persists pendingSync on failure',
      (tester) async {
    var wroteOnce = false;
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      wroteOnce = true;
      throw StateError('offline');
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final enableCompleter = Completer<String?>();
    final pushEnv = _DelayedEnablePushEnv(enableCompleter);
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pump();

    // Unmount NotificationsPage while enable() is still pending.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    enableCompleter.complete('test_token');
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(wroteOnce, isTrue);
    final saved = jsonDecode(pushEnv.storage[web_push.WebPushRepository.storageKey]!) as Map<String, dynamic>;
    expect(saved['pendingSync'], isTrue);
  });

  testWidgets('reopening NotificationsPage resumes persisted pendingSync automatically', (tester) async {
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(
      permission: 'granted',
      storage: {
        web_push.WebPushRepository.storageKey: jsonEncode({
          'syncedToken': 'tok_saved',
          'syncedWant': ['announcements', 'lang_ar'],
          'syncedRem': <String>[],
          'pendingSync': true,
        }),
      },
    );
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    final saved = jsonDecode(pushEnv.storage[web_push.WebPushRepository.storageKey]!) as Map<String, dynamic>;
    expect(saved['pendingSync'], isFalse);
  });

  testWidgets('rapid switch toggles after registration coalesce into one debounced write', (tester) async {
    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(
      permission: 'granted',
      storage: {
        web_push.WebPushRepository.storageKey: jsonEncode({
          'syncedToken': 'tok_saved',
          'syncedWant': <String>[],
          'syncedRem': <String>[],
          'pendingSync': false,
        }),
      },
    );
    final installEnv = FakeTestInstallEnv();

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.seasons],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pump();
    await tester.tap(find.text('مواسم وأعياد خاصة'));
    await tester.pump();

    // Debounced toggles should persist pending state without immediate server burst.
    expect(writes, isEmpty);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    final want = (writes.single['want'] as List).cast<String>();
    expect(want, containsAll(['web_announcements_ar', 'web_seasons_ar']));
  });

  testWidgets('turning switch off after permission revoked still syncs when syncedToken exists', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final writes = <Map<String, dynamic>>[];
    web_push.WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
      writes.add(Map<String, dynamic>.from(queueData));
    };
    addTearDown(() => web_push.WebPushRepository.debugBatchWriter = null);

    final pushEnv = FakeTestPushEnv(
      permission: 'denied',
      storage: {
        web_push.WebPushRepository.storageKey: jsonEncode({
          'syncedToken': 'tok_saved',
          'syncedWant': ['web_announcements_ar', 'web_seasons_ar'],
          'syncedRem': <String>[],
          'pendingSync': false,
        }),
      },
    );
    final installEnv = FakeTestInstallEnv(
      storage: {
        'church_portal_push': {
          'types': ['announcements', 'seasons'],
          'lang': 'ar',
          'updatedAt': '2026-11-12T00:00:00.000Z',
        },
      },
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements, NotifyType.seasons],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنويهات وأخبار'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(pushEnv.enableCalls, 0);
    expect(writes, hasLength(1));
    expect((writes.single['want'] as List).cast<String>(), ['web_seasons_ar']);
  });

  testWidgets('clipboard failure reveals manual link fallback and preview URL strips query/fragment', (tester) async {
    expect(
      NotificationsPage.shareableNotificationsUrlForUri(
        Uri.parse('https://maximos-domadios-church--pr-60.web.app/notifications?fbclid=1#top'),
      ),
      'https://maximos-domadios-church--pr-60.web.app/notifications',
    );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'copy_failed');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final pushEnv = FakeTestPushEnv();
    final installEnv = FakeTestInstallEnv(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) Mobile/15E148 Telegram/10.9.1',
      platform: 'iPhone',
      isStandalone: false,
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('نسخ الرابط للمتصفح'));
    await tester.pumpAndSettle();

    expect(find.text('تم نسخ الرابط'), findsNothing);
    expect(find.text('تعذّر النسخ التلقائي — انسخ الرابط يدويًا:'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('opening NotificationsPage with pendingSync and missing token never triggers enable or requestPermission',
      (tester) async {
    final pushEnv = FakeTestPushEnv(
      permission: 'default',
      storage: {
        web_push.WebPushRepository.storageKey: jsonEncode({
          'syncedToken': null,
          'pendingSync': true,
        }),
      },
    );
    final installEnv = FakeTestInstallEnv(
      storage: {
        'church_portal_push': {
          'types': ['announcements'],
          'lang': 'ar',
          'updatedAt': '2026-11-12T00:00:00.000Z',
        },
      },
    );

    await tester.pumpWidget(buildTestable(
      child: const NotificationsPage(isWeb: true),
      pushSettings: const PushSettings(
        enabled: true,
        offered: [NotifyType.announcements],
        vapidKey: 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
      ),
      pushEnv: pushEnv,
      installEnv: installEnv,
    ));
    await tester.pumpAndSettle();

    expect(pushEnv.requestCalls, 0);
    expect(pushEnv.enableCalls, 0);
  });
}

class _DelayedEnablePushEnv extends FakeTestPushEnv {
  final Completer<String?> _completer;
  _DelayedEnablePushEnv(this._completer) : super(permission: 'granted');

  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) {
    enableCalls++;
    return _completer.future;
  }
}
