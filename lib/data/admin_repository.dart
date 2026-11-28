import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'content_repository.dart';
import 'media_repository.dart';

/// Thrown when an admin attempts to save a document that another admin
/// modified or deleted since it was loaded into the editor.
class StaleDocumentException implements Exception {
  final String path;
  const StaleDocumentException(this.path);

  @override
  String toString() => 'StaleDocumentException($path)';
}

/// True when both [a] and [b] are null or represent the same instant.
bool sameTimestamp(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.isAtSameMomentAs(b);
}

/// True when [current] (read inside a [AdminBackend.saveDocsFresh] transaction)
/// no longer matches the loaded state ([expectedExists] and [expectedUpdatedAt]).
bool isStaleDoc(
  Map<String, dynamic>? current, {
  required bool expectedExists,
  required DateTime? expectedUpdatedAt,
}) {
  if (!expectedExists) return current != null;
  if (current == null) return true;
  final curUpdatedAt = current['updatedAt'] is DateTime ? current['updatedAt'] as DateTime : null;
  return !sameTimestamp(curUpdatedAt, expectedUpdatedAt);
}

class AdminDoc {
  final String id;
  final Map<String, dynamic> data;
  const AdminDoc(this.id, this.data);

  DateTime? get updatedAt => data['updatedAt'] is DateTime ? data['updatedAt'] as DateTime : null;
  String get updatedBy => data['updatedBy'] is String ? data['updatedBy'] as String : '';
}

/// Admin roles (admins/{uid}.role). Owners also manage other admins.
class AdminRoles {
  AdminRoles._();
  static const owner = 'owner';
  static const editor = 'editor';
  static const all = [owner, editor];
}

/// Everything the admin UI reads and writes. [AdminRepository] is the
/// Firestore implementation; tests use an in-memory fake.
abstract class AdminBackend {
  /// Email of the signed-in admin (stored as `updatedBy`).
  String get actor;

  /// Image uploads for the editors (null = only pasted URLs).
  MediaRepository? get media => null;

  Stream<List<AdminDoc>> watch(String collection);

  /// Watches up to [limit] documents of [collection] ordered newest-first by
  /// `createdAt`. Defaults to a client-side slice of [watch] so test fakes
  /// only need to implement [watch].
  Stream<List<AdminDoc>> watchLatest(String collection, {int limit = 50}) =>
      watch(collection).map((docs) {
        final sorted = [...docs]..sort((a, b) {
            final ta = a.data['createdAt'], tb = b.data['createdAt'];
            if (ta is DateTime && tb is DateTime) return tb.compareTo(ta);
            return ta is DateTime ? -1 : (tb is DateTime ? 1 : 0);
          });
        return sorted.length <= limit ? sorted : sorted.sublist(0, limit);
      });

  Stream<AdminDoc?> watchDoc(String path);

  /// Creates (id == null) or merges a document; stamps updatedAt/updatedBy.
  /// Returns the document id.
  Future<String> save(String collection, String? id, Map<String, dynamic> data);

  /// Saves an existing document at [collection]/[id] inside a transaction
  /// only if its stored `updatedAt` still matches [expectedUpdatedAt],
  /// returning the document's new `updatedAt` after the write.
  /// Throws [StaleDocumentException] when another admin modified or deleted it.
  ///
  /// The default delegates to [save] so in-memory test backends keep
  /// recording collection saves; [AdminRepository] uses [saveDocsFresh].
  Future<DateTime?> saveFresh(
    String collection,
    String id,
    Map<String, dynamic> data, {
    required DateTime? expectedUpdatedAt,
  }) async {
    await save(collection, id, data);
    return expectedUpdatedAt;
  }

  /// Merges a single document (settings/church, settings/features).
  Future<void> saveDoc(String path, Map<String, dynamic> data);

  /// Merges several documents together (path → fields), atomically on
  /// Firestore (one batch). The default writes them in order (in-memory test
  /// backends). The season preset (ADR-042) uses [saveDocsFresh].
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) async {
    for (final e in writes.entries) {
      await saveDoc(e.key, e.value);
    }
  }

  /// Reads [paths] and writes what [plan] makes of their current data
  /// (path → fields; a missing document = null), atomically on Firestore (one
  /// transaction): a switch another admin saved meanwhile is not reverted, a
  /// preset applied or restored meanwhile is seen, and a season deleted
  /// meanwhile is not recreated (ADR-042, CodeRabbit review on PR #33).
  /// [plan] throws to write nothing. The default reads each path's latest
  /// value and calls [saveDocs] (in-memory test backends).
  Future<void> saveDocsFresh(
      List<String> paths, Map<String, Map<String, dynamic>> Function(Map<String, Map<String, dynamic>?> current) plan) async {
    final current = {for (final p in paths) p: (await watchDoc(p).first)?.data};
    await saveDocs(plan(current));
  }

  /// Merges a few fields (visibility switch, message status).
  Future<void> update(String collection, String id, Map<String, dynamic> data);
  Future<void> delete(String collection, String id);

  /// Atomically applies document updates and deletions in one WriteBatch.
  /// [updates] maps `(collection, id)` to fields to merge; [deletes] lists
  /// `(collection, id)` pairs to delete. The default runs sequentially for
  /// in-memory test backends.
  Future<void> batchWrite({
    Map<(String, String), Map<String, dynamic>> updates = const {},
    List<(String, String)> deletes = const [],
  }) async {
    for (final e in updates.entries) {
      await update(e.key.$1, e.key.$2, e.value);
    }
    for (final d in deletes) {
      await delete(d.$1, d.$2);
    }
  }

  /// Writes `order` = [base] + 10, 20, 30… following [ids].
  Future<void> reorder(String collection, List<String> ids, {int base = 0});

  /// admins/{uid}: owners only (enforced by firestore.rules).
  Future<void> setAdmin(String uid, {required String email, required String role});
  Future<void> removeAdmin(String uid);
}

