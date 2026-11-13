// Tests for LocalNotifier, NotifyPlanner debouncing, snapshot persistence,
// and WorkManager replenishment task (ADR-058 / PR B).

import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:church_portal/data/local_notifications.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/notify_plan.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:church_portal/state/notify_providers.dart';
import 'package:church_portal/state/providers.dart';

/// Test fake for [LocalNotifier] capturing all dispatched calls and state.
class FakeLocalNotifier implements LocalNotifier {
  bool initialized = false;
  void Function(String? payload)? selectNotificationCallback;
  bool permissionGranted = true;
  bool notificationsEnabled = true;
  bool exactAlarmsAllowed = true;
  String? launchPayload;
  List<PlannedNotification> scheduledPlan = [];
  final List<int> cancelledIds = [];
  bool allCancelled = false;
  final List<(int, String, String, String?, String?)> shownInstants = [];

  @override
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {
    initialized = true;
    selectNotificationCallback = onSelectNotification;
  }

  @override
  Future<bool> requestPermissions() async => permissionGranted;

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<bool> canScheduleExactAlarms() async => exactAlarmsAllowed;

  @override
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang}) async {
    scheduledPlan = List<PlannedNotification>.from(plan);
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    scheduledPlan.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> cancelAll() async {
    allCancelled = true;
    scheduledPlan.clear();
  }

  @override
  Future<void> showInstant(
    int id,
    String title,
    String body, {
    String? channelId,
    String? payload,
  }) async {
    shownInstants.add((id, title, body, channelId, payload));
  }

  @override
  Future<int> pendingCount() async => scheduledPlan.length;

  @override
  Future<String?> getLaunchPayload() async => launchPayload;
}

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  group('LocalNotifier & Channel Resolution', () {
    test('resolves canonical and alias channel IDs correctly', () {
      expect(resolveChannelId('verse'), equals(NotificationChannels.verse));
      expect(resolveChannelId('verse_daily'), equals(NotificationChannels.verse));
      expect(resolveChannelId('readings'), equals(NotificationChannels.readings));
      expect(resolveChannelId('katameros_daily'), equals(NotificationChannels.readings));
      expect(resolveChannelId('feasts'), equals(NotificationChannels.feasts));
      expect(resolveChannelId('reminders'), equals(NotificationChannels.reminders));
      expect(resolveChannelId('announcements'), equals(NotificationChannels.announcements));
      expect(resolveChannelId('seasons'), equals(NotificationChannels.seasons));
      expect(resolveChannelId('unknown_custom_id'), equals(NotificationChannels.reminders));
    });

    test('LocalNotifierStub performs no-ops without throwing', () async {
      const stub = LocalNotifierStub();
      await stub.initialize(onSelectNotification: (_) {});
      expect(await stub.requestPermissions(), isFalse);
      expect(await stub.canScheduleExactAlarms(), isFalse);
      await stub.schedulePlan(const []);
      await stub.showInstant(1, 'Title', 'Body');
      await stub.cancel(1);
      await stub.cancelAll();
      expect(await stub.pendingCount(), equals(0));
    });

    test('FakeLocalNotifier tracks scheduled plans and cancellations', () async {
      final fake = FakeLocalNotifier();
      await fake.initialize(onSelectNotification: (payload) {});
      expect(fake.initialized, isTrue);

      final now = CairoTime.at(2026, 11, 8, 8 * 60);
      final notif = PlannedNotification(
        id: 101,
        key: 'local:test:101',
        type: NotifyType.reminders,
        scheduledAt: now.add(const Duration(hours: 2)),
        titleAr: 'تذكير تجريبي',
        titleEn: 'Test Reminder',
        bodyAr: 'نص التذكير',
        bodyEn: 'Reminder body',
        exact: true,
        channelId: NotificationChannels.reminders,
      );

      await fake.schedulePlan([notif]);
      expect(fake.scheduledPlan.length, equals(1));
      expect(await fake.pendingCount(), equals(1));

      await fake.showInstant(202, 'فوري', 'نص فوري', channelId: 'announcements', payload: 'p1');
      expect(fake.shownInstants.length, equals(1));
      expect(fake.shownInstants.first.$1, equals(202));
      expect(fake.shownInstants.first.$2, equals('فوري'));

      await fake.cancel(101);
      expect(fake.cancelledIds, contains(101));
      expect(await fake.pendingCount(), equals(0));

      await fake.cancelAll();
      expect(fake.allCancelled, isTrue);
    });
  });

  group('Snapshot & Stored Plan Persistence', () {
    test('savePlannerSnapshot and loadPlannerSnapshot roundtrip all fields accurately', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final snapshotNow = DateTime.utc(2026, 11, 8, 10, 0, 0);
      final pushPrefs = PushPrefs(
        types: {NotifyType.verse_daily, NotifyType.reminders},
        lang: 'ar',
        updatedAt: snapshotNow,
      );

      final features = const FeatureSettings(
        pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
        dailyVerse: DailyVerseConfig(mode: 'fixed', textAr: 'آية ثابتة', refAr: 'مرجع'),
      );

      final reminder = Reminder(
        eventKey: 'lit-1',
        startsAt: snapshotNow.add(const Duration(days: 1)),
        lead: 60,
        title: const {'ar': 'قداس الأحد', 'en': 'Sunday Mass'},
        createdAt: snapshotNow,
      );

      final liturgy = const Liturgy(
        id: 'lit-1',
        type: 'mass',
        nameAr: 'قداس الصباح',
        nameEn: 'Morning Mass',
        weekday: 7,
        start: '07:00',
        end: '09:30',
      );

      final meeting = const Meeting(
        id: 'meeting-1',
        stage: 'youth',
        nameAr: 'اجتماع الشباب',
        nameEn: 'Youth Meeting',
        weekday: 5,
        start: '19:00',
        end: '21:00',
      );

      final season = const Season(
        id: 's-1',
        key: 'holy_week',
        nameAr: 'أسبوع الآلام',
        nameEn: 'Holy Week',
      );

      await savePlannerSnapshot(
        prefs: prefs,
        now: snapshotNow,
        pushPrefs: pushPrefs,
        features: features,
        reminders: [reminder],
        verseConfig: features.dailyVerse,
        verses: const [
          Verse(textAr: 'الرب راعيّ', refAr: 'مزمور ٢٣: ١', refEn: 'Psalm 23:1', textEn: 'The Lord is my shepherd')
        ],
        liturgies: [liturgy],
        meetings: [meeting],
        seasons: [season],
      );

      final loaded = await loadPlannerSnapshot(prefs: prefs);
      expect(loaded, isNotNull);
      expect(loaded!.savedAt.isAtSameMomentAs(snapshotNow), isTrue);
      expect(loaded.pushPrefs.types, contains(NotifyType.verse_daily));
      expect(loaded.pushPrefs.types, contains(NotifyType.reminders));
      expect(loaded.features.dailyVerse.textAr, equals('آية ثابتة'));
      expect(loaded.reminders.length, equals(1));
      expect(loaded.reminders.first.eventKey, equals('lit-1'));
      expect(loaded.liturgies.length, equals(1));
      expect(loaded.liturgies.first.id, equals('lit-1'));
      expect(loaded.meetings.length, equals(1));
      expect(loaded.meetings.first.id, equals('meeting-1'));
      expect(loaded.seasons.length, equals(1));
      expect(loaded.seasons.first.key, equals('holy_week'));
      expect(loaded.verses.length, equals(1));
      expect(loaded.verses.first.textAr, equals('الرب راعيّ'));
    });

    test('loadStoredPlan handles missing or malformed JSON gracefully', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(await loadStoredPlan(prefs: prefs), isEmpty);

      await prefs.setString(notifyPlanStorageKey, 'invalid-json-string');
      expect(await loadStoredPlan(prefs: prefs), isEmpty);

      final validItem = PlannedNotification(
        id: 42,
        key: 'local:test:42',
        type: NotifyType.verse_daily,
        scheduledAt: CairoTime.at(2026, 11, 8, 7 * 60),
        titleAr: 'عنوان',
        titleEn: 'Title',
        bodyAr: 'محتوى',
        bodyEn: 'Body',
        channelId: NotificationChannels.verse,
      );
      await prefs.setString(notifyPlanStorageKey, jsonEncode([validItem.toJson()]));

      final reloaded = await loadStoredPlan(prefs: prefs);
      expect(reloaded.length, equals(1));
      expect(reloaded.first.id, equals(42));
      expect(reloaded.first.titleAr, equals('عنوان'));
    });
  });

  group('NotifyPlanner Debounced Re-planning', () {
    test('debounces multiple rapid changes and replans once after 2 seconds', () {
      fakeAsync((async) {
        SharedPreferences.setMockInitialValues({});
        final fakeNotifier = FakeLocalNotifier();

        final container = ProviderContainer(
          overrides: [
            localNotifierProvider.overrideWithValue(fakeNotifier),
          ],
        );

        final planner = container.read(notifyPlannerProvider);
        expect(planner.hasActiveDebounce, isFalse);

        // Rapid triggers
        planner.scheduleReplan(const Duration(seconds: 2));
        expect(planner.hasActiveDebounce, isTrue);

        async.elapse(const Duration(milliseconds: 500));
        planner.scheduleReplan(const Duration(seconds: 2)); // resets timer

        async.elapse(const Duration(milliseconds: 1500));
        // Only 1.5 seconds elapsed since reset -> not executed yet
        expect(fakeNotifier.scheduledPlan, isEmpty);

        async.elapse(const Duration(milliseconds: 600));
        // 2.1 seconds elapsed since last reset -> debounce fired!
        async.flushMicrotasks();

        expect(planner.hasActiveDebounce, isFalse);
        container.dispose();
      });
    });

    test('replan directly schedules plan with LocalNotifier and stores plan in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeNotifier = FakeLocalNotifier();

      final now = CairoTime.at(2026, 11, 8, 5 * 60);

      final container = ProviderContainer(
        overrides: [
          localNotifierProvider.overrideWithValue(fakeNotifier),
          pushPrefsProvider.overrideWith(
            () => _TestPushPrefsNotifier(PushPrefs(
              types: {NotifyType.verse_daily, NotifyType.feasts},
              lang: 'ar',
              updatedAt: now,
            )),
          ),
          dailyVersesProvider.overrideWith((ref) async => [
                const Verse(textAr: 'الرب نوري وخلاصي', refAr: 'مزمور ٢٧: ١', textEn: 'The Lord is my light'),
              ]),
        ],
      );

      final planner = container.read(notifyPlannerProvider);
      final plan = await planner.replan(now: now, prefs: prefs);

      expect(plan, isNotEmpty);
      expect(fakeNotifier.scheduledPlan.length, equals(plan.length));

      // Check persisted plan in SharedPreferences
      final storedPlan = await loadStoredPlan(prefs: prefs);
      expect(storedPlan.length, equals(plan.length));
      expect(storedPlan.first.key, equals(plan.first.key));

      // Check persisted snapshot
      final snapshot = await loadPlannerSnapshot(prefs: prefs);
      expect(snapshot, isNotNull);
      expect(snapshot!.pushPrefs.types, contains(NotifyType.verse_daily));

      container.dispose();
    });
  });

  group('WorkManager Replenishment Task', () {
    test('skips re-planning when current plan has >= 4 future days', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeNotifier = FakeLocalNotifier();

      final now = CairoTime.at(2026, 11, 8, 6 * 60);

      // Create a plan with 6 future days
      final futurePlan = <PlannedNotification>[
        for (var i = 1; i <= 6; i++)
          PlannedNotification(
            id: 1000 + i,
            key: 'local:verse_daily:2026-11-${(8 + i).toString().padLeft(2, '0')}:verse',
            type: NotifyType.verse_daily,
            scheduledAt: CairoTime.at(2026, 11, 8 + i, 7 * 60),
            titleAr: 'آية اليوم',
            titleEn: 'Daily Verse',
            bodyAr: 'نص الآية',
            bodyEn: 'Verse body',
            channelId: NotificationChannels.verse,
          ),
      ];

      await prefs.setString(notifyPlanStorageKey, jsonEncode(futurePlan.map((n) => n.toJson()).toList()));

      final result = await executeReplenishmentTask(
        now: now,
        prefs: prefs,
        notifier: fakeNotifier,
      );

      expect(result, isTrue);
      // No re-scheduling called because >= 4 future days exist
      expect(fakeNotifier.scheduledPlan, isEmpty);
    });

    test('replenishes plan when fewer than 4 future days remain', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeNotifier = FakeLocalNotifier();

      final now = CairoTime.at(2026, 11, 8, 6 * 60);

      // Only 2 future days remaining in current plan
      final shortPlan = <PlannedNotification>[
        for (var i = 1; i <= 2; i++)
          PlannedNotification(
            id: 2000 + i,
            key: 'local:verse_daily:2026-11-${(8 + i).toString().padLeft(2, '0')}:verse',
            type: NotifyType.verse_daily,
            scheduledAt: CairoTime.at(2026, 11, 8 + i, 7 * 60),
            titleAr: 'آية اليوم',
            titleEn: 'Daily Verse',
            bodyAr: 'نص الآية',
            bodyEn: 'Verse body',
            channelId: NotificationChannels.verse,
          ),
      ];
      await prefs.setString(notifyPlanStorageKey, jsonEncode(shortPlan.map((n) => n.toJson()).toList()));

      // Store a snapshot from which replenishment can rebuild the ~9-day rolling plan
      await savePlannerSnapshot(
        prefs: prefs,
        now: now,
        pushPrefs: PushPrefs(
          types: {NotifyType.verse_daily},
          lang: 'ar',
          updatedAt: now,
        ),
        features: const FeatureSettings(
          pushSettings: PushSettings(enabled: true, offered: NotifyType.values),
        ),
        reminders: const [],
        verseConfig: DailyVerseConfig.defaults,
        verses: const [
          Verse(textAr: 'الرب نوري وخلاصي', refAr: 'مزمور ٢٧: ١', textEn: 'The Lord is my light'),
        ],
        liturgies: const [],
        meetings: const [],
        seasons: const [],
      );

      final result = await executeReplenishmentTask(
        now: now,
        prefs: prefs,
        notifier: fakeNotifier,
      );

      expect(result, isTrue);
      // Re-scheduled plan should now cover ~9 days
      expect(fakeNotifier.scheduledPlan.length, greaterThanOrEqualTo(8));
      expect(fakeNotifier.scheduledPlan.first.type, equals(NotifyType.verse_daily));

      // Plan saved in storage
      final updatedStoredPlan = await loadStoredPlan(prefs: prefs);
      expect(updatedStoredPlan.length, equals(fakeNotifier.scheduledPlan.length));

      // Diagnostic timestamp recorded
      final lastReplenish = prefs.getString(notifyDiagLastReplenishKey);
      expect(lastReplenish, isNotNull);
      expect(DateTime.parse(lastReplenish!).isAtSameMomentAs(now), isTrue);
    });

    test('changing localeProvider updates pushPrefsProvider.lang', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeNotifier = FakeLocalNotifier();

      final container = ProviderContainer(
        overrides: [
          localNotifierProvider.overrideWithValue(fakeNotifier),
          pushPrefsProvider.overrideWith(
            () => _TestPushPrefsNotifier(PushPrefs(
              types: {NotifyType.verse_daily},
              lang: 'ar',
              updatedAt: DateTime.utc(2026, 11, 8),
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(notifyPlannerProvider);
      expect(container.read(pushPrefsProvider).lang, 'ar');

      container.read(localeProvider.notifier).toggle();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(localeProvider).languageCode, 'en');
      expect(container.read(pushPrefsProvider).lang, 'en');
    });

    test('caps stored and scheduled plans to 64 on iOS and skips scheduling on Linux', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeNotifier = FakeLocalNotifier();
      final now = CairoTime.at(2026, 11, 8, 5 * 60);

      final reminders = [
        for (var i = 1; i <= 70; i++)
          Reminder(
            eventKey: 'lit-r$i',
            lead: 0,
            title: {'ar': 'تذكير $i', 'en': 'Reminder $i'},
            startsAt: now.add(Duration(hours: i)),
            createdAt: now,
          ),
      ];

      // 1. iOS caps at 64 in both scheduledPlan and persisted storage
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final container = ProviderContainer(
          overrides: [
            localNotifierProvider.overrideWithValue(fakeNotifier),
            pushPrefsProvider.overrideWith(
              () => _TestPushPrefsNotifier(PushPrefs(
                types: {NotifyType.reminders},
                lang: 'ar',
                updatedAt: now,
              )),
            ),
            userRemindersProvider.overrideWith(() => _TestUserRemindersNotifier(reminders)),
          ],
        );
        addTearDown(container.dispose);

        final plan = await container.read(notifyPlannerProvider).replan(now: now, prefs: prefs);
        expect(plan.length, equals(iosPendingNotificationCap));
        expect(fakeNotifier.scheduledPlan.length, equals(iosPendingNotificationCap));

        final storedPlan = await loadStoredPlan(prefs: prefs);
        expect(storedPlan.length, equals(iosPendingNotificationCap));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      // 2. Linux skips scheduling and removes any prior stored plan
      fakeNotifier.scheduledPlan = [];
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final container = ProviderContainer(
          overrides: [
            localNotifierProvider.overrideWithValue(fakeNotifier),
            pushPrefsProvider.overrideWith(
              () => _TestPushPrefsNotifier(PushPrefs(
                types: {NotifyType.reminders},
                lang: 'ar',
                updatedAt: now,
              )),
            ),
            userRemindersProvider.overrideWith(() => _TestUserRemindersNotifier(reminders)),
          ],
        );
        addTearDown(container.dispose);

        final linuxPlan = await container.read(notifyPlannerProvider).replan(now: now, prefs: prefs);
        expect(linuxPlan, isEmpty);
        expect(fakeNotifier.scheduledPlan, isEmpty);
        expect(await loadStoredPlan(prefs: prefs), isEmpty);

        final replenishOk = await executeReplenishmentTask(now: now, prefs: prefs, notifier: fakeNotifier);
        expect(replenishOk, isTrue);
        expect(fakeNotifier.scheduledPlan, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

class _TestPushPrefsNotifier extends PushPrefsNotifier {
  final PushPrefs _initial;
  _TestPushPrefsNotifier(this._initial);

  @override
  PushPrefs build() => _initial;
}

class _TestUserRemindersNotifier extends UserRemindersNotifier {
  final List<Reminder> _initial;
  _TestUserRemindersNotifier(this._initial);

  @override
  List<Reminder> build() => _initial;
}
