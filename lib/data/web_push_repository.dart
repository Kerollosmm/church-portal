import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../core/push_env.dart';
import '../domain/push.dart';
import '../domain/reminders.dart';
import '../firebase_options.dart';

typedef BatchWriterFn = Future<void> Function(
  String qid,
  Map<String, dynamic> queueData,
  Map<String, dynamic> rateData, {
  bool isSetCount1,
});

/// Default web Firebase configuration extracted from DefaultFirebaseOptions.web.
Map<String, dynamic> defaultWebFirebaseConfig() {
  const o = DefaultFirebaseOptions.web;
  return {
    'apiKey': o.apiKey,
    'appId': o.appId,
    'messagingSenderId': o.messagingSenderId,
    'projectId': o.projectId,
    'authDomain': o.authDomain,
    'storageBucket': o.storageBucket,
  };
}

/// Parses an RFC 1123 HTTP Date header into a UTC DateTime.
DateTime? parseHttpDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = months[match.group(2)!] ?? 1;
      final year = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final min = int.parse(match.group(5)!);
      final sec = int.parse(match.group(6)!);
      return DateTime.utc(year, month, day, hour, min, sec);
    }
  } catch (_) {}
  return null;
}

/// Repository responsible for Web Push subscriptions, synchronization with Firestore
/// push_queue & meta/push_rate, local state persistence, and deterministic retry.
class WebPushRepository {
  static const String storageKey = 'church_portal_push_web';

  final PushEnv pushEnv;
  final FirebaseFirestore? _firestore;
  final BatchWriterFn? _batchWriter;
  final Future<DateTime> Function()? _fetchServerDate;
  final http.Client? _httpClient;

  Timer? _debounceTimer;

  String? _syncedToken;
  List<String> _syncedWant = const [];
  List<String> _syncedRem = const [];
  bool _pendingSync = false;
  String? _lastSyncedAt;
  String? _lastTokenRefreshCheck;

  // Stored preferences for sync calculation
  PushPrefs? _lastPrefs;
  List<Reminder> _lastReminders = const [];

  WebPushRepository({
    PushEnv? pushEnv,
    this._firestore,
    this._batchWriter,
    this._fetchServerDate,
    this._httpClient,
  })  : pushEnv = pushEnv ?? const PlatformPushEnv() {
    _loadState();
  }

  bool get isSupported => pushEnv.isSupported;
  String get permission => pushEnv.permission;
  String? get syncedToken => _syncedToken;
  List<String> get syncedWant => List.unmodifiable(_syncedWant);
  List<String> get syncedRem => List.unmodifiable(_syncedRem);
  bool get hasPendingSync => _pendingSync;
  String? get lastSyncedAt => _lastSyncedAt;
  String? get lastTokenRefreshCheck => _lastTokenRefreshCheck;

