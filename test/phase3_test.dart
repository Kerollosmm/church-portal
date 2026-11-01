import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/locale_storage.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
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

Future<(ProviderContainer, _MemoryStore)> _pumpApp(WidgetTester tester, {String? saved}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = _MemoryStore(saved);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(_seed())),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    languageStoreProvider.overrideWithValue(store),
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
      expect(ld['alternateName'], contains(church['nameEn']));
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
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('loaded'), findsOneWidget);
    });

    testWidgets('/admin and /ask still open through their deferred chunks', (tester) async {
      final (container, _) = await _pumpApp(tester);
      final router = container.read(routerProvider);
      router.go('/admin');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/admin');
      expect(find.byType(DeferredLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      router.go('/ask');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/ask');
      expect(find.byType(CircularProgressIndicator), findsNothing);
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
}
