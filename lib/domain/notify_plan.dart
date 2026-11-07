// Pure Dart domain logic for local notification planning on Android (ADR-058 / PR B).
// Schedules local-owned notification types (verse, Katameros, feasts, reminders).
// All time computations run on Africa/Cairo wall-clock time via CairoTime.

import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;

import 'cairo_time.dart';
import 'coptic_feasts.dart';
import 'daily_verse.dart';
import 'features.dart';
import 'models.dart';
import 'readings.dart';
import 'reminders.dart';
import 'schedule.dart';
import 'season_verses.dart';
import 'time_format.dart';
import 'today.dart';

typedef ChurchEvent = DayEvent;

/// A concrete meeting occurrence for reminder scheduling.
class MeetingOccurrence {
  final Meeting meeting;
  final DateTime start;
  final DateTime end;
  final int dayOffset;

  const MeetingOccurrence(this.meeting, this.start, this.end, [this.dayOffset = 0]);
}

/// A planned notification ready to be scheduled on the Android device.
class PlannedNotification {
  final int id;
  final String key;
  final NotifyType type;
  final DateTime scheduledAt;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String? payload;
  final bool exact;
  final String channelId;
  final bool silent;

  const PlannedNotification({
    required this.id,
    required this.key,
    required this.type,
    required this.scheduledAt,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    this.payload,
    this.exact = false,
    required this.channelId,
    this.silent = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'type': type.name,
        'scheduledAt': scheduledAt.toIso8601String(),
        'titleAr': titleAr,
        'titleEn': titleEn,
        'bodyAr': bodyAr,
        'bodyEn': bodyEn,
        if (payload != null) 'payload': payload,
        'exact': exact,
        'channelId': channelId,
        if (silent) 'silent': silent,
      };

  factory PlannedNotification.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String?;
    final type = NotifyType.tryParse(rawType) ?? NotifyType.verse_daily;
    return PlannedNotification(
      id: (json['id'] as num).toInt(),
      key: json['key'] as String? ?? '',
      type: type,
      scheduledAt: CairoTime.fromInstant(DateTime.parse(json['scheduledAt'] as String)),
      titleAr: json['titleAr'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      bodyAr: json['bodyAr'] as String? ?? '',
      bodyEn: json['bodyEn'] as String? ?? '',
      payload: json['payload'] as String?,
      exact: json['exact'] == true,
      channelId: json['channelId'] as String? ?? type.name,
      silent: json['silent'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannedNotification &&
          other.id == id &&
          other.key == key &&
          other.type == type &&
          other.scheduledAt.isAtSameMomentAs(scheduledAt) &&
          other.titleAr == titleAr &&
          other.titleEn == titleEn &&
          other.bodyAr == bodyAr &&
          other.bodyEn == bodyEn &&
          other.payload == payload &&
          other.exact == exact &&
          other.channelId == channelId &&
          other.silent == silent;

  @override
  int get hashCode => Object.hash(
        id,
        key,
        type,
        scheduledAt.millisecondsSinceEpoch,
        titleAr,
        titleEn,
        bodyAr,
        bodyEn,
        payload,
        exact,
        channelId,
        silent,
      );

  @override
  String toString() =>
      'PlannedNotification(id: $id, key: $key, type: ${type.name}, at: $scheduledAt, exact: $exact)';
}

/// Deterministic 31-bit positive integer hash of [key] in [0, 2147483647].
int notificationIdFor(String key) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Evaluates whether [moment] falls within quiet hours [fromHm]..[toHm],
/// and calculates the end moment when quiet hours finish.
(bool inside, tz.TZDateTime nextEnd) evaluateQuietHours(
  tz.TZDateTime moment,
  String fromHm,
  String toHm,
) {
  final fromM = parseHm(fromHm) ?? 22 * 60;
  final toM = parseHm(toHm) ?? 7 * 60;
  final minuteOfDay = moment.hour * 60 + moment.minute;

  if (fromM <= toM) {
    // Single-day window (e.g. 01:00 to 06:00)
    final inside = minuteOfDay >= fromM && minuteOfDay < toM;
    final endMoment = CairoTime.at(moment.year, moment.month, moment.day, toM);
    return (inside, endMoment);
  } else {
    // Crosses midnight (e.g. 22:00 to 07:00)
    final inside = minuteOfDay >= fromM || minuteOfDay < toM;
    final endDay = minuteOfDay >= fromM ? moment.day + 1 : moment.day;
    final endMoment = CairoTime.at(moment.year, moment.month, endDay, toM);
    return (inside, endMoment);
  }
}

/// Plans pending local notifications on Android for a rolling ~9-day window.
///
/// Only local-owned Android types are scheduled (`verse_daily`, `katameros_daily`,
/// `feasts`, `reminders`). Remote-owned FCM types (`announcements`, `seasons`)
/// are never emitted.
List<PlannedNotification> planNotifications({
  required DateTime now,
  required PushPrefs prefs,
  required FeatureSettings features,
  required List<Reminder> reminders,
  required DailyVerseConfig verseConfig,
  required List<Verse> verses,
  required List<LiturgyOccurrence> liturgies,
  required List<MeetingOccurrence> meetings,
  required List<ChurchEvent> dayEvents,
  required Map<String, DayReadings> cachedReadings,
  required List<CopticFeast> computedFeasts,
  bool exactAlarmsAllowed = true,
  List<Season> seasons = const [],
}) {
  CairoTime.ensureInitialized();
  final cairoNow = CairoTime.fromInstant(now);

  final offered = features.pushSettings.offered;
  bool isLocalTypeAllowed(NotifyType type) {
    if (!isLocalOwned(type, 'app')) return false;
    if (!offered.contains(type)) return false;
    if (!prefs.types.contains(type)) return false;
    return true;
  }

  final reminderNotifications = <PlannedNotification>[];
  final dailyNotifications = <PlannedNotification>[];

  // 1. Daily types: rolling ~9-day window (day 0 through day 8)
  for (var dayOffset = 0; dayOffset < 9; dayOffset++) {
    final dayDate = CairoTime.at(cairoNow.year, cairoNow.month, cairoNow.day + dayOffset);
    final dateIso = isoDate(dayDate);

    // 1A. Daily verse
    if (isLocalTypeAllowed(NotifyType.verse_daily)) {
      final vTime = prefs.verseTime ?? NotifyTypeConfig.defaultVerseTime;
      final parsedVTime = parseHm(vTime) ?? (7 * 60);
      var vScheduledAt = CairoTime.at(dayDate.year, dayDate.month, dayDate.day, parsedVTime);

      if (prefs.quietHoursEnabled) {
        final (inQuiet, quietEnd) = evaluateQuietHours(vScheduledAt, prefs.quiet.from, prefs.quiet.to);
        if (inQuiet) {
          vScheduledAt = quietEnd;
        }
      }

      if (!vScheduledAt.isBefore(now)) {
        // Same choice as Home / the reading screen: fixed admin verse, else the active season's set.
        final seasonSet = features.seasonVerses.activeSet(seasons, vScheduledAt);
        final verse = resolveSeasonalVerse(verseConfig, verses, vScheduledAt, day: dayDate, seasonSet: seasonSet);
        String titleAr = 'آية اليوم';
        String titleEn = 'Daily Verse';
        String bodyAr = 'آية يومية مشجعة مع قراءات اليوم';
        String bodyEn = 'Encouraging daily verse with scripture reference';

        if (verse != null) {
          final arText = verse.textAr.trim();
          final arRef = verse.refAr.trim();
          final truncatedAr = arText.length > 120 ? '${arText.substring(0, 120).trimRight()}…' : arText;
          bodyAr = arRef.isNotEmpty ? '$truncatedAr ($arRef)' : truncatedAr;

          final enText = verse.textEn.trim().isNotEmpty ? verse.textEn.trim() : arText;
          final enRef = verse.refEn.trim().isNotEmpty
              ? verse.refEn.trim()
              : (verse.refAr.trim().isNotEmpty ? verse.refAr.trim() : '');
          final truncatedEn = enText.length > 120 ? '${enText.substring(0, 120).trimRight()}…' : enText;
          bodyEn = enRef.isNotEmpty ? '$truncatedEn ($enRef)' : truncatedEn;
        }

        final key = 'local:verse_daily:$dateIso:verse';
        final payload = jsonEncode({'type': 'verse_daily', 'date': dateIso});

        dailyNotifications.add(PlannedNotification(
          id: notificationIdFor(key),
          key: key,
          type: NotifyType.verse_daily,
          scheduledAt: vScheduledAt,
          titleAr: titleAr,
          titleEn: titleEn,
          bodyAr: bodyAr,
          bodyEn: bodyEn,
          payload: payload,
          exact: false,
          channelId: NotifyType.verse_daily.name,
        ));
      }
    }

    // 1B. Katameros daily readings
    if (isLocalTypeAllowed(NotifyType.katameros_daily)) {
      final kTime = prefs.katamerosTime ?? NotifyTypeConfig.defaultKatamerosTime;
      final parsedKTime = parseHm(kTime) ?? (6 * 60 + 30);
      var kScheduledAt = CairoTime.at(dayDate.year, dayDate.month, dayDate.day, parsedKTime);

      if (prefs.quietHoursEnabled) {
        final (inQuiet, quietEnd) = evaluateQuietHours(kScheduledAt, prefs.quiet.from, prefs.quiet.to);
        if (inQuiet) {
          kScheduledAt = quietEnd;
        }
      }

      if (!kScheduledAt.isBefore(now)) {
        String titleAr = 'قراءات اليوم';
        String titleEn = "Today's Readings";
        String bodyAr = 'قراءات القداس اليومية بحسب طقس الكنيسة القبطية';
        String bodyEn = 'Daily Coptic liturgical readings';

        final readings = cachedReadings[dateIso];
        if (readings != null) {
          if (readings.titleAr.trim().isNotEmpty) {
            titleAr = 'قراءات اليوم — ${readings.titleAr.trim()}';
          }
          if (readings.titleEn.trim().isNotEmpty) {
            titleEn = "Today's Readings — ${readings.titleEn.trim()}";
          }
          final gospel = readings.liturgyGospel;
          if (gospel != null && gospel.refAr.trim().isNotEmpty) {
            bodyAr = 'إنجيل القداس: ${gospel.refAr.trim()}';
            bodyEn = gospel.refEn.trim().isNotEmpty
                ? 'Liturgy Gospel: ${gospel.refEn.trim()}'
                : 'Liturgy Gospel: ${gospel.refAr.trim()}';
          }
        }

        final key = 'local:katameros_daily:$dateIso:katameros';
        final payload = jsonEncode({'type': 'katameros_daily', 'date': dateIso});

        dailyNotifications.add(PlannedNotification(
          id: notificationIdFor(key),
          key: key,
          type: NotifyType.katameros_daily,
          scheduledAt: kScheduledAt,
          titleAr: titleAr,
          titleEn: titleEn,
          bodyAr: bodyAr,
          bodyEn: bodyEn,
          payload: payload,
          exact: false,
          channelId: NotifyType.katameros_daily.name,
        ));
      }
    }

    // 1C. Feasts & commemorations
    if (isLocalTypeAllowed(NotifyType.feasts)) {
      List<CopticFeast> feastsOnDay;
      if (dayOffset == 0 && computedFeasts.isNotEmpty) {
        feastsOnDay = computedFeasts;
      } else {
        feastsOnDay = copticFeastsOn(dayDate);
      }

      if (feastsOnDay.isNotEmpty) {
        final feast = feastsOnDay.first;
        final fTime = NotifyTypeConfig.defaultFeastsTime;
        final parsedFTime = parseHm(fTime) ?? (7 * 60 + 30);
        var fScheduledAt = CairoTime.at(dayDate.year, dayDate.month, dayDate.day, parsedFTime);

        if (prefs.quietHoursEnabled) {
          final (inQuiet, quietEnd) = evaluateQuietHours(fScheduledAt, prefs.quiet.from, prefs.quiet.to);
          if (inQuiet) {
            fScheduledAt = quietEnd;
          }
        }

        if (!fScheduledAt.isBefore(now)) {
          final key = 'local:feasts:$dateIso:feast';
          final payload = jsonEncode({'type': 'feasts', 'date': dateIso});

          dailyNotifications.add(PlannedNotification(
            id: notificationIdFor(key),
            key: key,
            type: NotifyType.feasts,
            scheduledAt: fScheduledAt,
            titleAr: feast.ar,
            titleEn: feast.en,
            bodyAr: 'تذكار مبارك: ${feast.ar}',
            bodyEn: 'Commemoration: ${feast.en}',
            payload: payload,
            exact: false,
            channelId: NotifyType.feasts.name,
          ));
        }
      }
    }
  }

  // 2. User Reminders
  if (isLocalTypeAllowed(NotifyType.reminders)) {
    // Liturgy occurrences cover a known date range (the provider computes ~60 days). Inside it, a
    // `lit-` reminder whose service has no occurrence that day is replaced / removed; outside it (or
    // before the liturgies have loaded) nothing can be concluded, so the stored time is kept.
    final litDays = liturgies.map((o) => isoDate(o.start)).toList()..sort();
    bool covered(String iso) =>
        litDays.isNotEmpty && iso.compareTo(litDays.first) >= 0 && iso.compareTo(litDays.last) <= 0;

    for (final reminder in reminders) {
      if (reminder.every) {
        // Recurring reminder: schedule up to 4 upcoming occurrences within 60 days
        var scheduledOccurrences = 0;
        final cBase = CairoTime.fromInstant(reminder.startsAt);
        final baseMinutes = cBase.hour * 60 + cBase.minute;

        // Start from next startsAt
        var candidateStartsAt = CairoTime.fromInstant(reminder.nextStartsAt(now));
        // If fireTime is before now, advance by weekly intervals
        while (candidateStartsAt.subtract(Duration(minutes: reminder.lead)).isBefore(now)) {
          final cCand = CairoTime.fromInstant(candidateStartsAt);
          candidateStartsAt = CairoTime.at(cCand.year, cCand.month, cCand.day + 7, baseMinutes);
        }

        while (scheduledOccurrences < 4 && candidateStartsAt.difference(now).inDays <= 60) {
          final cCand = CairoTime.fromInstant(candidateStartsAt);
          final candDateIso = isoDate(cCand);

          // Check if replaced
          bool replaced = false;
          tz.TZDateTime effectiveStart = candidateStartsAt;

          if (reminder.eventKey.startsWith('lit-') && covered(candDateIso)) {
            final matching = liturgies.where((o) =>
                isoDate(o.start) == candDateIso &&
                (o.liturgy.id == reminder.eventKey || 'lit-${o.liturgy.id}' == reminder.eventKey)).toList();
            if (matching.isEmpty) {
              // Replaced by a season (e.g. Holy Week — even when the season leaves the day with no
              // liturgy at all), hidden or removed: nothing rings that day.
              replaced = true;
            } else {
              effectiveStart = matching.first.start;
            }
          } else if (reminder.eventKey.startsWith('meeting-')) {
            final sameDayMeetings = meetings.where((m) => isoDate(m.start) == candDateIso).toList();
            if (sameDayMeetings.isNotEmpty) {
              final matching = sameDayMeetings.where((m) =>
                  m.meeting.id == reminder.eventKey ||
                  'meeting-${m.meeting.id}' == reminder.eventKey).toList();
              if (matching.isNotEmpty) {
                effectiveStart = CairoTime.fromInstant(matching.first.start);
              }
            }
          }

          if (!replaced) {
            final nominalFire = effectiveStart.subtract(Duration(minutes: reminder.lead));
            final scheduledAt = reminderFireTime(
              nominalFire: nominalFire,
              now: now,
              createdAt: reminder.createdAt,
              exactAllowed: exactAlarmsAllowed,
            );
            final exact = exactAlarmsAllowed;

            if (scheduledAt != null) {
              bool silent = false;
              if (prefs.quietHoursEnabled && prefs.remindersRespectQuietHours) {
                final (inQuiet, _) = evaluateQuietHours(scheduledAt, prefs.quiet.from, prefs.quiet.to);
                if (inQuiet) silent = true;
              }

              final titleAr = reminder.title['ar']?.trim().isNotEmpty == true
                  ? 'تذكير: ${reminder.title['ar']!.trim()}'
                  : 'تذكير';
              final titleEn = reminder.title['en']?.trim().isNotEmpty == true
                  ? 'Reminder: ${reminder.title['en']!.trim()}'
                  : 'Reminder';

              final cOcc = CairoTime.fromInstant(effectiveStart);
              final hm = '${cOcc.hour.toString().padLeft(2, '0')}:${cOcc.minute.toString().padLeft(2, '0')}';
              final leadAr = leadLabel(reminder.lead, 'ar');
              final leadEn = leadLabel(reminder.lead, 'en');
              final timeAr = formatTimeArabic(hm);
              final timeEn = formatTimeLatin(hm);

              final bodyAr = '$leadAr — $timeAr';
              final bodyEn = '$leadEn — $timeEn';

              final key = 'local:reminders:$candDateIso:${reminder.eventKey}:${reminder.lead}';
              final payload = jsonEncode({
                'type': 'reminders',
                'eventKey': reminder.eventKey,
                'date': candDateIso,
                'lead': reminder.lead,
              });

              reminderNotifications.add(PlannedNotification(
                id: notificationIdFor(key),
                key: key,
                type: NotifyType.reminders,
                scheduledAt: scheduledAt,
                titleAr: titleAr,
                titleEn: titleEn,
                bodyAr: bodyAr,
                bodyEn: bodyEn,
                payload: payload,
                exact: exact,
                channelId: NotifyType.reminders.name,
                silent: silent,
              ));

              scheduledOccurrences++;
            }
          }

          // Advance 7 days for next candidate occurrence
          candidateStartsAt = CairoTime.at(cCand.year, cCand.month, cCand.day + 7, baseMinutes);
        }
      } else {
        // One-off reminder
        var startsAt = CairoTime.fromInstant(reminder.startsAt);
        final remDateIso = reminder.occurrence ?? isoDate(startsAt);
        bool replaced = false;

        if (reminder.eventKey.startsWith('lit-') && covered(remDateIso)) {
          final matching = liturgies.where((o) =>
              isoDate(o.start) == remDateIso &&
              (o.liturgy.id == reminder.eventKey || 'lit-${o.liturgy.id}' == reminder.eventKey)).toList();
          if (matching.isEmpty) {
            replaced = true;
          } else {
            startsAt = matching.first.start;
          }
        } else if (reminder.eventKey.startsWith('meeting-')) {
          final sameDayMeetings = meetings.where((m) => isoDate(m.start) == remDateIso).toList();
          if (sameDayMeetings.isNotEmpty) {
            final matching = sameDayMeetings.where((m) =>
                m.meeting.id == reminder.eventKey ||
                'meeting-${m.meeting.id}' == reminder.eventKey).toList();
            if (matching.isNotEmpty) {
              startsAt = CairoTime.fromInstant(matching.first.start);
            }
          }
        } else if (reminder.eventKey.startsWith('day-')) {
          final matching = dayEvents.where((e) =>
              e.id == reminder.eventKey ||
              'day-${e.id}' == reminder.eventKey).toList();
          if (matching.isNotEmpty) {
            final e = matching.first;
            final sMinutes = parseHm(e.start);
            if (sMinutes != null) {
              final d = DateTime.tryParse(remDateIso) ?? (e.firstDay ?? startsAt);
              startsAt = CairoTime.at(d.year, d.month, d.day, sMinutes);
            }
          }
        }

        if (!replaced) {
          final nominalFire = startsAt.subtract(Duration(minutes: reminder.lead));
          final scheduledAt = reminderFireTime(
            nominalFire: nominalFire,
            now: now,
            createdAt: reminder.createdAt,
            exactAllowed: exactAlarmsAllowed,
          );
          final exact = exactAlarmsAllowed;

          if (scheduledAt != null) {
            bool silent = false;
            if (prefs.quietHoursEnabled && prefs.remindersRespectQuietHours) {
              final (inQuiet, _) = evaluateQuietHours(scheduledAt, prefs.quiet.from, prefs.quiet.to);
              if (inQuiet) silent = true;
            }

            final titleAr = reminder.title['ar']?.trim().isNotEmpty == true
                ? 'تذكير: ${reminder.title['ar']!.trim()}'
                : 'تذكير';
            final titleEn = reminder.title['en']?.trim().isNotEmpty == true
                ? 'Reminder: ${reminder.title['en']!.trim()}'
                : 'Reminder';

            final cStarts = CairoTime.fromInstant(startsAt);
            final hm = '${cStarts.hour.toString().padLeft(2, '0')}:${cStarts.minute.toString().padLeft(2, '0')}';
            final leadAr = leadLabel(reminder.lead, 'ar');
            final leadEn = leadLabel(reminder.lead, 'en');
            final timeAr = formatTimeArabic(hm);
            final timeEn = formatTimeLatin(hm);

            final bodyAr = '$leadAr — $timeAr';
            final bodyEn = '$leadEn — $timeEn';

            final key = 'local:reminders:$remDateIso:${reminder.eventKey}:${reminder.lead}';
            final payload = jsonEncode({
              'type': 'reminders',
              'eventKey': reminder.eventKey,
              'date': remDateIso,
              'lead': reminder.lead,
            });

            reminderNotifications.add(PlannedNotification(
              id: notificationIdFor(key),
              key: key,
              type: NotifyType.reminders,
              scheduledAt: scheduledAt,
              titleAr: titleAr,
              titleEn: titleEn,
              bodyAr: bodyAr,
              bodyEn: bodyEn,
              payload: payload,
              exact: exact,
              channelId: NotifyType.reminders.name,
              silent: silent,
            ));
          }
        }
      }
    }
  }

  // 3. Prioritize: user reminders first, then earliest date/time first.
  reminderNotifications.sort((a, b) {
    final cmp = a.scheduledAt.compareTo(b.scheduledAt);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });

  dailyNotifications.sort((a, b) {
    final cmp = a.scheduledAt.compareTo(b.scheduledAt);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });

  final combined = <PlannedNotification>[...reminderNotifications, ...dailyNotifications];
  return combined.take(80).toList();
}

/// When a reminder occurrence whose nominal fire time is [nominalFire] should be scheduled, or
/// null when it must not be (PR B §3.2 «Exactness»).
///
/// * A nominal time already in the past is never (re)scheduled — otherwise every re-plan would
///   ring an expired reminder again.
/// * Exact alarms: the nominal time.
/// * Inexact fallback: 10 min earlier. When that early slot has already passed, a reminder that
///   existed before it was already scheduled for (and has rung at) that slot, so it is skipped —
///   re-planning it would ring twice. A reminder created inside the last 10 minutes rings in 30 s.
tz.TZDateTime? reminderFireTime({
  required tz.TZDateTime nominalFire,
  required DateTime now,
  required DateTime createdAt,
  required bool exactAllowed,
}) {
  if (nominalFire.isBefore(now)) return null;
  if (exactAllowed) return nominalFire;
  final early = nominalFire.subtract(const Duration(minutes: 10));
  if (!early.isBefore(now)) return early;
  if (createdAt.isBefore(early)) return null;
  final soon = CairoTime.fromInstant(now.add(const Duration(seconds: 30)));
  return soon.isAfter(nominalFire) ? nominalFire : soon;
}

/// Replenishment check: returns true if fewer than [minRemainingDays] future
/// calendar days have scheduled daily notifications.
bool needsReplenishment(
  List<PlannedNotification> currentPlan,
  DateTime now, {
  int minRemainingDays = 4,
}) {
  final remainingDays = <String>{};
  for (final notif in currentPlan) {
    if (notif.type == NotifyType.verse_daily ||
        notif.type == NotifyType.katameros_daily ||
        notif.type == NotifyType.feasts) {
      if (notif.scheduledAt.isAfter(now)) {
        final cairoTime = CairoTime.fromInstant(notif.scheduledAt);
        remainingDays.add(isoDate(cairoTime));
      }
    }
  }
  return remainingDays.length < minRemainingDays;
}
