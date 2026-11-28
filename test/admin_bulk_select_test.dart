import 'dart:async';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_strings.dart' show registerAdminStrings;
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: child,
    );

class _BulkTestBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> collections = {};
  final List<({Map<(String, String), Map<String, dynamic>> updates, List<(String, String)> deletes})> batchCalls = [];
  final List<String> deletedIds = [];

  _BulkTestBackend(Map<String, List<AdminDoc>> initial) {
    collections.addAll(initial);
  }

  @override
  String get actor => 'admin@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(collections[collection] ?? const []);

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);

  @override
  Future<void> batchWrite({
    Map<(String, String), Map<String, dynamic>> updates = const {},
    List<(String, String)> deletes = const [],
  }) async {
    batchCalls.add((updates: Map.of(updates), deletes: List.of(deletes)));
    await super.batchWrite(updates: updates, deletes: deletes);
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    final list = collections[collection];
    if (list == null) return;
    for (final doc in list) {
      if (doc.id == id) {
        doc.data.addAll(data);
        if (data.containsKey('deletedAt') && data['deletedAt'] == null) {
          doc.data.remove('deletedAt');
        }
      }
    }
  }

  @override
  Future<void> delete(String collection, String id) async {
    deletedIds.add('$collection/$id');
    collections[collection]?.removeWhere((d) => d.id == id);
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}

  @override
  Future<void> removeAdmin(String uid) async {}
}

class _CountingFirestore implements FirebaseFirestore {
  final List<int> committedBatchSizes = [];

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _FakeCollectionRef(collectionPath);

