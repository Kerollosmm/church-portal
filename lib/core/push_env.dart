import 'dart:async';

import '../domain/push.dart';
import 'push_env_stub.dart'
    if (dart.library.js_interop) 'push_env_web.dart' as impl;

/// Storage key in localStorage for notification preferences.
const pushStorageKey = 'church_portal_push';

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
  Future<bool> syncQuietHours({required bool enabled, required String start, required String end});
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
  Future<bool> syncQuietHours({required bool enabled, required String start, required String end}) =>
      impl.syncQuietHours(enabled: enabled, start: start, end: end);

  @override
  Stream<String> get deepLinks => impl.getDeepLinks();

  @override
  Stream<WebInboxItem> get inboxEvents => impl.getInboxEvents();
}
