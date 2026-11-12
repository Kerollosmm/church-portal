import 'dart:async';
import 'dart:convert';

import '../domain/push.dart';
import 'push_env_stub.dart'
    if (dart.library.js_interop) 'push_env_web.dart' as impl;

/// Storage key in localStorage for notification preferences.
const pushStorageKey = 'church_portal_push';

/// Storage key in localStorage for Web Push token & topic sync state.
const webPushStorageKey = 'church_portal_push_web';

/// Parsed summary of persisted Web Push storage state.
class WebPushStorageState {
  final String? syncedToken;
  final bool pendingSync;

  const WebPushStorageState({this.syncedToken, this.pendingSync = false});
}

/// Parses [webPushStorageKey] from [env] safely using `jsonDecode`.
WebPushStorageState? readWebPushStorageState(PushEnv env) {
  final raw = env.readStorage(webPushStorageKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final token = decoded['syncedToken'];
    return WebPushStorageState(
      syncedToken: token is String && token.isNotEmpty ? token : null,
      pendingSync: decoded['pendingSync'] == true,
    );
  } catch (_) {
    return null;
  }
}

/// Returns `true` when persisted Web Push state has both a token and pending sync.
bool hasPendingWebPushSync(PushEnv env) {
  final state = readWebPushStorageState(env);
  return state != null && state.pendingSync && state.syncedToken != null;
}

/// Abstraction over browser push notification capabilities.
abstract class PushEnv {
  const PushEnv();

  bool get isSupported;
  String get permission;
  Future<String> requestPermission();
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link});

  // Web push extensions (ADR-060)
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig});
  Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig});
  Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig});
  Future<bool> showSwTestNotification({String? title, String? body, String? link});
  Future<List<WebInboxItem>> readInbox();
  Future<bool> clearInbox();
  Future<bool> syncQuietHours({
    required bool enabled,
    required String start,
    required String end,
    bool remindersRespectQuietHours = true,
  });
  String? readStorage(String key) => null;
  void writeStorage(String key, String value) {}
  Stream<String> get deepLinks;
  Stream<WebInboxItem> get inboxEvents;
}

/// Default platform push environment.
class PlatformPushEnv extends PushEnv {
  const PlatformPushEnv();

  @override
  bool get isSupported => impl.getIsSupported();

  @override
  String get permission => impl.getPermission();

  @override
  Future<String> requestPermission() => impl.requestPermission();

  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) =>
      impl.showLocalNotification(title, body, icon: icon, link: link);

  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
      impl.enableAndGetToken(vapidKey: vapidKey, firebaseConfig: firebaseConfig);

  @override
  Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
      impl.getWebToken(vapidKey: vapidKey, firebaseConfig: firebaseConfig);

  @override
  Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) =>
      impl.deleteWebToken(firebaseConfig: firebaseConfig);

  @override
  Future<bool> showSwTestNotification({String? title, String? body, String? link}) =>
      impl.showSwTestNotification(title: title, body: body, link: link);

  @override
  Future<List<WebInboxItem>> readInbox() => impl.readInbox();

  @override
  Future<bool> clearInbox() => impl.clearInbox();

  @override
  Future<bool> syncQuietHours({
    required bool enabled,
    required String start,
    required String end,
    bool remindersRespectQuietHours = true,
  }) =>
      impl.syncQuietHours(
        enabled: enabled,
        start: start,
        end: end,
        remindersRespectQuietHours: remindersRespectQuietHours,
      );

  @override
  String? readStorage(String key) => impl.readStorage(key);

  @override
  void writeStorage(String key, String value) => impl.writeStorage(key, value);

  @override
  Stream<String> get deepLinks => impl.getDeepLinks();

  @override
  Stream<WebInboxItem> get inboxEvents => impl.getInboxEvents();
}
