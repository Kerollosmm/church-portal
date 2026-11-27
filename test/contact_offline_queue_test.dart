import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/connectivity_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/firebase_bootstrap.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuedContactRepo extends SeedRepository {
  Completer<void>? nextCommit;
  bool queueNext = true;
  bool verifyResult = false;
  int submitCount = 0;
  int verifyCalls = 0;

  _QueuedContactRepo(super.seed);

  @override
  Future<ContactSubmitResult> submitContact(Map<String, dynamic> payload, {required String lang}) async {
    submitCount++;
    if (!queueNext) return ContactSubmitResult.sent;
    final completer = nextCommit ?? Completer<void>();
    nextCommit = completer;
    return ContactSubmitResult.queuedOffline(
      msgId: 'msg-${submitCount}000000000',
      pendingCommit: completer.future,
    );
  }

  @override
  Future<bool> verifyPendingContactWrites({Duration timeout = const Duration(seconds: 5)}) async {
    verifyCalls++;
    return verifyResult;
  }
}

class _FakeConnectivityEnv extends ConnectivityEnv {
  bool online;
  final _ctl = StreamController<bool>.broadcast();

  _FakeConnectivityEnv({this.online = false});

  @override
  bool get isOnline => online;

  @override
  Future<bool> checkOnline() async => online;

  @override
  Stream<bool> get onOnlineChanged => _ctl.stream;

  void emit(bool next) {
    online = next;
    _ctl.add(next);
  }

  void dispose() => _ctl.close();
}

// --- Lightweight Firestore fakes for FirestoreRepository.submitContact unit tests ---

class _FakeSnapshotMetadata implements SnapshotMetadata {
  @override
  final bool hasPendingWrites;
  @override
  final bool isFromCache = true;

  const _FakeSnapshotMetadata({required this.hasPendingWrites});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDocSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final bool exists;
  @override
  final SnapshotMetadata metadata;
  final Map<String, dynamic>? _data;

  // ignore: prefer_initializing_formals
  _FakeDocSnapshot({required this.exists, required this.metadata, Map<String, dynamic>? data}) : _data = data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDocCacheState {
  bool existsInCache = false;
  bool pendingInCache = false;
}

// ignore: subtype_of_sealed_class
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  @override
  final String id;
  @override
  final String path;
  final _FakeDocCacheState cacheState = _FakeDocCacheState();

  _FakeDocRef(this.id, this.path);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return _FakeDocSnapshot(
      exists: cacheState.existsInCache,
      metadata: _FakeSnapshotMetadata(hasPendingWrites: cacheState.pendingInCache),
      data: cacheState.existsInCache ? {'message': 'hi'} : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeCollectionRef implements CollectionReference<Map<String, dynamic>> {
  final _FakeDocRef nextDoc;
  _FakeCollectionRef(this.nextDoc);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => nextDoc;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWriteBatch implements WriteBatch {
  final Completer<void> commitCompleter;
  final List<({String path, Map<String, dynamic> data})> writes = [];
  final void Function()? onCommit;

  _FakeWriteBatch(this.commitCompleter, {this.onCommit});

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    writes.add((path: document.path, data: Map<String, dynamic>.from(data as Map)));
  }

  @override
  Future<void> commit() {
    onCommit?.call();
    return commitCompleter.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeContactFirestore implements FirebaseFirestore {
  final _FakeDocRef msgDoc;
  final _FakeDocRef rateDoc;
  final _FakeWriteBatch activeBatch;
  Completer<void> waitForPendingCompleter = Completer<void>()..complete();

  _FakeContactFirestore({
    required this.msgDoc,
    required this.rateDoc,
    required this.activeBatch,
  });

  @override
  WriteBatch batch() => activeBatch;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    assert(collectionPath == 'contact_messages');
    return _FakeCollectionRef(msgDoc);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    assert(documentPath == 'meta/contact_rate');
    return rateDoc;
  }

  @override
  Future<void> waitForPendingWrites() => waitForPendingCompleter.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SeedData _loadSeed() {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  return SeedData(raw);
}

Future<void> _fillValidContactForm(WidgetTester tester, {required String message}) async {
  final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), 'مينا عاطف');
  await tester.enterText(fields.at(1), '01012345678');
  await tester.enterText(fields.at(2), 'mina@example.com');
  await tester.enterText(fields.at(3), message);
  await tester.pumpAndSettle();

  final consent = find.descendant(of: find.byType(ContactForm), matching: find.byType(CheckboxListTile));
  await tester.tap(consent);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetContactRateLimiterForTest();
  });

