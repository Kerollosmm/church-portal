import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'content_repository.dart';

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

  Stream<List<AdminDoc>> watch(String collection);
  Stream<AdminDoc?> watchDoc(String path);

  /// Creates (id == null) or merges a document; stamps updatedAt/updatedBy.
  /// Returns the document id.
  Future<String> save(String collection, String? id, Map<String, dynamic> data);

  /// Merges a single document (settings/church, settings/features).
  Future<void> saveDoc(String path, Map<String, dynamic> data);

  /// Merges a few fields (visibility switch, message status).
  Future<void> update(String collection, String id, Map<String, dynamic> data);
  Future<void> delete(String collection, String id);

  /// Writes `order` = 10, 20, 30… following [ids].
  Future<void> reorder(String collection, List<String> ids);

  /// admins/{uid}: owners only (enforced by firestore.rules).
  Future<void> setAdmin(String uid, {required String email, required String role});
  Future<void> removeAdmin(String uid);
}

/// Content editing for signed-in admins (admins/{uid} must exist; enforced
/// by firestore.rules).
class AdminRepository implements AdminBackend {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  AdminRepository(this.db, this.auth);

  Stream<User?> authChanges() => auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordReset(String email) => auth.sendPasswordResetEmail(email: email.trim());

  @override
  String get actor => auth.currentUser?.email ?? auth.currentUser?.uid ?? '';

  /// The admin's role ('owner' | 'editor'), or null when admins/{uid} does
  /// not exist. Network/permission errors propagate so the UI can offer a
  /// retry instead of a misleading "not admin" screen.
  Future<String?> adminRole(String uid) async {
    final d = await db
        .doc('admins/$uid')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    if (!d.exists) return null;
    final role = d.data()?['role'];
    return role == AdminRoles.owner ? AdminRoles.owner : AdminRoles.editor;
  }

  @override
  Stream<List<AdminDoc>> watch(String collection) => db.collection(collection).snapshots().map(
        (s) => s.docs.map((d) => AdminDoc(d.id, normalizeDoc(d.data()))).toList(),
      );

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
    await col.doc(id).set(_stamp(data), SetOptions(merge: true));
    return id;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) =>
      db.doc(path).set(_stamp(data), SetOptions(merge: true));

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) =>
      db.collection(collection).doc(id).update(_stamp(data));

  @override
  Future<void> delete(String collection, String id) => db.collection(collection).doc(id).delete();

  @override
  Future<void> reorder(String collection, List<String> ids) async {
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(db.collection(collection).doc(ids[i]), _stamp({'order': (i + 1) * 10}));
    }
    await batch.commit();
  }

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) =>
      db.doc('admins/$uid').set({'email': email.trim(), 'role': role});

  @override
  Future<void> removeAdmin(String uid) => db.doc('admins/$uid').delete();
}
