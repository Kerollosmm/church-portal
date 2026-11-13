import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:church_portal/core/push_env.dart';
import 'package:church_portal/data/web_push_repository.dart';
import 'package:church_portal/domain/push.dart';
import 'package:church_portal/domain/reminders.dart';

class FakePushEnv implements PushEnv {
  String _perm = 'granted';
  String? tokenToReturn = 'test_token_123';
  bool deleted = false;
  final List<WebInboxItem> mockInbox = [];
  bool quietSynced = false;
  final Map<String, String> storage = {};

  @override
  String? readStorage(String key) => storage[key];

  @override
  void writeStorage(String key, String value) => storage[key] = value;

  @override
  bool get isSupported => true;

  @override
  String get permission => _perm;

  void setPermission(String p) => _perm = p;

  @override
  Future<String> requestPermission() async => _perm;

  @override
  Future<String> refreshPermission() async => _perm;

  @override
  Future<bool> openSystemSettings() async => false;

  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async => true;

  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async =>
      tokenToReturn;

  @override
  Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async =>
      tokenToReturn;

  @override
  Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) async {
    deleted = true;
    return true;
  }

  @override
  Future<bool> showSwTestNotification({String? title, String? body, String? link}) async => true;

  @override
  Future<List<WebInboxItem>> readInbox() async => mockInbox;

  @override
  Future<bool> clearInbox() async {
    mockInbox.clear();
    return true;
  }

  @override
  Future<bool> syncQuietHours({
    required bool enabled,
    required String start,
    required String end,
    bool remindersRespectQuietHours = true,
  }) async {
    quietSynced = true;
    return true;
  }

  @override
  Stream<String> get deepLinks => const Stream.empty();

  @override
  Stream<WebInboxItem> get inboxEvents => const Stream.empty();
}