  group('FirestoreRepository.submitContact & verifyPendingContactWrites', () {
    test('offline branch polls Source.cache hasPendingWrites and returns queuedOffline without 15s wait', () async {
      final seed = _loadSeed();
      final msgDoc = _FakeDocRef('msgOffline123456', 'contact_messages/msgOffline123456');
      final rateDoc = _FakeDocRef('contact_rate', 'meta/contact_rate');
      final commit = Completer<void>();
      final batch = _FakeWriteBatch(
        commit,
        onCommit: () {
          // Simulate Firestore persisting the batch into local cache before server ack.
          msgDoc.cacheState.existsInCache = true;
          msgDoc.cacheState.pendingInCache = true;
        },
      );
      final db = _FakeContactFirestore(msgDoc: msgDoc, rateDoc: rateDoc, activeBatch: batch);
      final repo = FirestoreRepository(db, seed, isOffline: () => true);

      final result = await repo.submitContact(
        {'name': 'Mina', 'phone': '01012345678', 'email': '', 'message': 'Hello church'},
        lang: 'ar',
      );

      expect(result.isQueuedOffline, isTrue);
      expect(result.msgId, 'msgOffline123456');
      expect(result.pendingCommit, isNotNull);
      expect(batch.writes.map((w) => w.path), ['contact_messages/msgOffline123456', 'meta/contact_rate']);
      expect(batch.writes.last.data['lastMsgId'], 'msgOffline123456');

      var settled = false;
      unawaited(result.pendingCommit!.then((_) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);

      commit.complete();
      await result.pendingCommit;
      expect(settled, isTrue);
    });

    test('offline branch returns sent immediately if commit wins before cache poll', () async {
      final seed = _loadSeed();
      final msgDoc = _FakeDocRef('msgFast123456', 'contact_messages/msgFast123456');
      final rateDoc = _FakeDocRef('contact_rate', 'meta/contact_rate');
      final commit = Completer<void>();
      final batch = _FakeWriteBatch(commit, onCommit: () => commit.complete());
      final db = _FakeContactFirestore(msgDoc: msgDoc, rateDoc: rateDoc, activeBatch: batch);
      final repo = FirestoreRepository(db, seed, isOffline: () => true);

      final result = await repo.submitContact(
        {'name': 'Mina', 'phone': '01012345678', 'email': '', 'message': 'Hello church'},
        lang: 'en',
      );

      expect(result.isSent, isTrue);
      expect(result.isQueuedOffline, isFalse);
    });

    test('offline branch keeps waiting on commitFuture when cache polls never observe hasPendingWrites', () async {
      final seed = _loadSeed();
      final msgDoc = _FakeDocRef('msgUnobs123456', 'contact_messages/msgUnobs123456');
      final rateDoc = _FakeDocRef('contact_rate', 'meta/contact_rate');
      final commit = Completer<void>();
      // onCommit leaves cacheState.existsInCache = false, pendingInCache = false.
      final batch = _FakeWriteBatch(commit);
      final db = _FakeContactFirestore(msgDoc: msgDoc, rateDoc: rateDoc, activeBatch: batch);
      final repo = FirestoreRepository(db, seed, isOffline: () => true);

      ContactSubmitResult? result;
      final submitFuture = repo.submitContact(
        {'name': 'Mina', 'phone': '01012345678', 'email': '', 'message': 'Hello church'},
        lang: 'en',
      ).then((r) => result = r);

      // Exhaust the 40 * 25 ms = 1000 ms cache poll window: must NOT resolve as queuedOffline.
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(result, isNull);

      commit.complete();
      await submitFuture;
      expect(result, isNotNull);
      expect(result!.isSent, isTrue);
      expect(result!.isQueuedOffline, isFalse);
    });

    test('verifyPendingContactWrites returns false offline or on timeout, and true when online & flushed', () async {
      final seed = _loadSeed();
      final msgDoc = _FakeDocRef('m1', 'contact_messages/m1');
      final rateDoc = _FakeDocRef('contact_rate', 'meta/contact_rate');
      final db = _FakeContactFirestore(
        msgDoc: msgDoc,
        rateDoc: rateDoc,
        activeBatch: _FakeWriteBatch(Completer<void>()),
      );

      var offline = true;
      final repo = FirestoreRepository(db, seed, isOffline: () => offline);

      expect(await repo.verifyPendingContactWrites(timeout: const Duration(milliseconds: 20)), isFalse);

      offline = false;
      db.waitForPendingCompleter = Completer<void>(); // hangs
      expect(await repo.verifyPendingContactWrites(timeout: const Duration(milliseconds: 20)), isFalse);

      db.waitForPendingCompleter = Completer<void>()..complete();
      expect(await repo.verifyPendingContactWrites(timeout: const Duration(milliseconds: 50)), isTrue);
    });
  });

  group('ContactQueue UX & restart marker', () {
    testWidgets('offline queued submission writes minimal marker (no PII/text), disables resend, and clears on ack',
        (tester) async {
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed);
      final commit = Completer<void>();
      repo.nextCommit = commit;
      final env = _FakeConnectivityEnv(online: false);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: Consumer(builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              locale: const Locale('ar'),
              theme: buildTheme(const Locale('ar')),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            );
          }),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/contact');
      await tester.pumpAndSettle();

      const msgText = 'رسالة اختبار أثناء انقطاع الاتصال';
      await _fillValidContactForm(tester, message: msgText);
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactQueuedStatus')), findsOneWidget);
      expect(find.text('محفوظة وهتتبعت أول ما النت يرجع — خلي التطبيق مفتوح'), findsOneWidget);

      // Marker is saved with msgId + timestamp ONLY — never message text, name, phone, or email (ADR-034).
      final sp = await SharedPreferences.getInstance();
      final rawMarker = sp.getString(contactPendingMarkerKey);
      expect(rawMarker, isNotNull);
      final decoded = jsonDecode(rawMarker!) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'msgId', 'timestamp'});
      expect(decoded['msgId'], 'msg-1000000000');
      expect(decoded['timestamp'], isA<int>());
      expect(rawMarker, isNot(contains(msgText)));
      expect(rawMarker, isNot(contains('مينا عاطف')));
      expect(rawMarker, isNot(contains('01012345678')));
      expect(rawMarker, isNot(contains('mina@example.com')));

