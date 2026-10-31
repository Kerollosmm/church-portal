import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'content_repository.dart';

class AdminDoc {
  final String id;
  final Map<String, dynamic> data;
  const AdminDoc(this.id, this.data);
}

/// Content editing for signed-in admins (admins/{uid} must exist; enforced
/// by firestore.rules).
class AdminRepository {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  AdminRepository(this.db, this.auth);

  Stream<User?> authChanges() => auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => auth.signOut();

  /// Whether admins/{uid} exists. Network/permission errors propagate so the
  /// UI can offer a retry instead of a misleading "not admin" screen.
  Future<bool> isAdmin(String uid) async {
    final d = await db
        .doc('admins/$uid')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    return d.exists;
  }

  Stream<List<AdminDoc>> watch(String collection) => db.collection(collection).snapshots().map(
        (s) => s.docs.map((d) => AdminDoc(d.id, normalizeDoc(d.data()))).toList()
          ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b))),
      );

  static String _sortKey(AdminDoc d) {
    final o = d.data['order'] ?? d.data['weekday'] ?? '';
    return '${o.toString().padLeft(4, '0')}_${d.data['start'] ?? ''}_${d.id}';
  }

  /// Creates (id == null) or overwrites a document. DateTime values are
  /// stored as Firestore Timestamps.
  Future<void> save(String collection, String? id, Map<String, dynamic> data) {
    final converted = data.map((k, v) => MapEntry(k, v is DateTime ? Timestamp.fromDate(v) : v));
    final col = db.collection(collection);
    return id == null || id.isEmpty ? col.add(converted) : col.doc(id).set(converted, SetOptions(merge: true));
  }

  Future<void> delete(String collection, String id) => db.collection(collection).doc(id).delete();
}
