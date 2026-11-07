// Domain logic for user-chosen event reminders (ADR-057).
// Pure Dart: no Flutter / web imports, so it is fully unit-tested.

/// Stable key generator for events that can be reminded.
class EventKey {
  EventKey._();

  static String liturgy(String id) => 'lit-$id';
  static String meeting(String id) => 'meeting-$id';
  static String dayEvent(String id) => 'day-$id';
  static String seasonService(String id) => 'season-$id';
  static String custom(String source, String id) => '$source-$id';
}

/// A user reminder scheduled on this device.
class Reminder {
  final String eventKey;
  final String? occurrence;
  final int lead;
  final bool every;
  final Map<String, String> title;
  final DateTime startsAt;
  final DateTime createdAt;

  const Reminder({
    required this.eventKey,
    this.occurrence,
    required this.lead,
    this.every = false,
    required this.title,
    required this.startsAt,
    required this.createdAt,
  });

  /// When the reminder should trigger.
  DateTime get fireTime => startsAt.subtract(Duration(minutes: lead));

  /// Whether the event has already started/passed.
  bool isExpired(DateTime now) => startsAt.isBefore(now);

  /// Unique composite identifier for this reminder instance.
  String get id => '$eventKey:${occurrence ?? 'all'}:$lead:${every ? 'every' : 'once'}';

  Map<String, dynamic> toJson() => {
        'eventKey': eventKey,
        'occurrence': occurrence,
        'lead': lead,
        'every': every,
        'title': title,
        'startsAt': startsAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final titleMap = <String, String>{};
    if (json['title'] is Map) {
      (json['title'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          titleMap[k.toString()] = v.toString();
        }
      });
    }

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is String) {
        try {
          return DateTime.parse(val);
        } catch (_) {}
      }
      return fallback;
    }

    return Reminder(
      eventKey: json['eventKey']?.toString() ?? '',
      occurrence: json['occurrence']?.toString(),
      lead: (json['lead'] is num) ? (json['lead'] as num).toInt() : 60,
      every: json['every'] == true,
      title: titleMap,
      startsAt: parseDate(json['startsAt'], DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      createdAt: parseDate(json['createdAt'], DateTime.now().toUtc()),
    );
  }

  Reminder copyWith({
    String? eventKey,
    String? occurrence,
    int? lead,
    bool? every,
    Map<String, String>? title,
    DateTime? startsAt,
    DateTime? createdAt,
  }) {
    return Reminder(
      eventKey: eventKey ?? this.eventKey,
      occurrence: occurrence ?? this.occurrence,
      lead: lead ?? this.lead,
      every: every ?? this.every,
      title: title ?? this.title,
      startsAt: startsAt ?? this.startsAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Reminder &&
          other.eventKey == eventKey &&
          other.occurrence == occurrence &&
          other.lead == lead &&
          other.every == every &&
          other.startsAt == startsAt;

  @override
  int get hashCode => Object.hash(eventKey, occurrence, lead, every, startsAt);
}

/// Reminder state after reconciliation against current server events.
enum ReminderState {
  scheduled,
  moved,
  changed,
  expired,
}

/// A classified reminder item with its reconciliation status.
class ReconciledItem {
  final Reminder reminder;
  final ReminderState state;
  final DateTime? newStartsAt;

  const ReconciledItem({
    required this.reminder,
    required this.state,
    this.newStartsAt,
  });
}

/// Reconciliation report.
class ReconciledReminders {
  final List<ReconciledItem> items;
  final List<Reminder> kept;
  final List<Reminder> moved;
  final List<Reminder> changed;
  final List<Reminder> expired;

  const ReconciledReminders({
    required this.items,
    required this.kept,
    required this.moved,
    required this.changed,
    required this.expired,
  });
}

/// Reconciles stored reminders against current live event occurrences.
///
/// [currentOccurrences] maps event keys (e.g. `'lit-123'` or `'lit-123:2027-04-30'`)
/// to their updated `startsAt` timestamps.
ReconciledReminders reconcileReminders(
  List<Reminder> stored,
  Map<String, DateTime> currentOccurrences,
  DateTime now,
) {
  final items = <ReconciledItem>[];
  final kept = <Reminder>[];
  final moved = <Reminder>[];
  final changed = <Reminder>[];
  final expired = <Reminder>[];

  for (final reminder in stored) {
    if (reminder.isExpired(now)) {
      items.add(ReconciledItem(reminder: reminder, state: ReminderState.expired));
      expired.add(reminder);
      continue;
    }

    // Lookup event by composite key first, then bare key.
    final compositeKey = '${reminder.eventKey}:${reminder.occurrence ?? 'all'}';
    final currentStartsAt = currentOccurrences[compositeKey] ?? currentOccurrences[reminder.eventKey];

    if (currentStartsAt == null) {
      // Event missing or removed from calendar
      items.add(ReconciledItem(reminder: reminder, state: ReminderState.changed));
      changed.add(reminder);
    } else if (currentStartsAt == reminder.startsAt) {
      // Unchanged
      items.add(ReconciledItem(reminder: reminder, state: ReminderState.scheduled));
      kept.add(reminder);
    } else {
      // Event time changed
      final updated = reminder.copyWith(startsAt: currentStartsAt);
      items.add(ReconciledItem(reminder: updated, state: ReminderState.moved, newStartsAt: currentStartsAt));
      moved.add(updated);
    }
  }

  return ReconciledReminders(
    items: items,
    kept: kept,
    moved: moved,
    changed: changed,
    expired: expired,
  );
}

/// Returns a localized display label for reminder lead times (minutes before event).
String leadLabel(int lead, String lang) {
  final isEn = lang.trim().toLowerCase() == 'en';
  switch (lead) {
    case 0:
      return isEn ? 'At event time' : 'في الموعد';
    case 5:
      return isEn ? '5 minutes before' : 'قبل ٥ دقائق';
    case 10:
      return isEn ? '10 minutes before' : 'قبل ١٠ دقائق';
    case 15:
      return isEn ? '15 minutes before' : 'قبل ١٥ دقيقة';
    case 30:
      return isEn ? '30 minutes before' : 'قبل ٣٠ دقيقة';
    case 60:
      return isEn ? '1 hour before' : 'قبل ساعة';
    case 120:
      return isEn ? '2 hours before' : 'قبل ساعتين';
    case 180:
      return isEn ? '3 hours before' : 'قبل ٣ ساعات';
    case 1440:
      return isEn ? '1 day before' : 'قبل يوم';
    default:
      if (lead >= 60 && lead % 60 == 0) {
        final hours = lead ~/ 60;
        return isEn ? '$hours hours before' : 'قبل $hours ساعات';
      }
      return isEn ? '$lead minutes before' : 'قبل $lead دقيقة';
  }
}
