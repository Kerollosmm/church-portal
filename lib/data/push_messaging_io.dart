// Native (Android / IO) FCM push messaging client (ADR-059).

import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notify_plan.dart';
import '../domain/push.dart';
import '../firebase_options.dart';
import 'local_notifications.dart';

const String seenNidsKey = 'church_portal_seen_nids';
const String pendingTopicSyncKey = 'church_portal_fcm_pending_sync';
const int maxSeenNids = 100;

/// Background FCM message entry point. Annotated with `@pragma('vm:entry-point')`
/// to prevent Dart AOT compiler from tree-shaking it when running in background isolate.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    final opts = DefaultFirebaseOptions.currentPlatformOrNull;
    if (opts != null) {
      try {
        await Firebase.initializeApp(options: opts);
      } catch (_) {}
    }
  }
  await PushMessaging.handleIncomingMessage(message);
}

class PushMessaging {
  const PushMessaging._();

  static const Duration topicSyncTimeout = Duration(seconds: 20);

  static void Function(String route)? _onSelectRoute;
  static bool _initializedInMainIsolate = false;

  /// Handles incoming remote FCM message (both foreground and background isolates).
  /// Returns `true` if notification was accepted and presented, `false` if dropped by guard/dedup.
  static Future<bool> handleIncomingMessage(
    RemoteMessage message, {
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferences? prefs,
    void Function(String route)? onSelectRoute,
  }) async {
    // 1. Client Guard: Only remote-owned types ('announcements' and 'seasons') are processed.
    // Local types ('verse_daily', 'katameros_daily', 'feasts', 'reminders') are strictly local on native apps.
    final type = message.data['type']?.toString().trim();
    if (type != 'announcements' && type != 'seasons') {
      return false;
    }

    // 2. Seen NID Ring-Buffer Deduplication (up to 100 entries).
    final nid = message.data['nid']?.toString().trim();
    if (nid != null && nid.isNotEmpty) {
      final sp = prefs ?? await SharedPreferences.getInstance();
      final seenList = sp.getStringList(seenNidsKey) ?? <String>[];
      if (seenList.contains(nid)) {
        return false;
      }
      final updatedList = List<String>.of(seenList)..add(nid);
      if (updatedList.length > maxSeenNids) {
        updatedList.removeRange(0, updatedList.length - maxSeenNids);
      }
      await sp.setStringList(seenNidsKey, updatedList);
    }

    // 3. Slot Sharing: 'event:X' slot when eventKey is provided.
    // An admin push for event X shares the exact same slot ID as an event reminder for X,
    // so they replace rather than stack on the device.
    final eventKey = message.data['eventKey']?.toString().trim();
    final int notifId;
    if (eventKey != null && eventKey.isNotEmpty) {
      notifId = notificationIdFor('event:$eventKey');
    } else if (nid != null && nid.isNotEmpty) {
      notifId = notificationIdFor('push:$nid');
    } else {
      notifId = notificationIdFor('push:${message.messageId ?? DateTime.now().millisecondsSinceEpoch}');
    }

    // 4. Resolve notification channel.
    final channelId = type == 'seasons'
        ? NotificationChannels.seasons
        : NotificationChannels.announcements;

    // 5. Extract and validate content.
    final title = (message.data['title']?.toString() ?? message.notification?.title ?? '').trim();
    final body = (message.data['body']?.toString() ?? message.notification?.body ?? '').trim();
    final rawLink = message.data['link']?.toString();
    final link = safeNotificationLink(rawLink);

    if (title.isEmpty && body.isEmpty) {
      return false;
    }

    // 6. Present notification via FlutterLocalNotificationsPlugin.
    final fln = plugin ?? FlutterLocalNotificationsPlugin();
    final channel = channelId == NotificationChannels.seasons
        ? const AndroidNotificationChannel(
            NotificationChannels.seasons,
            'مواسم وأعياد خاصة',
            description: 'Seasons & special occasions',
            importance: Importance.defaultImportance,
          )
        : const AndroidNotificationChannel(
            NotificationChannels.announcements,
            'تنويهات وأخبار',
            description: 'Announcements & news',
            importance: Importance.high,
          );

    final effectiveSelect = onSelectRoute ?? _onSelectRoute;
    if (plugin == null && !_initializedInMainIsolate) {
      const androidInit = AndroidInitializationSettings(notificationSmallIcon);
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxInit = LinuxInitializationSettings(defaultActionName: 'Open');
      try {
        await fln.initialize(
          settings: const InitializationSettings(
            android: androidInit,
            iOS: darwinInit,
            macOS: darwinInit,
            linux: linuxInit,
          ),
          onDidReceiveNotificationResponse: effectiveSelect == null
              ? null
              : (NotificationResponse response) {
                  final raw = response.payload?.trim() ?? '';
                  if (raw.isEmpty) return;
                  final route = notificationRouteFromPayload(raw);
                  if (route.isNotEmpty) effectiveSelect(route);
                },
        );
        final androidPlugin =
            fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(channel);
      } catch (_) {}
    }

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.importance == Importance.high ? Priority.high : Priority.defaultPriority,
      color: notificationColor,
      icon: notificationSmallIcon,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails();

    await fln.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: linuxDetails,
      ),
      payload: link,
    );

    return true;
  }

  /// Initializes native Firebase Messaging listeners and foreground presentation.
  static Future<void> initialize({void Function(String route)? onSelectRoute}) async {
    if (kIsWeb) return;
    _onSelectRoute = onSelectRoute;
    _initializedInMainIsolate = true;
    try {
      final messaging = FirebaseMessaging.instance;

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Foreground presentation is handled uniformly by handleIncomingMessage
      // (with seenNids deduplication and local-type filtering); disabling iOS
      // system foreground presentation avoids duplicate banners when aps.alert is set.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        handleIncomingMessage(message, onSelectRoute: onSelectRoute ?? _onSelectRoute);
      });

      // App opened from notification in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data.isEmpty) return;
        final route = notificationRouteFromPayload(jsonEncode(message.data));
        if (route.isNotEmpty) {
          (onSelectRoute ?? _onSelectRoute)?.call(route);
        }
      });

      // App launched from terminated state via notification tap
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && initialMessage.data.isNotEmpty) {
        final route = notificationRouteFromPayload(jsonEncode(initialMessage.data));
        if (route.isNotEmpty && route != '/') {
          (onSelectRoute ?? _onSelectRoute)?.call(route);
        }
      }
    } catch (_) {
      // Ignore if Firebase Messaging is not available (e.g. without google-services on test device)
    }
  }

  static Future<bool> hasPendingTopicSync({SharedPreferences? prefs}) async {
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      return sp.getBool(pendingTopicSyncKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearPendingTopicSync({SharedPreferences? prefs}) async {
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      await sp.remove(pendingTopicSyncKey);
    } catch (_) {}
  }

  /// Synchronizes Android topic subscriptions with user PushPrefs and language.
  /// Returns `true` when all topic updates succeed, or persists
  /// [pendingTopicSyncKey] and returns `false` on error so [NotifyPlanner]
  /// can retry on reconnect or app resume.
  static Future<bool> updateSubscriptions(
    PushPrefs prefs,
    String lang, {
    FirebaseMessaging? messagingInstance,
    SharedPreferences? sharedPrefs,
    Duration timeout = topicSyncTimeout,
  }) async {
    if (kIsWeb) return true;
    try {
      final messaging = messagingInstance ?? FirebaseMessaging.instance;
      final effectiveLang = lang == 'en' ? 'en' : 'ar';
      final otherLang = effectiveLang == 'en' ? 'ar' : 'en';

      // Announcements
      if (prefs.types.contains(NotifyType.announcements)) {
        await messaging.subscribeToTopic('app_announcements_$effectiveLang').timeout(timeout);
        await messaging.unsubscribeFromTopic('app_announcements_$otherLang').timeout(timeout);
      } else {
        await messaging.unsubscribeFromTopic('app_announcements_ar').timeout(timeout);
        await messaging.unsubscribeFromTopic('app_announcements_en').timeout(timeout);
      }

      // Seasons
      if (prefs.types.contains(NotifyType.seasons)) {
        await messaging.subscribeToTopic('app_seasons_$effectiveLang').timeout(timeout);
        await messaging.unsubscribeFromTopic('app_seasons_$otherLang').timeout(timeout);
      } else {
        await messaging.unsubscribeFromTopic('app_seasons_ar').timeout(timeout);
        await messaging.unsubscribeFromTopic('app_seasons_en').timeout(timeout);
      }
      await clearPendingTopicSync(prefs: sharedPrefs);
      return true;
    } catch (_) {
      // Persist pending sync flag so reconnect or resume can retry (single writer).
      try {
        final sp = sharedPrefs ?? await SharedPreferences.getInstance();
        await sp.setBool(pendingTopicSyncKey, true);
      } catch (_) {}
      return false;
    }
  }

  /// Reads the currently enrolled test push topic from local preferences, if valid.
  static Future<String?> getStoredTestTopic({SharedPreferences? sharedPrefs}) async {
    if (kIsWeb) return null;
    try {
      final sp = sharedPrefs ?? await SharedPreferences.getInstance();
      final raw = sp.getString(testPushTopicStorageKey)?.trim();
      return (raw != null && isValidTestPushTopic(raw)) ? raw : null;
    } catch (_) {
      return null;
    }
  }

  /// Subscribes this device to a validated `test_*` FCM topic and stores it locally.
  /// Unsubscribes from any different previously stored test topic first.
  static Future<bool> subscribeTestTopic(
    String topic, {
    FirebaseMessaging? messagingInstance,
    SharedPreferences? sharedPrefs,
    Duration timeout = topicSyncTimeout,
  }) async {
    if (kIsWeb) return false;
    final normalized = normalizeTestPushTopic(topic);
    if (normalized == null) return false;
    try {
      final sp = sharedPrefs ?? await SharedPreferences.getInstance();
      final messaging = messagingInstance ?? FirebaseMessaging.instance;
      final previous = sp.getString(testPushTopicStorageKey)?.trim();
      if (previous != null &&
          previous.isNotEmpty &&
          previous != normalized &&
          isValidTestPushTopic(previous)) {
        await messaging.unsubscribeFromTopic(previous).timeout(timeout);
      }
      await messaging.subscribeToTopic(normalized).timeout(timeout);
      await sp.setString(testPushTopicStorageKey, normalized);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unsubscribes this device from [topic] (and any stored test topic) and clears storage.
  static Future<bool> unsubscribeTestTopic(
    String topic, {
    FirebaseMessaging? messagingInstance,
    SharedPreferences? sharedPrefs,
    Duration timeout = topicSyncTimeout,
  }) async {
    if (kIsWeb) return false;
    final trimmed = topic.trim();
    final normalized = trimmed.isEmpty ? null : normalizeTestPushTopic(trimmed);
    if (trimmed.isNotEmpty && normalized == null) return false;
    try {
      final sp = sharedPrefs ?? await SharedPreferences.getInstance();
      final stored = sp.getString(testPushTopicStorageKey)?.trim();
      final targets = <String>{
        ?normalized,
        if (stored != null && isValidTestPushTopic(stored)) stored,
      };
      if (targets.isNotEmpty) {
        final messaging = messagingInstance ?? FirebaseMessaging.instance;
        for (final t in targets) {
          await messaging.unsubscribeFromTopic(t).timeout(timeout);
        }
      }
      await sp.remove(testPushTopicStorageKey);
      return true;
    } catch (_) {
      return false;
    }
  }
}
