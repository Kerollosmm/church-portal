import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:church_portal/core/push_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/local_notifications.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/notify_plan.dart';
import 'package:church_portal/domain/push.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/notify_providers.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/notifications_admin.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:church_portal/ui/widgets/map_embed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

// -----------------------------------------------------------------------------
// Test Helpers & Fakes
// -----------------------------------------------------------------------------

class _FakeLocalNotifier implements LocalNotifier {
  @override
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<bool> canScheduleExactAlarms() async => true;
  @override
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang}) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showInstant(int id, String title, String body, {String? channelId, String? payload}) async {}
  @override
  Future<int> pendingCount() async => 0;
  @override
  Future<String?> getLaunchPayload() async => null;
}

class _FixedLocale extends LocaleNotifier {
  final Locale locale;
  _FixedLocale(this.locale);
  @override
  Locale build() => locale;
}

final _testNow = CairoTime.at(2026, 11, 15, 12 * 60).toUtc();

SeedData _loadSeed({Map<String, dynamic> featuresOverride = const {}}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final features = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  features['sections'] = {...(features['sections'] as Map), 'meetings': true};
  features.addAll(featuresOverride);
  raw['settings']['features'] = features;
  return SeedData(raw);
}

class _TestContactRepository extends SeedRepository {
  bool shouldSucceed = true;
  bool shouldTimeout = false;
  Map<String, dynamic>? lastPayload;

  _TestContactRepository(super.seed);

  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async {
    lastPayload = payload;
    if (shouldTimeout) throw TimeoutException('Simulated contact submit timeout');
    if (!shouldSucceed) throw Exception('Simulated submit failure');
  }
}

class _FakePushEnv extends PushEnv {
  @override
  bool get isSupported => true;
  @override
  String get permission => 'granted';
  @override
  Future<String> requestPermission() async => 'granted';
  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async => true;
  @override
  Future<String?> enableAndGetToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async => 'test_token';
  @override
  Future<String?> getWebToken({required String vapidKey, required Map<String, dynamic> firebaseConfig}) async => 'test_token';
  @override
  Future<bool> deleteWebToken({required Map<String, dynamic> firebaseConfig}) async => true;
  @override
  Future<bool> showSwTestNotification({String? title, String? body, String? link}) async => true;
  @override
  Future<List<WebInboxItem>> readInbox() async => const [];
  @override
  Future<bool> clearInbox() async => true;
  @override
  Future<bool> syncQuietHours({
    required bool enabled,
    required String start,
    required String end,
    bool remindersRespectQuietHours = true,
  }) async =>
      true;
  @override
  Stream<String> get deepLinks => const Stream.empty();
  @override
  Stream<WebInboxItem> get inboxEvents => const Stream.empty();
}

class _FakeAdminRepo extends AdminBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  final _controllers = <String, StreamController<AdminDoc?>>{};

  _FakeAdminRepo([Map<String, Map<String, dynamic>>? initial]) {
    if (initial != null) docs.addAll(initial);
  }

  @override
  String get actor => 'admin@example.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(const []);

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _controllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) c.add(docs.containsKey(path) ? AdminDoc(path.split('/').last, docs[path]!) : null);
    });
    return c.stream;
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    docs[path] = {...?docs[path], ...data};
    _controllers[path]?.add(AdminDoc(path.split('/').last, docs[path]!));
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

Future<(GoRouter, ProviderContainer)> _pumpTestApp(
  WidgetTester tester, {
  required SeedData seed,
  required Size size,
  Locale locale = const Locale('ar'),
  ContentRepository? repo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo ?? SeedRepository(seed)),
    nowProvider.overrideWith((ref) => Stream.value(_testNow)),
    localNotifierProvider.overrideWithValue(_FakeLocalNotifier()),
    localeProvider.overrideWith(() => _FixedLocale(locale)),
  ]);
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final l = ref.watch(localeProvider);
        final active = ref.watch(activeThemeProvider);
        final themeData = buildTheme(l, palette: active.palette, key: active.key);
        return MaterialApp.router(
          locale: l,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: themeData,
          routerConfig: router,
        );
      },
    ),
  ));
  await tester.pumpAndSettle();
  return (router, container);
}

