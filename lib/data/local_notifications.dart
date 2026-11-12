// Local notifications wrapper interface and platform dispatcher (ADR-058 / PR B).

import 'package:material_ui/material_ui.dart';

import '../domain/notify_plan.dart';
import 'local_notifications_stub.dart'
    if (dart.library.io) 'local_notifications_io.dart';

export 'local_notifications_stub.dart' show LocalNotifierStub;
export 'local_notifications_stub.dart'
    if (dart.library.io) 'local_notifications_io.dart';

/// Notification color: church brand burgundy (#6E1C1C).
const notificationColor = Color(0xFF6E1C1C);

/// Small (status-bar) icon for local notifications: the white monochrome seal
/// (`res/drawable/ic_stat_seal.xml`, kept from resource shrinking by `res/raw/keep.xml`). The
/// full-colour launcher icon would render as a solid white square on Android 5+.
const notificationSmallIcon = 'ic_stat_seal';

/// Canonical notification channel IDs.
class NotificationChannels {
  NotificationChannels._();

  static const verse = 'verse';
  static const readings = 'readings';
  static const feasts = 'feasts';
  static const reminders = 'reminders';
  static const announcements = 'announcements';
  static const seasons = 'seasons';
}

/// Maps type names and aliases to the 6 canonical notification channels.
String resolveChannelId(String? id) {
  switch (id) {
    case NotificationChannels.verse:
    case 'verse_daily':
      return NotificationChannels.verse;
    case NotificationChannels.readings:
    case 'katameros_daily':
      return NotificationChannels.readings;
    case NotificationChannels.feasts:
      return NotificationChannels.feasts;
    case NotificationChannels.reminders:
      return NotificationChannels.reminders;
    case NotificationChannels.announcements:
      return NotificationChannels.announcements;
    case NotificationChannels.seasons:
      return NotificationChannels.seasons;
    default:
      return NotificationChannels.reminders;
  }
}

/// Abstract contract for scheduling and managing local notifications.
abstract class LocalNotifier {
  /// Creates the platform-appropriate notifier (IO implementation on Android/native,
  /// or no-op stub on Web).
  factory LocalNotifier({dynamic plugin}) => createLocalNotifier(plugin: plugin);

  /// Initializes notification plugin, callbacks, and notification channels.
  Future<void> initialize({void Function(String? payload)? onSelectNotification});

  /// Requests notification permission on Android 13+ (POST_NOTIFICATIONS).
  Future<bool> requestPermissions();

  /// Checks whether exact alarms can be scheduled (SCHEDULE_EXACT_ALARM).
  Future<bool> canScheduleExactAlarms();

  /// Schedules planned local notifications in Cairo wall-clock time.
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang});

  /// Cancels a specific scheduled notification by [id].
  Future<void> cancel(int id);

  /// Cancels all pending notifications.
  Future<void> cancelAll();

  /// Displays an instant notification immediately.
  Future<void> showInstant(
    int id,
    String title,
    String body, {
    String? channelId,
    String? payload,
  });

  /// Returns the count of pending scheduled notifications.
  Future<int> pendingCount();
}
