import 'dart:typed_data';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _TrackingFirestore implements FirebaseFirestore {
  int touches = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    throw StateError('Firestore should not be touched while offline: ${invocation.memberName}');
  }
}

class _TrackingAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineFailingBackend extends AdminBackend {
  @override
  String get actor => 'admin@test';

  @override
  Stream<List<AdminDoc>> watch(String collection) => const Stream.empty();

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async =>
      throw const AdminOfflineException();

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async =>
      throw const AdminOfflineException();

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async =>
      throw const AdminOfflineException();

  @override
  Future<void> delete(String collection, String id) async =>
      throw const AdminOfflineException();

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async =>
      throw const AdminOfflineException();

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async =>
      throw const AdminOfflineException();

  @override
  Future<void> removeAdmin(String uid) async =>
      throw const AdminOfflineException();
}

void main() {
  group('AdminRepository single-chokepoint offline lock', () {
    test('all write operations throw AdminOfflineException without touching Firestore when offline', () async {
      final db = _TrackingFirestore();
      final auth = _TrackingAuth();
      final repo = AdminRepository(db, auth, isOnline: () => false);

      await expectLater(repo.save('liturgies', null, {'nameAr': 'قداس'}), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.save('liturgies', 'l1', {'nameAr': 'قداس'}), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.saveDoc('settings/church', {'nameAr': 'كنيسة'}), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.saveDocs({'settings/features': {'heroMotion': false}}), throwsA(isA<AdminOfflineException>()));
      await expectLater(
        repo.saveDocsFresh(['settings/features'], (_) => {'settings/features': {'heroMotion': false}}),
        throwsA(isA<AdminOfflineException>()),
      );
      await expectLater(repo.update('liturgies', 'l1', {'visible': false}), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.delete('liturgies', 'l1'), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.reorder('liturgies', ['l1', 'l2']), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.setAdmin('u1', email: 'a@b.c', role: AdminRoles.editor), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.removeAdmin('u1'), throwsA(isA<AdminOfflineException>()));

      final img = EncodedImage(Uint8List.fromList([1, 2, 3, 4]), 'image/webp', 10, 10);
      await expectLater(repo.media.upload(img, alt: 'cover'), throwsA(isA<AdminOfflineException>()));
      await expectLater(repo.media.delete('m1'), throwsA(isA<AdminOfflineException>()));

      expect(db.touches, 0);
    });

    test('formatAdminError formats AdminOfflineException clearly', () {
      final formatted = formatAdminError(const AdminOfflineException());
      expect(formatted, contains('[offline]'));
    });

    testWidgets('DocEditor preserves typed edits when AdminOfflineException is thrown', (tester) async {
      final backend = _OfflineFailingBackend();
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

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تنويه أثناء انقطاع النت');
      await tester.enterText(find.byKey(const ValueKey('field-bodyAr')), 'نص محفوظ في النموذج');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('editor-save-top')));
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(find.textContaining('[offline]'), findsWidgets);
      expect(find.text('تنويه أثناء انقطاع النت'), findsOneWidget);
      expect(find.text('نص محفوظ في النموذج'), findsOneWidget);
    });
  });
}
