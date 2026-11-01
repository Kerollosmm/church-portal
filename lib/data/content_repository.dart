import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/features.dart';
import '../domain/models.dart';
import 'seed_data.dart';

class ContactUnavailableException implements Exception {
  @override
  String toString() => 'Contact form is unavailable (Firebase not configured).';
}

/// Read access to the public content + the one public write (contact form).
abstract class ContentRepository {
  /// True when content comes from Firestore (false = bundled seed data).
  bool get isLive;

  /// True while any visible content is being served from the bundled seed
  /// (no Firebase, database not seeded yet, or a query fell back).
  ValueListenable<bool> get servingSeed;

  Stream<ChurchSettings> settings();

  /// Section toggles + home layout (`settings/features`; defaults = all on).
  Stream<FeatureSettings> features();
  Stream<List<Alert>> alerts();
  Stream<List<Season>> seasons();
  Stream<List<Liturgy>> liturgies();
  Stream<List<Meeting>> meetings();
  Stream<List<Activity>> activities();
  Stream<List<Clinic>> clinics();
  Stream<List<Facility>> facilities();
  Stream<List<Priest>> priests();
  Stream<List<Milestone>> milestones();
  Stream<List<Saint>> saints();

  /// Writes a validated contact message (payload from validateContactForm).
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang});
}

/// Offline / unconfigured implementation backed by assets/seed/seed.json.
class SeedRepository implements ContentRepository {
  final SeedData seed;
  SeedRepository(this.seed);

  @override
  bool get isLive => false;

  @override
  final ValueListenable<bool> servingSeed = ValueNotifier<bool>(true);

  Stream<T> _once<T>(T v) => Stream<T>.value(v);

  @override
  Stream<ChurchSettings> settings() => _once(seed.settings);
  @override
  Stream<FeatureSettings> features() => _once(seed.features);
  @override
  Stream<List<Alert>> alerts() => _once(seed.alerts);
  @override
  Stream<List<Season>> seasons() => _once(seed.seasons);
  @override
  Stream<List<Liturgy>> liturgies() => _once(seed.liturgies);
  @override
  Stream<List<Meeting>> meetings() => _once(seed.meetings);
  @override
  Stream<List<Activity>> activities() => _once(seed.activities);
  @override
  Stream<List<Clinic>> clinics() => _once(seed.clinics);
  @override
  Stream<List<Facility>> facilities() => _once(seed.facilities);
  @override
  Stream<List<Priest>> priests() => _once(seed.priests);
  @override
  Stream<List<Milestone>> milestones() => _once(seed.milestones);
  @override
  Stream<List<Saint>> saints() => _once(seed.saints);

  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async =>
      throw ContactUnavailableException();
}

/// Converts Firestore-specific values to plain Dart (Timestamp -> UTC DateTime).
Object? normalizeFirestoreValue(Object? v) {
  if (v is Timestamp) return v.toDate().toUtc();
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), normalizeFirestoreValue(val)));
  if (v is List) return v.map(normalizeFirestoreValue).toList();
  return v;
}

Map<String, dynamic> normalizeDoc(Map<String, dynamic>? data) =>
    (normalizeFirestoreValue(data ?? const {}) as Map).cast<String, dynamic>();

/// Live Firestore implementation (offline persistence is enabled at startup).
///
/// Fallback rules: if `settings/church` does not exist (database not seeded
/// yet) every stream serves the bundled seed; if a query fails (permissions,
/// network with empty cache, ...) that stream falls back to the seed too.
class FirestoreRepository implements ContentRepository {
  final FirebaseFirestore db;
  final SeedData seed;
  FirestoreRepository(this.db, this.seed);

  @override
  bool get isLive => true;

  final ValueNotifier<bool> _servingSeed = ValueNotifier<bool>(false);
  final Set<String> _fallbackStreams = {};

  @override
  ValueListenable<bool> get servingSeed => _servingSeed;

