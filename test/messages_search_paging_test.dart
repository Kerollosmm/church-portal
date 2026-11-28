import 'dart:async';

import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

class _CountingMessagesBackend extends AdminBackend {
  final List<AdminDoc> messages;
  final List<int> watchLatestLimits = [];
  final List<String> otherWatched = [];
  int activeMessageListeners = 0;
  int totalMessageSubscriptions = 0;
  final Set<StreamController<List<AdminDoc>>> _controllers = {};

  _CountingMessagesBackend(this.messages);

  @override
  String get actor => 'admin@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    otherWatched.add(collection);
    if (collection == 'contact_messages') {
      return watchLatest(collection);
    }
    return Stream.value(const []);
  }

  @override
  Stream<List<AdminDoc>> watchLatest(String collection, {int limit = 50}) {
    if (collection != 'contact_messages') return super.watchLatest(collection, limit: limit);
    watchLatestLimits.add(limit);
    late StreamController<List<AdminDoc>> ctrl;
    ctrl = StreamController<List<AdminDoc>>(
      onListen: () {
        activeMessageListeners++;
        totalMessageSubscriptions++;
        ctrl.add(_slice(limit));
      },
      onCancel: () {
        activeMessageListeners--;
        _controllers.remove(ctrl);
      },
    );
    _controllers.add(ctrl);
    return ctrl.stream;
  }

  List<AdminDoc> _slice(int limit) {
    final sorted = [...messages]..sort((a, b) {
        final ta = a.data['createdAt'], tb = b.data['createdAt'];
        if (ta is DateTime && tb is DateTime) return tb.compareTo(ta);
        return ta is DateTime ? -1 : (tb is DateTime ? 1 : 0);
      });
    return sorted.length <= limit ? sorted : sorted.sublist(0, limit);
  }

  void emitAll() {
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers.elementAt(i);
      if (!c.isClosed) {
        final limit = watchLatestLimits.isEmpty ? 50 : watchLatestLimits.last;
        c.add(_slice(limit));
      }
    }
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    if (collection == 'contact_messages') {
      for (final d in messages) {
        if (d.id == id) d.data.addAll(data);
      }
      emitAll();
    }
  }

  @override
  Future<void> delete(String collection, String id) async {}

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

  void dispose() {
    for (final c in _controllers.toList()) {
      c.close();
    }
  }
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('messageMatchesQuery', () {
    const cfg = ContactSettings.defaults;
    final bookingDoc = AdminDoc('b1', {
      'category': 'c2',
      'kind': 'booking',
      'name': 'مينا جرجس',
      'phone': '+20 101 234 5678',
      'message': 'حجز القاعة الكبرى',
      'bookingType': 'wedding',
      'preferredDate': '2027-02-14',
      'createdAt': DateTime.utc(2026, 11, 20, 9, 0),
      'status': 'new',
    });
    final anonDoc = AdminDoc('a1', {
      'category': 'c3',
      'kind': 'complaint',
      'anonymous': true,
      'message': 'ملاحظة على الصوت',
      'createdAt': DateTime.utc(2026, 11, 19, 12, 0),
      'status': 'new',
    });

    test('matches name, Arabic-normalized phone, text, type, and date', () {
      expect(messageMatchesQuery(bookingDoc, cfg, ''), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, 'مينا'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, '٠١٠١٢٣٤'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, '01012345678'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, 'القاعة الكبرى'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, 'حجز قاعة'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, 'Wedding'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, '٢٠٢٧-٠٢-١٤'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, '2026-11-20'), isTrue);
      expect(messageMatchesQuery(bookingDoc, cfg, 'غير موجود'), isFalse);

      expect(
        messageMatchesQuery(anonDoc, cfg, 'مجهول', anonymousLabel: 'مُرسِل مجهول'),
        isTrue,
      );
      expect(messageMatchesQuery(anonDoc, cfg, 'شكوى'), isTrue);
    });
  });

  group('MessagesFeed shared stream and paging', () {
    test('shares one listener, tracks unread count, and increases limit on loadMore', () async {
      final msgs = List.generate(
        75,
        (i) => AdminDoc('m$i', {
          'name': 'Sender $i',
          'message': 'Message $i',
          'status': i < 3 ? 'new' : 'handled',
          'createdAt': DateTime.utc(2026, 11, 1).add(Duration(minutes: i)),
        }),
      );
      final repo = _CountingMessagesBackend(msgs);
      addTearDown(repo.dispose);

      final feed = MessagesFeed(repo);
      addTearDown(feed.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(repo.totalMessageSubscriptions, 1);
      expect(repo.activeMessageListeners, 1);
      expect(repo.watchLatestLimits, [50]);
      expect(feed.docs, hasLength(50));
      expect(feed.canLoadMore, isTrue);
      // Newest 50 are m74..m25 (all 'handled'); m0..m2 are older.
      expect(feed.unreadCount, 0);

      feed.loadMore();
      await Future<void>.delayed(Duration.zero);

      expect(repo.watchLatestLimits, [50, 100]);
      expect(repo.activeMessageListeners, 1);
      expect(feed.docs, hasLength(75));
      expect(feed.canLoadMore, isFalse);
      expect(feed.unreadCount, 3);
    });

    test('reverts limit when loadMore fails and preserves existing docs', () async {
      final msgs = List.generate(
        50,
        (i) => AdminDoc('m$i', {
          'name': 'Sender $i',
          'message': 'Message $i',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 1).add(Duration(minutes: i)),
        }),
      );
      final repo = _FailSecondWatchBackend(msgs);
      final feed = MessagesFeed(repo);
      addTearDown(feed.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(feed.docs, hasLength(50));
      expect(feed.canLoadMore, isTrue);

      feed.loadMore();
      await Future<void>.delayed(Duration.zero);

      expect(feed.limit, 50);
      expect(feed.hasError, isTrue);
      expect(feed.docs, hasLength(50));
      expect(feed.loadingMore, isFalse);
    });
  });

  group('MessagesScreen search & paging widgets', () {
    testWidgets('search filters by name, Arabic-digit phone, text, type, date and clears cleanly', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _CountingMessagesBackend([
        AdminDoc('m1', {
          'category': 'c1',
          'name': 'أبانوب عادل',
          'phone': '01012345678',
          'message': 'سؤال عن مواعيد القداس',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 10, 8, 0),
        }),
        AdminDoc('m2', {
          'category': 'c2',
          'kind': 'booking',
          'name': 'مارينا نبيل',
          'phone': '01298765432',
          'message': 'طلب حجز القاعة',
          'bookingType': 'wedding',
          'preferredDate': '2027-02-14',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 15, 8, 0),
        }),
      ]);
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('m2')), findsOneWidget);

      // Search by Arabic-Indic phone digits
      await tester.enterText(find.byKey(const Key('messages-search')), '٠١٢٩٨٧');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m1')), findsNothing);
      expect(find.byKey(const ValueKey('m2')), findsOneWidget);

      // Search by preferred date
      await tester.enterText(find.byKey(const Key('messages-search')), '2027-02-14');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m2')), findsOneWidget);
      expect(find.byKey(const ValueKey('m1')), findsNothing);

      // Search by name
      await tester.enterText(find.byKey(const Key('messages-search')), 'أبانوب');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('m2')), findsNothing);

      // Clear search restores both
      await tester.tap(find.byKey(const Key('messages-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('m2')), findsOneWidget);
    });

    testWidgets('load more increases limit by 50 and hides once all messages are loaded (320px/200% safe)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final msgs = List.generate(
        60,
        (i) => AdminDoc('msg-$i', {
          'name': 'Visitor $i',
          'message': 'Body $i',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 1).add(Duration(hours: i)),
        }),
      );
      final repo = _CountingMessagesBackend(msgs);
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(repo.watchLatestLimits, [50]);
      // Newest message (msg-59) is present; oldest (msg-0) is not loaded yet.
      expect(find.byKey(const ValueKey('msg-59')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-0')), findsNothing);
      final loadMoreFinder = find.byKey(const Key('messages-load-more'));
      await tester.scrollUntilVisible(
        loadMoreFinder,
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(loadMoreFinder, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(loadMoreFinder);
      await tester.pumpAndSettle();

      expect(repo.watchLatestLimits, [50, 100]);
      expect(loadMoreFinder, findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('msg-0')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('msg-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('load more stays available when search matches nothing in the first page', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final msgs = List.generate(
        60,
        (i) => AdminDoc('msg-$i', {
          'name': 'Visitor $i',
          'message': 'Body $i',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 1).add(Duration(hours: i)),
        }),
      );
      final repo = _CountingMessagesBackend(msgs);
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('en')));
      await tester.pumpAndSettle();

      // Visitor 0 is on page 2 (older than newest 50).
      await tester.enterText(find.byKey(const Key('messages-search')), 'Visitor 0');
      await tester.pumpAndSettle();
      expect(find.text('No messages'), findsOneWidget);
      expect(find.byKey(const Key('messages-load-more')), findsOneWidget);

      await tester.tap(find.byKey(const Key('messages-load-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('msg-0')), findsOneWidget);
      expect(find.byKey(const Key('messages-load-more')), findsNothing);
    });

    testWidgets('AdminDashboard shares one contact_messages stream across nav badge, OverviewScreen, and MessagesScreen',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _CountingMessagesBackend([
        AdminDoc('m1', {
          'name': 'مرسل ١',
          'phone': '01012345678',
          'message': 'رسالة أولى',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 10, 9),
        }),
        AdminDoc('m2', {
          'name': 'مرسل ٢',
          'phone': '01112345678',
          'message': 'رسالة ثانية',
          'status': 'new',
          'createdAt': DateTime.utc(2026, 11, 10, 10),
        }),
      ]);
      addTearDown(repo.dispose);

      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u1',
            email: 'admin@church.org',
            role: AdminRoles.editor,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      // Only 1 listener opened for contact_messages across AdminDashboard + OverviewScreen.
      expect(repo.totalMessageSubscriptions, 1);
      expect(repo.activeMessageListeners, 1);
      expect(repo.otherWatched, isNot(contains('contact_messages')));
      final badge = find.byKey(const ValueKey('nav-messages-badge'));
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);

      // Navigate to MessagesScreen -> STILL only 1 subscription total!
      await tester.tap(find.byKey(const ValueKey('nav-messages')));
      await tester.pumpAndSettle();
      expect(repo.totalMessageSubscriptions, 1);
      expect(repo.activeMessageListeners, 1);

      // Mark one message done -> both MessagesScreen and nav badge update via the shared stream.
      await tester.tap(find.byKey(const ValueKey('msgToggleStatus-m2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m2')), findsNothing);
      expect(find.descendant(of: badge, matching: find.text('1')), findsOneWidget);

      // Navigate back to OverviewScreen -> STILL only 1 subscription total!
      await tester.tap(find.byKey(const ValueKey('nav-overview')));
      await tester.pumpAndSettle();
      expect(repo.totalMessageSubscriptions, 1);
      expect(repo.activeMessageListeners, 1);
    });
  });
}

class _FailSecondWatchBackend extends _CountingMessagesBackend {
  int _calls = 0;
  _FailSecondWatchBackend(super.messages);

  @override
  Stream<List<AdminDoc>> watchLatest(String collection, {int limit = 50}) {
    _calls++;
    if (_calls == 1) return super.watchLatest(collection, limit: limit);
    return Stream<List<AdminDoc>>.error(StateError('network error'));
  }
}
