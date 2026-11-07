import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/reminders.dart';

/// Storage key for user reminders on device.
const remindersStorageKey = 'church_portal_reminders';

/// Maximum allowed reminders per device to prevent unbounded storage or scheduling.
const int maxDeviceReminders = 30;

/// Outcome of [ReminderStore.put].
enum ReminderPutResult {
  /// Saved on this device.
  ok,

  /// A new reminder would exceed [maxDeviceReminders]; nothing changed.
  full,

  /// Device storage refused the write (private mode, quota, disabled
  /// storage); nothing was saved.
  storageError,
}

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

  /// Adds or updates a reminder (same event key and exact occurrence).
  ///
  /// [replacing], when given, is the reminder being edited: it is removed in
  /// the same write (e.g. switching «هذه المرة فقط» to «كل مرة» changes the
  /// stored occurrence). Reports [ReminderPutResult.full] when a new reminder
  /// would exceed [maxDeviceReminders] and [ReminderPutResult.storageError]
  /// when device storage refuses the write.
  ReminderPutResult put(Reminder reminder, {Reminder? replacing}) {
    final current = List<Reminder>.of(load());
    if (replacing != null) {
      current.removeWhere((r) => r.eventKey == replacing.eventKey && r.occurrence == replacing.occurrence);
    }
    final index = current.indexWhere((r) => r.eventKey == reminder.eventKey && r.occurrence == reminder.occurrence);

    if (index >= 0) {
      current[index] = reminder;
    } else {
      if (current.length >= maxDeviceReminders) return ReminderPutResult.full;
      current.add(reminder);
    }
    return save(current) ? ReminderPutResult.ok : ReminderPutResult.storageError;
  }

  /// Removes a reminder by eventKey and occurrence (strict match).
  void remove(String eventKey, {String? occurrence}) {
    final current = List<Reminder>.of(load());
    current.removeWhere((r) => r.eventKey == eventKey && r.occurrence == occurrence);
    save(current);
  }

  /// Removes all reminders whose event has passed (recurring «كل مرة»
  /// reminders never expire; see [Reminder.isExpired]).
  void clearExpired(DateTime now) {
    final current = List<Reminder>.of(load());
    current.removeWhere((r) => r.isExpired(now));
    save(current);
  }

  /// Finds the reminder covering the given event occurrence: the exact
  /// occurrence first (strict, `null` matches only `null`), else a recurring
  /// reminder for the event.
  Reminder? find(String eventKey, {String? occurrence}) => findIn(load(), eventKey, occurrence: occurrence);

  /// As [find], on an already loaded list.
  ///
  /// [startsAt], when given, is the occurrence the caller shows: a one-off
  /// reminder stored without an occurrence (a weekly item's «هذه المرة فقط»)
  /// matches only when it is for that same Cairo calendar date, so last
  /// week's one-off is not reported as set on next week's card.
  static Reminder? findIn(List<Reminder> list, String eventKey, {String? occurrence, DateTime? startsAt}) {
    Reminder? recurring;
    for (final r in list) {
      if (r.eventKey != eventKey) continue;
      if (r.occurrence == occurrence &&
          (r.every || occurrence != null || startsAt == null || _sameCairoDay(r.startsAt, startsAt))) {
        return r;
      }
      if (r.every) recurring ??= r;
    }
    return recurring;
  }

  static bool _sameCairoDay(DateTime a, DateTime b) {
    final x = CairoTime.fromInstant(a), y = CairoTime.fromInstant(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}