      // Resend must stay disabled while hasPendingWrites is true.
      final btnDuringPending = tester.widget<FilledButton>(find.byKey(const Key('contactSendButton')));
      expect(btnDuringPending.onPressed, isNull);
      expect(container.read(contactQueueProvider).hasPendingWrites, isTrue);

      // Server ack completes pending write -> clears marker, fields, and shows success notice.
      commit.complete();
      await tester.pumpAndSettle();

      expect(sp.getString(contactPendingMarkerKey), isNull);
      expect(container.read(contactQueueProvider).hasPendingWrites, isFalse);
      expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
      expect(find.text(msgText), findsNothing);
    });

    testWidgets('rejected queued send clears marker, preserves draft, and applies local rate limiter', (tester) async {
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed);
      final commit = Completer<void>();
      repo.nextCommit = commit;
      final env = _FakeConnectivityEnv(online: false);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: Consumer(builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              locale: const Locale('ar'),
              theme: buildTheme(const Locale('ar')),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            );
          }),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/contact');
      await tester.pumpAndSettle();

      const msgText = 'رسالة هامة لا يجب أن تضيع عند رفض الخادم';
      await _fillValidContactForm(tester, message: msgText);
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactQueuedStatus')), findsOneWidget);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(contactPendingMarkerKey), isNotNull);

      // Simulate navigating away before server rejects on reconnect.
      container.read(routerProvider).go('/');
      await tester.pumpAndSettle();

      // Server rejects the queued batch (e.g. meta/contact_rate throttle / rules).
      commit.completeError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Caller throttled by meta/contact_rate',
        ),
      );
      await tester.pumpAndSettle();

      // Marker is cleared on handled rejection.
      expect(sp.getString(contactPendingMarkerKey), isNull);

      // Return to /contact: failure notice is shown and draft text is preserved!
      container.read(routerProvider).go('/contact');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactQueuedError')), findsOneWidget);
      expect(find.text('تعذّر إرسال الرسالة المحفوظة عند عودة الاتصال. يمكنك مراجعتها وإعادة الإرسال.'), findsOneWidget);
      expect(find.text('مينا عاطف'), findsOneWidget);
      expect(find.text('01012345678'), findsOneWidget);
      expect(find.text('mina@example.com'), findsOneWidget);
      expect(find.text(msgText), findsOneWidget);

      // Resend button is re-enabled, and immediate resend hits the local rate limiter rather than the server.
      final btnAfterReject = tester.widget<FilledButton>(find.byKey(const Key('contactSendButton')));
      expect(btnAfterReject.onPressed, isNotNull);

      repo.queueNext = false;
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      expect(repo.submitCount, 1);
      expect(find.textContaining('الانتظار'), findsOneWidget);

      // Once cooldown passes, resend succeeds.
      resetContactRateLimiterForTest();
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      expect(repo.submitCount, 2);
      expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
    });

    testWidgets('_restoreDraft does not overwrite user edits made while queued', (tester) async {
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed);
      final commit = Completer<void>();
      repo.nextCommit = commit;
      final env = _FakeConnectivityEnv(online: false);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: Consumer(builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              locale: const Locale('ar'),
              theme: buildTheme(const Locale('ar')),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            );
          }),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/contact');
      await tester.pumpAndSettle();

      await _fillValidContactForm(tester, message: 'الرسالة الأصلية المعلقة');
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      // User edits the message field while still on /contact before rejection arrives.
      final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
      const editedText = 'تعديل المستخدم أثناء الانتظار';
      await tester.enterText(fields.at(3), editedText);
      await tester.pump();

      commit.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'throttled'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactQueuedError')), findsOneWidget);
      expect(find.text(editedText), findsOneWidget);
      expect(find.text('الرسالة الأصلية المعلقة'), findsNothing);
    });

    testWidgets('queued success does not clear edits made to the form after submit', (tester) async {
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed);
      final commit = Completer<void>();
      repo.nextCommit = commit;
      final env = _FakeConnectivityEnv(online: false);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: ContactForm())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillValidContactForm(tester, message: 'الرسالة الأولى المعلقة');
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      // User starts composing a follow-up message while the first is still queued.
      final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
      const nextDraft = 'مسودة رسالة جديدة بعد الإرسال';
      await tester.enterText(fields.at(3), nextDraft);
      await tester.pump();

      // Queued message succeeds -> shows sent banner, keeps the user's new edits intact.
      commit.complete();
      await tester.pumpAndSettle();

      expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
      expect(find.text(nextDraft), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('contactSendButton'))).onPressed, isNotNull);
    });

    testWidgets('immediate online success records submission once in rate limiter (3 allowed, 4th throttled)',
        (tester) async {
      resetContactRateLimiterForTest(minInterval: Duration.zero, maxPerWindow: 3);
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed)..queueNext = false;
      final env = _FakeConnectivityEnv(online: true);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(true)),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: ContactForm())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 1; i <= 3; i++) {
        await _fillValidContactForm(tester, message: 'رسالة سريعة رقم $i للتحقق من الحد');
        await tester.tap(find.byKey(const Key('contactSendButton')));
        await tester.pumpAndSettle();
        expect(repo.submitCount, i);
        expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
      }

      await _fillValidContactForm(tester, message: 'رسالة رابعة يجب إيقافها بالحد المحلي');
      await tester.tap(find.byKey(const Key('contactSendButton')));
      await tester.pumpAndSettle();

      expect(repo.submitCount, 3);
      expect(find.textContaining('الانتظار'), findsOneWidget);
    });

    testWidgets('shows unverified previous notice on restart when marker exists, and dismiss clears marker',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        contactPendingMarkerKey: jsonEncode({'msgId': 'prev-msg-1', 'timestamp': 1700000000000}),
      });
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed)..verifyResult = false;
      final env = _FakeConnectivityEnv(online: false);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => env.onOnlineChanged),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: ContactForm())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactUnverifiedNotice')), findsOneWidget);
      expect(find.text('رسالتك السابقة ممكن متكونش اتبعتت — اتصل بالكنيسة للتأكيد'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismissUnverifiedContactButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contactUnverifiedNotice')), findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(contactPendingMarkerKey), isNull);
    });

    testWidgets('auto-clears unverified marker on restart when online and pending writes verify cleanly',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        contactPendingMarkerKey: jsonEncode({'msgId': 'prev-msg-2', 'timestamp': 1700000000000}),
      });
      final seed = _loadSeed();
      final repo = _QueuedContactRepo(seed)..verifyResult = true;
      final env = _FakeConnectivityEnv(online: true);
      addTearDown(env.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
            repositoryProvider.overrideWithValue(repo),
            featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
            settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
            dailyVersesProvider.overrideWith((_) async => const []),
            connectivityEnvProvider.overrideWithValue(env),
            connectivityProvider.overrideWith((_) => Stream.value(true)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: buildTheme(const Locale('en')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: ContactForm())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.verifyCalls, 1);
      expect(find.byKey(const Key('contactUnverifiedNotice')), findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(contactPendingMarkerKey), isNull);
    });
  });
}
