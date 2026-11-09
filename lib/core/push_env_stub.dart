// Stub implementation for non-web environments (Android APK / desktop).

import 'dart:async';

import '../domain/push.dart';

bool getIsSupported() => false;
String getPermission() => 'denied';
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

Future<bool> syncQuietHours({required bool enabled, required String start, required String end}) =>
    Future.value(false);

Stream<String> getDeepLinks() => const Stream.empty();

Stream<WebInboxItem> getInboxEvents() => const Stream.empty();
