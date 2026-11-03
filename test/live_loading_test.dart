// PR #23: live admin test fixes.
// 1. custom category items stayed on placeholders / 2. cold deep links to
// /section/<slug> and /page/<slug> said "not available" before the data had
// loaded — settleFirst + guardSeeded(fallbackDelay); 3. contact types added
// in the admin did not reach the /contact picker — confirms + re-keyed
// dropdown; 4. admin menu icons (fingerprinted icon fonts) and one selected
// colour.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:fake_async/fake_async.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _tick() => Future<void>.delayed(Duration.zero);

LiveReading<List<int>> _r(List<int> v, {bool cache = false, bool changed = true}) =>
    (value: v, provisional: cache, changed: changed);

SeedData _seed() => SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);

const _cat = CustomCategory(id: 'k9', slug: 'hark-test', nameAr: 'اختبار', nameEn: 'Hark test');
const _entry = CategoryEntry(id: 'e9', categoryId: 'k9', titleAr: 'عنصر', titleEn: 'Test item', descEn: 'Shown at last');
const _page = CustomPage(id: 'p9', slug: 'hark-page', titleAr: 'صفحة', titleEn: 'Hark page', blocks: [
  PageBlock(type: BlockTypes.paragraph, textAr: 'نص', textEn: 'Page body'),
]);

/// Seed data with custom content / contact types fed by test controllers, so
/// a test decides when (and whether) each stream answers.
class _LateRepo extends SeedRepository {
  _LateRepo() : super(_seed());
  final cats = StreamController<List<CustomCategory>>.broadcast();
  final entriesCtl = StreamController<List<CategoryEntry>>.broadcast();
  final pagesCtl = StreamController<List<CustomPage>>.broadcast();
  final contact = StreamController<ContactSettings>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<List<CustomCategory>> categories() => cats.stream;
  @override
  Stream<List<CategoryEntry>> entries() => entriesCtl.stream;
  @override
  Stream<List<CustomPage>> pages() => pagesCtl.stream;
  @override
  Stream<ContactSettings> contactSettings() => contact.stream;
  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async => sent.add(payload);
}

class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

Future<GoRouter> _pumpApp(WidgetTester tester, _LateRepo repo, String path, {Size size = const Size(420, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 3, 12 * 60).toUtc())),
    localeProvider.overrideWith(_English.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  // A cold deep link: the first location is the slug itself.
  router.go(path);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  ));
  await tester.pump();
  await tester.pump();
  return router;
}

/// Minimal in-memory admin backend for the dashboard.
class _Backend extends AdminBackend {
  @override
  String get actor => 'admin@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}
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
}