  @override
  WriteBatch batch() => _CountingWriteBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeCollectionRef implements CollectionReference<Map<String, dynamic>> {
  @override
  final String path;
  _FakeCollectionRef(this.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _FakeDocRef('${this.path}/$path', path ?? '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  @override
  final String path;
  @override
  final String id;
  _FakeDocRef(this.path, this.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingWriteBatch implements WriteBatch {
  final _CountingFirestore db;
  int _ops = 0;
  _CountingWriteBatch(this.db);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) => _ops++;

  @override
  void update<T>(DocumentReference<T> document, T data) => _ops++;

  @override
  void delete(DocumentReference<Object?> document) => _ops++;

  @override
  Future<void> commit() async {
    db.committedBatchSizes.add(_ops);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(registerAdminStrings);

  group('batchWriteChunked & AdminRepository.batchWrite chunking', () {
    test('batchWriteChunked chunks updates at 400 per WriteBatch', () async {
      final repo = _BulkTestBackend({});
      final updates = <(String, String), Map<String, dynamic>>{
        for (var i = 0; i < 850; i++) ('liturgies', 'l$i'): {'sample': false},
      };
      await batchWriteChunked(repo, updates: updates);
      expect(repo.batchCalls.map((c) => c.updates.length).toList(), [400, 400, 50]);
    });

    test('AdminRepository.batchWrite chunks Firestore WriteBatch commits at 400', () async {
      final db = _CountingFirestore();
      final repo = AdminRepository(db, _FakeAuth());
      final updates = <(String, String), Map<String, dynamic>>{
        for (var i = 0; i < 450; i++) ('liturgies', 'l$i'): {'visible': false},
      };
      await repo.batchWrite(updates: updates);
      expect(db.committedBatchSizes, [400, 50]);
    });
  });

  group('CollectionListScreen bulk selection mode', () {
    testWidgets('selecting two liturgies and tapping Hide writes visible:false on both in one batch', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'liturgies': [
          AdminDoc('l1', {'nameAr': 'القداس الأول', 'weekday': 7, 'start': '07:00', 'visible': true, 'sample': true}),
          AdminDoc('l2', {'nameAr': 'القداس الثاني', 'weekday': 7, 'start': '09:00', 'visible': true, 'sample': true}),
          AdminDoc('l3', {'nameAr': 'قداس الأربعاء', 'weekday': 3, 'start': '08:00', 'visible': true, 'sample': false}),
        ],
      });

      await tester.pumpWidget(_app(CollectionListScreen(repo: repo, def: collectionById('liturgies')!)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bulk-selection-bar')), findsOneWidget);
      expect(find.byKey(const Key('bulk-show')), findsOneWidget);
      expect(find.byKey(const Key('bulk-hide')), findsOneWidget);
      expect(find.byKey(const Key('bulk-confirm')), findsOneWidget);
      expect(find.byKey(const Key('bulk-delete')), findsOneWidget);

      // Accessibility: checkboxes have >= 48x48 hit targets and semantic labels.
      final cbSize = tester.getSize(find.byKey(const ValueKey('select-l1')));
      expect(cbSize.width, greaterThanOrEqualTo(48));
      expect(cbSize.height, greaterThanOrEqualTo(48));
      final cbWidget = tester.widget<Checkbox>(
        find.descendant(of: find.byKey(const ValueKey('select-l1')), matching: find.byType(Checkbox)),
      );
      expect(cbWidget.semanticLabel, contains('القداس الأول'));

      await tester.tap(find.byKey(const ValueKey('select-l1')));
      await tester.tap(find.byKey(const ValueKey('select-l2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk-hide')));
      await tester.pumpAndSettle();

      expect(repo.batchCalls.length, 1);
      expect(repo.batchCalls.single.updates, {
        ('liturgies', 'l1'): {'visible': false},
        ('liturgies', 'l2'): {'visible': false},
      });
      // Selection clears and exits selection mode after successful action.
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);
    });

    testWidgets('long-press enters selection mode and Confirm sets sample:false in one batch', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'liturgies': [
          AdminDoc('l1', {'nameAr': 'قداس ١', 'weekday': 7, 'start': '07:00', 'visible': true, 'sample': true}),
          AdminDoc('l2', {'nameAr': 'قداس ٢', 'weekday': 7, 'start': '09:00', 'visible': true, 'sample': true}),
        ],
      });

      await tester.pumpWidget(_app(CollectionListScreen(repo: repo, def: collectionById('liturgies')!)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('قداس ١'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-selection-bar')), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('select-l2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-confirm')));
      await tester.pumpAndSettle();

      expect(repo.batchCalls.length, 1);
      expect(repo.batchCalls.single.updates, {
        ('liturgies', 'l1'): {'sample': false},
        ('liturgies', 'l2'): {'sample': false},
      });
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);
    });

    testWidgets('Select all applies to currently filtered list only, and Escape/Cancel exits selection mode',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'liturgies': [
          AdminDoc('l1', {'nameAr': 'Alpha Mass', 'weekday': 7, 'start': '07:00', 'visible': false}),
          AdminDoc('l2', {'nameAr': 'Alpha Vespers', 'weekday': 7, 'start': '18:00', 'visible': false}),
          AdminDoc('l3', {'nameAr': 'Beta Praise', 'weekday': 7, 'start': '21:00', 'visible': false}),
        ],
      });

      await tester.pumpWidget(_app(CollectionListScreen(repo: repo, def: collectionById('liturgies')!)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('admin-search')), 'Alpha');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();

      // Escape exits selection mode.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);

      // Re-enter and tap Select all -> selects only the 2 filtered Alpha items.
      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk-show')));
      await tester.pumpAndSettle();

      expect(repo.batchCalls.length, 1);
      expect(repo.batchCalls.single.updates, {
        ('liturgies', 'l1'): {'visible': true},
        ('liturgies', 'l2'): {'visible': true},
      });
      expect(repo.batchCalls.single.updates.containsKey(('liturgies', 'l3')), isFalse);

      // Cancel exits selection mode without writing.
      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);
      expect(repo.batchCalls.length, 1);
    });