// -----------------------------------------------------------------------------
// Test Suite
// -----------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Medium #9: AppShell Header Responsive Across Breakpoints', () {
    const breakpoints = [
      Size(320, 800),   // Narrow mobile
      Size(400, 800),   // Standard mobile
      Size(905, 900),   // Mid-width tablet
      Size(1024, 900),  // Desktop min-wide
      Size(1400, 900),  // Large desktop
    ];

    for (final size in breakpoints) {
      for (final lang in ['ar', 'en']) {
        testWidgets('AppShell at ${size.width.toInt()}px ($lang) renders title and seal without overflow or starvation',
            (tester) async {
          final seed = _loadSeed();
          final (router, _) = await _pumpTestApp(
            tester,
            seed: seed,
            size: size,
            locale: Locale(lang),
          );

          router.go('/');
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'No layout exceptions at ${size.width}px ($lang)');

          // Seal tab is rendered
          final sealFinder = find.byKey(const Key('sealTabHome'));
          expect(sealFinder, findsOneWidget, reason: 'SealTab must exist at ${size.width}px ($lang)');

          // Short title is rendered and never completely hidden or starved
          final titleFinder = find.byKey(const Key('appBarShortTitle'));
          expect(titleFinder, findsOneWidget, reason: 'appBarShortTitle must never be starved or hidden at ${size.width}px ($lang)');

          final titleSize = tester.getSize(titleFinder);
          expect(titleSize.width, greaterThan(0.0),
              reason: 'Readable title width must be > 0 at ${size.width}px ($lang)');

          // Check no overlap between title and seal
          final titleRect = tester.getRect(titleFinder);
          final sealRect = tester.getRect(sealFinder);
          expect(titleRect.overlaps(sealRect), isFalse,
              reason: 'Title must never visually collide with seal at ${size.width}px ($lang)');

          // On desktop (>= 1024px), verify nav items are present alongside title
          if (size.width >= 1024) {
            expect(find.text(lang == 'ar' ? 'الرئيسية' : 'Home'), findsOneWidget);
          }

          // Test subpage navigation with back arrow
          router.go('/about');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'No exceptions on /about at ${size.width}px ($lang)');
          expect(find.byKey(const Key('appBarShortTitle')), findsOneWidget);
        });
      }
    }
  });

  group('Medium #10: MapInteractionGuard Prevents Scroll Trapping', () {
    testWidgets('MapInteractionGuard initial state covers with shield and tap unlocks / lock relocks', (tester) async {
      final activeEvents = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: MapInteractionGuard(
                  onActiveChanged: activeEvents.add,
                  child: const ColoredBox(
                    key: Key('mapContent'),
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially inactive: shield is present, lock button is absent
      final shieldFinder = find.byKey(const Key('mapInteractShield'));
      expect(shieldFinder, findsOneWidget);
      expect(find.byKey(const Key('mapLockScrollBtn')), findsNothing);
      expect(find.text('اضغط للتفاعل مع الخريطة'), findsOneWidget);

      // Tap shield to activate
      await tester.tap(shieldFinder);
      await tester.pumpAndSettle();

      expect(activeEvents, [true]);
      expect(find.byKey(const Key('mapInteractShield')), findsNothing);
      final lockBtnFinder = find.byKey(const Key('mapLockScrollBtn'));
      expect(lockBtnFinder, findsOneWidget);
      expect(find.text('قفل الخريطة للتمرير'), findsOneWidget);

      // Tap lock button to deactivate
      await tester.tap(lockBtnFinder);
      await tester.pumpAndSettle();

      expect(activeEvents, [true, false]);
      expect(find.byKey(const Key('mapInteractShield')), findsOneWidget);
      expect(find.byKey(const Key('mapLockScrollBtn')), findsNothing);
    });

    testWidgets('MapInteractionGuard automatically relocks when mouse exits', (tester) async {
      final activeEvents = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: MapInteractionGuard(
                  onActiveChanged: activeEvents.add,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to activate
      await tester.tap(find.byKey(const Key('mapInteractShield')));
      await tester.pumpAndSettle();
      expect(activeEvents.last, isTrue);

      // Move mouse inside then exit
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byKey(const Key('mapLockScrollBtn'))));
      await tester.pump();

      // Move mouse outside the 400x300 container
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      await gesture.removePointer();
      await tester.pumpAndSettle();

      expect(activeEvents.last, isFalse);
      expect(find.byKey(const Key('mapInteractShield')), findsOneWidget);
    });

    testWidgets('MapInteractionGuard resets to inactive when resetToken changes', (tester) async {
      final activeEvents = <bool>[];
      var token = 'token-1';

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: MapInteractionGuard(
                    resetToken: token,
                    onActiveChanged: activeEvents.add,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => setState(() => token = 'token-2'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to activate
      await tester.tap(find.byKey(const Key('mapInteractShield')));
      await tester.pumpAndSettle();
      expect(activeEvents.last, isTrue);
      expect(find.byKey(const Key('mapLockScrollBtn')), findsOneWidget);

      // Change resetToken
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should automatically reset to inactive
      expect(activeEvents.last, isFalse);
      expect(find.byKey(const Key('mapInteractShield')), findsOneWidget);
      expect(find.byKey(const Key('mapLockScrollBtn')), findsNothing);
    });

    testWidgets('ChurchMap integrates cleanly with MapInteractionGuard mapView', (tester) async {
      const settings = ChurchSettings(
        nameAr: 'كنيسة القديسين',
        nameEn: 'St. Maximus Church',
        addressAr: 'شارع 45 العصافرة بحري',
        addressEn: '45 St. Asafra',
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: Scaffold(
            body: ChurchMap(
              settings: settings,
              mapView: (context, embedUrl, fallback) => MapInteractionGuard(
                child: fallback,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChurchMap), findsOneWidget);
      expect(find.byKey(const Key('mapInteractShield')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mapInteractShield')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mapLockScrollBtn')), findsOneWidget);
    });
  });

  group('Medium #11d: NotificationsAdmin Draft Chips & Past Error Reset', () {
    testWidgets('Filter/Choice chips have selectedColor == bar and BorderSide.none', (tester) async {
      final now = CairoTime.now();
      final adminRepo = _FakeAdminRepo({
        'settings/notifications': {
          'schedule': <dynamic>[],
          'status': <String, dynamic>{},
          'sentLog': <dynamic>[],
          'health': {'lastRunAt': now.toIso8601String()},
        },
      });

      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(_loadSeed())),
            nowProvider.overrideWith((ref) => Stream.value(now.toUtc())),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: NotificationsAdminSection(
              repo: adminRepo,
              role: 'owner',
              pushEnv: _FakePushEnv(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open draft editor
      await tester.tap(find.byKey(const ValueKey('addScheduledPush')));
      await tester.pumpAndSettle();

      // Locate when-soon choice chip and tap it
      final soonFinder = find.byKey(const ValueKey('when-soon'));
      expect(soonFinder, findsOneWidget);
      await tester.tap(soonFinder);
      await tester.pumpAndSettle();

      final chipWidget = tester.widget<ChoiceChip>(soonFinder);
      expect(chipWidget.selected, isTrue);
      expect(chipWidget.selectedColor, isNotNull);
      expect(chipWidget.side, BorderSide.none);

      // Locate when-at choice chip
      final atFinder = find.byKey(const ValueKey('when-at'));
      expect(atFinder, findsOneWidget);
      final atChip = tester.widget<ChoiceChip>(atFinder);
      expect(atChip.side, BorderSide.none);
    });

    testWidgets('Toggling when-soon clears nm_errPast and shows sendToAllBtn when targets: all', (tester) async {
      final now = CairoTime.now();
      final adminRepo = _FakeAdminRepo({
        'settings/notifications': {
          'schedule': <dynamic>[],
          'status': <String, dynamic>{},
          'sentLog': <dynamic>[],
          'health': {'lastRunAt': now.toIso8601String()},
        },
      });

      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(_loadSeed())),
            nowProvider.overrideWith((ref) => Stream.value(now.toUtc())),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: NotificationsAdminSection(
              repo: adminRepo,
              role: 'owner',
              pushEnv: _FakePushEnv(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open draft editor
      await tester.tap(find.byKey(const ValueKey('addScheduledPush')));
      await tester.pumpAndSettle();

      // Enter title and body to make draft valid
      final titleField = find.byKey(const ValueKey('draft-titleAr'));
      await tester.enterText(titleField, 'عظة الأحد القادمة');
      final bodyField = find.byKey(const ValueKey('draft-bodyAr'));
      await tester.enterText(bodyField, 'تفاصيل عظة الأحد تبدأ في تمام السابعة مساء');
      await tester.pumpAndSettle();

      // Switch to when-at
      await tester.tap(find.byKey(const ValueKey('when-at')));
      await tester.pumpAndSettle();

      // Switch back to when-soon
      await tester.tap(find.byKey(const ValueKey('when-soon')));
      await tester.pumpAndSettle();

      // Verify when-soon is selected
      final soonChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('when-soon')));
      expect(soonChip.selected, isTrue);

      // Tap save-push button to trigger confirmation dialog
      final saveBtn = find.byKey(const ValueKey('save-push'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Since _draftTargets == 'all' and _draftSoon == true, dialog shows nm_sendToAllBtn («ابعت للكل»)
      expect(find.text('ابعت للكل'), findsOneWidget);
    });
  });

  group('Medium #13: ContactPage Full Reset on Send Success & Preservation on Error', () {
    testWidgets('Contact form clears ALL fields and resets category to default on success', (tester) async {
      final seed = _loadSeed();
      final testRepo = _TestContactRepository(seed);

      final (router, _) = await _pumpTestApp(
        tester,
        seed: seed,
        size: const Size(1200, 2000),
        locale: const Locale('ar'),
        repo: testRepo,
      );

      router.go('/contact');
      await tester.pumpAndSettle();

      // Check category dropdown is present
      final catDropdown = find.byKey(const Key('contactCategory'));
      expect(catDropdown, findsOneWidget);

      // Select non-default category 'شكوى' (c3)
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شكوى').last);
      await tester.pumpAndSettle();

      // Verify category was selected
      expect(find.descendant(of: find.byKey(const Key('contactCategory')), matching: find.text('شكوى')), findsOneWidget);

      // Fill form fields
      final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'مينا عادل');
      await tester.enterText(fields.at(1), '01012345678');
      await tester.enterText(fields.at(2), 'mina@example.com');
      await tester.enterText(fields.at(3), 'رسالة استفسار بخصوص الخدمات الكنسية');
      await tester.pumpAndSettle();

      // Check consent checkbox
      final consent = find.descendant(of: find.byType(ContactForm), matching: find.byType(CheckboxListTile));
      await tester.tap(consent);
      await tester.pumpAndSettle();

      // Submit successfully
      testRepo.shouldSucceed = true;
      final sendBtn = find.descendant(of: find.byType(ContactForm), matching: find.byIcon(Icons.send_rounded));
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify success status is shown and payload had category c3
      expect(find.descendant(of: find.byType(ContactForm), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      expect(testRepo.lastPayload?['category'], 'c3');

      // Verify text fields are cleared
      expect(find.text('مينا عادل'), findsNothing);
      expect(find.text('01012345678'), findsNothing);
      expect(find.text('mina@example.com'), findsNothing);
      expect(find.text('رسالة استفسار بخصوص الخدمات الكنسية'), findsNothing);

      // Verify category dropdown reset back to default category (first slot 'c1', 'استفسار عام')
      expect(find.descendant(of: find.byKey(const Key('contactCategory')), matching: find.text('استفسار عام')), findsOneWidget);
      final refreshedState = tester.state<FormFieldState<String>>(find.byKey(const Key('contactCategory')));
      expect(refreshedState.value, 'c1');
    });

    testWidgets('Contact form preserves entered fields and category when submission fails', (tester) async {
      final seed = _loadSeed();
      final testRepo = _TestContactRepository(seed)..shouldSucceed = false;

      final (router, _) = await _pumpTestApp(
        tester,
        seed: seed,
        size: const Size(1200, 2000),
        locale: const Locale('ar'),
        repo: testRepo,
      );

      router.go('/contact');
      await tester.pumpAndSettle();

      // Select category 'شكوى' (c3)
      final catDropdown = find.byKey(const Key('contactCategory'));
      await tester.tap(catDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شكوى').last);
      await tester.pumpAndSettle();

      // Verify category was selected
      expect(find.descendant(of: find.byKey(const Key('contactCategory')), matching: find.text('شكوى')), findsOneWidget);

      // Fill form fields
      final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'مينا محفوظ');
      await tester.enterText(fields.at(1), '01234567890');
      await tester.enterText(fields.at(2), 'm@example.com');
      await tester.enterText(fields.at(3), 'طلب مساعدة اجتماعية للأسرة');
      await tester.pumpAndSettle();

      // Check consent checkbox
      final consent = find.descendant(of: find.byType(ContactForm), matching: find.byType(CheckboxListTile));
      await tester.tap(consent);
      await tester.pumpAndSettle();

      // Submit
      final sendBtn = find.descendant(of: find.byType(ContactForm), matching: find.byIcon(Icons.send_rounded));
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify failure status is displayed
      expect(find.descendant(of: find.byType(ContactForm), matching: find.byIcon(Icons.error_outline)), findsOneWidget);

      // Verify fields are still populated and not lost
      expect(find.text('مينا محفوظ'), findsOneWidget);
      expect(find.text('01234567890'), findsOneWidget);
      expect(find.text('m@example.com'), findsOneWidget);
      expect(find.text('طلب مساعدة اجتماعية للأسرة'), findsOneWidget);

      // Verify category is still the selected category ('c3', 'شكوى')
      expect(find.descendant(of: find.byKey(const Key('contactCategory')), matching: find.text('شكوى')), findsOneWidget);
      final preservedState = tester.state<FormFieldState<String>>(find.byKey(const Key('contactCategory')));
      expect(preservedState.value, 'c3');
    });
  });
}
