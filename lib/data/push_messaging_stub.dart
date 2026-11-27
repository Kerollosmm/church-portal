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
}
