import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/assistant_settings.dart';
import '../domain/contact_categories.dart';
import '../domain/custom_content.dart';
import '../domain/features.dart';
import '../domain/models.dart';
import 'error_reporting.dart';
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

  /// Admin-defined categories, their items and custom pages (ADR-027). Not
  /// in the bundled seed: empty until an admin creates some.
  Stream<List<CustomCategory>> categories();
  Stream<List<CategoryEntry>> entries();
  Stream<List<CustomPage>> pages();

  /// Contact-form categories (`settings/contact`; missing = code defaults, ADR-028).
  Stream<ContactSettings> contactSettings();

  /// Assistant settings (`settings/assistant`; missing = code defaults, ADR-029).
  Stream<AssistantSettings> assistantSettings();

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
  Stream<List<CustomCategory>> categories() => _once(const []);
  @override
  Stream<List<CategoryEntry>> entries() => _once(const []);
  @override
  Stream<List<CustomPage>> pages() => _once(const []);
  @override
  Stream<ContactSettings> contactSettings() => _once(ContactSettings.defaults);
  @override
  Stream<AssistantSettings> assistantSettings() => _once(AssistantSettings.defaults);

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
///
/// The marker can also be proven without this check: the live
/// `settings/church` listener calls [markSeeded] as soon as a snapshot shows
/// the document (ADR-038). [whenSeeded] then lets every stream still on the
/// bundled copy switch to the live value it already holds — a missing
/// optional doc (code defaults) or an empty collection gets no second
/// snapshot from Firestore, so it could otherwise never recover from a
/// seeding check that timed out on a slow cold start.
@visibleForTesting
class SeedGate {
  SeedGate(this._read);
  final Future<bool> Function() _read;
  Future<bool>? _pending;
  bool _seeded = false;
  bool _markerAbsent = false;
  final Completer<void> _seededSignal = Completer<void>();

  /// The last check that could answer found no `settings/church` (known
  /// unseeded, as opposed to "could not tell").
  bool get markerAbsent => _markerAbsent;

  /// The database is known to be seeded (a check said so, or [markSeeded]).
  bool get isSeeded => _seeded;

  /// Completes once the database is known to be seeded.
  Future<void> get whenSeeded => _seededSignal.future;

  /// Records proof that `settings/church` exists (a live snapshot of it).
  void markSeeded() {
    _seeded = true;
    _markerAbsent = false;
    if (!_seededSignal.isCompleted) _seededSignal.complete();
  }

