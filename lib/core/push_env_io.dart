// Native (Android / iOS / desktop IO) implementation of PushEnv (ADR-058 / ADR-059).

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/local_notifications.dart';
import '../domain/notify_plan.dart';
import '../domain/push.dart';

const _deviceChannel = MethodChannel('church_portal/device');
const _pushAskedKey = 'church_portal_notif_asked';

SharedPreferences? _prefs;
final Map<String, String> _memory = {};
bool _memoryAsked = false;
String _cachedPermission = 'default';

/// Loads native notification permission state before the first frame so
/// synchronous readers (`PushEnv.permission`) start with the true OS state.
Future<void> initPushStore() async {
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  await refreshPermission();
}

bool getIsSupported() =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

String getPermission() => getIsSupported() ? _cachedPermission : 'denied';

Future<bool> _osNotificationsAllowed() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final diag = await _deviceChannel.invokeMapMethod<dynamic, dynamic>('getDiagnostics');
      if (diag != null && diag.containsKey('notificationsAllowed')) {
        return diag['notificationsAllowed'] == true;
      }
    } catch (_) {}
  }
  return await LocalNotifier().areNotificationsEnabled();
}

/// Re-queries the operating system notification permission and updates the cached status.
Future<String> refreshPermission() async {
  if (!getIsSupported()) {
    _cachedPermission = 'denied';
    return _cachedPermission;
  }
  final allowed = await _osNotificationsAllowed();
  if (allowed) {
    _cachedPermission = 'granted';
    return _cachedPermission;
  }
  var asked = _memoryAsked;
  try {
    asked = _prefs?.getBool(_pushAskedKey) ?? _memoryAsked;
  } catch (_) {}
  _cachedPermission = asked ? 'denied' : 'default';
  return _cachedPermission;
}

Future<String> requestPermission() async {
  if (!getIsSupported()) {
    _cachedPermission = 'denied';
    return _cachedPermission;
  }
  _memoryAsked = true;
  try {
    await _prefs?.setBool(_pushAskedKey, true);
  } catch (_) {}

  bool granted = false;
  try {
    granted = await LocalNotifier().requestPermissions();
  } catch (_) {}

  if (!granted) {
    granted = await _osNotificationsAllowed();
  }
  _cachedPermission = granted ? 'granted' : 'denied';
  return _cachedPermission;
}

/// Opens the system app notification / details settings screen when supported.
Future<bool> openSystemSettings() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final ok = await _deviceChannel.invokeMethod<bool>('openAppSettings');
      return ok ?? true;
    } catch (_) {
      return false;
    }
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      return await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {
      return false;
    }
  }
  return false;
}

Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async {
  try {
    var perm = await refreshPermission();
    if (perm != 'granted') {
      perm = await requestPermission();
      if (perm != 'granted') return false;
    }
    final payload = (link != null && link.isNotEmpty) ? safeNotificationLink(link) : '/notifications';
    final id = notificationIdFor('instant:${DateTime.now().millisecondsSinceEpoch}');
    await LocalNotifier().showInstant(
      id,
      title,
      body,
      channelId: NotificationChannels.reminders,
      payload: payload,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
    Future.value(null);

Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
    Future.value(null);

Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) => Future.value(false);

Future<bool> showSwTestNotification({String? title, String? body, String? link}) =>
    showLocalNotification(
      title ?? 'اختبار الإشعارات',
      body ?? 'تم إرسال إشعار تجريبي بنجاح',
      link: link,
    );

Future<List<WebInboxItem>> readInbox() => Future.value(const []);

Future<bool> clearInbox() => Future.value(false);

Future<bool> syncQuietHours({
  required bool enabled,
  required String start,
  required String end,
  bool remindersRespectQuietHours = true,
}) =>
    Future.value(false);

String? readStorage(String key) {
  try {
    return _prefs?.getString(key) ?? _memory[key];
  } catch (_) {
    return _memory[key];
  }
}

void writeStorage(String key, String value) {
  _memory[key] = value;
  try {
    _prefs?.setString(key, value).catchError((_) => false);
  } catch (_) {}
}

Stream<String> getDeepLinks() => const Stream.empty();

Stream<WebInboxItem> getInboxEvents() => const Stream.empty();
