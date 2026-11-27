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
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];

  @override
  Future<void> subscribeToTopic(String topic) async {
    if (shouldThrow) throw Exception('network offline');
    subscribed.add(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
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

  group('PushMessaging.updateSubscriptions persistence', () {
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
  });

  group('NotifyPlanner FCM retry on connectivity reconnect', () {
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
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(pendingTopicSyncKey), isTrue);

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
      expect(sp.getBool(pendingTopicSyncKey), isNull);

      // Subsequent offline -> online with no pending flag does NOT call topicSync again.
      conn.add(false);
      await Future<void>.delayed(Duration.zero);
      conn.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(syncCalls, 2);
    });
  });
}
