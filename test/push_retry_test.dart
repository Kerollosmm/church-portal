import 'dart:async';

import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/data/local_notifications.dart';
import 'package:church_portal/data/push_messaging_io.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/notify_plan.dart';
import 'package:church_portal/state/notify_providers.dart';
import 'package:church_portal/state/providers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryInstallEnv extends InstallEnv {
  final Map<String, Map<String, dynamic>> _store = {};

  @override
  String get userAgent => '';
  @override
  String get platform => '';
  @override
  int get maxTouchPoints => 0;
  @override
  bool get isStandalone => false;
  @override
  bool get hasDeferredPrompt => false;
  @override
  bool get installedEventReceived => false;
  @override
  void clearInstalledSessionFlag() {}
  @override
  Future<bool> promptInstall() async => false;
  @override
  Map<String, dynamic>? readJson(String key) => _store[key];
  @override
  void writeJson(String key, Map<String, dynamic> data) => _store[key] = data;
  @override
  void remove(String key) => _store.remove(key);
  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};
}

class _FakeLocalNotifier implements LocalNotifier {
  @override
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<bool> canScheduleExactAlarms() async => true;
  @override
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang}) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showInstant(int id, String title, String body, {String? channelId, String? payload}) async {}
  @override
  Future<int> pendingCount() async => 0;
  @override
  Future<String?> getLaunchPayload() async => null;
}