void main() {
  group('parseHttpDate', () {
    test('parses standard RFC 1123 HTTP Date header', () {
      final dt = parseHttpDate('Mon, 09 Nov 2026 12:34:56 GMT');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 11);
      expect(dt.day, 9);
      expect(dt.hour, 12);
      expect(dt.minute, 34);
      expect(dt.second, 56);
      expect(dt.isUtc, isTrue);
    });

    test('returns null for invalid or empty date', () {
      expect(parseHttpDate(null), isNull);
      expect(parseHttpDate(''), isNull);
      expect(parseHttpDate('invalid-date'), isNull);
    });
  });

  group('WebPushRepository', () {
    test('enable calls pushEnv and saves token', () async {
      final fakeEnv = FakePushEnv();
      final repo = WebPushRepository(pushEnv: fakeEnv);

      final token = await repo.enable(vapidKey: 'test_vapid');
      expect(token, 'test_token_123');
      expect(repo.syncedToken, 'test_token_123');
      expect(repo.hasPendingSync, isTrue);
    });

    test('syncPreferences and flushPendingSync batch write to push_queue', () async {
      final fakeEnv = FakePushEnv();
      final writtenBatches = <Map<String, dynamic>>[];

      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writtenBatches.add({
            'qid': qid,
            'queueData': queueData,
            'rateData': rateData,
            'isSetCount1': isSetCount1,
          });
        },
      );

      await repo.enable(vapidKey: 'test_vapid');

      final prefs = PushPrefs(
        types: const {NotifyType.announcements, NotifyType.reminders},
        lang: 'ar',
        updatedAt: DateTime.now().toUtc(),
      );

      final reminders = [
        Reminder(
          eventKey: 'lit-first',
          startsAt: DateTime.now().toUtc().add(const Duration(days: 2)),
          lead: 60,
          title: const {'ar': 'قداس باكر', 'en': 'Morning Liturgy'},
          createdAt: DateTime.now().toUtc(),
          every: true,
        ),
      ];

      await repo.syncPreferences(
        prefs: prefs,
        reminders: reminders,
        immediate: false,
      );
      await repo.flushPendingSync();

      expect(writtenBatches.length, 1);
      final batch = writtenBatches.first;
      final qData = batch['queueData'] as Map<String, dynamic>;
      expect(qData['token'], 'test_token_123');
      expect(qData['want'], contains('web_announcements_ar'));
      expect(qData['rem'], contains('web_rem_lit-first_60_ar'));
      expect(repo.hasPendingSync, isFalse);
      expect(repo.syncedWant, contains('web_announcements_ar'));
    });

    test('deterministic retry sequence attempts rollover on rejection', () async {
      final fakeEnv = FakePushEnv();
      int attempt = 0;
      final attemptsCount1 = <bool>[];

      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        fetchServerDate: () async => DateTime.utc(2026, 11, 10, 0, 1),
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          attempt++;
          attemptsCount1.add(isSetCount1);
          if (attempt == 1) {
            // Attempt 1 fails (e.g. rate limit or day rollover)
            throw Exception('permission-denied');
          }
          if (attempt == 2) {
            // Attempt 2 fails
            throw Exception('permission-denied');
          }
          // Attempt 3 (rollover count: 1) succeeds!
        },
      );

      await repo.enable(vapidKey: 'test_vapid');

      await repo.syncPreferences(
        prefs: PushPrefs(
          types: const {NotifyType.announcements},
          lang: 'ar',
          updatedAt: DateTime.now().toUtc(),
        ),
        reminders: const [],
        immediate: false,
      );

      final success = await repo.flushPendingSync();
      expect(success, isTrue);
      expect(attempt, 3);
      expect(attemptsCount1, [false, false, true]); // 3rd attempt had isSetCount1: true!
    });

    test('syncPreferences returns true when syncedToken is null and types empty, false if types not empty', () async {
      final fakeEnv = FakePushEnv();
      final repo = WebPushRepository(pushEnv: fakeEnv);

      final okEmpty = await repo.syncPreferences(
        prefs: PushPrefs(types: const {}, updatedAt: DateTime.now().toUtc()),
        reminders: const [],
      );
      expect(okEmpty, isTrue);

      final notOkNonEmpty = await repo.syncPreferences(
        prefs: PushPrefs(types: const {NotifyType.announcements}, updatedAt: DateTime.now().toUtc()),
        reminders: const [],
      );
      expect(notOkNonEmpty, isFalse);
    });

    test('concurrent calls to flushPendingSync serialize safely via queue', () async {
      final fakeEnv = FakePushEnv();
      final order = <int>[];

      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          order.add(1);
          await Future.delayed(const Duration(milliseconds: 20));
          order.add(2);
        },
      );

      await repo.enable(vapidKey: 'test_vapid');

      await repo.syncPreferences(
        prefs: PushPrefs(
          types: const {NotifyType.announcements},
          lang: 'ar',
          updatedAt: DateTime.now().toUtc(),
        ),
        reminders: const [],
        immediate: false,
      );

      final f1 = repo.flushPendingSync();
      final f2 = repo.flushPendingSync();
      final results = await Future.wait([f1, f2]);

      expect(results, [true, true]);
      expect(order, [1, 2]); // First completed and cleared pending sync before second ran
    });

    test('unsubscribeAll clears local state and deletes token', () async {
      final fakeEnv = FakePushEnv();
      final writtenBatches = <Map<String, dynamic>>[];

      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writtenBatches.add({
            'queueData': queueData,
          });
        },
      );

      await repo.enable(vapidKey: 'test_vapid');
      await repo.unsubscribeAll();

      expect(fakeEnv.deleted, isTrue);
      expect(repo.syncedToken, isNull);
      expect(repo.syncedWant, isEmpty);
      expect(repo.syncedRem, isEmpty);
      expect(writtenBatches.length, 1);
      expect(writtenBatches.first['queueData']['want'], isEmpty);
    });

    test('syncPreferences with empty PushPrefs queues want: [], rem: empty, drop: previous topics', () async {
      final fakeEnv = FakePushEnv();
      final writes = <Map<String, dynamic>>[];
      final now = DateTime.now().toUtc();
      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        fetchServerDate: () async => now,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writes.add(Map<String, dynamic>.from(queueData));
        },
      );

      await repo.enable(vapidKey: 'test_vapid');
      final reminder = Reminder(
        eventKey: 'lit-1',
        lead: 15,
        every: false,
        title: const {'ar': 'قداس', 'en': 'Liturgy'},
        startsAt: now.add(const Duration(hours: 2)),
        createdAt: now,
      );
      final okOn = await repo.syncPreferences(
        prefs: PushPrefs(
          types: const {NotifyType.announcements, NotifyType.reminders},
          lang: 'ar',
          updatedAt: now,
        ),
        reminders: [reminder],
        immediate: true,
      );
      expect(okOn, isTrue);
      expect(writes.last['rem'], isNotEmpty);

      final okEmpty = await repo.syncPreferences(
        prefs: PushPrefs(
          types: const {},
          lang: 'ar',
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
        reminders: const [],
        immediate: true,
      );
      expect(okEmpty, isTrue);
      expect(writes.last['want'], isEmpty);
      expect(writes.last['rem'], '');
      expect(writes.last['drop'], isNotEmpty);
    });

    test('resumePendingSync flushes stored pendingSync opt-out on new repository instance', () async {
      final fakeEnv = FakePushEnv();
      fakeEnv.storage[WebPushRepository.storageKey] = jsonEncode({
        'syncedToken': 'tok_saved',
        'syncedWant': ['announcements', 'lang_ar'],
        'syncedRem': <String>[],
        'pendingSync': true,
      });
      final writes = <Map<String, dynamic>>[];
      final now = DateTime.now().toUtc();
      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        fetchServerDate: () async => now,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writes.add(Map<String, dynamic>.from(queueData));
        },
      );
      addTearDown(repo.dispose);

      expect(repo.hasPendingSync, isTrue);
      final ok = await repo.resumePendingSync(
        prefs: PushPrefs(types: const {}, lang: 'ar', updatedAt: now),
        reminders: const [],
      );
      expect(ok, isTrue);
      expect(repo.hasPendingSync, isFalse);
      expect(writes.length, 1);
      expect(writes.single['want'], isEmpty);
      expect(writes.single['drop'], isEmpty); // prevWant is not stored locally, rem only
    });

    test('enableRetryTimer retries failed flush with backoff and clears pendingSync once healthy', () async {
      final fakeEnv = FakePushEnv();
      var failWrites = true;
      var writeAttempts = 0;
      final recovered = Completer<void>();
      final now = DateTime.now().toUtc();
      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        fetchServerDate: () async => now,
        enableRetryTimer: true,
        retryBaseDelay: const Duration(milliseconds: 15),
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writeAttempts++;
          if (failWrites) {
            throw StateError('transient network error');
          }
          if (!recovered.isCompleted) {
            recovered.complete();
          }
        },
      );
      addTearDown(repo.dispose);

      await repo.enable(vapidKey: 'test_vapid');
      final firstResult = await repo.syncPreferences(
        prefs: PushPrefs(
          types: const {NotifyType.announcements},
          lang: 'ar',
          updatedAt: now,
        ),
        reminders: const [],
        immediate: true,
      );
      expect(firstResult, isFalse);
      expect(repo.hasPendingSync, isTrue);
      expect(repo.pendingRetryAttempts, 1);

      // Heal server before the scheduled backoff timer fires.
      failWrites = false;
      await recovered.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(writeAttempts, greaterThanOrEqualTo(2));
      expect(repo.hasPendingSync, isFalse);
      expect(repo.pendingRetryAttempts, 0);
    });

    test('concurrent resumePendingSync on sharedFor executes only a single write', () async {
      final fakeEnv = FakePushEnv();
      fakeEnv.storage[WebPushRepository.storageKey] = jsonEncode({
        'syncedToken': 'tok_shared',
        'syncedWant': ['announcements', 'lang_ar'],
        'syncedRem': <String>[],
        'pendingSync': true,
      });
      final writes = <Map<String, dynamic>>[];
      WebPushRepository.debugBatchWriter = (qid, queueData, rateData, {bool isSetCount1 = false}) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        writes.add(Map<String, dynamic>.from(queueData));
      };
      addTearDown(() => WebPushRepository.debugBatchWriter = null);

      final now = DateTime.now().toUtc();
      final repoA = WebPushRepository.sharedFor(fakeEnv);
      final repoB = WebPushRepository.sharedFor(fakeEnv);
      addTearDown(repoA.dispose);
      expect(identical(repoA, repoB), isTrue);

      final prefs = PushPrefs(types: const {NotifyType.seasons}, lang: 'ar', updatedAt: now);
      final results = await Future.wait([
        repoA.resumePendingSync(prefs: prefs, reminders: const []),
        repoB.resumePendingSync(prefs: prefs, reminders: const []),
      ]);
      expect(results, [true, true]);
      expect(writes, hasLength(1));
      expect(writes.single['want'], ['web_seasons_ar']);
    });

    test('resumePendingSync skips without prompting when token is missing or permission denied with types', () async {
      final fakeEnv = FakePushEnv();
      fakeEnv.setPermission('default');
      fakeEnv.storage[WebPushRepository.storageKey] = jsonEncode({
        'syncedToken': null,
        'pendingSync': true,
      });
      var writeCalls = 0;
      final now = DateTime.now().toUtc();
      final repo = WebPushRepository(
        pushEnv: fakeEnv,
        batchWriter: (qid, queueData, rateData, {bool isSetCount1 = false}) async {
          writeCalls++;
        },
      );
      addTearDown(repo.dispose);

      await repo.resumePendingSync(
        prefs: PushPrefs(types: const {NotifyType.announcements}, lang: 'ar', updatedAt: now),
        reminders: const [],
      );
      expect(writeCalls, 0);
    });
  });
}
