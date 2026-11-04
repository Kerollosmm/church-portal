import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/document_lang.dart';
import 'package:church_portal/core/locale_storage.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/pages/assistant_page.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:church_portal/ui/widgets/deferred_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Plan PR 3: PDPL consent, SEO head tags, deferred routes, saved language.

class _MemoryStore extends LanguageStore {
  String? value;
  final writes = <String>[];
  _MemoryStore([this.value]);
  @override
  String? read() => value;
  @override
  void write(String code) {
    value = code;
    writes.add(code);
  }
}

SeedData _seed() {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  return SeedData(raw);
}

Map<String, dynamic> _seedChurch() =>
    (jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>)['settings']['church']
        as Map<String, dynamic>;

Future<(ProviderContainer, _MemoryStore)> _pumpApp(WidgetTester tester, {String? saved, bool? assistantVisible}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = _MemoryStore(saved);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(_seed())),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    languageStoreProvider.overrideWithValue(store),
    if (assistantVisible != null) assistantVisibleProvider.overrideWithValue(assistantVisible),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (context, ref, _) {
      final l = ref.watch(localeProvider);
      return MaterialApp.router(
        locale: l,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      );
    }),
  ));
  await tester.pumpAndSettle();
  return (container, store);
}

/// The English display title (`appName` in l10n.dart, ADR-018).
const kAppNameEn = 'St. Maximus & Domadius and St. Moses the Black Church';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('3.1 PDPL consent (FR-CT-06)', () {
    test('validateContactForm rejects a message without consent', () {
      final v = validateContactForm(
          const ContactFormInput(name: 'Mina', phone: '01012345678', message: 'Hello there', consented: false));
      expect(v.isValid, isFalse);
      expect(v.errors[ContactField.consent], ContactError.consentRequired);
      expect(v.payload, isNull);
    });

    test('consent is not stored: the payload key set is unchanged (firestore.rules)', () {
      final v = validateContactForm(
          const ContactFormInput(name: 'Mina', phone: '01012345678', message: 'Hello there', consented: true));
      expect(v.isValid, isTrue);
      expect(v.payload!.keys.toSet(), {'name', 'phone', 'email', 'message'});
    });

    testWidgets('the form shows the notice and blocks sending until the box is ticked', (tester) async {
      final (container, _) = await _pumpApp(tester);
      container.read(routerProvider).go('/contact');
      await tester.pumpAndSettle();
      final form = find.byType(ContactForm);
      expect(find.descendant(of: form, matching: find.textContaining('خصوصيتك')), findsOneWidget);
      final box = find.descendant(of: form, matching: find.byType(CheckboxListTile));
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      final fields = find.descendant(of: form, matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Mina Adel');
      await tester.enterText(fields.at(1), '01012345678');
      await tester.enterText(fields.at(3), 'When is the next youth meeting?');
      await tester.tap(find.descendant(of: form, matching: find.byIcon(Icons.send_rounded)));
      await tester.pumpAndSettle();
      expect(find.text('برجاء الموافقة على إشعار الخصوصية لإرسال الرسالة'), findsOneWidget);
      // Nothing was attempted: no send status, the visitor's text is kept.
      expect(find.descendant(of: form, matching: find.byIcon(Icons.error_outline)), findsNothing);
      expect(find.text('Mina Adel'), findsOneWidget);
      await tester.tap(box);
      await tester.pump();
      expect(find.text('برجاء الموافقة على إشعار الخصوصية لإرسال الرسالة'), findsNothing);
    });
  });

  group('3.2 SEO head tags', () {
    final html = File('web/index.html').readAsStringSync();

    test('static canonical link', () {
      expect(html, contains('<link rel="canonical" href="https://maximos-domadios-church.web.app/">'));
    });

    test('Church JSON-LD is valid JSON and matches the verified seed facts', () {
      final m = RegExp(r'<script type="application/ld\+json">([\s\S]*?)</script>').firstMatch(html);
      expect(m, isNotNull);
      final ld = jsonDecode(m!.group(1)!) as Map<String, dynamic>;
      final church = _seedChurch();
      expect(ld['@context'], 'https://schema.org');
      expect(ld['@type'], 'Church');
      expect(ld['name'], church['nameAr']);
      expect(ld['alternateName'], [kAppNameEn, church['nameEn']]);
      expect(File('lib/core/l10n.dart').readAsStringSync(), contains(kAppNameEn));
      expect((ld['address'] as Map)['streetAddress'], startsWith('آخر شارع 45، العصافرة قبلي'));
      expect(church['addressAr'], startsWith((ld['address'] as Map)['streetAddress'] as String));
      expect(ld['url'], 'https://maximos-domadios-church.web.app/');
      expect(ld['telephone'], '+2035368888');
      expect((ld['geo'] as Map)['latitude'], church['lat']);
      expect((ld['geo'] as Map)['longitude'], church['lng']);
      expect((ld['address'] as Map)['@type'], 'PostalAddress');
      expect((ld['address'] as Map)['addressCountry'], 'EG');
      expect(ld['sameAs'], unorderedEquals([church['facebook'], church['youtube'], church['instagram'], church['whatsappChannel']]));
    });
  });

  group('3.3 deferred routes', () {
    testWidgets('DeferredLoader: spinner, then the page', (tester) async {
      final done = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeferredLoader(loadLibrary: () => done.future, builder: (_) => const Text('loaded'))),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('loaded'), findsNothing);
      done.complete();
      await tester.pumpAndSettle();
      expect(find.text('loaded'), findsOneWidget);
    });

    testWidgets('DeferredLoader: a failed chunk download offers a retry', (tester) async {
      var calls = 0;
      Future<void> load() async {
        calls++;
        if (calls == 1) throw Exception('chunk failed');
      }

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeferredLoader(loadLibrary: load, builder: (_) => const Text('loaded'))),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      // While the retry is in flight: spinner, no second Retry button.
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('loaded'), findsOneWidget);
    });

    // One test: on the Dart VM, loadLibrary() futures are cached per isolate,
    // so a chunk first requested under another test's fake clock never
    // completes in a later test (not a production concern on the web).
    testWidgets('/admin and /ask (assistant on) open through their deferred chunks', (tester) async {
      final (container, _) = await _pumpApp(tester, assistantVisible: true);
      final router = container.read(routerProvider);
      router.go('/admin');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/admin');
      expect(find.byType(DeferredLoader), findsOneWidget);
      expect(find.byType(AdminPage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      router.go('/ask');
      // The chat page keeps a ticker running (focused field), so pumpAndSettle
      // never settles: pump until the chunk has loaded.
      for (var i = 0; i < 50 && find.byType(AssistantPage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1)); // /admin's page transition ends
      expect(tester.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/ask');
      expect(find.byType(DeferredLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AssistantPage), findsOneWidget);
    });

    testWidgets('/ask with the assistant off says so without fetching the chunk', (tester) async {
      final (container, _) = await _pumpApp(tester, assistantVisible: false);
      container.read(routerProvider).go('/ask');
      await tester.pumpAndSettle();
      expect(find.byType(DeferredLoader), findsNothing);
      expect(find.byType(AssistantPage), findsNothing);
      expect(find.text('المساعد غير متاح حاليًا.'), findsOneWidget);
    });
  });

  group('3.3 saved language', () {
    test('startup precedence: ?lang= → saved choice → Arabic', () {
      Locale init(String url, String? saved) => LocaleNotifier.initialLocale(Uri.parse(url), saved);
      expect(init('https://x/clinics?lang=en', 'ar'), const Locale('en'));
      expect(init('https://x/?lang=ar', 'en'), const Locale('ar'));
      expect(init('https://x/', 'en'), const Locale('en'));
      expect(init('https://x/', 'ar'), const Locale('ar'));
      expect(init('https://x/', null), const Locale('ar'));
      expect(init('https://x/?lang=fr', null), const Locale('ar'));
    });

    test('the platform store is a no-op off the web', () {
      const store = PlatformLanguageStore();
      store.write('en');
      expect(store.read(), isNull);
      expect(languageStorageKey, 'church_portal_lang');
    });

    testWidgets('a saved English choice starts in English and adds ?lang=en', (tester) async {
      final (container, store) = await _pumpApp(tester, saved: 'en');
      expect(container.read(localeProvider), const Locale('en'));
      expect(container.read(routerProvider).routerDelegate.currentConfiguration.uri.queryParameters['lang'], 'en');
      expect(store.writes, isEmpty);
    });

    testWidgets('toggle() and set() persist the choice; URL sync does not', (tester) async {
      final (container, store) = await _pumpApp(tester);
      final n = container.read(localeProvider.notifier);
      n.toggle();
      await tester.pumpAndSettle();
      expect(store.writes, ['en']);
      n.set(const Locale('ar'));
      await tester.pumpAndSettle();
      expect(store.writes, ['en', 'ar']);
      n.syncFromUrl(const Locale('en'));
      await tester.pumpAndSettle();
      expect(store.writes, ['en', 'ar']);
    });
  });

  group('PR #10: per-route canonical / noindex, URL fragments, sitemap', () {
    test('canonicalUrlForPath', () {
      expect(canonicalUrlForPath('/'), 'https://maximos-domadios-church.web.app/');
      expect(canonicalUrlForPath(''), 'https://maximos-domadios-church.web.app/');
      expect(canonicalUrlForPath('/mass-schedule'), 'https://maximos-domadios-church.web.app/mass-schedule');
      expect(canonicalUrlForPath('/about/?lang=en#altars'), 'https://maximos-domadios-church.web.app/about');
    });

    test('routeHeadSpec never combines noindex with a canonical URL', () {
      final about = routeHeadSpec(path: '/about', indexable: true);
      expect(about.canonicalUrl, 'https://maximos-domadios-church.web.app/about');
      expect(about.noIndex, isFalse);
      final admin = routeHeadSpec(path: '/admin', indexable: false);
      expect(admin.canonicalUrl, isNull);
      expect(admin.noIndex, isTrue);
    });

    testWidgets('navigating updates the head spec: indexable pages, disabled section, 404, back', (tester) async {
      final applied = <DocumentHeadSpec>[];
      debugOnRouteMeta = applied.add;
      addTearDown(() => debugOnRouteMeta = null);
      final (container, _) = await _pumpApp(tester);
      final router = container.read(routerProvider);
      expect(applied.last.canonicalUrl, 'https://maximos-domadios-church.web.app/');
      expect(applied.last.noIndex, isFalse);

      router.go('/about');
      await tester.pumpAndSettle();
      expect(applied.last.canonicalUrl, 'https://maximos-domadios-church.web.app/about');
      expect(applied.last.noIndex, isFalse);

      router.go('/clinics'); // clinics: false in the seed
      await tester.pumpAndSettle();
      expect(applied.last.noIndex, isTrue);
      expect(applied.last.canonicalUrl, isNull);

      router.go('/unknown-404');
      await tester.pumpAndSettle();
      expect(applied.last.noIndex, isTrue);
      expect(applied.last.canonicalUrl, isNull);

      router.go('/mass-schedule');
      await tester.pumpAndSettle();
      expect(applied.last.canonicalUrl, 'https://maximos-domadios-church.web.app/mass-schedule');
      expect(applied.last.noIndex, isFalse);
    });

    test('resolveLangSync keeps the URL fragment', () {
      expect(resolveLangSync(Uri.parse('/about?lang=ar#altars'), english: true).redirect, '/about#altars');
      expect(resolveLangSync(Uri.parse('/about#altars'), english: true).redirect, '/about?lang=en#altars');
    });

    test('sitemap.xml lists only active public routes', () {
      // Commented-out entries (<!-- ... -->) are not listed.
      final xml = File('web/sitemap.xml').readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      final locs = RegExp(r'^\s*<url><loc>([^<]+)</loc></url>', multiLine: true)
          .allMatches(xml)
          .map((m) => m.group(1)!)
          .toList();
      final sections = (jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>)['settings']
          ['features']['sections'] as Map<String, dynamic>;
      expect(sections['clinics'], isFalse);
      expect(locs, isNot(contains('https://maximos-domadios-church.web.app/clinics')));
      expect(locs, isNot(contains('https://maximos-domadios-church.web.app/admin')));
      expect(locs, isNot(contains('https://maximos-domadios-church.web.app/ask')));
      expect(locs, contains('https://maximos-domadios-church.web.app/'));
      expect(locs, contains('https://maximos-domadios-church.web.app/mass-schedule'));
      expect(locs, contains('https://maximos-domadios-church.web.app/about'));
      expect(locs, contains('https://maximos-domadios-church.web.app/contact'));
    });
  });

  group('PageSpeed & agentic headers, rewrites and llms.txt', () {
    test('firebase.json headers cache static assets & canvaskit with 1-year immutable and set COOP', () {
      final json = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
      final hosting = (json['hosting'] as List).first as Map<String, dynamic>;
      final headers = hosting['headers'] as List;

      // Global COOP header
      final global = headers.firstWhere((h) => h['source'] == '**') as Map<String, dynamic>;
      final globalList = global['headers'] as List;
      expect(
        globalList.any((h) => h['key'] == 'Cross-Origin-Opener-Policy' && h['value'] == 'same-origin-allow-popups'),
        isTrue,
        reason: 'COOP allows popup auth and satisfies best practices',
      );

      // Static assets (images, fonts, mp4 videos)
      final staticAssets = headers.firstWhere(
        (h) => (h['source'] as String).contains('mp4') && (h['source'] as String).contains('png'),
      ) as Map<String, dynamic>;
      final staticCache = (staticAssets['headers'] as List)
          .firstWhere((h) => h['key'] == 'Cache-Control')['value'] as String;
      expect(staticCache, 'public, max-age=31536000, immutable');

      // CanvasKit
      final canvaskit = headers.firstWhere((h) => h['source'] == 'canvaskit/**') as Map<String, dynamic>;
      final canvaskitCache = (canvaskit['headers'] as List)
          .firstWhere((h) => h['key'] == 'Cache-Control')['value'] as String;
      expect(canvaskitCache, 'public, max-age=31536000, immutable');

      // Rewrites exclude .map and .well-known/**
      final rewrites = hosting['rewrites'] as List;
      final spaRewrite = rewrites.firstWhere((r) => r['destination'] == '/index.html') as Map<String, dynamic>;
      expect(spaRewrite['source'], contains('*.map'));
      expect(spaRewrite['source'], contains('.well-known/**'));
    });

    test('web/llms.txt starts with #, lists core verified links, and contains no unverified content', () {
      final text = File('web/llms.txt').readAsStringSync();
      expect(text, startsWith('# كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود — العصافرة قبلي، الإسكندرية'));
      expect(text, contains('https://maximos-domadios-church.web.app/'));
      expect(text, contains('https://maximos-domadios-church.web.app/mass-schedule'));
      expect(text, contains('https://maximos-domadios-church.web.app/church-education'));
      expect(text, contains('https://maximos-domadios-church.web.app/church-activities'));
      expect(text, contains('https://maximos-domadios-church.web.app/public-services'));
      expect(text, contains('https://maximos-domadios-church.web.app/about'));
      expect(text, contains('https://maximos-domadios-church.web.app/contact'));
      // No unverified content
      expect(text, isNot(contains('sample')));
      expect(text, isNot(contains('fake')));
    });
  });
}
