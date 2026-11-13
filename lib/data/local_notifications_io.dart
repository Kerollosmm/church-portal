// Native (Android / IO) implementation of LocalNotifier (ADR-058 / PR B).

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/cairo_time.dart';
import '../domain/notify_plan.dart';
import 'local_notifications.dart';

/// Creates the native platform local notifier.
LocalNotifier createLocalNotifier({dynamic plugin}) =>
    LocalNotifierImpl(plugin: plugin as FlutterLocalNotificationsPlugin?);

/// Concrete Android/IO implementation using [FlutterLocalNotificationsPlugin].
class LocalNotifierImpl implements LocalNotifier {
  final FlutterLocalNotificationsPlugin _plugin;

  LocalNotifierImpl({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Canonical 6 notification channels configured for the church app.
  static const channels = [
    AndroidNotificationChannel(
      NotificationChannels.verse,
      'آية اليوم',
      description: 'Daily verse',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      NotificationChannels.readings,
      'قراءات القطمارس',
      description: 'Katameros readings',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      NotificationChannels.feasts,
      'أعياد وتذكارات',
      description: 'Feasts & commemorations',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      NotificationChannels.reminders,
      'تذكيراتي',
      description: 'Event reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      NotificationChannels.announcements,
      'تنويهات وأخبار',
      description: 'Announcements & news',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      NotificationChannels.seasons,
      'مواسم وأعياد خاصة',
      description: 'Seasons & special occasions',
      importance: Importance.defaultImportance,
    ),
  ];

  static AndroidNotificationChannel _channelFor(String channelId) {
    final resolved = resolveChannelId(channelId);
    return channels.firstWhere(
      (c) => c.id == resolved,
      orElse: () => channels[3], // default: reminders
    );
  }

  @override
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {
    const androidSettings = AndroidInitializationSettings(notificationSmallIcon);
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        onSelectNotification?.call(response.payload);
      },
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (final channel in channels) {
        try {
          await androidPlugin.createNotificationChannel(channel);
        } catch (_) {}
      }
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final macPlugin =
        _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    if (macPlugin != null) {
      final granted = await macPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.linux) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return (await androidPlugin.areNotificationsEnabled()) ?? false;
      }

      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final perms = await iosPlugin.checkPermissions();
        return perms?.isEnabled ?? false;
      }

      final macPlugin =
          _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (macPlugin != null) {
        final perms = await macPlugin.checkPermissions();
        return perms?.isEnabled ?? false;
      }

      if (defaultTargetPlatform == TargetPlatform.linux) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<String?> getLaunchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        return details.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final can = await androidPlugin.canScheduleExactNotifications();
      return can ?? true; // On Android < 12, exact alarms do not require permission.
    }
    return true;
  }

  @override
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang}) async {
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      try {
        await _plugin.cancelAll();
      } catch (_) {}
    }

    final now = DateTime.now();
    final useEnglish = lang == 'en';

    for (final n in plan) {
      if (n.scheduledAt.isBefore(now)) continue;

      final tzDate = tz.TZDateTime.from(n.scheduledAt, CairoTime.location);
      final scheduleMode = n.exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          // Daily types (and the reminder fallback) must still fire in Doze, within ~10 min
          // (PR B §3.2 «Exactness»); plain `inexact` waits for the next maintenance window.
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final channel = _channelFor(n.channelId);

      final title = useEnglish && n.titleEn.trim().isNotEmpty ? n.titleEn : n.titleAr;
      final body = useEnglish && n.bodyEn.trim().isNotEmpty ? n.bodyEn : n.bodyAr;

      final androidDetails = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: channel.importance == Importance.high ? Priority.high : Priority.defaultPriority,
        color: notificationColor,
        icon: notificationSmallIcon,
        playSound: n.silent ? false : channel.playSound,
        enableVibration: n.silent ? false : channel.enableVibration,
        silent: n.silent,
      );

      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: false,
        presentSound: !n.silent,
      );
      const linuxDetails = LinuxNotificationDetails();

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: linuxDetails,
      );

      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
            id: n.id,
            title: title,
            body: body,
            scheduledDate: tzDate,
            notificationDetails: details,
            androidScheduleMode: mode,
            payload: n.payload ?? '',
          );
      try {
        await schedule(scheduleMode);
      } catch (_) {
        // Exact-alarm access can be revoked between the planner's check and this call
        // (`exact_alarms_not_permitted`): the reminder still rings, approximately.
        if (n.exact) {
          try {
            await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
          } catch (_) {}
        }
      }
    }
  }

  @override
  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  @override
  Future<void> showInstant(
    int id,
    String title,
    String body, {
    String? channelId,
    String? payload,
  }) async {
    final channel = _channelFor(channelId ?? NotificationChannels.reminders);
    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.importance == Importance.high ? Priority.high : Priority.defaultPriority,
      color: notificationColor,
      icon: notificationSmallIcon,
      playSound: channel.playSound,
      enableVibration: channel.enableVibration,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails();

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: linuxDetails,
      ),
      payload: payload,
    );
  }

  @override
  Future<int> pendingCount() async {
    try {
      final list = await _plugin.pendingNotificationRequests();
      return list.length;
    } catch (_) {
      return 0;
    }
  }
}
