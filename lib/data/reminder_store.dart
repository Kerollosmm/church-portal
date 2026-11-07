import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/domain/reminders.dart';

/// Storage key for user reminders on device.
const remindersStorageKey = 'church_portal_reminders';

/// Maximum allowed reminders per device to prevent unbounded storage or scheduling.
const int maxDeviceReminders = 30;

/// Manages persistent storage of event reminders on the device.
class ReminderStore {
  final InstallEnv env;

  ReminderStore({this.env = const PlatformInstallEnv()});

  /// Loads stored reminders sorted by next fire time.
  List<Reminder> load() {
    try {
      final json = env.readJson(remindersStorageKey);
      if (json == null) return const [];
      final rawList = json['reminders'];
      if (rawList is! List) return const [];

      final reminders = <Reminder>[];
      for (final item in rawList) {
        if (item is Map) {
          reminders.add(Reminder.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      reminders.sort((a, b) => a.fireTime.compareTo(b.fireTime));
      return reminders;
    } catch (_) {
      return const [];
    }
  }

  /// Saves the complete list of reminders.
  ///
  /// Returns `true` if saved successfully, `false` on storage errors.
  bool save(List<Reminder> reminders) {
    try {
      final capped = reminders.take(maxDeviceReminders).toList();
      capped.sort((a, b) => a.fireTime.compareTo(b.fireTime));
      env.writeJson(remindersStorageKey, {
        'reminders': capped.map((r) => r.toJson()).toList(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Adds or updates a reminder.
  ///
  /// Returns `false` if adding a new reminder would exceed [maxDeviceReminders]
  /// or if writing to device storage fails.
  bool put(Reminder reminder) {
    final current = List<Reminder>.of(load());
    final index = current.indexWhere((r) => r.eventKey == reminder.eventKey && r.occurrence == reminder.occurrence);

    if (index >= 0) {
      current[index] = reminder;
      return save(current);
    }

    if (current.length >= maxDeviceReminders) {
      return false;
    }

    current.add(reminder);
    return save(current);
  }

  /// Removes a reminder by eventKey and occurrence (strict match).
  void remove(String eventKey, {String? occurrence}) {
    final current = List<Reminder>.of(load());
    current.removeWhere((r) => r.eventKey == eventKey && r.occurrence == occurrence);
    save(current);
  }

  /// Removes all reminders whose event has passed.
  void clearExpired(DateTime now) {
    final current = List<Reminder>.of(load());
    current.removeWhere((r) => r.isExpired(now));
    save(current);
  }

  /// Finds a reminder for the given event, matching exact occurrence.
  Reminder? find(String eventKey, {String? occurrence}) {
    final current = load();
    for (final r in current) {
      if (r.eventKey == eventKey && r.occurrence == occurrence) {
        return r;
      }
    }
    return null;
  }
}
