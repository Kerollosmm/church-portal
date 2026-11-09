import 'dart:async';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/ui/admin/notifications_admin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAdminRepo extends AdminBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  final savedDocs = <String, Map<String, dynamic>>{};
  final _controllers = <String, StreamController<AdminDoc?>>{};

  _FakeAdminRepo([Map<String, Map<String, dynamic>>? initial]) {
    if (initial != null) docs.addAll(initial);
  }

  @override
  String get actor => 'test-admin@example.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(const []);

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _controllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        c.add(docs.containsKey(path) ? AdminDoc(path.split('/').last, docs[path]!) : null);
      }
    });
    return c.stream;
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    savedDocs[path] = data;
    docs[path] = data;
    if (_controllers.containsKey(path) && !_controllers[path]!.isClosed) {
      _controllers[path]!.add(AdminDoc(path.split('/').last, data));
    }
  }

  @override
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) async {
    for (final e in writes.entries) {
      await saveDoc(e.key, e.value);
    }
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
    for (final c in _controllers.values) {
      c.close();
    }
  }
}

Widget _app(Widget child, {Locale locale = const Locale('ar'), double textScale = 1.0}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('AppAndNotificationsScreen (ADR-059)', () {
    late _FakeAdminRepo repo;

    setUp(() {
      repo = _FakeAdminRepo({
        'settings/features': {
          'push': true,
          'pushVapidKey': 'test_vapid_key',
          'pushTypes': ['announcements', 'verse_daily'],
          'reminderLeads': [0, 15, 60],
          'reminderDefaultLead': 60,
          'reminderSources': 'lit,mtg,day',
          'notifyTypes': <String>[],
        },
        'settings/notifications': {
          'schedule': [
            'row1\u001f2026-11-10T10:00:00Z\u001fall\u001fعظة الأحد\u001fSunday Sermon\u001fتفاصيل العظة\u001fSermon details\u001f/\u001flit-123',
          ],
          'status': {
            'row1': {
              'state': 'error',
              'updatedAt': '2026-11-08T12:00:00Z',
              'error': 'FCM send failed',
            },
          },
          'sentLog': [
            'log1\u001f2026-11-08T09:00:00Z\u001fall\u001fتنبيه تجريبي\u001fTest alert\u001f/\u001fok\u001fok',
          ],
          'health': {
            'cronStatus': 'healthy',
            'lastRunAt': '2026-11-08T10:00:00Z',
            'lastSuccessAt': '2026-11-08T10:00:00Z',
            'totalSent24h': 5,
            'errors24h': 0,
          },
        },
      });
    });

    tearDown(() {
      repo.dispose();
    });

    testWidgets('responsive layout at 320px (200% text scale), 390px, and 1280px', (tester) async {
      final sizes = [
        const Size(320, 800),
        const Size(390, 844),
        const Size(1280, 900),
      ];

      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(_app(
          AppAndNotificationsScreen(repo: repo, role: 'owner'),
          textScale: size.width == 320 ? 2.0 : 1.0,
        ));
        await tester.pumpAndSettle();

        expect(find.byType(TabBar), findsOneWidget);
        expect(find.byType(NotificationsAdminSection), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'No layout exceptions at ${size.width}px');
      }

      addTearDown(tester.view.reset);
    });

    testWidgets('tab switching between Notifications and App Settings', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(AppAndNotificationsScreen(repo: repo, role: 'owner')));
      await tester.pumpAndSettle();

      // Initially on Notifications tab
      expect(find.byType(NotificationsAdminSection), findsOneWidget);

      // Switch to App Settings tab
      final appTab = find.byIcon(Icons.install_mobile_outlined);
      expect(appTab, findsOneWidget);
      await tester.tap(appTab);
      await tester.pumpAndSettle();

      // App install doc editor is visible
      expect(find.byKey(const ValueKey('app-install-doc')), findsOneWidget);

      // Switch back to Notifications tab
      final notifTab = find.byIcon(Icons.notifications_active_outlined);
      expect(notifTab, findsOneWidget);
      await tester.tap(notifTab);
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsAdminSection), findsOneWidget);
    });

    testWidgets('expanding notification type card, inserting placeholder chip, and reset defaults', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(AppAndNotificationsScreen(repo: repo, role: 'owner')));
      await tester.pumpAndSettle();

      // Tap the expansion tile for verse_daily
      final verseTile = find.descendant(
        of: find.byKey(const ValueKey('type_verse_daily')),
        matching: find.text('آية اليوم'),
      );
      expect(verseTile, findsOneWidget);
      await tester.tap(verseTile);
      await tester.pumpAndSettle();

      // Find a placeholder chip for verse_daily e.g. '{ref}'
      final chipRef = find.widgetWithText(ActionChip, '{ref}');
      expect(chipRef, findsWidgets);

      await tester.tap(chipRef.first);
      await tester.pumpAndSettle();

      // Bottom bar with Save button should now be visible (dirty)
      expect(find.text('تعديلات غير محفوظة'), findsOneWidget);
      expect(find.text('حفظ'), findsOneWidget);

      // Tap Reset Defaults button
      final resetBtn = find.widgetWithText(TextButton, 'استعادة النص الافتراضي');
      expect(resetBtn, findsWidgets);
      await tester.tap(resetBtn.first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('scheduled notification row: clone for retry', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(AppAndNotificationsScreen(repo: repo, role: 'owner')));
      await tester.pumpAndSettle();

      // Scroll down to the scheduled pushes section
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      // Verify the scheduled row "عظة الأحد" is displayed
      expect(find.text('عظة الأحد'), findsOneWidget);

      // Test cloning row for retry
      final cloneBtn = find.widgetWithText(TextButton, 'نسخ لإعادة الإرسال');
      expect(cloneBtn, findsOneWidget);
      await tester.tap(cloneBtn);
      await tester.pumpAndSettle();

      // Verify draft form is open with the cloned title
      expect(find.text('إضافة إشعار مجدول'), findsOneWidget);
      expect(find.text('عظة الأحد'), findsWidgets);
    });

    testWidgets('scheduled notification row: delete non-sending row', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(AppAndNotificationsScreen(repo: repo, role: 'owner')));
      await tester.pumpAndSettle();

      // Scroll down to the scheduled pushes section
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      final deleteBtn = find.widgetWithText(TextButton, 'حذف');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify saveDoc was called for settings/notifications with schedule having 0 rows
      expect(repo.savedDocs['settings/notifications'], isNotNull);
      final savedSchedule = repo.savedDocs['settings/notifications']!['schedule'] as List;
      expect(savedSchedule, isEmpty);
    });
  });
}
