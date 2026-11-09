// Admin notification manager (ADR-059) — widget tests, incl. the PR #55 UX
// review: friendly labels (no raw keys), delete confirmation, inline
// validation, rows the rules and the sender accept, and the settings save.
import 'dart:async';
import 'dart:io';

import 'package:church_portal/core/push_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/push.dart';
import 'package:church_portal/ui/admin/notifications_admin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// In-memory backend with Firestore-like top-level merge on save.
class _FakeAdminRepo extends AdminBackend {
  final Map<String, Map<String, dynamic>> docs = {};
  final saves = <String, List<Map<String, dynamic>>>{};
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
      if (!c.isClosed) c.add(docs.containsKey(path) ? AdminDoc(path.split('/').last, docs[path]!) : null);
    });
    return c.stream;
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    saves.putIfAbsent(path, () => []).add(data);
    docs[path] = {...?docs[path], ...data};
    _controllers[path]?.add(AdminDoc(path.split('/').last, docs[path]!));
  }

  Map<String, dynamic>? lastSave(String path) => saves[path]?.last;

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

class _FakePushEnv extends PushEnv {
  int shown = 0;
  @override
  bool get isSupported => true;
  @override
  String get permission => 'granted';
  @override
  Future<String> requestPermission() async => 'granted';
  @override
  Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async {
    shown++;
    return true;
  }
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
  Future<bool> syncQuietHours({required bool enabled, required String start, required String end}) async => true;
  @override
  Stream<String> get deepLinks => const Stream.empty();
  @override
  Stream<WebInboxItem> get inboxEvents => const Stream.empty();
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

String _iso(DateTime d) => scheduleIso(d);
const _s = '\u001f';

/// `validNotifyRow`'s regex, read from firestore.rules (so this test breaks if
/// the rule and the client drift apart).
RegExp _rulesRowRegex() {
  final rules = File('firestore.rules').readAsStringSync();
  final fn = rules.substring(rules.indexOf('function validNotifyRow('));
  final m = RegExp(r"s\.matches\('(.+?)'\);").firstMatch(fn)!;
  final pattern = m.group(1)!.replaceAll(r'\\', r'\').replaceAll(r'\x1f', '\u001f');
  return RegExp(pattern);
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  late _FakeAdminRepo repo;
  final now = DateTime.now().toUtc();

  Map<String, Map<String, dynamic>> seed({Map<String, dynamic>? health, List<String>? notifyTypes}) => {
        'settings/features': {
          'push': true,
          'pushVapidKey': '',
          'pushTypes': ['announcements', 'verse_daily', 'reminders'],
          'reminderLeads': [0, 15, 60],
          'reminderDefaultLead': 60,
          'reminderSources': 'lit,mtg,day',
          'notifyTypes': notifyTypes ?? <String>[],
        },
        'settings/notifications': {
          'schedule': [
            ['row1', _iso(now.subtract(const Duration(hours: 3))), 'all', 'عظة الأحد', 'Sunday Sermon', 'تفاصيل العظة', 'Sermon details', '/', 'lit-123'].join(_s),
            ['row2', _iso(now.add(const Duration(days: 2))), 'all', 'نهضة العذراء', '', 'تبدأ ٧ مساءً', '', '/mass-schedule', ''].join(_s),
          ],
          'status': {
            'row1': {'state': 'error', 'appState': 'error', 'webState': 'error'},
          },
          'sentLog': [
            ['row1', _iso(now.subtract(const Duration(hours: 3))), 'error', 'عظة الأحد', 'cron'].join(_s),
          ],
          'health': health ?? {'lastRunAt': _iso(now.subtract(const Duration(minutes: 10)))},
        },
      };

  setUp(() => repo = _FakeAdminRepo(seed()));
  tearDown(() => repo.dispose());

  Future<void> pump(WidgetTester tester, {Size size = const Size(1000, 4000), String role = 'owner', PushEnv? env, double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(
      env == null
          ? AppAndNotificationsScreen(repo: repo, role: role)
          : NotificationsAdminSection(repo: repo, role: role, pushEnv: env),
      textScale: textScale,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    // The save bar is not in the list; ensureVisible would scroll the
    // surrounding TabBarView instead.
    if (!key.endsWith('-settings')) await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('no layout errors at 320 px (200% text), 390 px and 1280 px', (tester) async {
    for (final (size, scale) in [(const Size(320, 3000), 2.0), (const Size(390, 3000), 1.0), (const Size(1280, 2400), 1.0)]) {
      await pump(tester, size: size, textScale: scale);
      expect(find.byType(NotificationsAdminSection), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at ${size.width}px');
    }
  });

  testWidgets('every label is plain text: no raw l10n keys, stored codes or W:/A: markers', (tester) async {
    await pump(tester);
    final raw = RegExp(r'^(nm_|err_)|^[a-z]+[A-Z][A-Za-z]+$|^[WA]:|^(ALL|APP|WEB)$|^(lit|mtg|day)$');
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((s) => s.isNotEmpty);
    final bad = texts.where(raw.hasMatch).toList();
    expect(bad, isEmpty);
    expect(find.text('الإشعارات'), findsWidgets);
    expect(find.text('تثبيت التطبيق'), findsOneWidget);
    expect(find.text('تشغيل الإشعارات'), findsOneWidget);
    expect(find.text('خدمة الإرسال تعمل'), findsOneWidget);
    // Friendly status names and the explanation of what to do.
    expect(find.text('فشل'), findsWidgets);
    expect(find.text('مجدول'), findsOneWidget);
    expect(find.textContaining('أعد الإرسال'), findsWidgets);
    expect(find.text('الجميع'), findsWidgets);
  });

  testWidgets('sender status: never run / stopped are explained, not shown as an error code', (tester) async {
    repo = _FakeAdminRepo(seed(health: {}));
    await pump(tester);
    expect(find.text('خدمة الإرسال لم تعمل بعد'), findsOneWidget);
    repo = _FakeAdminRepo(seed(health: {'lastRunAt': _iso(now.subtract(const Duration(hours: 5)))}));
    await pump(tester);
    expect(find.text('خدمة الإرسال متوقفة'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation; cancel keeps the row, confirm removes only it', (tester) async {
    await pump(tester);
    await tapKey(tester, 'delete-row2');
    expect(find.text('حذف هذا الإعلان؟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastSave('settings/notifications'), isNull);

    await tapKey(tester, 'delete-row2');
    await tester.tap(find.byKey(const ValueKey('confirm-ok')));
    await tester.pumpAndSettle();
    final saved = repo.lastSave('settings/notifications')!['schedule'] as List;
    expect(saved, hasLength(1));
    expect((saved.single as String).split(_s).first, 'row1');
    expect(find.text('تم الحذف.'), findsOneWidget);
  });

  testWidgets('new announcement: inline validation for missing Arabic title and body', (tester) async {
    await pump(tester);
    await tapKey(tester, 'addScheduledPush');
    await tapKey(tester, 'save-push');
    expect(find.text('اكتب عنوان الإشعار بالعربي.'), findsOneWidget);
    expect(repo.lastSave('settings/notifications'), isNull);

    await tester.enterText(find.byKey(const ValueKey('draft-titleAr')), 'قداس عيد الملاك');
    await tapKey(tester, 'save-push');
    expect(find.text('اكتب نص الإشعار بالعربي.'), findsOneWidget, reason: 'rules and sender both require the Arabic body');
    expect(repo.lastSave('settings/notifications'), isNull);
  });

  testWidgets('new announcement saved as a row the rules regex and the sender accept', (tester) async {
    await pump(tester);
    await tapKey(tester, 'addScheduledPush');
    // Default is a set time (tomorrow 9 AM Cairo), shown in words.
    expect(find.byKey(const ValueKey('when-summary')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('draft-titleAr')), 'قداس عيد الملاك');
    await tester.enterText(find.byKey(const ValueKey('draft-bodyAr')), 'القداس غدًا الساعة ٦ صباحًا');
    await tapKey(tester, 'target-app');
    // Preview mirrors the text.
    expect(find.descendant(of: find.byKey(const ValueKey('push-preview')), matching: find.text('قداس عيد الملاك')), findsOneWidget);
    await tapKey(tester, 'save-push');

    final rows = (repo.lastSave('settings/notifications')!['schedule'] as List).cast<String>();
    expect(rows, hasLength(3));
    final added = rows.last;
    expect(_rulesRowRegex().hasMatch(added), isTrue, reason: added);
    expect(added.split(_s)[1], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')), reason: 'no milliseconds');
    final parsed = ScheduledNotification.fromRow(added)!;
    expect(parsed.targets, 'app');
    final c = CairoTime.fromInstant(parsed.atUtc);
    expect((c.hour, c.minute), (9, 0), reason: 'default send time is 9:00 Cairo');
    expect(find.byKey(const ValueKey('push-editor')), findsNothing);
  });

  testWidgets('the old millisecond timestamp is what the rules rejected', (tester) async {
    final re = _rulesRowRegex();
    final base = ['r1', 'T', 'all', 'عنوان', '', 'نص', '', '/', ''];
    String row(String t) => (List.of(base)..[1] = t).join(_s);
    expect(re.hasMatch(row('2026-11-10T10:00:00Z')), isTrue);
    expect(re.hasMatch(row(DateTime.utc(2026, 11, 10, 10).toIso8601String())), isFalse);
    expect(re.hasMatch(ScheduledNotification(id: 'r1', atUtc: DateTime.utc(2026, 11, 10, 10, 0, 0, 123), titleAr: 'ع', bodyAr: 'ن').toRow()), isTrue);
  });

  testWidgets('a scheduled row can be edited; a failed row offers «أعد الإرسال» instead', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('edit-row2')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-row1')), findsNothing);
    expect(find.byKey(const ValueKey('retry-row1')), findsOneWidget);

    await tapKey(tester, 'edit-row2');
    expect(find.text('تعديل الإعلان'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('draft-titleAr')), 'نهضة العذراء — معدّلة');
    await tapKey(tester, 'save-push');
    final rows = (repo.lastSave('settings/notifications')!['schedule'] as List).cast<String>();
    expect(rows, hasLength(2), reason: 'edited in place, not added');
    expect(rows.firstWhere((r) => r.startsWith('row2')).split(_s)[3], 'نهضة العذراء — معدّلة');

    await tapKey(tester, 'retry-row1');
    expect(find.text('إعلان جديد'), findsWidgets);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('draft-titleAr'))).controller!.text, 'عظة الأحد');
  });

  testWidgets('settings: friendly switches save pushTypes, sources and leads; unknown placeholder blocks save', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('save-settings')), findsNothing, reason: 'loading stored settings never marks the form dirty');

    await tapKey(tester, 'offer-katameros_daily');
    await tapKey(tester, 'src-day');
    await tapKey(tester, 'lead-1440');
    await tapKey(tester, 'lead-30');
    expect(find.text('يمكن اختيار ٤ مدد على الأكثر. ألغِ واحدة أولًا.'), findsOneWidget);
    await tapKey(tester, 'save-settings');

    final saved = repo.lastSave('settings/features')!;
    expect(saved['pushTypes'], ['announcements', 'verse_daily', 'katameros_daily', 'reminders']);
    expect(saved['reminderSources'], 'lit,mtg');
    expect(saved['reminderLeads'], [0, 15, 60, 1440]);
    expect(saved['notifyTypes'], isEmpty, reason: 'unchanged templates are not stored');

    await tapKey(tester, 'customize-verse_daily');
    final title = find.descendant(of: find.byKey(const ValueKey('type_verse_daily')), matching: find.byType(TextField)).first;
    await tester.enterText(title, 'آية {bogus}');
    await tester.pumpAndSettle();
    expect(find.textContaining('{bogus}'), findsWidgets);
    final before = repo.saves['settings/features']!.length;
    await tapKey(tester, 'save-settings');
    expect(repo.saves['settings/features']!.length, before, reason: 'invalid template not saved');
  });

  testWidgets('customised templates load without marking dirty and the placeholder chips are named', (tester) async {
    repo = _FakeAdminRepo(seed(notifyTypes: [
      ['seasons', '08:00', '2', 'موسم {season}', '', '', ''].join(_s),
    ]));
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('save-settings')), findsNothing);
    expect(find.textContaining('٨:٠٠'), findsWidgets);
    await tapKey(tester, 'customize-seasons');
    expect(find.text('اسم الموسم'), findsWidgets);
    expect(find.text('{season}'), findsNothing);
  });

  testWidgets('clear log (owner) asks first; editors do not see it', (tester) async {
    await pump(tester);
    await tapKey(tester, 'clear-log');
    expect(find.text('مسح السجل'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('confirm-ok')));
    await tester.pumpAndSettle();
    expect(repo.lastSave('settings/notifications'), {'sentLog': <String>[]});

    await pump(tester, role: 'editor');
    expect(find.byKey(const ValueKey('clear-log')), findsNothing);
  });

  testWidgets('test on this device uses the draft text', (tester) async {
    final env = _FakePushEnv();
    await pump(tester, env: env);
    await tapKey(tester, 'addScheduledPush');
    await tapKey(tester, 'test-device');
    expect(env.shown, 1);
  });

  testWidgets('tab switching between Notifications and App install', (tester) async {
    await pump(tester, size: const Size(800, 1000));
    await tester.tap(find.byIcon(Icons.install_mobile_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-install-doc')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_active_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsAdminSection), findsOneWidget);
  });

  test('season defaults shown in the admin are the ones the sender uses (tool/push_daily.js)', () {
    final js = File('tool/push_daily.js').readAsStringSync();
    final block = js.substring(js.indexOf('DEFAULT_SEASONS_SPEC = {'), js.indexOf('};', js.indexOf('DEFAULT_SEASONS_SPEC = {')));
    String field(String k) => RegExp("$k: '([^']*)'").firstMatch(block)!.group(1)!;
    final d = NotifyTypeSpec.builtInDefaults[NotifyType.seasons]!;
    expect(d.time, field('time'));
    expect(d.titleAr, field('titleAr'));
    expect(d.titleEn, field('titleEn'));
    expect(d.bodyAr, field('bodyAr'));
    expect(d.bodyEn, field('bodyEn'));
    expect(d.defaultLink, field('defaultLink'));
    expect('${d.daysBefore}', RegExp(r'daysBefore: (\d+)').firstMatch(block)!.group(1));
  });
}