void main() {
  group('settleFirst: a page only trusts loaded data (bugs 1 & 2)', () {
    late StreamController<LiveReading<List<int>>> src;
    setUp(() => src = StreamController<LiveReading<List<int>>>());
    tearDown(() => src.close());

    test('a cache-only reading is held back; the server reading goes out at once', () {
      fakeAsync((async) {
        final got = <List<int>>[];
        settleFirst(source: src.stream, patience: const Duration(seconds: 8)).listen(got.add);
        async.flushMicrotasks();
        src.add(_r([], cache: true)); // stale empty cache: "not available" must not flash
        async.flushMicrotasks();
        expect(got, isEmpty);
        src.add(_r([1, 2]));
        async.flushMicrotasks();
        expect(got, [
          [1, 2]
        ]);
        // Later: metadata-only events are dropped, real changes forwarded
        // (cache or not: the page already trusts the data).
        src.add(_r([1, 2], changed: false));
        src.add(_r([1, 2, 3], cache: true));
        async.flushMicrotasks();
        expect(got.last, [1, 2, 3]);
        expect(got, hasLength(2));
        async.elapse(const Duration(seconds: 20));
        expect(got, hasLength(2), reason: 'no timeout emission after the data arrived');
      });
    });

    test('no server answer within the patience: the held cache reading is shown', () {
      fakeAsync((async) {
        final got = <List<int>>[];
        settleFirst(source: src.stream, patience: const Duration(seconds: 8)).listen(got.add);
        src.add(_r([4], cache: true));
        async.elapse(const Duration(seconds: 7));
        expect(got, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(got, [
          [4]
        ]);
      });
    });

    test('a listener that never answers still ends the loading state (cache read)', () {
      fakeAsync((async) {
        final got = <List<int>>[];
        var reads = 0;
        settleFirst(
          source: src.stream,
          patience: const Duration(seconds: 8),
          onTimeout: () async {
            reads++;
            return [9];
          },
        ).listen(got.add);
        async.elapse(const Duration(seconds: 8));
        expect(reads, 1);
        expect(got, [
          [9]
        ]);
        // A late server reading still replaces it.
        src.add(_r([9, 10]));
        async.flushMicrotasks();
        expect(got.last, [9, 10]);
      });
    });

    test('a failing cache read leaves the stream open for the live answer; errors pass through', () {
      fakeAsync((async) {
        final got = <List<int>>[];
        final errors = <Object>[];
        settleFirst(
          source: src.stream,
          patience: const Duration(seconds: 1),
          onTimeout: () async => throw StateError('no cache'),
        ).listen(got.add, onError: errors.add);
        async.elapse(const Duration(seconds: 2));
        expect(got, isEmpty);
        src.addError(StateError('permission-denied'));
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        src.add(_r([3]));
        async.flushMicrotasks();
        expect(got, [
          [3]
        ]);
      });
    });

    test('cancelling stops the timer and the source', () {
      fakeAsync((async) {
        var reads = 0;
        final sub = settleFirst(
          source: src.stream,
          patience: const Duration(seconds: 1),
          onTimeout: () async {
            reads++;
            return [1];
          },
        ).listen((_) {});
        async.flushMicrotasks();
        sub.cancel();
        async.elapse(const Duration(seconds: 5));
        expect(reads, 0);
        expect(src.hasListener, isFalse);
      });
    });
  });

  group('guardSeeded: custom content waits, settings docs prove themselves', () {
    test('fallbackDelay: an unanswered seeding check does not emit the empty fallback at once', () {
      fakeAsync((async) {
        final live = StreamController<List<int>>();
        final got = <List<int>>[];
        final marks = <bool>[];
        guardSeeded<List<int>>(
          gate: SeedGate(() async => throw TimeoutException('slow')),
          live: () => live.stream,
          fallback: const [],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: const Duration(seconds: 8),
          onSeed: marks.add,
        ).listen(got.add);
        async.elapse(const Duration(seconds: 3));
        expect(got, isEmpty, reason: 'still loading, never "not available"');
        live.add([5]); // the category arrives
        async.flushMicrotasks();
        expect(got, [
          [5]
        ]);
        async.elapse(const Duration(seconds: 10));
        expect(got, hasLength(1), reason: 'the fallback timer was cancelled');
        expect(marks, [false]);
        live.close();
      });
    });

    test('fallbackDelay: nothing at all → the fallback after the delay', () {
      fakeAsync((async) {
        final live = StreamController<List<int>>();
        final got = <List<int>>[];
        guardSeeded<List<int>>(
          gate: SeedGate(() async => false),
          live: () => live.stream,
          fallback: const [],
          fallbackDelay: const Duration(seconds: 8),
          onSeed: (_) {},
        ).listen(got.add);
        async.elapse(const Duration(seconds: 7));
        expect(got, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(got, [<int>[]]);
        live.close();
      });
    });

    // CodeRabbit (PR #23): the delayed fallback must not overtake a live value
    // whose seeding re-check is still in flight.
    SeedGate slowRecheck(Future<bool> Function() second) {
      var calls = 0;
      return SeedGate(() {
        calls++;
        if (calls == 1) return Future<bool>.error(TimeoutException('cold start'));
        return second();
      });
    }

    test('fallbackDelay: deferred while a live value is being re-checked; the confirmed value wins', () {
      fakeAsync((async) {
        final live = StreamController<List<int>>();
        final got = <List<int>>[];
        guardSeeded<List<int>>(
          gate: slowRecheck(() => Future<bool>.delayed(const Duration(seconds: 10), () => throw TimeoutException('slow'))),
          live: () => live.stream,
          fallback: const [],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: const Duration(seconds: 8),
          onSeed: (_) {},
        ).listen(got.add);
        async.elapse(const Duration(seconds: 7));
        live.add([5]); // arrives at 7 s; its re-check answers at 17 s
        async.elapse(const Duration(seconds: 5)); // 12 s: past the fallback delay
        expect(got, isEmpty, reason: 'the fallback waits for the re-check in flight');
        async.elapse(const Duration(seconds: 6)); // 18 s: re-check failed, confirms([5])
        expect(got, [
          [5]
        ]);
        live.close();
      });
    });

    test('fallbackDelay: a deferred fallback goes out once the re-check rejects the value', () {
      fakeAsync((async) {
        final live = StreamController<List<int>>();
        final got = <List<int>>[];
        guardSeeded<List<int>>(
          // the re-check finds no settings/church: known unseeded, [5] proves nothing
          gate: slowRecheck(() => Future<bool>.delayed(const Duration(seconds: 10), () => false)),
          live: () => live.stream,
          fallback: const [],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: const Duration(seconds: 8),
          onSeed: (_) {},
        ).listen(got.add);
        async.elapse(const Duration(seconds: 7));
        live.add([5]);
        async.elapse(const Duration(seconds: 5));
        expect(got, isEmpty);
        async.elapse(const Duration(seconds: 6));
        expect(got, [<int>[]], reason: 'the fallback fires once, after the re-check');
        async.elapse(const Duration(seconds: 30));
        expect(got, hasLength(1));
        live.close();
      });
    });

    test('custom delays: the guard outlasts settleFirst patience + its cache read', () {
      expect(FirestoreRepository.customFallbackDelay,
          greaterThan(FirestoreRepository.customPatience + FirestoreRepository.customCacheRead));
    });

    test('custom stack: a held cache list reaches the page before "unavailable" (offline, seeding check fails)', () {
      fakeAsync((async) {
        final source = StreamController<LiveReading<List<int>>>();
        final got = <List<int>>[];
        guardSeeded<List<int>>(
          // every check fails (offline); the re-check of the held list takes 3 s
          gate: slowRecheck(() => Future<bool>.delayed(const Duration(seconds: 3), () => throw TimeoutException('offline'))),
          live: () => settleFirst<List<int>>(
            source: source.stream,
            patience: FirestoreRepository.customPatience,
          ),
          fallback: const [],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: FirestoreRepository.customFallbackDelay,
          onSeed: (_) {},
        ).listen(got.add);
        async.flushMicrotasks();
        source.add((value: [5], provisional: true, changed: true)); // cache only
        async.elapse(const Duration(seconds: 30));
        expect(got.first, [5], reason: 'never "unavailable" first');
        expect(got, hasLength(1));
        source.close();
      });
    });

    test('custom stack: the cache read at patience also beats the fallback', () {
      fakeAsync((async) {
        final source = StreamController<LiveReading<List<int>>>();
        final got = <List<int>>[];
        guardSeeded<List<int>>(
          gate: slowRecheck(() => Future<bool>.error(TimeoutException('offline'))),
          live: () => settleFirst<List<int>>(
            source: source.stream, // the listener never answers
            patience: FirestoreRepository.customPatience,
            onTimeout: () => Future<List<int>?>.delayed(
                FirestoreRepository.customCacheRead - const Duration(milliseconds: 500), () => [7]),
          ),
          fallback: const [],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: FirestoreRepository.customFallbackDelay,
          onSeed: (_) {},
        ).listen(got.add);
        async.elapse(const Duration(seconds: 30));
        expect(got, [
          [7]
        ]);
        source.close();
      });
    });

    test('a stored settings doc replaces the code defaults even when the seeding check cannot answer (bug 3)', () async {
      final live = StreamController<ContactSettings>();
      final got = <ContactSettings>[];
      final sub = guardSeeded<ContactSettings>(
        gate: SeedGate(() async => throw TimeoutException('slow')),
        live: () => live.stream,
        fallback: ContactSettings.defaults,
        confirms: (v) => !identical(v, ContactSettings.defaults),
        onSeed: (_) {},
      ).listen(got.add);
      await _tick();
      expect(got.single, same(ContactSettings.defaults));
      live.add(ContactSettings.defaults); // missing doc: proves nothing
      await _tick();
      expect(got, hasLength(1));
      final stored = ContactSettings([
        ...ContactSettings.defaults.categories,
        const ContactCategory(slot: 'cq7w2e9r4t1', labelAr: 'طلب صلاة', labelEn: 'Prayer request', order: 50),
      ]);
      live.add(stored);
      await _tick();
      expect(got.last.categories.map((c) => c.slot), contains('cq7w2e9r4t1'));
      await sub.cancel();
      await live.close();
    });
  });

  group('public pages', () {
    testWidgets('cold link to a custom section: loading (never "not available") until the data arrives, then its items',
        (tester) async {
      final repo = _LateRepo();
      await _pumpApp(tester, repo, '/section/hark-test');
      expect(find.byKey(const Key('categoryUnavailable')), findsNothing);
      repo.cats.add(const [_cat]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('category-hark-test')), findsOneWidget);
      expect(find.byKey(const Key('entry-e9')), findsNothing, reason: 'items still loading');
      repo.entriesCtl.add(const [_entry]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('entry-e9')), findsOneWidget);
      expect(find.text('Shown at last'), findsOneWidget);
      expect(find.byKey(const Key('categoryUnavailable')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cold link to a custom page: loading first, then the page; an unknown slug only after loading',
        (tester) async {
      final repo = _LateRepo();
      final router = await _pumpApp(tester, repo, '/page/hark-page');
      expect(find.byKey(const Key('pageUnavailable')), findsNothing);
      repo.pagesCtl.add(const [_page]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('page-hark-page')), findsOneWidget);
      expect(find.text('Page body'), findsOneWidget);
      router.go('/page/nope');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('pageUnavailable')), findsOneWidget);
    });

    testWidgets('contact form lists the admin-managed types once settings/contact arrives (stable ids, anonymous rules)',
        (tester) async {
      final repo = _LateRepo();
      await _pumpApp(tester, repo, '/contact', size: const Size(420, 4000));
      repo.contact.add(ContactSettings.defaults);
      await tester.pump();
      await tester.pump();
      // Then the admin's list: the four defaults (c1…c4) plus two new types.
      repo.contact.add(ContactSettings([
        ...ContactSettings.defaults.categories,
        const ContactCategory(slot: 'cq7w2e9r4t1', labelAr: 'طلب صلاة', labelEn: 'Prayer request', order: 50),
        const ContactCategory(
            slot: 'cz81mq0w4re', labelAr: 'ملاحظة', labelEn: 'Feedback', kind: ContactKinds.suggestion, anonymous: true, order: 60),
        const ContactCategory(slot: 'cxhidden0001', labelAr: 'مخفي', labelEn: 'Hidden type', on: false, order: 70),
      ]));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('contactCategory')));
      await tester.pumpAndSettle();
      for (final l in ['General inquiry', 'Hall booking', 'Complaint', 'Suggestion', 'Prayer request', 'Feedback']) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      expect(find.text('Hidden type'), findsNothing);
      await tester.tap(find.text('Prayer request').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('anonSwitch')), findsNothing, reason: 'a general type is never anonymous');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mina');
      await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '01012345678');
      await tester.enterText(find.widgetWithText(TextField, 'Your message'), 'Please pray for my family');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(repo.sent.single['category'], 'cq7w2e9r4t1');
      expect(repo.sent.single['kind'], ContactKinds.general);
      // The suggestion-kind type offers anonymous sending.
      await tester.tap(find.byKey(const Key('contactCategory')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feedback').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('anonSwitch')), findsOneWidget);
    });
  });

  group('admin menu (bug 4)', () {
    testWidgets('every entry has an icon; one selected style for icon and text, highlight visible', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AdminDashboard(
            repo: _Backend(), uid: 'u', email: 'admin@example.org', role: AdminRoles.owner, onSignOut: () {}, initial: 'categories'),
      ));
      await tester.pump();
      for (final id in ['categories', 'entries', 'pages', 'contactCats']) {
        final tile = find.byKey(ValueKey('nav-$id'));
        expect(tile, findsOneWidget, reason: id);
        expect(find.descendant(of: tile, matching: find.byType(Icon)), findsOneWidget, reason: id);
      }
      final dests = adminDestinations(AdminRoles.owner);
      expect(dests.map((d) => d.icon).toSet(), hasLength(dests.length), reason: 'each entry has its own icon');
      for (final d in dests) {
        final t = tester.widget<ListTile>(find.byKey(ValueKey('nav-${d.id}')));
        expect(t.iconColor, AppColors.burgundy, reason: d.id);
        expect(t.selectedColor, AppColors.burgundy, reason: d.id);
        expect(t.textColor, AppColors.ink, reason: d.id);
        expect(t.selected, d.id == 'categories');
      }
      // The selected highlight is painted on a Material, not hidden under a
      // coloured Container.
      final selected = find.byKey(const ValueKey('nav-categories'));
      final material = tester.widget<Material>(find.ancestor(of: selected, matching: find.byType(Material)).first);
      expect(material.color, AppColors.parchment);
      final icon = tester.widget<Icon>(find.descendant(of: selected, matching: find.byType(Icon)));
      final iconColor = IconTheme.of(tester.element(find.byWidget(icon))).color;
      expect(iconColor, AppColors.burgundy);
    });

    test('icon fonts get a content-hashed name the FontManifest points at', () {
      final dir = Directory.systemTemp.createTempSync('fp');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/assets/fonts').createSync(recursive: true);
      Directory('${dir.path}/assets/packages/cupertino_icons/assets').createSync(recursive: true);
      File('${dir.path}/assets/fonts/MaterialIcons-Regular.otf').writeAsStringSync('icons-v1');
      File('${dir.path}/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf').writeAsStringSync('cup');
      File('${dir.path}/assets/fonts/Plex.ttf').writeAsStringSync('plex');
      File('${dir.path}/assets/FontManifest.json').writeAsStringSync(jsonEncode([
        {
          'family': 'MaterialIcons',
          'fonts': [
            {'asset': 'fonts/MaterialIcons-Regular.otf'}
          ]
        },
        {
          'family': 'Plex',
          'fonts': [
            {'asset': 'fonts/Plex.ttf'}
          ]
        },
        {
          'family': 'packages/cupertino_icons/CupertinoIcons',
          'fonts': [
            {'asset': 'packages/cupertino_icons/assets/CupertinoIcons.ttf'}
          ]
        },
      ]));
      List<String> assets() => [
            for (final f in jsonDecode(File('${dir.path}/assets/FontManifest.json').readAsStringSync()) as List)
              for (final a in (f as Map)['fonts'] as List) (a as Map)['asset'] as String
          ];
      final r = Process.runSync('python3', ['tool/fingerprint_icon_fonts.py', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final first = assets();
      expect(first[0], matches(RegExp(r'^fonts/MaterialIcons-Regular\.[0-9a-f]{12}\.otf$')));
      expect(first[1], 'fonts/Plex.ttf', reason: 'bundled text fonts keep their names');
      expect(first[2], matches(RegExp(r'^packages/cupertino_icons/assets/CupertinoIcons\.[0-9a-f]{12}\.ttf$')));
      for (final a in first) {
        expect(File('${dir.path}/assets/$a').existsSync(), isTrue, reason: a);
      }
      expect(File('${dir.path}/assets/fonts/MaterialIcons-Regular.otf').existsSync(), isFalse);
      // Idempotent.
      expect(Process.runSync('python3', ['tool/fingerprint_icon_fonts.py', dir.path]).exitCode, 0);
      expect(assets(), first);
    });
  });
}