  void _markFallback(String key, bool onSeed) {
    if (onSeed) {
      _fallbackStreams.add(key);
    } else {
      _fallbackStreams.remove(key);
    }
    _servingSeed.value = _fallbackStreams.isNotEmpty;
  }

  /// Whether `settings/church` exists. A successful answer is cached; a failed
  /// or timed-out read is not, so the next subscription retries.
  Future<bool>? _seededFuture;
  Future<bool> get _seeded async {
    try {
      return await (_seededFuture ??= db
          .doc('settings/church')
          .get()
          .timeout(const Duration(seconds: 8))
          .then((d) => d.exists));
    } catch (e) {
      debugPrint('settings/church check failed, serving seed: $e');
      _seededFuture = null;
      return false;
    }
  }

  Stream<T> _guard<T>(String key, Stream<T> Function() live, T fallback) async* {
    if (!await _seeded) {
      _markFallback(key, true);
      yield fallback;
      return;
    }
    try {
      await for (final v in live()) {
        _markFallback(key, false);
        yield v;
      }
    } catch (e) {
      debugPrint('Firestore stream $key failed, serving seed: $e');
      _markFallback(key, true);
      yield fallback;
    }
  }

  Stream<List<T>> _col<T>(String name, T Function(String, Map<String, dynamic>) f, List<T> fallback,
          {int Function(T a, T b)? sort}) =>
      _guard(name, () {
        return db.collection(name).snapshots().map((snap) {
          final list = snap.docs.map((d) => f(d.id, normalizeDoc(d.data()))).toList();
          if (sort != null) list.sort(sort);
          return list;
        });
      }, fallback);

  @override
  Stream<ChurchSettings> settings() => _guard(
        'settings',
        () => db.doc('settings/church').snapshots().map((d) => d.exists ? ChurchSettings.fromMap(normalizeDoc(d.data())) : seed.settings),
        seed.settings,
      );
  @override
  Stream<FeatureSettings> features() => _guard(
        'features',
        () => db
            .doc('settings/features')
            .snapshots()
            .map((d) => d.exists ? FeatureSettings.fromMap(normalizeDoc(d.data())) : seed.features),
        seed.features,
      );
  @override
  Stream<List<Alert>> alerts() => _col('alerts', Alert.fromMap, seed.alerts);
  @override
  Stream<List<Season>> seasons() => _col('seasons', Season.fromMap, seed.seasons);
  @override
  Stream<List<Liturgy>> liturgies() => _col('liturgies', Liturgy.fromMap, seed.liturgies);
  @override
  Stream<List<Meeting>> meetings() => _col('meetings', Meeting.fromMap, seed.meetings);
  @override
  Stream<List<Activity>> activities() => _col('activities', Activity.fromMap, seed.activities);
  @override
  Stream<List<Clinic>> clinics() => _col('clinics', Clinic.fromMap, seed.clinics);
  @override
  Stream<List<Facility>> facilities() => _col('facilities', Facility.fromMap, seed.facilities);
  @override
  Stream<List<Priest>> priests() =>
      _col('priests', Priest.fromMap, seed.priests, sort: (a, b) => a.order.compareTo(b.order));
  @override
  Stream<List<Milestone>> milestones() =>
      _col('milestones', Milestone.fromMap, seed.milestones, sort: (a, b) => a.order.compareTo(b.order));
  @override
  Stream<List<Saint>> saints() => _col('saints', Saint.fromMap, seed.saints, sort: (a, b) => a.order.compareTo(b.order));

  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async {
    // Batched with a global throttle doc so the rules can rate-limit public
    // submissions on the server (see firestore.rules: meta/contact_rate).
    final batch = db.batch();
    batch.set(db.collection('contact_messages').doc(), {
      'name': payload['name'],
      'phone': payload['phone'] ?? '',
      'email': payload['email'] ?? '',
      'message': payload['message'],
      'lang': lang,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.doc('meta/contact_rate'), {'lastAt': FieldValue.serverTimestamp()});
    await batch.commit().timeout(const Duration(seconds: 15));
  }
}
