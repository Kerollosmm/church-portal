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

/// Whether the database is seeded (`settings/church` exists).
///
/// Only a positive answer is cached; a "not there yet" answer or a failed /
/// timed-out read is not, so a later check (the next subscription, or the next
/// live value of a stream still on the seed) sees the database once it is
/// seeded — e.g. when seeding runs while the app is open.
@visibleForTesting
class SeedGate {
  SeedGate(this._read);
  final Future<bool> Function() _read;
  Future<bool>? _pending;
  bool _seeded = false;
  bool _markerAbsent = false;

  /// The last check that could answer found no `settings/church` (known
  /// unseeded, as opposed to "could not tell").
  bool get markerAbsent => _markerAbsent;

  Future<bool> check() async {
    if (_seeded) return true;
    try {
      final seeded = await (_pending ??= _read());
      _pending = null;
      _seeded = seeded;
      _markerAbsent = !seeded;
      return seeded;
    } catch (e) {
      debugPrint('settings/church check failed, serving seed: $e');
      _pending = null;
      _markerAbsent = false;
      return false;
    }
  }
}

/// Serves [live] once the database is known to be seeded, else [fallback].
///
/// A failed or timed-out seeding check (cold start, weak signal, offline) no
/// longer ends the stream: the seed is shown first and the live query stays
/// subscribed. Each live value re-checks [gate]; it replaces the seed when the
/// check succeeds or — only when the check could not answer at all — when the
/// value itself proves its own data exists ([confirms], e.g. a non-empty
/// collection; this never vouches for other streams). A database known to be
/// unseeded keeps serving the seed until a later check finds the marker.
/// [onSeed] reports whether this stream is on the seed; a stream cancelled
/// while on the seed reports false so the "bundled content" banner is never
/// stranded.
@visibleForTesting
Stream<T> guardSeeded<T>({
  required SeedGate gate,
  required Stream<T> Function() live,
  required T fallback,
  required void Function(bool onSeed) onSeed,
  bool Function(T v)? confirms,
  String label = '',
}) {
  // A plain controller (not an async* generator) so cancelling takes effect
  // at once, even while waiting for the next snapshot.
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  var onSeedNow = false;
  var cancelled = false;
  var done = false;
  void mark(bool v) {
    onSeedNow = v;
    onSeed(v);
  }

  out = StreamController<T>(
    onListen: () async {
      var confirmed = await gate.check();
      if (cancelled) return;
      if (!confirmed) {
        mark(true);
        out.add(fallback);
      }
      final s = live().listen(null);
      sub = s;
      s.onData((v) async {
        if (!confirmed) {
          s.pause(); // keep values in order while re-checking
          try {
            final seeded = await gate.check();
            confirmed = seeded || (!gate.markerAbsent && (confirms?.call(v) ?? false));
          } finally {
            if (!cancelled) s.resume();
          }
          if (!confirmed || cancelled) return;
        }
        mark(false);
        out.add(v);
      });
      s.onError((Object e) {
        debugPrint('Firestore stream $label failed, serving seed: $e');
        mark(true);
        out.add(fallback);
        done = true; // keeps showing the seed: the "bundled content" mark stays
        s.cancel();
        out.close();
      });
      s.onDone(() {
        done = true;
        out.close();
      });
    },
    onCancel: () async {
      cancelled = true;
      // Cancelled by the listener while on the seed: this stream no longer
      // serves anything, so it must not keep the banner on.
      if (!done && onSeedNow) onSeed(false);
      await sub?.cancel();
    },
  );
  return out.stream;
}

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

  /// `settings/church` existence check (the "database is seeded" marker).
  late final SeedGate _gate = SeedGate(
      () => db.doc('settings/church').get().timeout(const Duration(seconds: 8)).then((d) => d.exists));

  Stream<T> _guard<T>(String key, Stream<T> Function() live, T fallback, {bool Function(T v)? confirms}) =>
      guardSeeded(
        gate: _gate,
        live: live,
        fallback: fallback,
        confirms: confirms,
        onSeed: (onSeed) => _markFallback(key, onSeed),
        label: key,
      );

  Stream<List<T>> _col<T>(String name, T Function(String, Map<String, dynamic>) f, List<T> fallback,
          {int Function(T a, T b)? sort}) =>
      _guard(name, () {
        return db.collection(name).snapshots().map((snap) {
          final list = snap.docs.map((d) => f(d.id, normalizeDoc(d.data()))).toList();
          if (sort != null) list.sort(sort);
          return list;
        });
      }, fallback, confirms: (list) => list.isNotEmpty);

  @override
  Stream<ChurchSettings> settings() => _guard(
        'settings',
        () => db.doc('settings/church').snapshots().map((d) => d.exists ? ChurchSettings.fromMap(normalizeDoc(d.data())) : seed.settings),
        seed.settings,
        // settings/church IS the seeding marker: a live snapshot of it that
        // differs from the seed proves it exists.
        confirms: (v) => !identical(v, seed.settings),
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
    // meta/contact_rate.lastMsgId names the message created in the same
    // batch, so the rules can reject a standalone write to the throttle doc.
    final batch = db.batch();
    final msgRef = db.collection('contact_messages').doc();
    batch.set(msgRef, {
      'name': payload['name'],
      'phone': payload['phone'] ?? '',
      'email': payload['email'] ?? '',
      'message': payload['message'],
      'lang': lang,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.doc('meta/contact_rate'), {
      'lastAt': FieldValue.serverTimestamp(),
      'lastMsgId': msgRef.id,
    });
    await batch.commit().timeout(const Duration(seconds: 15));
  }
}
