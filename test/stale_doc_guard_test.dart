import 'dart:async';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/contact_admin.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/notifications_admin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Minimal in-memory [FirebaseFirestore] implementing `runTransaction`, `doc`,
/// `get`, `set(..., SetOptions(mergeFields: ...))`, and `FieldValue.serverTimestamp()`.
class _InMemoryFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> store = {};
  int _tick = 0;
  int txAttempts = 0;

  DateTime nextServerTime() => DateTime.utc(2026, 11, 20, 10, 0, ++_tick);

  Map<String, dynamic> _applyFields(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming,
    SetOptions? options,
    DateTime serverTime,
  ) {
    final result = <String, dynamic>{...?existing};
    final keysToWrite = options?.mergeFields != null
        ? options!.mergeFields!.map((fp) => fp.components.single).toSet()
        : incoming.keys.toSet();
    for (final k in keysToWrite) {
      if (!incoming.containsKey(k)) continue;
      final v = incoming[k];
      result[k] = v == FieldValue.serverTimestamp() ? Timestamp.fromDate(serverTime) : v;
    }
    return result;
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) =>
      _MemDocRef(this, documentPath);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _MemCollectionRef(this, collectionPath);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    txAttempts++;
    final tx = _MemTransaction(this);
    final result = await transactionHandler(tx);
    tx.commit();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemCollectionRef implements CollectionReference<Map<String, dynamic>> {
  final _InMemoryFirestore db;
  @override
  final String path;

  const _MemCollectionRef(this.db, this.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final id = path ?? 'auto-${++db._tick}';
    return _MemDocRef(db, '${this.path}/$id', id: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemDocRef implements DocumentReference<Map<String, dynamic>> {
  final _InMemoryFirestore db;
  @override
  final String path;
  @override
  final String id;

  _MemDocRef(this.db, this.path, {String? id}) : id = id ?? path.split('/').last;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final data = db.store[path];
    return _MemSnapshot(id, data == null ? null : Map<String, dynamic>.from(data));
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final serverTime = db.nextServerTime();
    db.store[path] = db._applyFields(db.store[path], data, options, serverTime);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic>? _data;

  _MemSnapshot(this.id, this._data);

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data == null ? null : Map<String, dynamic>.from(_data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemTransaction implements Transaction {
  final _InMemoryFirestore db;
  final List<({String path, Map<String, dynamic> data, SetOptions? options})> _writes = [];

  _MemTransaction(this.db);

  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> documentReference) async {
    final raw = db.store[documentReference.path];
    return _MemSnapshot(
      documentReference.id,
      raw == null ? null : Map<String, dynamic>.from(raw),
    ) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    _writes.add((
      path: documentReference.path,
      data: Map<String, dynamic>.from(data as Map),
      options: options,
    ));
    return this;
  }

  void commit() {
    final serverTime = db.nextServerTime();
    for (final w in _writes) {
      db.store[w.path] = db._applyFields(db.store[w.path], w.data, w.options, serverTime);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  String get uid => 'u-admin';
  @override
  String? get email => 'admin1@church.org';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  @override
  User? get currentUser => _FakeUser();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Broadcast streaming [AdminBackend] simulating Firestore snapshots + stamped transactions.
class _LiveAdminBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> collections = {};
  final Map<String, Map<String, dynamic>> docs = {};
  final List<({String path, Map<String, dynamic> data})> docSaves = [];
  final List<({String collection, String? id, Map<String, dynamic> data})> collectionSaves = [];
  final _docControllers = <String, StreamController<AdminDoc?>>{};
  final _colControllers = <String, StreamController<List<AdminDoc>>>{};
  int _seq = 0;

  _LiveAdminBackend({
    Map<String, List<AdminDoc>>? initialCollections,
    Map<String, Map<String, dynamic>>? initialDocs,
  }) {
    if (initialCollections != null) {
      for (final e in initialCollections.entries) {
        collections[e.key] = [for (final d in e.value) AdminDoc(d.id, Map<String, dynamic>.from(d.data))];
        for (final d in e.value) {
          docs['${e.key}/${d.id}'] = Map<String, dynamic>.from(d.data);
        }
      }
    }
    if (initialDocs != null) {
      for (final e in initialDocs.entries) {
        docs[e.key] = Map<String, dynamic>.from(e.value);
      }
    }
  }

  DateTime _nextTime() => DateTime.utc(2026, 11, 20, 12, 0, ++_seq);

  @override
  String get actor => 'admin1@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    final c = _colControllers.putIfAbsent(collection, () => StreamController<List<AdminDoc>>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) c.add(collections[collection] ?? const []);
    });
    return c.stream;
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _docControllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        final d = docs[path];
        c.add(d == null ? null : AdminDoc(path.split('/').last, Map<String, dynamic>.from(d)));
      }
    });
    return c.stream;
  }

  void emitRemoteDoc(String path, Map<String, dynamic>? data, {bool stamp = true}) {
    if (data == null) {
      docs.remove(path);
      _docControllers[path]?.add(null);
      return;
    }
    final next = Map<String, dynamic>.from(data);
    if (stamp && !next.containsKey('updatedAt')) {
      next['updatedAt'] = _nextTime();
      next['updatedBy'] = 'admin2@church.org';
    }
    docs[path] = next;
    _docControllers[path]?.add(AdminDoc(path.split('/').last, Map<String, dynamic>.from(next)));
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    collectionSaves.add((collection: collection, id: id, data: Map<String, dynamic>.from(data)));
    final newId = id ?? 'new-$_seq';
    final path = '$collection/$newId';
    final merged = {
      ...?docs[path],
      ...data,
      'updatedAt': _nextTime(),
      'updatedBy': actor,
    };
    docs[path] = merged;
    _docControllers[path]?.add(AdminDoc(newId, Map<String, dynamic>.from(merged)));
    return newId;
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
    final updated = docs[path]?['updatedAt'];
    return updated is DateTime ? updated : null;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    docSaves.add((path: path, data: Map<String, dynamic>.from(data)));
    final merged = {
      ...?docs[path],
      ...data,
      'updatedAt': _nextTime(),
      'updatedBy': actor,
    };
    docs[path] = merged;
    _docControllers[path]?.add(AdminDoc(path.split('/').last, Map<String, dynamic>.from(merged)));
  }

  @override
  Future<void> saveDocsFresh(
    List<String> paths,
    Map<String, Map<String, dynamic>> Function(Map<String, Map<String, dynamic>?> current) plan,
  ) async {
    final current = {
      for (final p in paths) p: docs[p] == null ? null : Map<String, dynamic>.from(docs[p]!),
    };
    await saveDocs(plan(current));
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {}
  @override
  Future<void> delete(String collection, String id) async {}
  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}
  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}
  @override
  Future<void> removeAdmin(String uid) async {}

  void dispose() {
    for (final c in _docControllers.values) {
      c.close();
    }
    for (final c in _colControllers.values) {
      c.close();
    }
  }
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);
  setUp(registerAdminStrings);

  group('AdminRepository updatedAt-guarded transactions', () {
    test('saveFresh succeeds when updatedAt matches, chains multi-chunk updatedAt, and rejects stale writes', () async {
      final db = _InMemoryFirestore();
      final t0 = DateTime.utc(2026, 11, 1, 8, 0);
      db.store['pages/p1'] = {
        'slug': 'about-youth',
        'titleAr': 'الشباب',
        'updatedAt': Timestamp.fromDate(t0),
        'updatedBy': 'seed@church.org',
      };
      final repo = AdminRepository(db, _FakeAuth());

      // Chunk 1 succeeds against t0 and returns t1.
      final t1 = await repo.saveFresh('pages', 'p1', {'titleAr': 'الشباب المحدّث'}, expectedUpdatedAt: t0);
      expect(t1, isNotNull);
      expect(t1!.isAfter(t0), isTrue);
      expect(db.store['pages/p1']!['titleAr'], 'الشباب المحدّث');
      expect(db.store['pages/p1']!['slug'], 'about-youth');

      // Chunk 2 succeeds against t1 (chaining multi-write saves).
      final t2 = await repo.saveFresh('pages', 'p1', {'blocks': ['p|x']}, expectedUpdatedAt: t1);
      expect(t2, isNotNull);
      expect(t2!.isAfter(t1), isTrue);

      // Admin B still holding stale t0 is rejected without overwriting t2.
      await expectLater(
        repo.saveFresh('pages', 'p1', {'titleAr': 'كتابة قديمة'}, expectedUpdatedAt: t0),
        throwsA(isA<StaleDocumentException>()),
      );
      expect(db.store['pages/p1']!['titleAr'], 'الشباب المحدّث');

      // Deleted doc is also rejected.
      db.store.remove('pages/p1');
      await expectLater(
        repo.saveFresh('pages', 'p1', {'titleAr': 'إعادة إنشاء'}, expectedUpdatedAt: t2),
        throwsA(isA<StaleDocumentException>()),
      );
      expect(db.store.containsKey('pages/p1'), isFalse);
    });

    test('formatAdminError maps StaleDocumentException to friendly localized message', () {
      const err = StaleDocumentException('liturgies/l1');
      expect(formatAdminError(err, isAr: true), adminStrings['staleDocError']![0]);
      expect(formatAdminError(err, isAr: false), adminStrings['staleDocError']![1]);
    });
  });

  group('Collection DocEditor concurrent-edit guard', () {
    testWidgets('watches existing doc, shows updatedElsewhere banner when dirty, reloads, and rejects stale save',
        (tester) async {
      final t0 = DateTime.utc(2026, 11, 10, 9, 0);
      final backend = _LiveAdminBackend(
        initialCollections: {
          'alerts': [
            AdminDoc('a1', {
              'titleAr': 'تنويه قديم',
              'bodyAr': 'نص قديم',
              'active': true,
              'priority': 10,
              'updatedAt': t0,
              'updatedBy': 'admin2@church.org',
            }),
          ],
        },
      );
      addTearDown(backend.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: backend, def: collectionById('alerts')!),
      ));
      await tester.pumpAndSettle();

      // Open existing doc in DocEditor.
      await tester.tap(find.text('تنويه قديم'));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);

      // Make local edit -> dirty.
      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تعديل المشرف الأول');
      await tester.pump();

      // Simulate another admin updating alerts/a1 remotely.
      final t1 = DateTime.utc(2026, 11, 10, 9, 5);
      backend.emitRemoteDoc('alerts/a1', {
        'titleAr': 'تعديل المشرف الثاني',
        'bodyAr': 'نص من المشرف الثاني',
        'active': true,
        'priority': 20,
        'updatedAt': t1,
        'updatedBy': 'admin2@church.org',
      }, stamp: false);
      await tester.pumpAndSettle();

      // Banner appears with Reload action.
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text(adminStrings['updatedElsewhere']![1]), findsOneWidget);

      // Saving before reloading rejects with StaleDocumentException and does NOT overwrite.
      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(find.textContaining(adminStrings['staleDocError']![1]), findsWidgets);
      expect(backend.docs['alerts/a1']!['titleAr'], 'تعديل المشرف الثاني');

      // Tapping Reload loads remote changes, clears banner, and lets subsequent edits save cleanly.
      await tester.tap(find.widgetWithText(TextButton, adminStrings['reload']![1]));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.text('تعديل المشرف الثاني'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تعديل مدمج بعد التحميل');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();
      expect(backend.docs['alerts/a1']!['titleAr'], 'تعديل مدمج بعد التحميل');
    });

    testWidgets('new collection DocEditor does not watch or use saveFresh', (tester) async {
      final backend = _LiveAdminBackend(initialCollections: {'alerts': []});
      addTearDown(backend.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: backend, def: collectionById('alerts')!),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تنويه جديد');
      await tester.enterText(find.byKey(const ValueKey('field-bodyAr')), 'نص التنويه الجديد');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();

      expect(backend.collectionSaves, hasLength(1));
      expect(backend.collectionSaves.single.id, isNull);
      expect(backend.docSaves, isEmpty);
    });
  });

  group('ContactCategoriesScreen concurrent-edit guard', () {
    testWidgets('shows updatedElsewhere banner when dirty, reloads, and rejects stale save', (tester) async {
      final t0 = DateTime.utc(2026, 11, 10, 10, 0);
      final t1 = DateTime.utc(2026, 11, 10, 10, 5);
      final initialCats = ContactSettings(const [
        ContactCategory(slot: 'c1', labelAr: 'استفسار', labelEn: 'Inquiry', order: 10),
        ContactCategory(slot: 'c2', labelAr: 'اقتراح', labelEn: 'Suggestion', order: 20),
      ]);
      final remoteCats = ContactSettings(const [
        ContactCategory(slot: 'c1', labelAr: 'استفسار محدث', labelEn: 'Updated inquiry', order: 10),
        ContactCategory(slot: 'c2', labelAr: 'اقتراح', labelEn: 'Suggestion', order: 20),
      ]);
      final backend = _LiveAdminBackend(initialDocs: {
        'settings/contact': {...initialCats.toMap(), 'updatedAt': t0},
      });
      addTearDown(backend.dispose);

      await tester.pumpWidget(_app(ContactCategoriesScreen(repo: backend)));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);

      // Edit c1 -> dirty.
      final c1Field = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('catLabelAr-c1-'),
      );
      await tester.enterText(c1Field, 'تعديل محلي');
      await tester.pump();

      // Remote admin updates settings/contact.
      backend.emitRemoteDoc('settings/contact', {...remoteCats.toMap(), 'updatedAt': t1}, stamp: false);
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text(adminStrings['updatedElsewhere']![1]), findsOneWidget);

      // Saving while stale aborts via saveDocsFresh and keeps remote data intact.
      await tester.tap(find.byKey(const Key('saveContactCats')));
      await tester.pumpAndSettle();
      expect(find.textContaining(adminStrings['staleDocError']![1]), findsOneWidget);
      expect(backend.docSaves, isEmpty);
      expect(ContactSettings.fromMap(backend.docs['settings/contact']).bySlot('c1')!.labelAr, 'استفسار محدث');

      // Reloading updates the form and clears the banner.
      await tester.tap(find.widgetWithText(TextButton, adminStrings['reload']![1]));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.text('استفسار محدث'), findsOneWidget);
    });
  });

  group('NotificationsAdminSection diff-writing & concurrent-edit guard', () {
    testWidgets('writes only changed push keys and guards against stale saves + shows updatedElsewhere banner',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final t0 = DateTime.utc(2026, 11, 10, 11, 0);
      final backend = _LiveAdminBackend(initialDocs: {
        'settings/features': {
          'push': false,
          'pushTypes': ['announcements', 'verse_daily', 'reminders'],
          'reminderLeads': [0, 15, 60],
          'reminderDefaultLead': 60,
          'reminderSources': 'lit,mtg,day',
          'notifyTypes': <String>[],
          'updatedAt': t0,
        },
        'settings/notifications': {'schedule': <String>[]},
      });
      addTearDown(backend.dispose);

      await tester.pumpWidget(_app(NotificationsAdminSection(repo: backend)));
      await tester.pumpAndSettle();

      // Toggle only master push switch -> only 'push' is written.
      await tester.tap(find.byKey(const ValueKey('push-master-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();

      expect(backend.docSaves, hasLength(1));
      expect(backend.docSaves.single.path, 'settings/features');
      expect(backend.docSaves.single.data, {'push': true});
      // Own save echo must NOT show updatedElsewhere banner.
      expect(find.byType(MaterialBanner), findsNothing);
      // Let the "Settings saved." SnackBar clear before tapping save-settings again.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Edit reminderSources -> dirty, then another admin changes settings/features remotely.
      await tester.tap(find.byKey(const ValueKey('src-day')));
      await tester.pumpAndSettle();
      final tRemote = DateTime.utc(2026, 11, 10, 11, 5);
      backend.emitRemoteDoc('settings/features', {
        ...backend.docs['settings/features']!,
        'push': false,
        'updatedAt': tRemote,
      }, stamp: false);
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text(adminStrings['updatedElsewhere']![1]), findsOneWidget);

      // Stale save is rejected without overwriting remote.
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();
      expect(backend.docSaves, hasLength(1));
      expect(find.textContaining(adminStrings['staleDocError']![1]), findsOneWidget);
      expect(backend.docs['settings/features']!['push'], isFalse);

      // Reload restores remote values and clears banner.
      await tester.tap(find.widgetWithText(TextButton, adminStrings['reload']![1]));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('includes reminderLeads when changing reminderDefaultLead on a doc without stored reminderLeads',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final backend = _LiveAdminBackend(initialDocs: {
        'settings/features': {'push': true, 'updatedAt': DateTime.utc(2026, 11, 10, 11, 0)},
        'settings/notifications': {'schedule': <String>[]},
      });
      addTearDown(backend.dispose);

      await tester.pumpWidget(_app(NotificationsAdminSection(repo: backend)));
      await tester.pumpAndSettle();

      // Change only default lead from 60 to 15 via the dropdown.
      await tester.tap(find.byKey(const ValueKey('default-lead-0,15,60,1440')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 minutes before').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();

      expect(backend.docSaves, hasLength(1));
      expect(backend.docSaves.single.data, {
        'reminderDefaultLead': 15,
        'reminderLeads': [0, 15, 60, 1440],
      });
    });
  });
}
