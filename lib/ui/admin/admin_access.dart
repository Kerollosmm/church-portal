import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../data/admin_repository.dart';
import '../../data/content_repository.dart';

/// Access state of an `admins/{uid}` record evaluated at a point in time.
enum AdminAccountStatus { active, stopped, expired, none }

class AdminAccess {
  final String? role;
  final AdminAccountStatus status;
  final DateTime? expiresAt;

  const AdminAccess({this.role, required this.status, this.expiresAt});

  bool get isAllowed => status == AdminAccountStatus.active && role != null;
}

/// Pure status evaluation for an `admins/{uid}` document at [now].
/// Mirrors `firestore.rules` (`active != false` and absent/future `expiresAt`).
AdminAccess evaluateAdminAccess(Map<String, dynamic>? data, DateTime now) {
  if (data == null) {
    return const AdminAccess(status: AdminAccountStatus.none);
  }
  final role = data['role'] == AdminRoles.owner ? AdminRoles.owner : AdminRoles.editor;
  final active = data['active'] is bool ? data['active'] as bool : true;
  final rawExpires = data['expiresAt'];
  DateTime? expiresAt;
  if (rawExpires is DateTime) {
    expiresAt = rawExpires;
  } else if (rawExpires is Timestamp) {
    expiresAt = rawExpires.toDate().toUtc();
  }
  if (!active) {
    return AdminAccess(role: role, status: AdminAccountStatus.stopped, expiresAt: expiresAt);
  }
  if (expiresAt != null && !now.toUtc().isBefore(expiresAt.toUtc())) {
    return AdminAccess(role: role, status: AdminAccountStatus.expired, expiresAt: expiresAt);
  }
  return AdminAccess(role: role, status: AdminAccountStatus.active, expiresAt: expiresAt);
}

extension AdminDocStatusExt on AdminDoc {
  bool get active => data['active'] is bool ? data['active'] as bool : true;
  DateTime? get expiresAt => data['expiresAt'] is DateTime ? data['expiresAt'] as DateTime : null;
}

extension AdminBackendStatusExt on AdminBackend {
  Future<void> setAdminStatus(
    String uid, {
    bool? active,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) {
    final patch = <String, dynamic>{
      'active': ?active,
      if (clearExpiresAt) 'expiresAt': null else 'expiresAt': ?expiresAt,
    };
    if (patch.isEmpty) return Future.value();
    if (this is AdminRepository) return saveDoc('admins/$uid', patch);
    return update('admins', uid, patch);
  }

  Future<void> setAdminRole(AdminDoc a, String role) async {
    final email = '${a.data['email'] ?? ''}'.trim();
    if (role == AdminRoles.owner && a.expiresAt != null && this is AdminRepository) {
      await saveDoc('admins/${a.id}', {'email': email, 'role': role, 'expiresAt': null});
      return;
    }
    await setAdmin(a.id, email: email, role: role);
    if (role == AdminRoles.owner && a.expiresAt != null) {
      await setAdminStatus(a.id, clearExpiresAt: true);
    }
  }
}

extension AdminRepositoryAccessExt on AdminRepository {
  Future<void> signInWithPersistence(String email, String password, {bool rememberMe = false}) async {
    if (kIsWeb) {
      try {
        await auth.setPersistence(rememberMe ? Persistence.LOCAL : Persistence.SESSION);
      } catch (_) {}
    }
    await signIn(email, password);
  }

  /// Authoritative server access check for `admins/{uid}` (`role`, `active`,
  /// `expiresAt`). Network/permission errors propagate so the UI can retry.
  Future<AdminAccess> adminAccess(String uid) async {
    final d = await db
        .doc('admins/$uid')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    if (!d.exists) return const AdminAccess(status: AdminAccountStatus.none);
    return evaluateAdminAccess(normalizeDoc(d.data()), DateTime.now().toUtc());
  }

  /// Live access stream of [uid]. Cache-only "missing" snapshots are skipped so
  /// a cold cache never flashes "not admin".
  Stream<AdminAccess> accessChanges(String uid) => db
      .doc('admins/$uid')
      .snapshots()
      .where((d) => d.exists || !d.metadata.isFromCache)
      .map((d) => d.exists
          ? evaluateAdminAccess(normalizeDoc(d.data()), DateTime.now().toUtc())
          : const AdminAccess(status: AdminAccountStatus.none));
}