  Future<bool> check() async {
    if (_seeded) return true;
    try {
      final seeded = await (_pending ??= _read());
      _pending = null;
      if (seeded) {
        markSeeded();
      } else if (!_seeded) {
        _markerAbsent = true;
      }
      // A proof that arrived while this read was in flight wins over it.
      return _seeded;
    } catch (e) {
      debugPrint('settings/church check failed, serving seed: $e');
      _pending = null;
      if (!_seeded) _markerAbsent = false;
      return _seeded;
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
/// When the gate learns later that the database is seeded
/// ([SeedGate.whenSeeded], e.g. from the `settings/church` listener), the last
/// live value held back is emitted at once and later values pass straight
/// through (ADR-038: an empty collection or a missing optional doc produces
/// no further snapshot, so waiting for "the next value" stranded the seed and
/// the footer's "bundled content" note).
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
  Duration? fallbackDelay,
  String label = '',
}) {
  // A plain controller (not an async* generator) so cancelling takes effect
  // at once, even while waiting for the next snapshot.
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  var onSeedNow = false;
  var cancelled = false;
  var done = false;
  var emitted = false;
  // A live value is waiting for its seeding re-check: the delayed fallback
  // must not overtake it ([fallbackDue] then fires once the re-check fails).
  var rechecking = false;
  var fallbackDue = false;
  Timer? fallbackTimer;
  // The last live value the gate has not vouched for yet (see whenSeeded).
  T? heldLive;
  var holding = false;
  void mark(bool v) {
    onSeedNow = v;
    onSeed(v);
  }

  void emit(T v, {required bool seed}) {
    if (out.isClosed) return;
    fallbackTimer?.cancel();
    emitted = true;
    mark(seed);
    out.add(v);
  }

  out = StreamController<T>(
    onListen: () async {
      var confirmed = await gate.check();
      if (cancelled) return;
      if (!confirmed) {
        // Proof of seeding that arrives later (another stream's check, or
        // the settings/church listener) releases the value held back.
        unawaited(gate.whenSeeded.then((_) {
          if (cancelled || done || confirmed) return;
          confirmed = true;
          fallbackTimer?.cancel(); // seeded: wait for the live value instead
          fallbackDue = false;
          if (holding) {
            holding = false;
            final v = heldLive as T;
            heldLive = null;
            emit(v, seed: false);
          }
        }));
        if (fallbackDelay == null) {
          emit(fallback, seed: true);
        } else {
          // No bundled copy worth showing (custom content): give the live
          // query [fallbackDelay] to answer before settling on the fallback,
          // so a page never says "not available" while its data is on its way.
          // A live value still on its re-check defers the fallback until the
          // re-check has answered (it may confirm the value instead).
          fallbackTimer = Timer(fallbackDelay, () {
            if (cancelled || emitted) return;
            if (rechecking) {
              fallbackDue = true;
            } else {
              emit(fallback, seed: true);
            }
          });
        }
      }
      final s = live().listen(null);
      sub = s;
      s.onData((v) async {
        if (!confirmed) {
          s.pause(); // keep values in order while re-checking
          rechecking = true;
          try {
            final seeded = await gate.check();
            // `confirmed` may have been set meanwhile by whenSeeded.
            confirmed = confirmed || seeded || (!gate.markerAbsent && (confirms?.call(v) ?? false));
          } finally {
            rechecking = false;
            if (!cancelled) s.resume();
          }
          if (cancelled) return;
          if (!confirmed) {
            heldLive = v;
            holding = true;
            if (fallbackDue && !emitted) {
              fallbackDue = false;
              emit(fallback, seed: true);
            }
            return;
          }
        }
        holding = false;
        heldLive = null;
        emit(v, seed: false);
      });
      s.onError((Object e, StackTrace st) {
        debugPrint('Firestore stream $label failed, serving seed: $e');
        ErrorReporting.capture(e, st, section: 'content:$label');
        emit(fallback, seed: true);
        done = true; // keeps showing the seed: the "bundled content" mark stays
        s.cancel();
        out.close();
      });
      s.onDone(() {
        fallbackTimer?.cancel();
        done = true;
        out.close();
      });
    },
    onCancel: () async {
      cancelled = true;
      fallbackTimer?.cancel();
      // Cancelled by the listener while on the seed: this stream no longer
      // serves anything, so it must not keep the banner on.
      if (!done && onSeedNow) onSeed(false);
      await sub?.cancel();
    },
  );
  return out.stream;
}

/// One live reading of a query: its [value], whether it is only
/// [provisional] (served from the local cache, not yet confirmed by the
/// server) and whether it [changed] anything compared with the previous
/// reading (false for a metadata-only event such as "now in sync").
typedef LiveReading<T> = ({T value, bool provisional, bool changed});

/// The first value of [source] that a page may trust (PR #23).
///
/// Before anything is emitted, provisional readings (cache only) are held
/// back: the first server-confirmed reading is emitted at once; when none
/// arrives within [patience] (offline, slow or stalled connection) the last
/// held reading is emitted instead, or, when the listener has said nothing
/// at all, the value of [onTimeout] (a cache read). So a page shows its
/// loading state until its data has actually loaded, never a provisional
/// "not available" / "empty", and never stays loading forever. After the
/// first emission every reading that [changed] something is forwarded.
@visibleForTesting
Stream<T> settleFirst<T>({
  required Stream<LiveReading<T>> source,
  required Duration patience,
  Future<T?> Function()? onTimeout,
}) {
  late final StreamController<T> out;
  StreamSubscription<LiveReading<T>>? sub;
  Timer? timer;
  var emitted = false;
  var closed = false;
  LiveReading<T>? held;
  void emit(T v) {
    if (closed) return;
    timer?.cancel();
    emitted = true;
    out.add(v);
  }

  Future<void> onPatience() async {
    if (emitted || closed) return;
    final h = held;
    if (h != null) {
      emit(h.value);
      return;
    }
    T? v;
    try {
      v = await onTimeout?.call();
    } catch (e) {
      debugPrint('settleFirst: cache read failed: $e');
    }
    if (!emitted && v != null) emit(v);
  }

  out = StreamController<T>(
    onListen: () {
      timer = Timer(patience, onPatience);
      sub = source.listen(
        (r) {
          if (emitted) {
            if (r.changed) emit(r.value);
          } else if (r.provisional) {
            held = r;
          } else {
            emit(r.value);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!closed) out.addError(e, st);
        },
        onDone: () {
          timer?.cancel();
          final h = held;
          if (!emitted && h != null) emit(h.value);
          closed = true;
          out.close();
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      closed = true;
      timer?.cancel();
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

  Stream<T> _guard<T>(String key, Stream<T> Function() live, T fallback,
          {bool Function(T v)? confirms, Duration? fallbackDelay}) =>
      guardSeeded(
        gate: _gate,
        live: live,
        fallback: fallback,
        confirms: confirms,
        fallbackDelay: fallbackDelay,
        onSeed: (onSeed) => _markFallback(key, onSeed),
        label: key,
      );

  /// How long custom content (no bundled copy) waits for the server before
  /// settling on the held / cached reading ([settleFirst] patience).
  static const customPatience = Duration(seconds: 8);

  /// Timeout of the `Source.cache` read [settleFirst] falls back to.
  static const customCacheRead = Duration(seconds: 4);

  /// How long the seeding fallback (the empty list) waits when the seeding
  /// check cannot answer. Longer than [customPatience] + [customCacheRead]
  /// (+1 s margin), so the cached list [settleFirst] emits at its patience
  /// always reaches the guard first and "not available" never wins the race.
  static const customFallbackDelay = Duration(seconds: 13);

  List<T> _docs<T>(QuerySnapshot<Map<String, dynamic>> snap, T Function(String, Map<String, dynamic>) f) =>
      snap.docs.map((d) => f(d.id, normalizeDoc(d.data()))).toList();

  /// Admin-defined collections (categories, entries, pages; ADR-027): there
  /// is no bundled copy, so a cache-only or fallback empty list must not be
  /// shown as "this does not exist" (PR #23). The live query reports cache
  /// readings as provisional ([settleFirst]) and the seeding fallback waits
  /// [customFallbackDelay] ([guardSeeded] `fallbackDelay`).
  Stream<List<T>> _custom<T>(String name, T Function(String, Map<String, dynamic>) f) => _guard(
        name,
        () {
          final col = db.collection(name);
          return settleFirst<List<T>>(
            source: col.snapshots(includeMetadataChanges: true).map((snap) => (
                  value: _docs(snap, f),
                  provisional: snap.metadata.isFromCache,
                  changed: snap.docChanges.isNotEmpty,
                )),
            patience: customPatience,
            onTimeout: () async =>
                _docs(await col.get(const GetOptions(source: Source.cache)).timeout(customCacheRead), f),
          );
        },
        <T>[],
        confirms: (list) => list.isNotEmpty,
        fallbackDelay: customFallbackDelay,
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
        () => db.doc('settings/church').snapshots().map((d) {
              if (!d.exists) return seed.settings;
              // settings/church IS the seeding marker: a snapshot showing it
              // answers the gate for every stream (ADR-038), even when the
              // one-shot check timed out on a slow cold start.
              _gate.markSeeded();
              return ChurchSettings.fromMap(normalizeDoc(d.data()));
            }),
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
        // A stored settings/features proves itself too (PR #23).
        confirms: (v) => !identical(v, seed.features),
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
  Stream<List<CustomCategory>> categories() => _custom('categories', CustomCategory.fromMap);
  @override
  Stream<List<CategoryEntry>> entries() => _custom('entries', CategoryEntry.fromMap);
  @override
  Stream<List<CustomPage>> pages() => _custom('pages', CustomPage.fromMap);
  @override
  Stream<ContactSettings> contactSettings() => _guard(
        'contact',
        () => db
            .doc('settings/contact')
            .snapshots()
            .map((d) => d.exists ? ContactSettings.fromMap(normalizeDoc(d.data())) : ContactSettings.defaults),
        ContactSettings.defaults,
        // A stored settings/contact (the admin's own list of types) proves
        // itself: it replaces the code defaults even while the seeding check
        // cannot answer (PR #23 — the public picker kept the 4 defaults).
        confirms: (v) => !identical(v, ContactSettings.defaults),
      );
  @override
  Stream<AssistantSettings> assistantSettings() => _guard(
        'assistant',
        () => db
            .doc('settings/assistant')
            .snapshots()
            .map((d) => d.exists ? AssistantSettings.fromMap(normalizeDoc(d.data())) : AssistantSettings.defaults),
        AssistantSettings.defaults,
        confirms: (v) => !identical(v, AssistantSettings.defaults),
      );

  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async {
    // Batched with a global throttle doc so the rules can rate-limit public
    // submissions on the server (see firestore.rules: meta/contact_rate).
    // meta/contact_rate.lastMsgId names the message created in the same
    // batch, so the rules can reject a standalone write to the throttle doc.
    final batch = db.batch();
    final msgRef = db.collection('contact_messages').doc();
    // The payload's own keys only: an anonymous message (ADR-028) has no
    // name / phone / email key at all.
    batch.set(msgRef, {
      ...payload,
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
