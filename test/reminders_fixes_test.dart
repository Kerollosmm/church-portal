// PR #51 review fixes (ADR-057): recurring reminders, storage failures,
// strict occurrence lookup, lead clamping, reconciliation of moved events.
import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/data/reminder_store.dart';
import 'package:church_portal/domain/app_install.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/push.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:church_portal/ui/widgets/reminder_sheet.dart' show initialReminderLead;
import 'package:flutter_test/flutter_test.dart';

class _Env implements InstallEnv {
  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};

  final Map<String, Map<String, dynamic>> storage = {};
  bool failWrites = false;

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
  Future<bool> promptInstall() async => false;
  @override
  Map<String, dynamic>? readJson(String key) => storage[key];
  @override
  void writeJson(String key, Map<String, dynamic> data) {
    // Like the web implementation's localStorage.setItem in private mode /
    // over quota.
    if (failWrites) throw StateError('QuotaExceededError');
    storage[key] = Map<String, dynamic>.from(data);
  }

  @override
  void remove(String key) => storage.remove(key);
}

Reminder _r(String key, {String? occ, bool every = false, int lead = 60, required DateTime startsAt}) => Reminder(
      eventKey: key,
      occurrence: occ,
      lead: lead,
      every: every,
      title: const {'ar': 'x', 'en': 'x'},
      startsAt: startsAt,
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('recurring «كل مرة» reminders', () {
    // Sun 25 Oct 2026 08:00 Cairo is still summer time (UTC+3) in the tz data?
    // Either way the next occurrence must keep 08:00 Cairo wall time.
    final first = CairoTime.at(2026, 10, 25, 8 * 60).toUtc();
    final now = CairoTime.at(2026, 11, 7, 12 * 60).toUtc(); // Sat 7 Nov

    test('never expire, roll forward weekly at the same Cairo wall time', () {
      final r = _r('lit-sun', every: true, startsAt: first);
      expect(r.isExpired(now), isFalse);
      final next = CairoTime.fromInstant(r.nextStartsAt(now));
      expect([next.year, next.month, next.day, next.hour, next.minute], [2026, 11, 8, 8, 0]);
      expect(r.nextFireTime(now), r.nextStartsAt(now).subtract(const Duration(minutes: 60)));
    });

    test('a one-off reminder still expires and keeps its own time', () {
      final r = _r('lit-sun', startsAt: first);
      expect(r.isExpired(now), isTrue);
      expect(r.nextStartsAt(now), first);
    });

    test('clearExpired keeps recurring reminders', () {
      final store = ReminderStore(env: _Env());
      store.put(_r('lit-sun', every: true, startsAt: first));
      store.put(_r('lit-once', occ: '2026-10-25', startsAt: first));
      store.clearExpired(now);
      expect(store.load().map((r) => r.eventKey), ['lit-sun']);
    });

    test('a recurring reminder covers every occurrence of its event; strict otherwise', () {
      final list = [
        _r('lit-sun', every: true, startsAt: first),
        _r('lit-fri', occ: '2026-11-13', startsAt: first),
      ];
      expect(ReminderStore.findIn(list, 'lit-sun', occurrence: '2026-11-08')?.every, isTrue);
      expect(ReminderStore.findIn(list, 'lit-fri', occurrence: '2026-11-13'), isNotNull);
      // null is not a wildcard
      expect(ReminderStore.findIn(list, 'lit-fri', occurrence: null), isNull);
      expect(ReminderStore.findIn(list, 'lit-fri', occurrence: '2026-11-20'), isNull);
    });

    test('reconcile: recurring stays scheduled; a past one-off moved to a future time is "moved"', () {
      final weekly = _r('lit-sun', every: true, startsAt: first);
      final once = _r('day-x', startsAt: first);
      final later = CairoTime.at(2026, 11, 9, 18 * 60).toUtc();
      final res = reconcileReminders([weekly, once], {
        'lit-sun': weekly.nextStartsAt(now),
        'day-x': later,
      }, now);
      expect(res.kept.map((r) => r.eventKey), ['lit-sun']);
      expect(res.moved.single.startsAt, later);
      expect(res.expired, isEmpty);
      // ...and expired when the event is gone or also in the past.
      final res2 = reconcileReminders([once], const {}, now);
      expect(res2.expired.single.eventKey, 'day-x');
    });
  });

  group('ReminderStore.put', () {
    final t = DateTime.utc(2027, 1, 1, 6);

    test('reports a storage failure and keeps nothing', () {
      final env = _Env()..failWrites = true;
      final store = ReminderStore(env: env);
      expect(store.put(_r('a', startsAt: t)), ReminderPutResult.storageError);
      expect(store.load(), isEmpty);
      env.failWrites = false;
      expect(store.put(_r('a', startsAt: t)), ReminderPutResult.ok);
    });

    test('replacing swaps a «هذه المرة فقط» reminder for a «كل مرة» one', () {
      final store = ReminderStore(env: _Env());
      final once = _r('lit', occ: '2027-01-01', startsAt: t);
      store.put(once);
      final every = _r('lit', every: true, startsAt: t);
      expect(store.put(every, replacing: once), ReminderPutResult.ok);
      expect(store.load().single.every, isTrue);
    });
  });

  group('initialReminderLead', () {
    final startsAt = DateTime.utc(2027, 1, 1, 10);
    const leads = [0, 15, 60, 1440];

    test('keeps the preferred lead while it is ahead', () {
      expect(initialReminderLead(preferred: 60, leads: leads, startsAt: startsAt, now: DateTime.utc(2027, 1, 1, 8)), 60);
    });
    test('default in the past -> the longest lead still ahead', () {
      // 09:30: 60 min before (09:00) has passed, 15 min (09:45) has not.
      expect(initialReminderLead(preferred: 60, leads: leads, startsAt: startsAt, now: DateTime.utc(2027, 1, 1, 9, 30)), 15);
      expect(initialReminderLead(preferred: 1440, leads: leads, startsAt: startsAt, now: DateTime.utc(2027, 1, 1, 9)), 60);
    });
    test('a lead no longer offered is not kept', () {
      expect(initialReminderLead(preferred: 30, leads: leads, startsAt: startsAt, now: DateTime.utc(2026, 12, 1)), 1440);
    });
    test('every lead passed -> null (save disabled)', () {
      expect(initialReminderLead(preferred: 0, leads: leads, startsAt: startsAt, now: DateTime.utc(2027, 1, 1, 10, 1)), isNull);
    });
  });

  group('review follow-ups', () {
    test('iOS version from the user agent; < 16.4 is too old for web push', () {
      expect(iosVersionFromUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X)'), 1603);
      expect(iosTooOldForPush('Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X)'), isTrue);
      expect(iosTooOldForPush('Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X)'), isFalse);
      expect(iosTooOldForPush('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/17.2 Safari/605.1.15'), isFalse);
      expect(iosTooOldForPush('Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X)'), isTrue);
      expect(iosTooOldForPush('Mozilla/5.0'), isFalse);
    });

    test('root-relative APK paths resolve against the portal origin', () {
      final base = Uri.parse('https://maximos-domadios-church.web.app/schedule');
      expect(resolveInstallUrl('/app/android/church.apk', base), 'https://maximos-domadios-church.web.app/app/android/church.apk');
      expect(resolveInstallUrl('https://x.org/a.apk', base), 'https://x.org/a.apk');
    });

    test('reminder topics keep only FCM topic characters', () {
      expect(reminderTopic(eventKey: 'lit-1', occurrence: '2027-04-30', lead: 60, lang: 'ar'), 'web_rem_lit-1_20270430_60_ar');
      expect(reminderTopic(eventKey: 'lit-1', occurrence: '2027/04/30T09:00', lead: 60, lang: 'en'), 'web_rem_lit-1_20270430T0900_60_en');
    });

    test('an explicitly empty pushTypes list offers nothing; an invalid one falls back', () {
      expect(PushSettings.fromMap({'pushTypes': []}).offered, isEmpty);
      expect(PushSettings.fromMap({'pushTypes': ['nope']}).offered, NotifyType.values);
    });

    test('PushPrefs hash ignores type order', () {
      final at = DateTime.utc(2026, 11, 7);
      final a = PushPrefs(types: {NotifyType.announcements, NotifyType.seasons}, updatedAt: at);
      final b = PushPrefs(types: {NotifyType.seasons, NotifyType.announcements}, updatedAt: at);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('reminderSources (README §6, default in PR A)', () {
    test('absent = lit, mtg, day; parsed from a comma string or a list', () {
      expect(PushSettings.fromMap({'push': true}).reminderSources, {'lit', 'mtg', 'day'});
      expect(PushSettings.fromMap({'reminderSources': 'lit, day'}).reminderSources, {'lit', 'day'});
      expect(PushSettings.fromMap({'reminderSources': ['mtg', 'bogus']}).reminderSources, {'mtg'});
      expect(PushSettings.fromMap({'reminderSources': 'bogus'}).reminderSources, {'lit', 'mtg', 'day'});
      expect(PushSettings.fromMap({'reminderSources': ''}).reminderSources, isEmpty);
    });

    test('remindsFor maps event keys to sources', () {
      final p = PushSettings.fromMap({'push': true, 'reminderSources': 'lit,mtg'});
      expect(p.remindsFor(EventKey.liturgy('1')), isTrue);
      expect(p.remindsFor(EventKey.seasonService('1')), isTrue);
      expect(p.remindsFor(EventKey.meeting('1')), isTrue);
      expect(p.remindsFor(EventKey.dayEvent('1')), isFalse);
      expect(p.remindsFor(EventKey.custom('clinic', '1')), isFalse);
      expect(PushSettings.fromMap({'push': false}).remindsFor(EventKey.liturgy('1')), isFalse);
    });
  });
}
