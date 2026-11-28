// Web / no-op stub implementation of PushMessaging (ADR-059).

import '../domain/push.dart';

const String pendingTopicSyncKey = 'church_portal_fcm_pending_sync';

class PushMessaging {
  const PushMessaging._();

  /// No-op initialization on web and non-supported platforms.
  static Future<void> initialize({void Function(String route)? onSelectRoute}) async {}

  /// No-op subscription updater on web.
  static Future<bool> updateSubscriptions(PushPrefs prefs, String lang) async => true;

  /// No-op pending topic sync check on web.
  static Future<bool> hasPendingTopicSync() async => false;

  /// No-op pending topic sync clear on web.
  static Future<void> clearPendingTopicSync() async {}

  /// No-op stored test topic lookup on web (web uses PushEnv storage).
  static Future<String?> getStoredTestTopic({Object? sharedPrefs}) async => null;

  /// No-op test topic subscription on web (web uses WebPushRepository).
  static Future<bool> subscribeTestTopic(
    String topic, {
    Object? messagingInstance,
    Object? sharedPrefs,
    Duration timeout = const Duration(seconds: 20),
  }) async =>
      false;

  /// No-op test topic unsubscription on web (web uses WebPushRepository).
  static Future<bool> unsubscribeTestTopic(
    String topic, {
    Object? messagingInstance,
    Object? sharedPrefs,
    Duration timeout = const Duration(seconds: 20),
  }) async =>
      false;
}
