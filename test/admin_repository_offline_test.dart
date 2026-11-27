import 'dart:async';
import 'dart:typed_data';

import 'package:church_portal/core/connectivity_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_strings.dart' show adminStrings, registerAdminStrings;
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _OfflineConnectivityEnv extends ConnectivityEnv {
  @override
  bool get isOnline => false;

  @override
  Future<bool> checkOnline() async => false;

  @override
  Stream<bool> get onOnlineChanged => Stream.value(false);
}

class _AllowingFirestore implements FirebaseFirestore {
  int touches = 0;

  int _seq = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    touches++;
    return _AllowingCollectionRef(this, collectionPath);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    touches++;
    return _AllowingDocRef(this, documentPath);
  }

  @override
  WriteBatch batch() {
    touches++;
    return _AllowingBatch(this);
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    touches++;
    return transactionHandler(_AllowingTransaction(this));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _AllowingCollectionRef implements CollectionReference<Map<String, dynamic>> {
  final _AllowingFirestore db;
  @override
  final String path;

  const _AllowingCollectionRef(this.db, this.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final id = path ?? 'doc-${++db._seq}';
    return _AllowingDocRef(db, '${this.path}/$id', id: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _AllowingDocRef implements DocumentReference<Map<String, dynamic>> {
  final _AllowingFirestore db;
  @override
  final String path;
  @override
  final String id;

  _AllowingDocRef(this.db, this.path, {String? id}) : id = id ?? path.split('/').last;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.touches++;
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    db.touches++;
  }

  @override
  Future<void> delete() async {
    db.touches++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AllowingBatch implements WriteBatch {
  final _AllowingFirestore db;
  _AllowingBatch(this.db);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    db.touches++;
  }

  @override
  void update<T>(DocumentReference<T> document, T data) {
    db.touches++;
  }

  @override
  void delete(DocumentReference<Object?> document) {
    db.touches++;
  }

  @override
  Future<void> commit() async {
    db.touches++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AllowingTransaction implements Transaction {
  final _AllowingFirestore db;
  _AllowingTransaction(this.db);

  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> documentReference) async {
    db.touches++;
    return _EmptySnap<T>();
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    db.touches++;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _EmptySnap<T> implements DocumentSnapshot<T> {
  @override
  bool get exists => false;

  @override
  T? data() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TimeoutFailingBackend extends AdminBackend {
  @override
  String get actor => 'admin@test';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(const []);

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> delete(String collection, String id) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async =>
      throw TimeoutException('Firestore server ack timed out');

  @override
  Future<void> removeAdmin(String uid) async =>
      throw TimeoutException('Firestore server ack timed out');
}

void main() {
  setUp(registerAdminStrings);

  group('Admin web-only offline hint (no hard write lock)', () {
    test('all AdminRepository write operations proceed without blocking when connectivity hints offline', () async {
      final offlineEnv = _OfflineConnectivityEnv();
      expect(offlineEnv.isOnline, isFalse);
      expect(await offlineEnv.checkOnline(), isFalse);

      final db = _AllowingFirestore();
      final auth = _TrackingAuth();
      final repo = AdminRepository(db, auth);

      await repo.save('liturgies', null, {'nameAr': 'قداس'});
      await repo.save('liturgies', 'l1', {'nameAr': 'قداس'});
      await repo.saveDoc('settings/church', {'nameAr': 'كنيسة'});
      await repo.saveDocs({'settings/features': {'heroMotion': false}});
      await repo.saveDocsFresh(['settings/features'], (_) => {'settings/features': {'heroMotion': false}});
      await repo.update('liturgies', 'l1', {'visible': false});
      await repo.delete('liturgies', 'l1');
      await repo.batchWrite(
        updates: {
          ('entries', 'e1'): {'visible': false},
          ('pages', 'p1'): {'placement': 'link', 'categoryId': ''},
        },
        deletes: const [('categories', 'k1')],
      );
      await repo.reorder('liturgies', ['l1', 'l2']);
      await repo.setAdmin('u1', email: 'a@b.c', role: AdminRoles.editor);
      await repo.removeAdmin('u1');

      final img = EncodedImage(Uint8List.fromList([1, 2, 3, 4]), 'image/webp', 10, 10);
      await repo.media.upload(img, alt: 'cover');
      await repo.media.delete('m1');

      expect(db.touches, greaterThanOrEqualTo(12));
    });

    test('formatAdminError maps TimeoutException to friendly localized adminTimeoutError copy', () {
      final err = TimeoutException('Server ack timed out');
      expect(formatAdminError(err), '[timeout] ${adminStrings['adminTimeoutError']![0]}');
      expect(formatAdminError(err, isAr: false), '[timeout] ${adminStrings['adminTimeoutError']![1]}');
    });

    testWidgets('AdminDashboard shows OfflineBanner as a hint when offline', (tester) async {
      final backend = _TimeoutFailingBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: AdminDashboard(
              repo: backend,
              uid: 'u1',
              email: 'admin@test',
              role: AdminRoles.owner,
              onSignOut: () {},
              initial: 'today',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offlineBanner')), findsOneWidget);
      expect(find.text(adminStrings['adminOfflineBanner']![0]), findsOneWidget);
    });

    testWidgets('DocEditor preserves typed edits and shows friendly timeout error on TimeoutException', (tester) async {
      final backend = _TimeoutFailingBackend();
      final alertsDef = collectionById('alerts')!;
      var saveCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: DocEditor(
            title: 'تنويه جديد',
            fields: alertsDef.fields,
            def: alertsDef,
            newDefaults: const {'active': true, 'priority': 10},
            onSave: (data) async {
              saveCalls++;
              await backend.save('alerts', null, data);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تنويه أثناء ضعف النت');
      await tester.enterText(find.byKey(const ValueKey('field-bodyAr')), 'نص محفوظ في النموذج');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-save-top')));
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(find.textContaining('[timeout]'), findsWidgets);
      expect(find.textContaining(adminStrings['adminTimeoutError']![0]), findsWidgets);
      expect(find.text('تنويه أثناء ضعف النت'), findsOneWidget);
      expect(find.text('نص محفوظ في النموذج'), findsOneWidget);
    });
  });
}
