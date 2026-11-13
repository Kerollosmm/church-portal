// Stub implementation for non-web environments (Android APK / desktop).

import 'dart:async';

import '../domain/push.dart';

Future<void> initPushStore() async {}
bool getIsSupported() => false;
String getPermission() => 'denied';
Future<String> refreshPermission() => Future.value('denied');
Future<bool> openSystemSettings() => Future.value(false);
Future<String> requestPermission() => Future.value('denied');
Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) => Future.value(false);

Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
    Future.value(null);

Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) =>
    Future.value(null);

Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) => Future.value(false);

Future<bool> showSwTestNotification({String? title, String? body, String? link}) => Future.value(false);

Future<List<WebInboxItem>> readInbox() => Future.value(const []);

Future<bool> clearInbox() => Future.value(false);

Future<bool> syncQuietHours({
  required bool enabled,
  required String start,
  required String end,
  bool remindersRespectQuietHours = true,
}) =>
    Future.value(false);

final _stubStorage = <String, String>{};
String? readStorage(String key) => _stubStorage[key];
void writeStorage(String key, String value) => _stubStorage[key] = value;

Stream<String> getDeepLinks() => const Stream.empty();

Stream<WebInboxItem> getInboxEvents() => const Stream.empty();
