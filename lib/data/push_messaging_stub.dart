// Web / no-op stub implementation of PushMessaging (ADR-059).

import '../domain/push.dart';

class PushMessaging {
  const PushMessaging._();

  /// No-op initialization on web and non-supported platforms.
  static Future<void> initialize({void Function(String route)? onSelectRoute}) async {}

  /// No-op subscription updater on web.
  static Future<void> updateSubscriptions(PushPrefs prefs, String lang) async {}
}
