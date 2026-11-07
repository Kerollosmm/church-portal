import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/data/reminder_store.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeInstallEnv implements InstallEnv {
  final Map<String, Map<String, dynamic>> storage = {};

  @override
  String get userAgent => 'Fake';
  @override
  String get platform => 'Fake';
  @override
  int get maxTouchPoints => 0;
  @override
  bool get isStandalone => false;
  @override
  bool get hasDeferredPrompt => false;
  @override
  bool get installedEventReceived => false;

  @override
  void clearInstalledSessionFlag() {}
  @override
  Future<bool> promptInstall() => Future.value(false);

  @override
  Map<String, dynamic>? readJson(String key) => storage[key];

  @override
  void writeJson(String key, Map<String, dynamic> data) {
    storage[key] = Map<String, dynamic>.from(data);
  }

  @override
  void remove(String key) {
    storage.remove(key);
  }
}

void main() {
  group('EventKey', () {
    test('builds stable event keys per source', () {
      expect(EventKey.liturgy('123'), 'lit-123');
      expect(EventKey.meeting('youth'), 'meeting-youth');
      expect(EventKey.dayEvent('feast'), 'day-feast');
      expect(EventKey.seasonService('pascha-1'), 'season-pascha-1');
      expect(EventKey.custom('vsp', '1'), 'vsp-1');
    });
  });

  group('Reminder model', () {
    test('JSON round-trip and fireTime calculation', () {
      final startsAt = DateTime.utc(2027, 4, 30, 9, 0);
      final createdAt = DateTime.utc(2027, 4, 25, 10, 0);
      final r = Reminder(
        eventKey: 'lit-123',
        occurrence: '2027-04-30',
        lead: 60,
        every: true,
        title: const {'ar': 'قداس الجمعة العظيمة', 'en': 'Good Friday Mass'},
        startsAt: startsAt,
        createdAt: createdAt,
      );

      final json = r.toJson();
      final decoded = Reminder.fromJson(json);

      expect(decoded.eventKey, 'lit-123');
      expect(decoded.occurrence, '2027-04-30');
      expect(decoded.lead, 60);
      expect(decoded.every, isTrue);
      expect(decoded.title['ar'], 'قداس الجمعة العظيمة');
      expect(decoded.startsAt, startsAt);
      expect(decoded.fireTime, DateTime.utc(2027, 4, 30, 8, 0));
    });

    test('isExpired check against now', () {
      final now = DateTime.utc(2027, 4, 30, 10, 0);
      final past = Reminder(
        eventKey: 'e1',
        lead: 0,
        title: const {},
        startsAt: DateTime.utc(2027, 4, 30, 9, 0),
        createdAt: DateTime.utc(2027, 4, 1),
      );
      final future = Reminder(
        eventKey: 'e2',
        lead: 0,
        title: const {},
        startsAt: DateTime.utc(2027, 4, 30, 11, 0),
        createdAt: DateTime.utc(2027, 4, 1),
      );

      expect(past.isExpired(now), isTrue);
      expect(future.isExpired(now), isFalse);
    });
  });

  group('leadLabel', () {
    test('formats bilingual lead times correctly', () {
      expect(leadLabel(0, 'ar'), 'في الموعد');
      expect(leadLabel(0, 'en'), 'At event time');
      expect(leadLabel(15, 'ar'), 'قبل ١٥ دقيقة');
      expect(leadLabel(15, 'en'), '15 minutes before');
      expect(leadLabel(60, 'ar'), 'قبل ساعة');
      expect(leadLabel(60, 'en'), '1 hour before');
      expect(leadLabel(120, 'ar'), 'قبل ساعتين');
      expect(leadLabel(120, 'en'), '2 hours before');
      expect(leadLabel(1440, 'ar'), 'قبل يوم');
      expect(leadLabel(1440, 'en'), '1 day before');
    });
  });

  group('reconcileReminders', () {
    final now = DateTime.utc(2027, 4, 20, 12, 0);

    test('classifies kept, moved, changed and expired correctly', () {
      final stored = [
        // Kept: still exists at same time
        Reminder(
          eventKey: 'lit-1',
          lead: 15,
          title: const {},
          startsAt: DateTime.utc(2027, 4, 25, 9, 0),
          createdAt: now,
        ),
        // Moved: event rescheduled to 10:00
        Reminder(
          eventKey: 'lit-2',
          lead: 60,
          title: const {},
          startsAt: DateTime.utc(2027, 4, 26, 9, 0),
          createdAt: now,
        ),
        // Changed: event deleted / not in calendar
        Reminder(
          eventKey: 'lit-missing',
          lead: 30,
          title: const {},
          startsAt: DateTime.utc(2027, 4, 27, 9, 0),
          createdAt: now,
        ),
        // Expired: date in the past
        Reminder(
          eventKey: 'lit-old',
          lead: 10,
          title: const {},
          startsAt: DateTime.utc(2027, 4, 10, 9, 0),
          createdAt: now,
        ),
      ];

      final current = {
        'lit-1': DateTime.utc(2027, 4, 25, 9, 0),
        'lit-2': DateTime.utc(2027, 4, 26, 10, 0), // rescheduled
      };

      final result = reconcileReminders(stored, current, now);

      expect(result.kept.length, 1);
      expect(result.kept.first.eventKey, 'lit-1');

      expect(result.moved.length, 1);
      expect(result.moved.first.eventKey, 'lit-2');
      expect(result.moved.first.startsAt, DateTime.utc(2027, 4, 26, 10, 0));

      expect(result.changed.length, 1);
      expect(result.changed.first.eventKey, 'lit-missing');

      expect(result.expired.length, 1);
      expect(result.expired.first.eventKey, 'lit-old');
    });
  });

  group('ReminderStore', () {
    late FakeInstallEnv env;
    late ReminderStore store;

    setUp(() {
      env = FakeInstallEnv();
      store = ReminderStore(env: env);
    });

    test('adds, sorts by fireTime, and retrieves reminders', () {
      final r1 = Reminder(
        eventKey: 'e1',
        lead: 60,
        title: const {'ar': 'أ'},
        startsAt: DateTime.utc(2027, 5, 2, 10, 0), // fire: 9:00
        createdAt: DateTime.utc(2027, 5, 1),
      );
      final r2 = Reminder(
        eventKey: 'e2',
        lead: 15,
        title: const {'ar': 'ب'},
        startsAt: DateTime.utc(2027, 5, 2, 9, 0), // fire: 8:45
        createdAt: DateTime.utc(2027, 5, 1),
      );

      expect(store.put(r1), isTrue);
      expect(store.put(r2), isTrue);

      final loaded = store.load();
      expect(loaded.length, 2);
      expect(loaded.first.eventKey, 'e2'); // 8:45 before 9:00
      expect(loaded.last.eventKey, 'e1');
    });

    test('updating existing reminder replaces it without consuming quota', () {
      final r1 = Reminder(
        eventKey: 'e1',
        lead: 15,
        title: const {'ar': 'أ'},
        startsAt: DateTime.utc(2027, 5, 2, 9, 0),
        createdAt: DateTime.utc(2027, 5, 1),
      );
      store.put(r1);

      final r1Updated = r1.copyWith(lead: 60);
      expect(store.put(r1Updated), isTrue);

      final loaded = store.load();
      expect(loaded.length, 1);
      expect(loaded.first.lead, 60);
    });

    test('enforces max 30 reminders cap', () {
      for (int i = 0; i < maxDeviceReminders; i++) {
        final r = Reminder(
          eventKey: 'event-$i',
          lead: 0,
          title: {'ar': 'حدث $i'},
          startsAt: DateTime.utc(2027, 5, 1, i),
          createdAt: DateTime.utc(2027, 4, 1),
        );
        expect(store.put(r), isTrue);
      }

      expect(store.load().length, maxDeviceReminders);

      // 31st item fails to put
      final overflow = Reminder(
        eventKey: 'event-overflow',
        lead: 0,
        title: const {'ar': 'فائض'},
        startsAt: DateTime.utc(2027, 5, 2, 0),
        createdAt: DateTime.utc(2027, 4, 1),
      );
      expect(store.put(overflow), isFalse);
      expect(store.load().length, maxDeviceReminders);
    });

    test('remove and clearExpired', () {
      final past = Reminder(
        eventKey: 'past',
        lead: 0,
        title: const {},
        startsAt: DateTime.utc(2027, 4, 1),
        createdAt: DateTime.utc(2027, 3, 1),
      );
      final future1 = Reminder(
        eventKey: 'future1',
        lead: 0,
        title: const {},
        startsAt: DateTime.utc(2027, 5, 1),
        createdAt: DateTime.utc(2027, 3, 1),
      );
      final future2 = Reminder(
        eventKey: 'future2',
        lead: 0,
        title: const {},
        startsAt: DateTime.utc(2027, 5, 2),
        createdAt: DateTime.utc(2027, 3, 1),
      );

      store.put(past);
      store.put(future1);
      store.put(future2);

      expect(store.load().length, 3);

      store.clearExpired(DateTime.utc(2027, 4, 15));
      expect(store.load().length, 2);

      store.remove('future1');
      expect(store.load().length, 1);
      expect(store.load().first.eventKey, 'future2');
    });
  });
}