    testWidgets('bulk Delete confirms, soft-deletes in one batch, offers Undo all, and commits after 10s',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'alerts': [
          AdminDoc('a1', {'titleAr': 'تنويه ١', 'visible': true}),
          AdminDoc('a2', {'titleAr': 'تنويه ٢', 'visible': true}),
        ],
      });

      await tester.pumpWidget(_app(CollectionListScreen(repo: repo, def: collectionById('alerts')!)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();
      // alerts has visible but no sample -> no bulk-confirm button.
      expect(find.byKey(const Key('bulk-show')), findsOneWidget);
      expect(find.byKey(const Key('bulk-hide')), findsOneWidget);
      expect(find.byKey(const Key('bulk-confirm')), findsNothing);

      await tester.tap(find.byKey(const Key('bulk-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('تنويه ١'), findsNothing);
      expect(find.text('تنويه ٢'), findsNothing);
      expect(repo.batchCalls.length, 1);
      expect(repo.batchCalls.single.updates.keys, containsAll([('alerts', 'a1'), ('alerts', 'a2')]));
      expect(find.text('Undo all'), findsOneWidget);

      // Tap Undo all -> restores both in one batch.
      await tester.tap(find.text('Undo all'));
      await tester.pumpAndSettle();
      expect(find.text('تنويه ١'), findsOneWidget);
      expect(find.text('تنويه ٢'), findsOneWidget);
      expect(repo.deletedIds, isEmpty);

      // Delete again and let 10s expire -> hard deletes committed.
      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, containsAll(['alerts/a1', 'alerts/a2']));
    });

    testWidgets('seasons selection bar shows Delete only (no Show/Hide/Confirm)', (tester) async {
      final repo = _BulkTestBackend({
        'seasons': [
          AdminDoc('s1', {'key': 'pascha', 'nameAr': 'الخماسين', 'active': true}),
        ],
      });

      await tester.pumpWidget(_app(CollectionListScreen(repo: repo, def: collectionById('seasons')!)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-selectMode')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bulk-delete')), findsOneWidget);
      expect(find.byKey(const Key('bulk-show')), findsNothing);
      expect(find.byKey(const Key('bulk-hide')), findsNothing);
      expect(find.byKey(const Key('bulk-confirm')), findsNothing);
    });
  });

  group('MessagesScreen bulk selection mode', () {
    testWidgets('selecting two messages and tapping Mark handled updates status in one batch', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'contact_messages': [
          AdminDoc('m1', {'name': 'Sender 1', 'message': 'Hello 1', 'status': 'new', 'createdAt': DateTime.utc(2026, 11, 1)}),
          AdminDoc('m2', {'name': 'Sender 2', 'message': 'Hello 2', 'status': 'new', 'createdAt': DateTime.utc(2026, 11, 2)}),
        ],
      });

      await tester.pumpWidget(_app(MessagesScreen(repo: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('messages-selectMode')));
      await tester.pumpAndSettle();

      final cbSize = tester.getSize(find.byKey(const ValueKey('select-msg-m1')));
      expect(cbSize.width, greaterThanOrEqualTo(48));
      expect(cbSize.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const ValueKey('select-msg-m1')));
      await tester.tap(find.byKey(const ValueKey('select-msg-m2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk-mark-handled')));
      await tester.pumpAndSettle();

      expect(repo.batchCalls.length, 1);
      expect(repo.batchCalls.single.updates, {
        ('contact_messages', 'm1'): {'status': 'handled'},
        ('contact_messages', 'm2'): {'status': 'handled'},
      });
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);
    });

    testWidgets('MessagesScreen bulk Delete soft-deletes in one batch with Undo all and Escape cancel', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _BulkTestBackend({
        'contact_messages': [
          AdminDoc('m1', {'name': 'Alice', 'message': 'Msg 1', 'status': 'new', 'createdAt': DateTime.utc(2026, 11, 1)}),
          AdminDoc('m2', {'name': 'Bob', 'message': 'Msg 2', 'status': 'new', 'createdAt': DateTime.utc(2026, 11, 2)}),
        ],
      });

      await tester.pumpWidget(_app(MessagesScreen(repo: repo)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-selection-bar')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-selection-bar')), findsNothing);

      await tester.tap(find.byKey(const Key('messages-selectMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      expect(repo.batchCalls.length, 1);
      expect(find.text('Undo all'), findsOneWidget);

      await tester.tap(find.text('Undo all'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('selection mode renders cleanly at 320 px / 200% text in RTL & LTR', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _BulkTestBackend({
        'liturgies': [
          AdminDoc('l1', {'nameAr': 'قداس', 'weekday': 7, 'start': '07:00', 'visible': true, 'sample': true}),
        ],
        'contact_messages': [
          AdminDoc('m1', {'name': 'Sender', 'message': 'Hello', 'status': 'new', 'createdAt': DateTime.utc(2026, 11, 1)}),
        ],
      });

      for (final locale in const [Locale('ar'), Locale('en')]) {
        await tester.pumpWidget(_app(
          CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'before selectMode locale=${locale.languageCode}');
        final colSelect = find.byKey(const Key('admin-selectMode'));
        await tester.ensureVisible(colSelect);
        await tester.pumpAndSettle();
        await tester.tap(colSelect);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'after selectMode locale=${locale.languageCode}');

        await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: locale));
        await tester.pumpAndSettle();
        final msgSelect = find.byKey(const Key('messages-selectMode'));
        await tester.ensureVisible(msgSelect);
        await tester.pumpAndSettle();
        await tester.tap(msgSelect);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