/// Content editing for signed-in admins (admins/{uid} must exist; enforced
/// by firestore.rules). Admin lives on web only; offline connectivity is shown
/// via [OfflineBanner] as a hint, while Firestore server-ack timeouts remain
/// the guard against stalled writes.
class AdminRepository implements AdminBackend {
  final FirebaseFirestore db;
  final FirebaseAuth auth;

  AdminRepository(this.db, this.auth);

  @override
  late final MediaRepository media = createMediaRepository(db, () => actor);

  Stream<User?> authChanges() => auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => auth.signOut();

  /// Sends a reset email. Returns false only for errors that do not reveal
  /// whether the account exists (network, rate limit, invalid email...).
  Future<bool> sendPasswordReset(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      // Same answer as success: never reveal whether an account exists.
      if (e.code == 'user-not-found') return true;
      return false;
    }
  }

  @override
  String get actor => auth.currentUser?.email ?? auth.currentUser?.uid ?? '';

  @override
  Stream<List<AdminDoc>> watch(String collection) => db.collection(collection).snapshots().map(
        (s) => s.docs.map((d) => AdminDoc(d.id, normalizeDoc(d.data()))).toList(),
      );

  @override
  Stream<List<AdminDoc>> watchLatest(String collection, {int limit = 50}) => db
      .collection(collection)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => AdminDoc(d.id, normalizeDoc(d.data()))).toList());

  @override
  Stream<AdminDoc?> watchDoc(String path) =>
      db.doc(path).snapshots().map((d) => d.exists ? AdminDoc(d.id, normalizeDoc(d.data())) : null);

  Map<String, dynamic> _stamp(Map<String, dynamic> data) => {
        ...data.map((k, v) => MapEntry(k, _toFirestore(v))),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actor,
      };

  static Object? _toFirestore(Object? v) {
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is List) return v.map(_toFirestore).toList();
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _toFirestore(val)));
    return v;
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    final col = db.collection(collection);
    if (id == null || id.isEmpty) {
      final ref = col.doc();
      await ref.set(_stamp(data));
      return ref.id;
    }
    await _merge(col.doc(id), data);
    return id;
  }

  @override
  Future<DateTime?> saveFresh(
    String collection,
    String id,
    Map<String, dynamic> data, {
    required DateTime? expectedUpdatedAt,
  }) async {
    final path = '$collection/$id';
    await saveDocsFresh([path], (current) {
      if (isStaleDoc(current[path], expectedExists: true, expectedUpdatedAt: expectedUpdatedAt)) {
        throw StaleDocumentException(path);
      }
      return {path: data};
    });
    // Read back the server-stamped updatedAt so subsequent splitSavePayload
    // chunks (gallery, extraFields, blocks) validate against the new stamp.
    final snap = await db.doc(path).get();
    return snap.exists ? AdminDoc(snap.id, normalizeDoc(snap.data())).updatedAt : null;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) => _merge(db.doc(path), data);

  @override
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) {
    final batch = db.batch();
    for (final e in writes.entries) {
      final stamped = _stamp(e.value);
      batch.set(db.doc(e.key), stamped, SetOptions(mergeFields: stamped.keys.toList()));
    }
    return batch.commit();
  }

  @override
  Future<void> saveDocsFresh(
          List<String> paths, Map<String, Map<String, dynamic>> Function(Map<String, Map<String, dynamic>?> current) plan) =>
      db.runTransaction((tx) async {
        final current = <String, Map<String, dynamic>?>{};
        for (final p in paths) {
          final snap = await tx.get(db.doc(p));
          current[p] = snap.exists ? normalizeDoc(snap.data()) : null;
        }
        for (final e in plan(current).entries) {
          final stamped = _stamp(e.value);
          tx.set(db.doc(e.key), stamped, SetOptions(mergeFields: stamped.keys.toList()));
        }
      });

  /// Writes [data]'s top-level fields and leaves every other field as it is.
  /// A written map field is replaced as a whole (`mergeFields`), never
  /// deep-merged (`merge: true`): a removed page header (settings/features
  /// pageHeaders) or a cover image switched from inline to a link must not
  /// keep its old keys.
  Future<void> _merge(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) {
    final stamped = _stamp(data);
    return ref.set(stamped, SetOptions(mergeFields: stamped.keys.toList()));
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) =>
      db.collection(collection).doc(id).update(_stamp(data));

  @override
  Future<void> delete(String collection, String id) => db.collection(collection).doc(id).delete();

  @override
  Future<void> batchWrite({
    Map<(String, String), Map<String, dynamic>> updates = const {},
    List<(String, String)> deletes = const [],
  }) {
    final batch = db.batch();
    for (final e in updates.entries) {
      final stamped = _stamp(e.value);
      batch.set(
        db.collection(e.key.$1).doc(e.key.$2),
        stamped,
        SetOptions(mergeFields: stamped.keys.toList()),
      );
    }
    for (final d in deletes) {
      batch.delete(db.collection(d.$1).doc(d.$2));
    }
    return batch.commit();
  }

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(db.collection(collection).doc(ids[i]), _stamp({'order': base + (i + 1) * 10}));
    }
    await batch.commit();
  }

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) =>
      db.doc('admins/$uid').set(_stamp({'email': email.trim(), 'role': role}), SetOptions(merge: true));

  @override
  Future<void> removeAdmin(String uid) => db.doc('admins/$uid').delete();
}