class _FakeFirebaseMessaging implements FirebaseMessaging {
  bool shouldThrow = false;
  bool shouldHang = false;
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];

  @override
  Future<void> subscribeToTopic(String topic) async {
    if (shouldHang) return Completer<void>().future;
    if (shouldThrow) throw Exception('network offline');
    subscribed.add(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    if (shouldHang) return Completer<void>().future;
    if (shouldThrow) throw Exception('network offline');
    unsubscribed.add(topic);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PushMessaging.updateSubscriptions persistence & timeout', () {
    test('persists pendingTopicSyncKey on failure and clears on success', () async {
      final prefs = await SharedPreferences.getInstance();
      final messaging = _FakeFirebaseMessaging()..shouldThrow = true;
      final userPrefs = PushPrefs(types: const {NotifyType.announcements}, updatedAt: DateTime.utc(2026, 11, 27));

      final failed = await PushMessaging.updateSubscriptions(
        userPrefs,
        'ar',
        messagingInstance: messaging,
        sharedPrefs: prefs,
      );
      expect(failed, isFalse);
      expect(prefs.getBool(pendingTopicSyncKey), isTrue);
      expect(await PushMessaging.hasPendingTopicSync(prefs: prefs), isTrue);

      messaging.shouldThrow = false;
      final ok = await PushMessaging.updateSubscriptions(
        userPrefs,
        'ar',
        messagingInstance: messaging,
        sharedPrefs: prefs,
      );
      expect(ok, isTrue);
      expect(prefs.getBool(pendingTopicSyncKey), isNull);
      expect(await PushMessaging.hasPendingTopicSync(prefs: prefs), isFalse);
      expect(messaging.subscribed, ['app_announcements_ar']);
    });

    test('times out hanging topic calls and persists pendingTopicSyncKey', () async {
      expect(PushMessaging.topicSyncTimeout, const Duration(seconds: 20));
      final prefs = await SharedPreferences.getInstance();
      final messaging = _FakeFirebaseMessaging()..shouldHang = true;
      final userPrefs = PushPrefs(types: const {NotifyType.announcements}, updatedAt: DateTime.utc(2026, 11, 27));

      final ok = await PushMessaging.updateSubscriptions(
        userPrefs,
        'ar',
        messagingInstance: messaging,
        sharedPrefs: prefs,
        timeout: const Duration(milliseconds: 30),
      );
      expect(ok, isFalse);
      expect(prefs.getBool(pendingTopicSyncKey), isTrue);
    });

    test('subscribeTestTopic normalizes, unsubscribes previous topic, and persists; unsubscribeTestTopic clears',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final messaging = _FakeFirebaseMessaging();

      // Rejects invalid without touching messaging or storage
      expect(
        await PushMessaging.subscribeTestTopic('test_ABC', messagingInstance: messaging, sharedPrefs: prefs),
        isFalse,
      );
      expect(messaging.subscribed, isEmpty);
      expect(prefs.getString(testPushTopicStorageKey), isNull);

      // Subscribes valid (auto-prefixed)
      expect(
        await PushMessaging.subscribeTestTopic('kerollos1', messagingInstance: messaging, sharedPrefs: prefs),
        isTrue,
      );
      expect(messaging.subscribed, ['test_kerollos1']);
      expect(prefs.getString(testPushTopicStorageKey), 'test_kerollos1');
      expect(await PushMessaging.getStoredTestTopic(sharedPrefs: prefs), 'test_kerollos1');

      // Subscribing a different test topic unsubscribes the previous one first
      expect(
        await PushMessaging.subscribeTestTopic('test_kerollos2', messagingInstance: messaging, sharedPrefs: prefs),
        isTrue,
      );
      expect(messaging.unsubscribed, ['test_kerollos1']);
      expect(messaging.subscribed, ['test_kerollos1', 'test_kerollos2']);
      expect(prefs.getString(testPushTopicStorageKey), 'test_kerollos2');

      // Unsubscribe clears storage and unsubscribes from FCM
      expect(
        await PushMessaging.unsubscribeTestTopic('kerollos2', messagingInstance: messaging, sharedPrefs: prefs),
        isTrue,
      );
      expect(messaging.unsubscribed, ['test_kerollos1', 'test_kerollos2']);
      expect(prefs.getString(testPushTopicStorageKey), isNull);
      expect(await PushMessaging.getStoredTestTopic(sharedPrefs: prefs), isNull);
    });
  });

  group('NotifyPlanner FCM retry on connectivity reconnect and app resume', () {
    test('retries only on offline->online transition, with no tight loop and deduped in-flight calls', () async {
      final conn = StreamController<bool>.broadcast();
      addTearDown(conn.close);

      var syncCalls = 0;
      Completer<bool>? completer;
      var nextResult = false;

      final container = ProviderContainer(
        overrides: [
          installEnvProvider.overrideWithValue(_MemoryInstallEnv()),
          localNotifierProvider.overrideWithValue(_FakeLocalNotifier()),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          liturgiesProvider.overrideWith((_) => const Stream.empty()),
          meetingsProvider.overrideWith((_) => const Stream.empty()),
          seasonsProvider.overrideWith((_) => const Stream.empty()),
          dailyVersesProvider.overrideWith((_) async => const []),
          connectivityProvider.overrideWith((_) => conn.stream),
          topicSyncProvider.overrideWithValue((prefs, lang) {
            syncCalls++;
            final active = completer;
            if (active != null) return active.future;
            return Future.value(nextResult);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Keep notifyPlannerProvider actively listened (as ChurchPortalApp does via ref.watch)
      // so Riverpod 3 does not pause its StreamProvider dependency.
      final sub = container.listen(notifyPlannerProvider, (_, _) {});
      final planner = sub.read();
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(syncCalls, 1);
      expect(planner.hasPendingTopicSyncInMemory, isTrue);

      // Repeated offline emissions do NOT trigger tight retry loops.
      conn.add(false);
      conn.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(syncCalls, 1);

      // Transition offline -> online triggers ONE deduped retry.
      completer = Completer<bool>();
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 2);

      // While retry is in flight, even another offline -> online does NOT start a concurrent retry.
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 2);

      // Complete the in-flight retry with success.
      completer.complete(true);
      completer = null;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(planner.hasPendingTopicSyncInMemory, isFalse);

      // Subsequent offline -> online with no pending flag does NOT call topicSync again.
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 2);
    });

    test('records reconnect arriving during an in-flight failed sync and runs one follow-up retry without looping',
        () async {
      final conn = StreamController<bool>.broadcast();
      addTearDown(conn.close);

      var syncCalls = 0;
      Completer<bool>? inFlight = Completer<bool>();
      var nextResult = false;

      final container = ProviderContainer(
        overrides: [
          installEnvProvider.overrideWithValue(_MemoryInstallEnv()),
          localNotifierProvider.overrideWithValue(_FakeLocalNotifier()),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          liturgiesProvider.overrideWith((_) => const Stream.empty()),
          meetingsProvider.overrideWith((_) => const Stream.empty()),
          seasonsProvider.overrideWith((_) => const Stream.empty()),
          dailyVersesProvider.overrideWith((_) async => const []),
          connectivityProvider.overrideWith((_) => conn.stream),
          topicSyncProvider.overrideWithValue((prefs, lang) {
            syncCalls++;
            final active = inFlight;
            if (active != null) return active.future;
            return Future.value(nextResult);
          }),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(notifyPlannerProvider, (_, _) {});
      final planner = sub.read();
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 1);

      // Reconnect arrives while initial topic sync is still in flight.
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 1);

      // Initial sync fails -> consumes the recorded reconnect to trigger ONE follow-up retry (which also fails), no loop.
      inFlight.complete(false);
      inFlight = null;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 2);
      expect(planner.hasPendingTopicSyncInMemory, isTrue);

      // If another reconnect arrives during a sync that succeeds, the recorded reconnect is cleared on success.
      inFlight = Completer<bool>();
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 3);

      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 3);

      inFlight.complete(true);
      inFlight = null;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 3);
      expect(planner.hasPendingTopicSyncInMemory, isFalse);
    });

    testWidgets('retries pending topic sync on app resume (single-flight deduped)', (tester) async {
      SharedPreferences.setMockInitialValues({pendingTopicSyncKey: true});
      final prefs = await SharedPreferences.getInstance();
      final messaging = _FakeFirebaseMessaging();
      final conn = StreamController<bool>.broadcast();
      addTearDown(conn.close);

      var syncCalls = 0;
      Completer<bool>? inFlight;
      var useFakeSuccess = false;

      late NotifyPlanner planner;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            installEnvProvider.overrideWithValue(_MemoryInstallEnv()),
            localNotifierProvider.overrideWithValue(_FakeLocalNotifier()),
            featuresProvider.overrideWithValue(FeatureSettings.defaults),
            liturgiesProvider.overrideWith((_) => const Stream.empty()),
            meetingsProvider.overrideWith((_) => const Stream.empty()),
            seasonsProvider.overrideWith((_) => const Stream.empty()),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityProvider.overrideWith((_) => conn.stream),
            topicSyncProvider.overrideWithValue((userPrefs, lang) async {
              syncCalls++;
              final active = inFlight;
              if (active != null) return active.future;
              if (useFakeSuccess) {
                messaging.shouldThrow = false;
                return PushMessaging.updateSubscriptions(
                  userPrefs,
                  lang,
                  messagingInstance: messaging,
                  sharedPrefs: prefs,
                );
              }
              messaging.shouldThrow = true;
              return PushMessaging.updateSubscriptions(
                userPrefs,
                lang,
                messagingInstance: messaging,
                sharedPrefs: prefs,
              );
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              planner = ref.watch(notifyPlannerProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(syncCalls, 1);
      expect(planner.hasPendingTopicSyncInMemory, isTrue);
      expect(prefs.getBool(pendingTopicSyncKey), isTrue);

      // Pause then resume while retry is in flight -> only 1 additional call, deduped on second resume.
      inFlight = Completer<bool>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(syncCalls, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(syncCalls, 2);

      // Finish the in-flight call cleanly (still failing): the second resume arrived while in-flight,
      // so it triggers ONE follow-up retry (which still fails since useFakeSuccess is false), then stops.
      inFlight.complete(false);
      inFlight = null;
      await tester.pump();
      expect(syncCalls, 3);

      useFakeSuccess = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(syncCalls, 4);
      expect(planner.hasPendingTopicSyncInMemory, isFalse);
      expect(prefs.getBool(pendingTopicSyncKey), isNull);

      // Resuming again with nothing pending does NOT trigger another sync.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(syncCalls, 4);
    });
  });
}