  void _loadState() {
    try {
      final raw = _readLocalStorage();
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _syncedToken = map['syncedToken'] as String?;
        _syncedWant = (map['syncedWant'] as List?)?.cast<String>() ?? const [];
        _syncedRem = (map['syncedRem'] as List?)?.cast<String>() ?? const [];
        _pendingSync = map['pendingSync'] as bool? ?? false;
        _lastSyncedAt = map['lastSyncedAt'] as String?;
        _lastTokenRefreshCheck = map['lastTokenRefreshCheck'] as String?;
      }
    } catch (_) {}
  }

  void _saveState() {
    try {
      final map = {
        'syncedToken': _syncedToken,
        'syncedWant': _syncedWant,
        'syncedRem': _syncedRem,
        'pendingSync': _pendingSync,
        'lastSyncedAt': _lastSyncedAt,
        'lastTokenRefreshCheck': _lastTokenRefreshCheck,
      };
      _writeLocalStorage(jsonEncode(map));
    } catch (_) {}
  }

  static String? _inMemoryStorage;

  String? _readLocalStorage() {
    return _inMemoryStorage;
  }

  void _writeLocalStorage(String value) {
    _inMemoryStorage = value;
  }

  /// Request permission and initialize web token.
  Future<String?> enable({
    required String vapidKey,
    Map<String, dynamic>? firebaseConfig,
  }) async {
    final cfg = firebaseConfig ?? defaultWebFirebaseConfig();
    final token = await pushEnv.enableAndGetToken(
      vapidKey: vapidKey,
      firebaseConfig: cfg,
    );
    if (token != null && token.isNotEmpty) {
      _syncedToken = token;
      _pendingSync = true;
      _saveState();
      return token;
    }
    return null;
  }

  /// Update preferences and schedule debounced sync.
  void syncPreferences({
    required PushPrefs prefs,
    required List<Reminder> reminders,
    bool immediate = false,
  }) {
    _lastPrefs = prefs;
    _lastReminders = List.from(reminders);

    if (_syncedToken == null) return;

    final plan = computeWebTopicSync(
      prefs: prefs,
      currentReminders: reminders,
      previousRemTopics: _syncedRem.toSet(),
      now: DateTime.now().toUtc(),
      previousSyncedToken: null,
      currentToken: _syncedToken!,
    );

    final remList = plan.rem.split(',').where((s) => s.isNotEmpty).toList();
    // If already in sync and not pending, skip
    final wantEqual = plan.want.length == _syncedWant.length &&
        plan.want.toSet().containsAll(_syncedWant);
    final remEqual = remList.length == _syncedRem.length &&
        remList.toSet().containsAll(_syncedRem);
    if (wantEqual && remEqual && !_pendingSync) {
      return;
    }

    _pendingSync = true;
    _saveState();

    _debounceTimer?.cancel();
    if (immediate) {
      flushPendingSync();
    } else {
      _debounceTimer = Timer(const Duration(seconds: 10), () {
        flushPendingSync();
      });
    }
  }

  /// Flush pending sync immediately.
  Future<bool> flushPendingSync() async {
    _debounceTimer?.cancel();
    if (_syncedToken == null || _lastPrefs == null) {
      return false;
    }

    final plan = computeWebTopicSync(
      prefs: _lastPrefs!,
      currentReminders: _lastReminders,
      previousRemTopics: _syncedRem.toSet(),
      now: DateTime.now().toUtc(),
      previousSyncedToken: null,
      currentToken: _syncedToken!,
    );

    final success = await _executeRetryWrite(
      token: _syncedToken!,
      prevToken: null,
      want: plan.want,
      rem: plan.rem,
      drop: plan.drop,
    );

    if (success) {
      _syncedWant = plan.want;
      _syncedRem = plan.rem.split(',').where((s) => s.isNotEmpty).toList();
      _pendingSync = false;
      _lastSyncedAt = DateTime.now().toUtc().toIso8601String();
      _saveState();
      return true;
    } else {
      _pendingSync = true;
      _saveState();
      return false;
    }
  }

  /// Checks token refresh on push surface (at most once every 7 days).
  Future<void> maybeRefreshTokenOnPushSurface({
    required String vapidKey,
    Map<String, dynamic>? firebaseConfig,
  }) async {
    if (_syncedToken == null || permission != 'granted') return;

    final now = DateTime.now().toUtc();
    if (_lastTokenRefreshCheck != null) {
      final last = DateTime.tryParse(_lastTokenRefreshCheck!);
      if (last != null && now.difference(last) < const Duration(days: 7)) {
        return;
      }
    }

    _lastTokenRefreshCheck = now.toIso8601String();
    _saveState();

    final cfg = firebaseConfig ?? defaultWebFirebaseConfig();
    final freshToken = await pushEnv.getWebToken(
      vapidKey: vapidKey,
      firebaseConfig: cfg,
    );

    if (freshToken != null && freshToken.isNotEmpty && freshToken != _syncedToken) {
      final oldToken = _syncedToken;
      _syncedToken = freshToken;
      _pendingSync = true;
      _saveState();

      if (_lastPrefs != null) {
        final plan = computeWebTopicSync(
          prefs: _lastPrefs!,
          currentReminders: _lastReminders,
          previousRemTopics: _syncedRem.toSet(),
          now: DateTime.now().toUtc(),
          previousSyncedToken: oldToken,
          currentToken: freshToken,
        );

        final success = await _executeRetryWrite(
          token: freshToken,
          prevToken: oldToken,
          want: plan.want,
          rem: plan.rem,
          drop: plan.drop,
        );

        if (success) {
          _syncedWant = plan.want;
          _syncedRem = plan.rem.split(',').where((s) => s.isNotEmpty).toList();
          _pendingSync = false;
          _lastSyncedAt = DateTime.now().toUtc().toIso8601String();
          _saveState();
        }
      }
    }
  }

  /// Unsubscribe all topics, delete web token and clear local state.
  Future<bool> unsubscribeAll({
    Map<String, dynamic>? firebaseConfig,
  }) async {
    _debounceTimer?.cancel();
    final oldToken = _syncedToken;
    final heldRem = List<String>.from(_syncedRem);

    if (oldToken != null) {
      await _executeRetryWrite(
        token: oldToken,
        prevToken: null,
        want: const [],
        rem: '',
        drop: heldRem.join(','),
      );

      final cfg = firebaseConfig ?? defaultWebFirebaseConfig();
      await pushEnv.deleteWebToken(firebaseConfig: cfg);
    }

    _syncedToken = null;
    _syncedWant = const [];
    _syncedRem = const [];
    _pendingSync = false;
    _lastSyncedAt = null;
    _saveState();
    return true;
  }

  Future<DateTime> _getServerDate() async {
    if (_fetchServerDate != null) {
      return _fetchServerDate();
    }
    try {
      final client = _httpClient ?? http.Client();
      final res = await client.head(
        Uri.parse('/data/today.json'),
        headers: {'cache-control': 'no-store'},
      );
      final dateHdr = res.headers['date'];
      final parsed = parseHttpDate(dateHdr);
      if (parsed != null) return parsed;
    } catch (_) {}
    return DateTime.now().toUtc();
  }

  /// Executes the deterministic 4-step retry sequence with server date sync.
  Future<bool> _executeRetryWrite({
    required String token,
    required String? prevToken,
    required List<String> want,
    required String rem,
    required String drop,
  }) async {
    final qid = 'q_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';

    final queueData = <String, dynamic>{
      'token': token,
      if (prevToken != null && prevToken.isNotEmpty) 'prevToken': prevToken,
      'want': want,
      'rem': rem,
      'drop': drop,
      'createdAt': FieldValue.serverTimestamp(),
      'retryCount': 0,
    };

    // Attempt 1: Normal path with local UTC day and increment(1)
    final localUtc = DateTime.now().toUtc();
    final localDayInt = localUtc.year * 10000 + localUtc.month * 100 + localUtc.day;

    try {
      await _writeBatch(qid, queueData, {
        'day': localDayInt,
        'count': FieldValue.increment(1),
        'lastAt': FieldValue.serverTimestamp(),
        'lastId': qid,
      }, isSetCount1: false);
      return true;
    } catch (_) {}

    // First rejection: Sync authoritative server date from HTTP header
    final serverDate = await _getServerDate();
    final serverDayInt = serverDate.year * 10000 + serverDate.month * 100 + serverDate.day;

    // Wait 3.2s + jitter (0-300ms) to clear 3s rate throttle
    final jitter1 = math.Random().nextInt(300);
    await Future.delayed(Duration(milliseconds: 3200 + jitter1));

    // Attempt 2: Synced serverDay with increment(1)
    try {
      await _writeBatch(qid, queueData, {
        'day': serverDayInt,
        'count': FieldValue.increment(1),
        'lastAt': FieldValue.serverTimestamp(),
        'lastId': qid,
      }, isSetCount1: false);
      return true;
    } catch (_) {}

    // Attempt 3: UTC day rollover path (literal count: 1)
    try {
      await _writeBatch(qid, queueData, {
        'day': serverDayInt,
        'count': 1,
        'lastAt': FieldValue.serverTimestamp(),
        'lastId': qid,
      }, isSetCount1: true);
      return true;
    } catch (_) {}

    // Wait 3.5s + jitter
    final jitter2 = math.Random().nextInt(300);
    await Future.delayed(Duration(milliseconds: 3500 + jitter2));

    // Attempt 4: Synced serverDay with increment(1) once more
    try {
      await _writeBatch(qid, queueData, {
        'day': serverDayInt,
        'count': FieldValue.increment(1),
        'lastAt': FieldValue.serverTimestamp(),
        'lastId': qid,
      }, isSetCount1: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBatch(
    String qid,
    Map<String, dynamic> queueData,
    Map<String, dynamic> rateData, {
    required bool isSetCount1,
  }) async {
    if (_batchWriter != null) {
      await _batchWriter(qid, queueData, rateData, isSetCount1: isSetCount1);
      return;
    }

    final firestore = _firestore ?? FirebaseFirestore.instance;
    final batch = firestore.batch();
    final qRef = firestore.collection('push_queue').doc(qid);
    final rateRef = firestore.collection('meta').doc('push_rate');

    batch.set(qRef, queueData);
    batch.set(rateRef, rateData, SetOptions(merge: true));
    await batch.commit();
  }

  Future<bool> showTestNotification({String? title, String? body, String? link}) =>
      pushEnv.showSwTestNotification(title: title, body: body, link: link);

  Future<List<WebInboxItem>> getInbox() => pushEnv.readInbox();

  Future<bool> clearInbox() => pushEnv.clearInbox();

  Future<bool> setQuietHours({
    required bool enabled,
    required String start,
    required String end,
  }) =>
      pushEnv.syncQuietHours(enabled: enabled, start: start, end: end);
}
