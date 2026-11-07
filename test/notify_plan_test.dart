import 'dart:convert';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/coptic_feasts.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/notify_plan.dart';
import 'package:church_portal/domain/readings.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/today.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  group('PlannedNotification model & notificationIdFor', () {
    test('notificationIdFor is deterministic, 31-bit positive integer', () {
      final key1 = 'local:verse_daily:2026-11-08:verse';
      final id1 = notificationIdFor(key1);
      final id2 = notificationIdFor(key1);

      expect(id1, equals(id2), reason: 'Must be idempotent and deterministic');
      expect(id1 >= 0, isTrue);
      expect(id1 <= 2147483647, isTrue);

      final key2 = 'local:katameros_daily:2026-11-08:katameros';
      final id3 = notificationIdFor(key2);
      expect(id1 != id3, isTrue, reason: 'Distinct keys should yield distinct hashes');
    });

    test('PlannedNotification JSON round-trip serialization', () {
      final scheduledAt = CairoTime.at(2026, 11, 8, 7 * 60);
      final original = PlannedNotification(
        id: notificationIdFor('local:verse_daily:2026-11-08:verse'),
        key: 'local:verse_daily:2026-11-08:verse',
        type: NotifyType.verse_daily,
        scheduledAt: scheduledAt,
        titleAr: 'آية اليوم',
        titleEn: 'Daily Verse',
        bodyAr: 'فِي الْبَدْءِ كَانَ الْكَلِمَةُ (يوحنا ١: ١)',
        bodyEn: 'In the beginning was the Word (John 1:1)',
        payload: jsonEncode({'type': 'verse_daily', 'date': '2026-11-08'}),
        exact: false,
        channelId: NotifyType.verse_daily.name,
        silent: false,
      );

      final json = original.toJson();
      final decoded = PlannedNotification.fromJson(json);

      expect(decoded.id, original.id);
      expect(decoded.key, original.key);
      expect(decoded.type, original.type);
      expect(decoded.scheduledAt.isAtSameMomentAs(original.scheduledAt), isTrue);
      expect(decoded.titleAr, original.titleAr);
      expect(decoded.titleEn, original.titleEn);
      expect(decoded.bodyAr, original.bodyAr);
      expect(decoded.bodyEn, original.bodyEn);
      expect(decoded.payload, original.payload);
      expect(decoded.exact, original.exact);
      expect(decoded.channelId, original.channelId);
      expect(decoded.silent, original.silent);
      expect(decoded, equals(original));
    });
  });

  group('9-day rolling window', () {
    test('schedules verse at 07:00, katameros at 06:30, feasts at 07:30 Cairo for 9 days', () {
      // 05:00 Cairo time on 2026-11-07: before all morning daily notifications
      final now = CairoTime.at(2026, 11, 7, 5 * 60);

      final prefs = PushPrefs(
        types: {
          NotifyType.verse_daily,
          NotifyType.katameros_daily,
          NotifyType.feasts,
        },
        quietHoursEnabled: false,
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(
          enabled: true,
          offered: NotifyType.values,
        ),
      );

      final verses = [
        const Verse(
          textAr: 'أَنَا هُوَ نُورُ الْعَالَمِ',
          refAr: 'يوحنا ٨: ١٢',
          textEn: 'I am the light of the world',
          refEn: 'John 8:12',
        ),
      ];

      final cachedReadings = <String, DayReadings>{
        '2026-11-07': const DayReadings(
          date: '2026-11-07',
          coptic: '27 بابه 1743',
          titleAr: 'تذكار القديس مكاريوس الكبير',
          titleEn: 'St Macarius the Great',
          sections: [
            ReadingsSection(
              key: 'liturgy',
              titleAr: 'القداس',
              titleEn: 'Liturgy',
              readings: [
                ReadingItem(
                  kind: 'gospel',
                  titleAr: 'إنجيل القداس',
                  titleEn: 'Liturgy Gospel',
                  refAr: 'لوقا ١٤: ٢٥-٣٥',
                  refEn: 'Luke 14:25-35',
                  introAr: '',
                  introEn: '',
                  textAr: '',
                  textEn: '',
                  conclusionAr: '',
                  conclusionEn: '',
                ),
              ],
            ),
          ],
          source: 'api.katameros.app',
          bibleAr: 'Van Dyck',
          bibleEn: 'refs-only',
        ),
      };

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: verses,
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: cachedReadings,
        computedFeasts: const [
          CopticFeast('عيد النيروز', 'Nayrouz', FeastRank.major),
        ],
      );

      final verseItems = plan.where((p) => p.type == NotifyType.verse_daily).toList();
      final katamerosItems = plan.where((p) => p.type == NotifyType.katameros_daily).toList();
      final feastItems = plan.where((p) => p.type == NotifyType.feasts).toList();

      expect(verseItems.length, equals(9), reason: '9 days of daily verses');
      expect(katamerosItems.length, equals(9), reason: '9 days of Katameros readings');

      // Check verse times: 07:00 Cairo
      for (final v in verseItems) {
        final cairoTime = CairoTime.fromInstant(v.scheduledAt);
        expect(cairoTime.hour, equals(7));
        expect(cairoTime.minute, equals(0));
        expect(v.channelId, equals(NotifyType.verse_daily.name));
        expect(v.bodyAr, contains('يوحنا ٨: ١٢'));
      }

      // Check katameros times: 06:30 Cairo
      for (final k in katamerosItems) {
        final cairoTime = CairoTime.fromInstant(k.scheduledAt);
        expect(cairoTime.hour, equals(6));
        expect(cairoTime.minute, equals(30));
        expect(k.channelId, equals(NotifyType.katameros_daily.name));
      }

      // Check first day cached readings title and gospel ref
      final firstKatameros = katamerosItems.first;
      expect(firstKatameros.titleAr, contains('تذكار القديس مكاريوس الكبير'));
      expect(firstKatameros.bodyAr, contains('لوقا ١٤: ٢٥-٣٥'));
      expect(firstKatameros.payload, equals(jsonEncode({'type': 'katameros_daily', 'date': '2026-11-07'})));

      // Day 0 has feast passed via computedFeasts
      expect(feastItems.isNotEmpty, isTrue);
      final firstFeast = feastItems.first;
      final cFeastTime = CairoTime.fromInstant(firstFeast.scheduledAt);
      expect(cFeastTime.hour, equals(7));
      expect(cFeastTime.minute, equals(30));
      expect(firstFeast.titleAr, contains('عيد النيروز'));
    });
  });

  group('Replenishment check (needsReplenishment)', () {
    test('returns false when 9 days remain, true when < 4 days remain', () {
      final now = CairoTime.at(2026, 11, 7, 10 * 60);

      // Create a 9-day plan
      final fullPlan = <PlannedNotification>[
        for (var i = 1; i <= 9; i++)
          PlannedNotification(
            id: i,
            key: 'local:verse_daily:2026-11-${(7 + i).toString().padLeft(2, '0')}:verse',
            type: NotifyType.verse_daily,
            scheduledAt: CairoTime.at(2026, 11, 7 + i, 7 * 60),
            titleAr: 'آية اليوم',
            titleEn: 'Daily Verse',
            bodyAr: 'نص',
            bodyEn: 'text',
            channelId: 'verse_daily',
          ),
      ];

      expect(needsReplenishment(fullPlan, now), isFalse);

      // Create a 3-day plan
      final lowPlan = fullPlan.take(3).toList();
      expect(needsReplenishment(lowPlan, now), isTrue);

      // Empty plan
      expect(needsReplenishment(const [], now), isTrue);

      // 4 days exactly: boundary condition
      final fourDaysPlan = fullPlan.take(4).toList();
      expect(needsReplenishment(fourDaysPlan, now), isFalse);
    });

    test('ignores past notifications when counting remaining days', () {
      final now = CairoTime.at(2026, 11, 10, 10 * 60);

      final plan = <PlannedNotification>[
        // 3 past days (Nov 7, 8, 9)
        for (var i = 7; i <= 9; i++)
          PlannedNotification(
            id: i,
            key: 'k$i',
            type: NotifyType.verse_daily,
            scheduledAt: CairoTime.at(2026, 11, i, 7 * 60),
            titleAr: 'آية',
            titleEn: 'verse',
            bodyAr: 'نص',
            bodyEn: 'text',
            channelId: 'verse_daily',
          ),
        // 2 future days (Nov 11, 12)
        for (var i = 11; i <= 12; i++)
          PlannedNotification(
            id: i,
            key: 'k$i',
            type: NotifyType.verse_daily,
            scheduledAt: CairoTime.at(2026, 11, i, 7 * 60),
            titleAr: 'آية',
            titleEn: 'verse',
            bodyAr: 'نص',
            bodyEn: 'text',
            channelId: 'verse_daily',
          ),
      ];

      // Only 2 future calendar days remain -> needs replenishment!
      expect(needsReplenishment(plan, now), isTrue);
    });
  });

  group('Quiet hours', () {
    test('moves katameros 06:30 -> 07:00 when quiet hours are 22:00-07:00', () {
      final now = CairoTime.at(2026, 11, 7, 5 * 60);

      final prefs = PushPrefs(
        types: {NotifyType.katameros_daily, NotifyType.verse_daily},
        quietHoursEnabled: true,
        quiet: const QuietHours(from: '22:00', to: '07:00'),
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      final katameros = plan.firstWhere((p) => p.type == NotifyType.katameros_daily);
      final cairoTime = CairoTime.fromInstant(katameros.scheduledAt);

      // Katameros was 06:30, moved to 07:00 (quiet hours end)
      expect(cairoTime.hour, equals(7));
      expect(cairoTime.minute, equals(0));
    });

    test('user reminder at 06:00 rings normally by default, marked silent when switch is on', () {
      final now = CairoTime.at(2026, 11, 7, 5 * 60);
      final eventTime = CairoTime.at(2026, 11, 7, 6 * 60);

      final reminder = Reminder(
        eventKey: 'lit-early-mass',
        lead: 0,
        title: const {'ar': 'قداس باكر', 'en': 'Early Mass'},
        startsAt: eventTime,
        createdAt: now,
      );

      // Case A: default remindersRespectQuietHours == false
      final prefsDefault = PushPrefs(
        types: {NotifyType.reminders},
        quietHoursEnabled: true,
        remindersRespectQuietHours: false,
        quiet: const QuietHours(from: '22:00', to: '07:00'),
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final planDefault = planNotifications(
        now: now,
        prefs: prefsDefault,
        features: features,
        reminders: [reminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      final notifDefault = planDefault.firstWhere((p) => p.type == NotifyType.reminders);
      expect(notifDefault.scheduledAt, equals(eventTime), reason: 'Reminders stay at event time');
      expect(notifDefault.silent, isFalse, reason: 'Rings normally by default');

      // Case B: remindersRespectQuietHours == true
      final prefsSilent = prefsDefault.copyWith(remindersRespectQuietHours: true);
      final planSilent = planNotifications(
        now: now,
        prefs: prefsSilent,
        features: features,
        reminders: [reminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      final notifSilent = planSilent.firstWhere((p) => p.type == NotifyType.reminders);
      expect(notifSilent.scheduledAt, equals(eventTime), reason: 'Reminders stay at event time');
      expect(notifSilent.silent, isTrue, reason: 'Marked silent when switch is on');
    });
  });

  group('Reminder exact mode vs inexact fallback', () {
    test('exact alarms mode when allowed, fallback inexact (-10 min) when disallowed', () {
      final now = CairoTime.at(2026, 11, 7, 8 * 60);
      final eventTime = CairoTime.at(2026, 11, 7, 10 * 60);

      final reminder = Reminder(
        eventKey: 'lit-mass',
        lead: 60, // 60 min before = 09:00
        title: const {'ar': 'قداس', 'en': 'Mass'},
        startsAt: eventTime,
        createdAt: now,
      );

      final prefs = PushPrefs(
        types: {NotifyType.reminders},
        quietHoursEnabled: false,
        updatedAt: now,
      );
      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      // Exact allowed: scheduled at 09:00, exact: true
      final planExact = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: [reminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
        exactAlarmsAllowed: true,
      );

      final notifExact = planExact.firstWhere((p) => p.type == NotifyType.reminders);
      expect(notifExact.exact, isTrue);
      expect(notifExact.scheduledAt, equals(CairoTime.at(2026, 11, 7, 9 * 60)));

      // Inexact fallback: scheduled at 08:50 (10 min earlier), exact: false
      final planInexact = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: [reminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
        exactAlarmsAllowed: false,
      );

      final notifInexact = planInexact.firstWhere((p) => p.type == NotifyType.reminders);
      expect(notifInexact.exact, isFalse);
      expect(notifInexact.scheduledAt, equals(CairoTime.at(2026, 11, 7, 8 * 60 + 50)));
    });
  });

  group('Reminder matching & recurrence', () {
    test('schedules reminder for dated service, meetings, and dayEvents', () {
      final now = CairoTime.at(2026, 11, 7, 8 * 60);

      // 1. Liturgy reminder
      final litStart = CairoTime.at(2026, 11, 7, 10 * 60);
      final liturgy = Liturgy(
        id: 'lit-1',
        type: 'mass',
        nameAr: 'قداس السبت',
        nameEn: 'Saturday Mass',
        start: '10:00',
        end: '12:00',
      );
      final litOccurrence = LiturgyOccurrence(liturgy, litStart, litStart.add(const Duration(hours: 2)), 0);
      final litReminder = Reminder(
        eventKey: 'lit-lit-1',
        lead: 30,
        title: const {'ar': 'قداس السبت', 'en': 'Saturday Mass'},
        startsAt: litStart,
        createdAt: now,
      );

      // 2. DayEvent reminder
      final dayEvent = DayEvent(
        id: 'day-revival',
        titleAr: 'نهضة الشفعاء',
        titleEn: 'Saints Revival',
        date: DateTime.utc(2026, 11, 7),
        start: '18:00',
        end: '21:00',
      );
      final dayReminder = Reminder(
        eventKey: 'day-day-revival',
        lead: 60,
        title: const {'ar': 'نهضة الشفعاء', 'en': 'Saints Revival'},
        startsAt: CairoTime.at(2026, 11, 7, 18 * 60),
        createdAt: now,
      );

      // 3. Meeting reminder
      final meeting = Meeting(
        id: 'youth',
        stage: 'youth',
        nameAr: 'اجتماع الشباب',
        nameEn: 'Youth Meeting',
        start: '19:30',
        end: '21:00',
      );
      final meetingStart = CairoTime.at(2026, 11, 7, 19 * 60 + 30);
      final meetingOccurrence = MeetingOccurrence(meeting, meetingStart, meetingStart.add(const Duration(hours: 2)));
      final meetingReminder = Reminder(
        eventKey: 'meeting-youth',
        lead: 15,
        title: const {'ar': 'اجتماع الشباب', 'en': 'Youth Meeting'},
        startsAt: meetingStart,
        createdAt: now,
      );

      final prefs = PushPrefs(
        types: {NotifyType.reminders},
        quietHoursEnabled: false,
        updatedAt: now,
      );
      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: [litReminder, dayReminder, meetingReminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: [litOccurrence],
        meetings: [meetingOccurrence],
        dayEvents: [dayEvent],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      expect(plan.length, equals(3));
      final litNotif = plan.firstWhere((p) => p.key.contains('lit-lit-1'));
      expect(litNotif.scheduledAt, equals(CairoTime.at(2026, 11, 7, 9 * 60 + 30)));

      final dayNotif = plan.firstWhere((p) => p.key.contains('day-day-revival'));
      expect(dayNotif.scheduledAt, equals(CairoTime.at(2026, 11, 7, 17 * 60)));

      final meetingNotif = plan.firstWhere((p) => p.key.contains('meeting-youth'));
      expect(meetingNotif.scheduledAt, equals(CairoTime.at(2026, 11, 7, 19 * 60 + 15)));
    });

    test('recurring weekly reminder schedules up to 4 upcoming occurrences and skips replaced days', () {
      // Sunday morning 2026-11-08 at 06:00 Cairo
      final now = CairoTime.at(2026, 11, 8, 6 * 60);
      final sundayMassStart = CairoTime.at(2026, 11, 8, 8 * 60);

      final liturgy = Liturgy(
        id: 'sun-mass',
        type: 'mass',
        nameAr: 'قداس الأحد',
        nameEn: 'Sunday Mass',
        start: '08:00',
        end: '10:30',
        weekday: 7,
      );

      // Recurring reminder for Sunday Mass: every week at 08:00
      final recurringReminder = Reminder(
        eventKey: 'lit-sun-mass',
        every: true,
        lead: 60,
        title: const {'ar': 'قداس الأحد', 'en': 'Sunday Mass'},
        startsAt: sundayMassStart,
        createdAt: now,
      );

      // Sundays:
      // Week 1: 2026-11-08 (normal)
      // Week 2: 2026-11-15 (replaced by special season - only Holy Week service exists)
      // Week 3: 2026-11-22 (normal)
      // Week 4: 2026-11-29 (normal)
      // Week 5: 2026-12-06 (normal)

      final specialLiturgy = Liturgy(
        id: 'holy-week-service',
        type: 'mass',
        nameAr: 'صلاة البصخة',
        nameEn: 'Pascha Service',
        start: '08:00',
        end: '11:00',
      );

      final liturgies = [
        LiturgyOccurrence(liturgy, CairoTime.at(2026, 11, 8, 8 * 60), CairoTime.at(2026, 11, 8, 10 * 60), 0),
        // On 2026-11-15, only specialLiturgy is held; regular Sunday mass was replaced!
        LiturgyOccurrence(specialLiturgy, CairoTime.at(2026, 11, 15, 8 * 60), CairoTime.at(2026, 11, 15, 11 * 60), 7),
        LiturgyOccurrence(liturgy, CairoTime.at(2026, 11, 22, 8 * 60), CairoTime.at(2026, 11, 22, 10 * 60), 14),
        LiturgyOccurrence(liturgy, CairoTime.at(2026, 11, 29, 8 * 60), CairoTime.at(2026, 11, 29, 10 * 60), 21),
        LiturgyOccurrence(liturgy, CairoTime.at(2026, 12, 6, 8 * 60), CairoTime.at(2026, 12, 6, 10 * 60), 28),
      ];

      final prefs = PushPrefs(
        types: {NotifyType.reminders},
        quietHoursEnabled: false,
        updatedAt: now,
      );
      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: [recurringReminder],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [],
        liturgies: liturgies,
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      // Exactly 4 occurrences scheduled
      expect(plan.length, equals(4));

      // Occurrences should be Week 1 (Nov 8), Week 3 (Nov 22), Week 4 (Nov 29), Week 5 (Dec 6).
      // Week 2 (Nov 15) MUST BE SKIPPED because it was replaced!
      final dates = plan.map((p) => isoDate(CairoTime.fromInstant(p.scheduledAt))).toList();
      expect(dates.contains('2026-11-08'), isTrue);
      expect(dates.contains('2026-11-15'), isFalse, reason: 'Nov 15 replaced service must be skipped');
      expect(dates.contains('2026-11-22'), isTrue);
      expect(dates.contains('2026-11-29'), isTrue);
      expect(dates.contains('2026-12-06'), isTrue);
    });
  });

  group('Safety & filtering constraints', () {
    test('NEVER emits announcement or season items even if enabled in prefs', () {
      final now = CairoTime.at(2026, 11, 7, 5 * 60);

      final prefs = PushPrefs(
        types: {
          NotifyType.announcements,
          NotifyType.seasons,
          NotifyType.verse_daily,
        },
        quietHoursEnabled: false,
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [
          Verse(textAr: 'آية', refAr: 'مرجع'),
        ],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      final types = plan.map((p) => p.type).toSet();
      expect(types.contains(NotifyType.announcements), isFalse);
      expect(types.contains(NotifyType.seasons), isFalse);
      expect(types.contains(NotifyType.verse_daily), isTrue);
    });

    test('respects offered types filter (features.pushTypes)', () {
      final now = CairoTime.at(2026, 11, 7, 5 * 60);

      final prefs = PushPrefs(
        types: {
          NotifyType.verse_daily,
          NotifyType.katameros_daily,
        },
        quietHoursEnabled: false,
        updatedAt: now,
      );

      // Admin offers only katameros_daily, not verse_daily
      final features = FeatureSettings(
        pushSettings: PushSettings(
          enabled: true,
          offered: [NotifyType.katameros_daily],
        ),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [
          Verse(textAr: 'آية', refAr: 'مرجع'),
        ],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      expect(plan.any((p) => p.type == NotifyType.verse_daily), isFalse);
      expect(plan.any((p) => p.type == NotifyType.katameros_daily), isTrue);
    });

    test('caps at 80 items with user reminders prioritized over daily notifications', () {
      final now = CairoTime.at(2026, 11, 7, 5 * 60);

      // Create 85 distinct reminders
      final reminders = <Reminder>[
        for (var i = 0; i < 85; i++)
          Reminder(
            eventKey: 'lit-$i',
            lead: 0,
            title: {'ar': 'قداس $i', 'en': 'Mass $i'},
            startsAt: CairoTime.at(2026, 11, 8, 8 * 60).add(Duration(minutes: i * 30)),
            createdAt: now,
          ),
      ];

      final prefs = PushPrefs(
        types: {
          NotifyType.reminders,
          NotifyType.verse_daily,
          NotifyType.katameros_daily,
        },
        quietHoursEnabled: false,
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: reminders,
        verseConfig: DailyVerseConfig.defaults,
        verses: const [Verse(textAr: 'آية', refAr: 'مرجع')],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      expect(plan.length, equals(80), reason: 'Must not exceed 80 items cap');
      expect(plan.every((p) => p.type == NotifyType.reminders), isTrue,
          reason: 'Reminders take highest priority over daily types');
    });

    test('skips any notification in the past', () {
      // 07:15 Cairo: Katameros (06:30) and Verse (07:00) of today are in the past
      final now = CairoTime.at(2026, 11, 7, 7 * 60 + 15);

      final prefs = PushPrefs(
        types: {
          NotifyType.verse_daily,
          NotifyType.katameros_daily,
          NotifyType.feasts,
        },
        quietHoursEnabled: false,
        updatedAt: now,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: now,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [Verse(textAr: 'آية', refAr: 'مرجع')],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      // Today's 06:30 and 07:00 are before now, so 8 days of verse and katameros remain
      final todayIso = '2026-11-07';
      expect(plan.any((p) => p.type == NotifyType.verse_daily && p.key.contains(todayIso)), isFalse);
      expect(plan.any((p) => p.type == NotifyType.katameros_daily && p.key.contains(todayIso)), isFalse);

      // Feasts at 07:30 today is still in the future (if computedFeasts had one)
      // All scheduled notifications must be after now
      expect(plan.every((p) => !p.scheduledAt.isBefore(now)), isTrue);
    });
  });

  group('DST switch night handling (Cairo summer/winter)', () {
    test('schedules correctly across Egypt summer time transition (last Friday of April)', () {
      // Egypt DST starts at midnight on the last Friday of April (e.g. 2026-04-24)
      final transitionDay = CairoTime.at(2026, 4, 23, 10 * 60);

      final prefs = PushPrefs(
        types: {NotifyType.verse_daily, NotifyType.katameros_daily},
        quietHoursEnabled: false,
        updatedAt: transitionDay,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: transitionDay,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [Verse(textAr: 'آية', refAr: 'مرجع')],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      for (final item in plan) {
        final cCairo = CairoTime.fromInstant(item.scheduledAt);
        if (item.type == NotifyType.verse_daily) {
          expect(cCairo.hour, equals(7), reason: 'Verse stays 07:00 Cairo regardless of DST');
        } else if (item.type == NotifyType.katameros_daily) {
          expect(cCairo.hour, equals(6), reason: 'Katameros stays 06:30 Cairo regardless of DST');
          expect(cCairo.minute, equals(30));
        }
      }
    });

    test('schedules correctly across Egypt winter time transition (last Thursday of October)', () {
      // Egypt DST ends at 24:00 on the last Thursday of October (e.g. 2026-10-29)
      final transitionDay = CairoTime.at(2026, 10, 28, 10 * 60);

      final prefs = PushPrefs(
        types: {NotifyType.verse_daily, NotifyType.katameros_daily},
        quietHoursEnabled: false,
        updatedAt: transitionDay,
      );

      final features = FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
      );

      final plan = planNotifications(
        now: transitionDay,
        prefs: prefs,
        features: features,
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [Verse(textAr: 'آية', refAr: 'مرجع')],
        liturgies: const [],
        meetings: const [],
        dayEvents: const [],
        cachedReadings: const {},
        computedFeasts: const [],
      );

      for (final item in plan) {
        final cCairo = CairoTime.fromInstant(item.scheduledAt);
        if (item.type == NotifyType.verse_daily) {
          expect(cCairo.hour, equals(7), reason: 'Verse stays 07:00 Cairo regardless of DST');
        } else if (item.type == NotifyType.katameros_daily) {
          expect(cCairo.hour, equals(6), reason: 'Katameros stays 06:30 Cairo regardless of DST');
          expect(cCairo.minute, equals(30));
        }
      }
    });
  });

  group('Reminder fire time (review fixes, ADR-058)', () {
    final prefs = PushPrefs(types: {NotifyType.reminders}, quietHoursEnabled: false, updatedAt: DateTime.utc(2026));
    final features = FeatureSettings(pushSettings: PushSettings(enabled: true, offered: NotifyType.values));
    List<PlannedNotification> plan(DateTime now, List<Reminder> reminders,
            {bool exact = true, List<LiturgyOccurrence> liturgies = const []}) =>
        planNotifications(
          now: now,
          prefs: prefs,
          features: features,
          reminders: reminders,
          verseConfig: DailyVerseConfig.defaults,
          verses: const [],
          liturgies: liturgies,
          meetings: const [],
          dayEvents: const [],
          cachedReadings: const {},
          computedFeasts: const [],
          exactAlarmsAllowed: exact,
        );

    test('an expired one-off reminder is never re-scheduled (inexact fallback)', () {
      final created = CairoTime.at(2026, 11, 6, 8 * 60);
      final r = Reminder(
        eventKey: 'day-e0',
        lead: 60,
        title: const {'ar': 'نهضة'},
        startsAt: CairoTime.at(2026, 11, 7, 10 * 60), // nominal fire 09:00
        createdAt: created,
      );
      expect(plan(CairoTime.at(2026, 11, 7, 9 * 60 + 30), [r], exact: false), isEmpty);
      expect(plan(CairoTime.at(2026, 11, 7, 9 * 60 + 30), [r], exact: true), isEmpty);
    });

    test('inexact: an early slot already passed for an older reminder is skipped (it has rung)', () {
      final r = Reminder(
        eventKey: 'day-e0',
        lead: 60,
        title: const {'ar': 'نهضة'},
        startsAt: CairoTime.at(2026, 11, 7, 10 * 60), // nominal 09:00, early slot 08:50
        createdAt: CairoTime.at(2026, 11, 6, 8 * 60),
      );
      expect(plan(CairoTime.at(2026, 11, 7, 8 * 60 + 55), [r], exact: false), isEmpty);
    });

    test('inexact: a reminder created inside the last 10 minutes rings in 30 s', () {
      final now = CairoTime.at(2026, 11, 7, 8 * 60 + 55);
      final r = Reminder(
        eventKey: 'day-e0',
        lead: 60,
        title: const {'ar': 'نهضة'},
        startsAt: CairoTime.at(2026, 11, 7, 10 * 60),
        createdAt: now,
      );
      final p = plan(now, [r], exact: false).single;
      expect(p.exact, isFalse);
      expect(p.scheduledAt, equals(now.add(const Duration(seconds: 30))));
    });

    test('a weekly lit- reminder is suppressed on a day the season leaves with no liturgy', () {
      final now = CairoTime.at(2026, 11, 7, 8 * 60); // Saturday
      final sunday = Liturgy(
        id: 'sun',
        type: 'mass',
        nameAr: 'قداس الأحد',
        nameEn: 'Sunday Mass',
        weekday: 7,
        start: '08:00',
        end: '10:00',
      );
      // Occurrences on Sun 8 Nov and Sun 22 Nov only: 15 Nov is a replaced day with no liturgy at all.
      LiturgyOccurrence occ(int day) {
        final s = CairoTime.at(2026, 11, day, 8 * 60);
        return LiturgyOccurrence(sunday, s, s.add(const Duration(hours: 2)), day - 7);
      }
      final weekdayOnly = Liturgy(id: 'wed', type: 'mass', nameAr: 'قداس', nameEn: 'Mass', weekday: 3, start: '07:00', end: '09:00');
      final wedStart = CairoTime.at(2026, 11, 25, 7 * 60);
      final liturgies = [occ(8), occ(22), LiturgyOccurrence(weekdayOnly, wedStart, wedStart.add(const Duration(hours: 2)), 18)];
      final r = Reminder(
        eventKey: 'lit-sun',
        every: true,
        lead: 60,
        title: const {'ar': 'قداس الأحد'},
        startsAt: CairoTime.at(2026, 11, 8, 8 * 60),
        createdAt: now,
      );
      final dates = plan(now, [r], liturgies: liturgies).map((p) => isoDate(CairoTime.fromInstant(p.scheduledAt))).toList();
      expect(dates, contains('2026-11-08'));
      expect(dates, contains('2026-11-22'));
      expect(dates, isNot(contains('2026-11-15')), reason: 'replaced day without any liturgy');
    });
  });
}
