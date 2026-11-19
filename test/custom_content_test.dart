// ADR-027 / ADR-028: admin-defined categories and their items, custom pages
// (blocks, donation info, link targets), contact categories (bookings,
// anonymous complaints / suggestions) and the admin inbox.

import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:church_portal/core/l10n.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart' show CustomizablePages, FeatureSettings, Sections;
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/contact_admin.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/pages/category_page.dart' show CustomPageCard;
import 'package:church_portal/ui/pages/custom_page.dart' show PageBlockView;
import 'package:church_portal/ui/widgets/cards.dart' show NextMassCard;
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/feature_gate.dart';
import 'package:church_portal/ui/widgets/golden.dart' show Reveal;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

SeedData _seed([Map<String, bool> sections = const {}]) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = raw['settings']['features'] as Map;
  f['sections'] = {...(f['sections'] as Map), ...sections};
  return SeedData(raw);
}

const _cats = [
  CustomCategory(id: 'k1', slug: 'youth-trips', nameAr: 'رحلات الشباب', nameEn: 'Youth trips', introEn: 'Trips intro', order: 20),
  CustomCategory(id: 'k2', slug: 'hidden-cat', nameAr: 'مخفي', nameEn: 'Hidden', visible: false),
  CustomCategory(id: 'k3', slug: 'library', nameAr: 'المكتبة', nameEn: 'Library', order: 10, showInNav: false),
];
const _entries = [
  CategoryEntry(id: 'e1', categoryId: 'k1', titleAr: 'رحلة', titleEn: 'Alexandria trip', descEn: 'A day by the sea',
      contactPhone: '01012345678', externalUrl: '/page/donate', externalLabelEn: 'Register'),
  CategoryEntry(id: 'e2', categoryId: 'k1', titleAr: 'مخفية', titleEn: 'Hidden trip', visible: false),
  CategoryEntry(id: 'e3', categoryId: 'gone', titleAr: 'يتيمة', titleEn: 'Orphan item'),
];
const _pages = [
  CustomPage(id: 'p1', slug: 'donate', titleAr: 'التبرع لمبنى الخدمات', titleEn: 'Building donations', subtitleEn: 'Help us build',
      placement: PagePlacements.nav, showInNav: true, blocks: [
        PageBlock(type: BlockTypes.heading, textAr: 'المبنى الجديد', textEn: 'The new building'),
        PageBlock(type: BlockTypes.paragraph, textAr: 'نص', textEn: 'Every gift helps.'),
        PageBlock(type: BlockTypes.button, textEn: 'Contact us', url: '/contact'),
        PageBlock(type: BlockTypes.link, textEn: 'Diocese site', url: 'https://example.org'),
        PageBlock(type: BlockTypes.donation, account: 'CIB 1000200030004', instapay: 'church@instapay', wallet: '01012345678',
            textEn: 'Write "building" in the note.'),
        PageBlock(type: BlockTypes.button, textEn: 'No link'), // empty: not rendered
      ]),
  CustomPage(id: 'p2', slug: 'draft', titleAr: 'مسودة', visible: false),
  CustomPage(
      id: 'p3',
      slug: 'trips-faq',
      titleAr: 'تفاصيل الرحلات',
      titleEn: 'Trips guide',
      subtitleEn: 'Rules & fees',
      placement: PagePlacements.section,
      categoryId: 'k1',
      featured: true),
];

/// Seed data plus custom categories / pages; records contact submissions.
class _Repo extends SeedRepository {
  _Repo([Map<String, bool> sections = const {}]) : super(_seed(sections));
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<List<CustomCategory>> categories() => Stream.value(_cats);
  @override
  Stream<List<CategoryEntry>> entries() => Stream.value(_entries);
  @override
  Stream<List<CustomPage>> pages() => Stream.value(_pages);
  @override
  Stream<ContactSettings> contactSettings() => Stream.value(ContactSettings.defaults);
  @override
  Future<void> submitContact(Map<String, dynamic> payload, {required String lang}) async => sent.add(payload);
}

class _English extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

class _Arabic extends LocaleNotifier {
  @override
  Locale build() => const Locale('ar');
}

Future<(GoRouter, _Repo)> _pump(WidgetTester tester, String path,
    {Size size = const Size(420, 3000), _Repo? repo, bool settle = true, Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Repo();
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(r),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    localeProvider.overrideWith(locale.languageCode == 'en' ? _English.new : _Arabic.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  router.go(path);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (router, r);
}

/// In-memory admin backend.
class _Backend extends AdminBackend {
  _Backend({Map<String, List<AdminDoc>> lists = const {}, Map<String, Map<String, dynamic>> docs = const {}})
      : _lists = {...lists},
        _docs = {...docs};
  final Map<String, List<AdminDoc>> _lists;
  final Map<String, Map<String, dynamic>> _docs;
  final saves = <(String, String?, Map<String, dynamic>)>[];
  final updates = <(String, String, Map<String, dynamic>)>[];
  final deletes = <(String, String)>[];
  final watchedDocs = <String>[];
  final savedDocs = <String, Map<String, dynamic>>{};

  @override
  String get actor => 'admin@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(_lists[collection] ?? const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) {
    watchedDocs.add(path);
    return Stream.value(_docs[path] == null ? null : AdminDoc(path.split('/').last, _docs[path]!));
  }
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    saves.add((collection, id, data));
    return id ?? 'new-${saves.length}';
  }
  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async => savedDocs[path] = data;
  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async => updates.add((collection, id, data));
  @override
  Future<void> delete(String collection, String id) async => deletes.add((collection, id));
  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}
  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}
  @override
  Future<void> removeAdmin(String uid) async {}
}

Widget _admin(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

void main() {
  group('domain: categories, items, pages (ADR-027)', () {
    test('slugs', () {
      for (final ok in ['a', 'youth-trips', 'new-building-2027', 'x1']) {
        expect(isValidSlug(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'Youth', 'a b', '-a', 'a-', 'a--b', 'رحلات', 'a_b', 'a' * 61]) {
        expect(isValidSlug(bad), isFalse, reason: bad);
      }
      expect(categoryPath('x'), '/section/x');
      expect(customPagePath('x'), '/page/x');
    });

    test('public categories: visible, usable, sorted, first slug wins', () {
      final list = publicCategories([
        ..._cats,
        const CustomCategory(id: 'k4', slug: 'library', nameAr: 'نسخة', order: 30),
        const CustomCategory(id: 'k5', slug: 'Bad Slug', nameAr: 'x'),
        const CustomCategory(id: 'k6', slug: 'no-name', nameAr: ' '),
      ]);
      expect(list.map((c) => c.id), ['k3', 'k1']);
    });

    test('items of a category; deleting a category hides (never deletes) its visible items', () {
      expect(entriesOf('k1', _entries).map((e) => e.id), ['e1']);
      expect(entriesOf('gone', _entries).map((e) => e.id), ['e3']);
      expect(
          entryIdsToHide('k1', [
            (id: 'a', data: {'categoryId': 'k1'}),
            (id: 'b', data: {'categoryId': 'k1', 'visible': false}),
            (id: 'c', data: {'categoryId': 'k2'}),
            (id: 'd', data: {'categoryId': 'k1', 'visible': true}),
          ]),
          ['a', 'd']);
    });

    test('page blocks: tolerant reader, unknown types dropped, empty blocks detected', () {
      const enc = PageBlock(type: BlockTypes.link, textEn: 'L', url: '/contact');
      expect(PageBlock.fromStored(enc.encode())!.toMap(), enc.toMap());
      expect(PageBlock.fromStored('paragraph\u001fonly two'), isNull);
      final p = CustomPage.fromMap('p', {
        'slug': 'x',
        'titleAr': 'ت',
        'blocks': [
          {'type': 'paragraph', 'textAr': 'نص'},
          enc.encode(),
          {'type': 'video', 'url': 'https://x.org'},
          'junk',
          {'type': 'donation', 'wallet': '010'},
        ],
      });
      expect(p.blocks.map((b) => b.type), ['paragraph', 'link', 'donation']);
      expect(p.showInNav, isFalse, reason: 'pages are off the menu by default');
      expect(const PageBlock(type: BlockTypes.button, textEn: 'x').isEmpty, isTrue);
      expect(const PageBlock(type: BlockTypes.image, url: 'https://x.org/a.jpg').isEmpty, isFalse);
      expect(const PageBlock(type: BlockTypes.donation).isEmpty, isTrue);
      expect(const PageBlock(type: BlockTypes.heading, textEn: 'H').toMap().keys,
          ['type', 'textAr', 'textEn', 'url', 'account', 'instapay', 'wallet']);
      expect(publicPages(_pages).map((p) => p.slug), ['donate', 'trips-faq']);
    });

    test('link targets: custom pages, then categories, then built-in routes', () {
      final t = linkTargets(
        pages: [(slug: 'donate', titleAr: 'تبرع', titleEn: 'Donate'), (slug: 'Bad', titleAr: '', titleEn: '')],
        categories: [(slug: 'youth-trips', titleAr: 'رحلات', titleEn: 'Trips')],
      );
      expect(t.first.path, '/page/donate');
      expect(t[1].path, '/section/youth-trips');
      expect(t.map((x) => x.path), containsAll(['/', '/mass-schedule', '/contact']));
      expect(t.where((x) => x.path.contains('Bad')), isEmpty);
    });

    test('admin validators: slug, image blocks, blocks saved on their own write', () {
      final slugField = collectionById('pages')!.fields.firstWhere((f) => f.key == 'slug');
      expect(validateFieldValue(slugField, 'New Building'), 'invalidSlug');
      expect(validateFieldValue(slugField, 'new-building'), isNull);
      expect(validateFieldValue(slugField, ''), 'required');
      expect(
          validateDocument(collectionById('pages'), {
            'blocks': [const PageBlock(type: BlockTypes.image, url: '/x.jpg').encode()]
          }),
          'blockImageUrl');
      expect(
          validateDocument(collectionById('pages'), {
            'blocks': [
              {'type': 'image', 'url': 'https://x.org/a.jpg'},
              {'type': 'button', 'url': '/contact'}
            ]
          }),
          isNull);
      expect(splitSavePayload({'titleAr': 'x', 'blocks': [{}]}), [
        {'titleAr': 'x'},
        {
          'blocks': [{}]
        },
      ]);
      expect(collectionById('alerts')!.fields.firstWhere((f) => f.key == 'link').linkPicker, isTrue);
    });
  });

  group('domain: contact categories (ADR-028)', () {
    final d = ContactSettings.defaults;
    test('code defaults mirror firestore.rules defaultContactCats()', () {
      expect(d.categories.map((c) => (c.slot, c.kind, c.allowsAnonymous)), [
        ('c1', 'general', false),
        ('c2', 'booking', false),
        ('c3', 'complaint', true),
        ('c4', 'suggestion', true),
      ]);
      expect(d.bySlot('c2')!.subtypes.map((s) => s.key), ['wedding', 'condolence']);
      expect(d.bySlot('c2')!.subtypes.map((s) => s.labelAr), ['فرح', 'عزاء']);
      expect(ContactSettings.fromMap(null), same(ContactSettings.defaults));
      // New categories get a fresh random id, never a legacy slot (PR #19).
      expect(d.newId(), matches(RegExp(r'^c[0-9a-z]{10}$')));
    });

    test('round trip, sorting, hidden ones and anonymous only for complaints / suggestions', () {
      final s = ContactSettings.fromMap({
        'categories': {
          'c3': 'complaint\u001f1\u001f1\u001f7\u001fشكوى\u001fComplaint\u001f',
          'c4': 'broken',
          'c2': {'labelAr': 'ب', 'kind': 'general', 'anon': true, 'order': 5, 'on': false},
          'c1': {'labelAr': 'أ', 'kind': 'complaint', 'anon': true, 'order': 9, 'subtypes': ['ok|x|', 'BAD|x|', 5]},
          'c99': {'labelAr': 'x'},
        }
      });
      // Any well-formed id is a category since PR #19 (stable random ids).
      expect(s.categories.map((c) => c.slot), ['c99', 'c2', 'c3', 'c1']);
      expect(s.visible.map((c) => c.slot), ['c99', 'c3', 'c1']);
      expect(s.bySlot('c3')!.allowsAnonymous, isTrue);
      expect(s.bySlot('c2')!.allowsAnonymous, isFalse, reason: 'general never anonymous');
      expect(s.bySlot('c2')!.encode(), 'general\u001f0\u001f0\u001f5\u001fب\u001f\u001f');
      expect(s.bySlot('c1')!.subtypes.map((x) => x.key), ['ok']);
      expect(ContactSettings.fromMap(s.toMap()).toMap(), s.toMap());
      expect(newSubtypeKey(['type1', 'type2']), 'type3');
    });

    test('inbox boxes and open status', () {
      expect(inboxBoxOf({'category': 'c3', 'anonymous': true}), 'anonymous');
      expect(inboxBoxOf({'category': 'c2'}), 'c2');
      expect(inboxBoxOf({'name': 'legacy'}), 'c1');
      expect(messageIsOpen({'status': 'new'}), isTrue);
      expect(messageIsOpen({}), isTrue);
      for (final s in ['handled', 'contacted', 'confirmed', 'declined']) {
        expect(messageIsOpen({'status': s}), isFalse);
      }
    });

    test('anonymous payload stores no identity at all', () {
      final v = validateContactForm(ContactFormInput(
          name: 'Mina', phone: '01012345678', email: 'm@x.org', message: 'A complaint', category: d.bySlot('c3'), anonymous: true));
      expect(v.isValid, isTrue);
      expect(v.payload, {'category': 'c3', 'kind': 'complaint', 'anonymous': true, 'message': 'A complaint'});
      // Anonymous is ignored where the category does not allow it.
      final g = validateContactForm(ContactFormInput(name: '', message: 'Hello there', category: d.bySlot('c1'), anonymous: true));
      expect(g.errors.keys, containsAll([ContactField.name, ContactField.contact]));
    });

    test('bookings need a phone, an occasion and a date from today', () {
      final c2 = d.bySlot('c2');
      var v = validateContactForm(ContactFormInput(
          name: 'Mina', email: 'm@x.org', message: 'Hall please', category: c2, preferredDate: '2026-10-01', today: '2026-11-01'));
      expect(v.errors[ContactField.phone], ContactError.phoneRequired);
      expect(v.errors[ContactField.subtype], ContactError.subtypeRequired);
      expect(v.errors[ContactField.date], ContactError.dateInvalid);
      v = validateContactForm(ContactFormInput(
          name: 'Mina',
          phone: '01012345678',
          message: 'Hall please',
          category: c2,
          bookingType: 'condolence',
          preferredDate: '2026-11-01',
          today: '2026-11-01'));
      expect(v.payload, {
        'category': 'c2',
        'kind': 'booking',
        'name': 'Mina',
        'phone': '01012345678',
        'email': '',
        'message': 'Hall please',
        'bookingType': 'condolence',
        'preferredDate': '2026-11-01',
      });
      expect(isValidIsoDate('2027-02-30'), isFalse);
      // Legacy callers (no category) keep the original payload shape.
      expect(validateContactForm(const ContactFormInput(name: 'Mina', phone: '01012345678', message: 'Hello there')).payload,
          {'name': 'Mina', 'phone': '01012345678', 'email': '', 'message': 'Hello there'});
    });
  });

  group('public pages', () {
    testWidgets('a category page lists its visible items with cards; hidden / unknown are unavailable', (tester) async {
      final (router, _) = await _pump(tester, '/section/youth-trips');
      expect(find.byKey(const Key('category-youth-trips')), findsOneWidget);
      expect(find.text('Youth trips'), findsWidgets);
      expect(find.text('Trips intro'), findsOneWidget);
      expect(find.byKey(const Key('entry-e1')), findsOneWidget);
      expect(find.text('A day by the sea'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.text('Hidden trip'), findsNothing);
      expect(tester.takeException(), isNull);
      for (final p in ['/section/hidden-cat', '/section/nope']) {
        router.go(p);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('categoryUnavailable')), findsOneWidget, reason: p);
      }
      // An empty category says so.
      router.go('/section/library');
      await tester.pumpAndSettle();
      expect(find.text('Nothing in this section yet'), findsOneWidget);
    });

    testWidgets('a custom page renders its blocks and donation info (display only)', (tester) async {
      final (router, _) = await _pump(tester, '/page/donate');
      expect(find.byKey(const Key('page-donate')), findsOneWidget);
      expect(find.text('Building donations'), findsWidgets);
      expect(find.text('The new building'), findsOneWidget);
      expect(find.text('Every gift helps.'), findsOneWidget);
      expect(find.byKey(const Key('donationBlock')), findsOneWidget);
      expect(find.text('CIB 1000200030004'), findsOneWidget);
      expect(find.text('church@instapay'), findsOneWidget);
      expect(find.text('For information only: no payment is made on this site.'), findsOneWidget);
      expect(find.text('No link'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Contact us'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/contact');
      router.go('/page/draft');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pageUnavailable')), findsOneWidget);
    });

    testWidgets('menu: categories with showInNav under services, pages switched into the menu', (tester) async {
      await _pump(tester, '/');
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Youth trips'), findsOneWidget);
      expect(find.text('Library'), findsNothing, reason: 'showInNav off');
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Building donations'), findsOneWidget);
    });

    testWidgets('menu hides empty category with showInNav: true, while direct route renders EmptyState', (tester) async {
      const emptyCat = CustomCategory(
        id: 'k-empty',
        slug: 'empty-cat',
        nameAr: 'قسم فارغ',
        nameEn: 'Empty Section',
        order: 5,
        showInNav: true,
      );
      final repo = _ControlledPagesRepo(
        Stream.value(_pages),
        cats: [..._cats, emptyCat],
        entries: _entries,
      );
      final (router, _) = await _pump(tester, '/', repo: repo);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Youth trips'), findsOneWidget);
      expect(find.text('Empty Section'), findsNothing, reason: 'empty category is hidden from menu');

      router.go('/section/empty-cat');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-empty-cat')), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nothing in this section yet'), findsOneWidget);
    });

    testWidgets('section switches: custom sections / pages off → not available and out of the menu', (tester) async {
      final (router, _) = await _pump(tester, '/section/youth-trips',
          repo: _Repo({Sections.customSections: false, Sections.customPages: false}));
      expect(find.byType(SectionUnavailable), findsOneWidget);
      router.go('/page/donate');
      await tester.pumpAndSettle();
      expect(find.byType(SectionUnavailable), findsOneWidget);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Youth trips'), findsNothing);
      expect(find.text('Building donations'), findsNothing);
    });

    testWidgets('contact form: choose a type; anonymous hides identity fields and says so', (tester) async {
      final (_, repo) = await _pump(tester, '/contact', size: const Size(420, 4000));
      expect(find.byKey(const Key('contactCategory')), findsOneWidget);
      expect(find.byKey(const Key('anonSwitch')), findsNothing, reason: 'general inquiry');
      await tester.tap(find.byKey(const Key('contactCategory')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complaint').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('anonSwitch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('anonHint')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsNothing);
      expect(find.widgetWithText(TextField, 'Email (optional)'), findsNothing);
      expect(find.textContaining('this message is sent without any personal details'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Your message'), 'The hall was cold');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(repo.sent.single, {'category': 'c3', 'kind': 'complaint', 'anonymous': true, 'message': 'The hall was cold'});
    });

    testWidgets('contact form: a hall booking asks for the occasion, a date and a mobile', (tester) async {
      final (_, repo) = await _pump(tester, '/contact', size: const Size(420, 4000));
      await tester.tap(find.byKey(const Key('contactCategory')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hall booking').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('preferredDate')), findsOneWidget);
      expect(find.byKey(const ValueKey('subtype-wedding')), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mina');
      await tester.enterText(find.widgetWithText(TextField, 'Your message'), 'We would like the hall');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(repo.sent, isEmpty);
      expect(find.text('Choose the occasion'), findsOneWidget);
      expect(find.text('A mobile number is required for a booking request'), findsOneWidget);
      expect(find.text('Choose a valid date from today on'), findsOneWidget);
    });
  });

  group('admin', () {
    final msgs = [
      AdminDoc('m1', {'name': 'Legacy Sender', 'message': 'old style', 'status': 'new', 'phone': '01012345678'}),
      AdminDoc('m2', {
        'category': 'c2', 'kind': 'booking', 'name': 'Bride Family', 'message': 'Hall', 'status': 'new', //
        'phone': '01012345678', 'bookingType': 'wedding', 'preferredDate': '2027-02-14',
      }),
      AdminDoc('m3', {'category': 'c3', 'kind': 'complaint', 'anonymous': true, 'message': 'Anon complaint', 'status': 'new'}),
      AdminDoc('m4', {'category': 'c9', 'kind': 'general', 'name': 'Old Type', 'message': 'gone type', 'status': 'handled'}),
    ];

    testWidgets('inbox: a box per category, the anonymous box, booking status and notes', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = _Backend(lists: {'contact_messages': msgs});
      await tester.pumpWidget(_admin(MessagesScreen(repo: b)));
      await tester.pumpAndSettle();
      for (final k in ['all', 'c1', 'c2', 'c3', 'c4', 'anonymous', 'other']) {
        expect(find.byKey(ValueKey('box-$k')), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const ValueKey('box-anonymous')));
      await tester.pumpAndSettle();
      expect(find.text('Anonymous sender'), findsOneWidget);
      expect(find.text('Legacy Sender'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('box-c1')));
      await tester.pumpAndSettle();
      expect(find.text('Legacy Sender'), findsOneWidget, reason: 'messages without a category are general inquiries');
      await tester.tap(find.byKey(const ValueKey('box-c2')));
      await tester.pumpAndSettle();
      expect(find.text('Wedding'), findsOneWidget);
      expect(find.text('📅 2027-02-14'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bookingStatus-m2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmed').last);
      await tester.pumpAndSettle();
      expect(b.updates.single.$2, 'm2');
      expect(b.updates.single.$3, {'status': 'confirmed'});
      await tester.tap(find.byKey(const ValueKey('notes-m2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('adminNotesField')), 'Called back');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(b.updates.last.$3, {'adminNotes': 'Called back'});
      await tester.tap(find.byKey(const ValueKey('box-other')));
      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      expect(find.text('Old Type'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('contact types: defaults shown, edits saved to settings/contact', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = _Backend();
      await tester.pumpWidget(_admin(ContactCategoriesScreen(repo: b)));
      await tester.pumpAndSettle();
      for (final s in ['c1', 'c2', 'c3', 'c4']) {
        expect(find.byKey(ValueKey('contactCat-$s')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('catAnon-c3')), findsOneWidget);
      expect(find.byKey(const ValueKey('catAnon-c1')), findsNothing);
      // Delete "Suggestion" (c4) first, then add a type: it gets a fresh
      // random id, never c4 again (PR #19), so c4's old messages are not
      // re-labelled.
      await tester.tap(find.byKey(const ValueKey('removeCat-c4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addContactCat')));
      await tester.pumpAndSettle();
      final labelKeys = find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && RegExp(r'^catLabelAr-c[0-9a-z]{10}-1$').hasMatch(k.value);
      });
      expect(labelKeys, findsOneWidget);
      final newId = (tester.widget(labelKeys).key! as ValueKey<String>).value.split('-')[1];
      expect(newId, isNot('c4'));
      expect(newId, isNot('c5'));
      await tester.enterText(labelKeys, 'شكر');
      await tester.tap(find.byKey(const Key('saveContactCats')));
      await tester.pumpAndSettle();
      final cats = b.savedDocs['settings/contact']!['categories'] as Map;
      expect(cats.keys, ['c1', 'c2', 'c3', newId]);
      final saved = ContactSettings.fromMap({'categories': cats});
      expect(saved.bySlot(newId)!.labelAr, 'شكر');
      expect(saved.bySlot('c4'), isNull);
      expect(cats['c2'], 'booking\u001f1\u001f0\u001f20\u001fحجز قاعة\u001fHall booking\u001fwedding|فرح|Wedding\u001econdolence|عزاء|Condolence');
    });

    testWidgets(
        'P3-31: ContactCategoriesScreen shows UnsavedBar on edits, confirms deletion by name, cancel keeps it, 320px/200% clean',
        (tester) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final locale in [const Locale('ar'), const Locale('en')]) {
        final b = _Backend();
        await tester.pumpWidget(
          _admin(ContactCategoriesScreen(key: ValueKey('cats-${locale.languageCode}'), repo: b), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // No UnsavedBar before edits.
        expect(find.byKey(const Key('unsaved-bar')), findsNothing);

        // Removing a type opens a confirmation naming it; cancelling preserves it cleanly.
        await tester.tap(find.byKey(const ValueKey('removeCat-c4')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining(locale.languageCode == 'ar' ? 'اقتراح' : 'Suggestion'), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('contactCat-c4')), findsOneWidget);
        expect(find.byKey(const Key('unsaved-bar')), findsNothing);

        // Confirming removes the type and surfaces UnsavedBar.
        await tester.tap(find.byKey(const ValueKey('removeCat-c4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('contactCat-c4')), findsNothing);
        expect(find.byKey(const Key('unsaved-bar')), findsOneWidget);
        expect(find.byKey(const Key('unsaved-bar-save')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'ContactCategoriesScreen 320px locale=${locale.languageCode}');

        // Saving through UnsavedBar writes settings/contact and clears dirty state.
        await tester.tap(find.byKey(const Key('unsaved-bar-save')));
        await tester.pumpAndSettle();
        expect(b.savedDocs.containsKey('settings/contact'), isTrue);
        expect(find.byKey(const Key('unsaved-bar')), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Ordinary field edit also surfaces UnsavedBar and S3 jargon never appears in Arabic.
        final c1Ar = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('catLabelAr-c1-'),
        );
        await tester.enterText(c1Ar, 'استفسار عام محدث');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsaved-bar')), findsOneWidget);
        if (locale.languageCode == 'ar') {
          final allText = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
              .join(' ');
          for (final banned in ['Firebase', 'UID', 'App Check', 'Sentry', 'APK', 'HH:mm']) {
            expect(allText, isNot(contains(banned)));
          }
        }
      }
    });

    testWidgets(
        'P3-31: remote snapshot during remove confirmation removes by slot without RangeError',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const c1 = ContactCategory(slot: 'c1', labelAr: 'استفسار', labelEn: 'Inquiry', order: 10);
      const c2 = ContactCategory(slot: 'c2', labelAr: 'اقتراح', labelEn: 'Suggestion', order: 20);
      final ctrl = StreamController<AdminDoc?>.broadcast();
      addTearDown(ctrl.close);
      final repo = _StreamContactBackend(ctrl.stream);

      await tester.pumpWidget(_admin(ContactCategoriesScreen(key: const Key('cats-remote-reorder'), repo: repo)));
      ctrl.add(AdminDoc('contact', ContactSettings(const [c1, c2]).toMap()));
      await tester.pumpAndSettle();

      // Open remove confirmation for c1 (index 0), then simulate remote reorder [c2, c1].
      await tester.tap(find.byKey(const ValueKey('removeCat-c1')));
      await tester.pumpAndSettle();
      ctrl.add(AdminDoc(
        'contact',
        ContactSettings([
          c2.copyWith(order: 10),
          c1.copyWith(order: 20),
        ]).toMap(),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('contactCat-c2'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('contactCat-c1'))).dy),
      );

      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('contactCat-c1')), findsNothing);
      expect(find.byKey(const ValueKey('contactCat-c2')), findsOneWidget);

      // Second scenario: remote snapshot already deleted c1 leaving only 1 category [c2].
      final ctrl2 = StreamController<AdminDoc?>.broadcast();
      addTearDown(ctrl2.close);
      final repo2 = _StreamContactBackend(ctrl2.stream);

      await tester.pumpWidget(_admin(ContactCategoriesScreen(key: const Key('cats-remote-gone'), repo: repo2)));
      ctrl2.add(AdminDoc('contact', ContactSettings(const [c1, c2]).toMap()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('removeCat-c1')));
      await tester.pumpAndSettle();
      ctrl2.add(AdminDoc('contact', ContactSettings(const [c2]).toMap()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('contactCat-c2')), findsOneWidget);
    });

    testWidgets('deleting a custom category hides its items (confirm dialog), then deletes it', (tester) async {
      final b = _Backend(lists: {
        'categories': [AdminDoc('k1', {'nameAr': 'رحلات', 'nameEn': 'Trips', 'slug': 'trips', 'order': 10})],
        'entries': [
          AdminDoc('e1', {'categoryId': 'k1', 'titleAr': 'أ'}),
          AdminDoc('e2', {'categoryId': 'k1', 'titleAr': 'ب', 'visible': false}),
          AdminDoc('e3', {'categoryId': 'k9', 'titleAr': 'ج'}),
        ],
      });
      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('categories')!)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-collectionNote')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-k1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteCategoryDialog')), findsOneWidget);
      expect(find.textContaining('items are hidden from the site, never deleted'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(b.updates.map((u) => '${u.$1}/${u.$2}'), ['entries/e1']);
      expect(b.updates.single.$3, {'visible': false});
      expect(b.deletes, [('categories', 'k1')]);
    });

    testWidgets('editors: category choice for items, link picker for notices', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(_admin(DocEditor(
        title: 'Notice',
        fields: collectionById('alerts')!.fields,
        def: collectionById('alerts'),
        popOnSave: false,
        onSave: (d) async => saved = d,
        linkTargets: const [('/page/donate', 'Building donations'), ('/contact', 'Contact us')],
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تنويه');
      await tester.tap(find.byKey(const ValueKey('group-advanced')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('linkPick-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('linkTarget-/page/donate')));
      await tester.pumpAndSettle();
      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.collect()['link'], '/page/donate');
      await state.save();
      await tester.pumpAndSettle();
      expect(saved?['link'], '/page/donate');

      await tester.pumpWidget(_admin(DocEditor(
        key: const ValueKey('entry'),
        title: 'Item',
        fields: collectionById('entries')!.fields,
        def: collectionById('entries'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {'categoryId': 'deleted-one', 'titleAr': 'x'},
        dynamicChoices: const {
          'categories': [('k1', 'Youth trips'), ('k3', 'Library')]
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('(deleted or no section)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('field-categoryId')));
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('page editor shows only the fields of each block type', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_admin(DocEditor(
        title: 'Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {
          'slug': 'donate',
          'titleAr': 'تبرع',
          'blocks': [
            'heading\u001fع\u001f\u001f\u001f\u001f\u001f',
            {'type': 'donation', 'textAr': '', 'textEn': '', 'url': '', 'account': 'CIB', 'instapay': '', 'wallet': ''},
          ],
        },
        takenSlugs: const {'donate-2'},
      )));
      await tester.pumpAndSettle();
      // Two rows: heading has no account / url fields, donation has them (no url).
      expect(find.byKey(const ValueKey('field-account')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-url')), findsNothing);
      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      // Every row is stored as one string of the 7 fields (firestore.rules validPageBlock).
      expect(state.collect()['blocks'], [
        'heading\u001fع\u001f\u001f\u001f\u001f\u001f',
        'donation\u001f\u001f\u001f\u001fCIB\u001f\u001f',
      ]);
      await tester.tap(find.byKey(const ValueKey('group-advanced')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-slug')), 'donate-2');
      await tester.pump();
      expect(find.text('This address is already used'), findsOneWidget);
    });
  });

  group('PR 3D (P1-14..P1-18)', () {
    test('P1-14: slugFromTitle generates valid, unique slugs from Arabic, empty, and long titles', () {
      final first = slugFromTitle('تبرعات المبنى الجديد', taken: const {});
      expect(isValidSlug(first), isTrue, reason: first);
      expect(first, isNotEmpty);

      final second = slugFromTitle('تبرعات المبنى الجديد', taken: {first});
      expect(isValidSlug(second), isTrue);
      expect(second, isNot(first));
      expect(second, endsWith('-2'));

      final blank = slugFromTitle('   ', taken: const {});
      expect(blank, 'page');
      expect(isValidSlug(blank), isTrue);

      final symbols = slugFromTitle('؟؟؟ *** !!!', taken: {'page', 'page-2'});
      expect(symbols, 'page-3');
      expect(isValidSlug(symbols), isTrue);

      final longBase = slugFromTitle('أ' * 120, taken: const {});
      expect(isValidSlug(longBase), isTrue);
      final longDup = slugFromTitle('أ' * 120, taken: {longBase});
      expect(isValidSlug(longDup), isTrue);
      expect(longDup, isNot(longBase));
    });

    testWidgets('P1-14: DocEditor auto-generates slug for new pages, hides under Advanced, preserves saved slugs',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_admin(DocEditor(
        title: 'New Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        takenSlugs: {'tbraat'},
      )));
      await tester.pumpAndSettle();

      // Slug is tucked inside collapsed Advanced group, unseen by default.
      expect(find.byKey(const ValueKey('groupCard-advanced')), findsOneWidget);
      final slugFinder = find.byKey(const ValueKey('field-slug'));
      expect(slugFinder.hitTestable(), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'تبرعات');
      await tester.pump();
      final newState = tester.state<DocEditorState>(find.byType(DocEditor));
      final generated = newState.collect()['slug'] as String;
      expect(isValidSlug(generated), isTrue);
      expect(generated, isNot('tbraat'));

      // Existing saved page: editing titleAr never alters its existing slug.
      await tester.pumpWidget(_admin(DocEditor(
        key: const ValueKey('saved-page'),
        title: 'Edit Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {'slug': 'existing-slug', 'titleAr': 'قديم'},
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'عنوان مختلف تماما');
      await tester.pump();
      final editState = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(editState.collect()['slug'], 'existing-slug');
    });

    testWidgets('P1-14: saving with an invalid or taken slug auto-expands Advanced group', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_admin(DocEditor(
        title: 'Edit Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {'slug': 'Invalid Slug!', 'titleAr': 'عنوان'},
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-slug')).hitTestable(), findsNothing);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('error-summary-slug')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-slug')).hitTestable(), findsOneWidget);
    });

    test('P1-15: donationPageTemplate has empty financial fields, no personal data, and passes validateDocument', () {
      final tpl = donationPageTemplate();
      final blocks = [
        for (final raw in tpl['blocks']! as List) PageBlock.fromStored(raw)!,
      ];
      final donation = blocks.singleWhere((b) => b.type == BlockTypes.donation);
      expect(donation.account, isEmpty);
      expect(donation.instapay, isEmpty);
      expect(donation.wallet, isEmpty);
      expect(tpl.toString(), isNot(contains(RegExp(r'01[0-2,5]\d{8}'))));

      final slug = slugFromTitle(tpl['titleAr']! as String, taken: const {});
      final filled = {
        ...tpl,
        'slug': slug,
        'blocks': [
          for (final b in blocks)
            b.type == BlockTypes.donation
                ? const PageBlock(type: BlockTypes.donation, account: 'CIB 123456').encode()
                : b.encode(),
        ],
      };
      expect(validateDocument(collectionById('pages'), filled), isNull);
    });

    testWidgets('P1-15: adding a page from CollectionListScreen offers donation template and saves in <= 5 steps',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final b = _Backend();
      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('pages')!)));
      await tester.pumpAndSettle();

      // Step 1: tap Add (+)
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPageDialog')), findsOneWidget);
      expect(find.byKey(const Key('addPage-donation')), findsOneWidget);

      // Step 2: choose Donations template
      await tester.tap(find.byKey(const Key('addPage-donation')));
      await tester.pumpAndSettle();

      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.dirty, isFalse, reason: 'initial auto-slug sync must not falsely dirty template');
      expect(isValidSlug(state.collect()['slug'] as String), isTrue);

      // Step 3: fill account field
      await tester.enterText(find.byKey(const ValueKey('field-account')), 'NBE 999888');
      await tester.pump();

      // Step 4: tap Save
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      // splitSavePayload writes base fields then `blocks` on its own write (2 writes).
      expect(b.saves.length, 2);
      expect(b.saves.every((s) => s.$1 == 'pages'), isTrue);
      final merged = {for (final s in b.saves) ...s.$3};
      expect(isValidSlug(merged['slug'] as String), isTrue);
      final savedBlocks = [for (final raw in merged['blocks'] as List) PageBlock.fromStored(raw)!];
      expect(savedBlocks.any((bl) => bl.type == BlockTypes.donation && bl.account == 'NBE 999888'), isTrue);
    });

    testWidgets('P1-16 & P1-17: empty sections prompt opens editor; populated sections nest items and unassigned card',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final emptyBackend = _Backend();
      await tester.pumpWidget(_admin(CollectionListScreen(repo: emptyBackend, def: collectionById('categories')!)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('emptyCategories')), findsOneWidget);
      expect(find.byKey(const Key('addFirstSectionBtn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('addFirstSectionBtn')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Populated sections + entries + orphan entry
      final popBackend = _Backend(lists: {
        'categories': [
          AdminDoc('k1', {'nameAr': 'رحلات', 'nameEn': 'Trips', 'slug': 'trips', 'order': 10}),
          AdminDoc('k2', {'nameAr': 'مكتبة', 'nameEn': 'Library', 'slug': 'library', 'order': 20}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'k1', 'titleAr': 'الإسكندرية', 'titleEn': 'Alex'}),
          AdminDoc('e9', {'categoryId': 'deleted', 'titleAr': 'يتيمة', 'titleEn': 'Orphan'}),
        ],
      });
      await tester.pumpWidget(KeyedSubtree(
        key: const ValueKey('populated-categories'),
        child: _admin(CollectionListScreen(repo: popBackend, def: collectionById('categories')!)),
      ));
      await tester.pumpAndSettle();

      final k1Tile = find.byKey(const ValueKey('k1'));
      final k2Tile = find.byKey(const ValueKey('k2'));
      expect(k1Tile, findsOneWidget);
      expect(k2Tile, findsOneWidget);
      expect(find.descendant(of: k1Tile, matching: find.byKey(const ValueKey('entry-e1'))), findsOneWidget);
      expect(find.descendant(of: k2Tile, matching: find.text('No items in this section yet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('unassignedItemsCard')), matching: find.byKey(const ValueKey('entry-e9'))),
          findsOneWidget);

      // Tap "+ Add item" inside k2 pre-selects categoryId == 'k2'
      await tester.tap(find.byKey(const ValueKey('addEntryIn-k2')));
      await tester.pumpAndSettle();
      final entryEditor = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(entryEditor.collect()['categoryId'], 'k2');
    });

    testWidgets('P1-17: section/page hints and strings do not point to other screens', (tester) async {
      registerAdminStrings();
      late String delAr, delEn;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (c) {
          delAr = c.tr('catDeleteConfirm', {'n': 'س', 'c': '١'});
          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (c) {
          delEn = c.tr('catDeleteConfirm', {'n': 'X', 'c': '1'});
          return const SizedBox.shrink();
        }),
      ));

      final catDef = collectionById('categories')!;
      final pageDef = collectionById('pages')!;
      final checkStrings = [
        catDef.noteAr,
        catDef.noteEn,
        pageDef.noteAr,
        pageDef.noteEn,
        for (final f in [...catDef.fields, ...pageDef.fields]) ...[f.hintAr, f.hintEn],
        delAr,
        delEn,
        ...adminStrings['emptySectionsPrompt']!,
        ...adminStrings['addFirstSection']!,
      ];
      for (final s in checkStrings) {
        expect(s, isNot(contains('الأقسام والصفحة الرئيسية')));
        expect(s, isNot(contains('عناوين الصفحات')));
        expect(s, isNot(contains('عناصر الأقسام')));
        expect(s, isNot(contains('Section items')));
        expect(s, isNot(contains('Sections & home page')));
      }
    });

    test('P1-18: CustomPage placement backward compatibility, sectionPages, and featuredPages', () {
      final legacyNav = CustomPage.fromMap('p1', {'slug': 'a', 'titleAr': 'أ', 'showInNav': true});
      expect(legacyNav.placement, PagePlacements.nav);
      expect(legacyNav.inNav, isTrue);

      final legacyLink = CustomPage.fromMap('p2', {'slug': 'b', 'titleAr': 'ب'});
      expect(legacyLink.placement, PagePlacements.link);
      expect(legacyLink.inNav, isFalse);

      final badPlacement = CustomPage.fromMap('p3', {'slug': 'c', 'titleAr': 'ج', 'placement': 'unknown', 'showInNav': true});
      expect(badPlacement.placement, PagePlacements.nav);

      final inSec = CustomPage.fromMap('p4', {
        'slug': 'd',
        'titleAr': 'د',
        'placement': 'section',
        'categoryId': 'k1',
        'featured': true,
      });
      final hidden = CustomPage.fromMap('p5', {
        'slug': 'e',
        'titleAr': 'هـ',
        'placement': 'section',
        'categoryId': 'k1',
        'featured': true,
        'visible': false,
      });

      expect(inSec.effectivePlacement, PagePlacements.section);
      expect(inSec.categoryId, 'k1');
      expect(sectionPages('k1', [legacyNav, inSec, hidden]).map((p) => p.id), ['p4']);
      expect(sectionPages('k2', [legacyNav, inSec, hidden]), isEmpty);
      expect(featuredPages([legacyNav, inSec, hidden]).map((p) => p.id), ['p4']);
    });

    test('featuredPages sorting: order first, then updatedAt newest-first, then null updatedAt last, ties keep original index', () {
      final p1 = CustomPage.fromMap('p1', {
        'slug': 'p1',
        'titleAr': 'Page 1',
        'featured': true,
        'order': 10,
        'updatedAt': '2026-11-10T10:00:00Z',
      });
      final p2 = CustomPage.fromMap('p2', {
        'slug': 'p2',
        'titleAr': 'Page 2',
        'featured': true,
        'order': 0,
        'updatedAt': '2026-11-05T10:00:00Z',
      });
      final p3 = CustomPage.fromMap('p3', {
        'slug': 'p3',
        'titleAr': 'Page 3',
        'featured': true,
        'order': 0,
        'updatedAt': DateTime(2026, 11, 15, 10, 0),
      });
      final p4 = CustomPage.fromMap('p4', {
        'slug': 'p4',
        'titleAr': 'Page 4',
        'featured': true,
        'order': 0,
      });
      final p5 = CustomPage.fromMap('p5', {
        'slug': 'p5',
        'titleAr': 'Page 5',
        'featured': true,
        'order': 0,
      });

      // p3 (order 0, 2026-11-15) > p2 (order 0, 2026-11-05) > p4 (order 0, null) > p5 (order 0, null) > p1 (order 10)
      final sorted = featuredPages([p1, p4, p2, p5, p3]);
      expect(sorted.map((p) => p.id), ['p3', 'p2', 'p4', 'p5', 'p1']);
    });

    test('isCategoryNonEmpty and publicNonEmptyCategories filter empty categories and non-section pages', () {
      const catWithEntry = CustomCategory(id: 'c1', slug: 'c1', nameAr: 'قسم 1', order: 10);
      const catWithSectionPage = CustomCategory(id: 'c2', slug: 'c2', nameAr: 'قسم 2', order: 20);
      const catEmpty = CustomCategory(id: 'c3', slug: 'c3', nameAr: 'قسم فارغ', order: 30);
      const catWithHiddenEntry = CustomCategory(id: 'c4', slug: 'c4', nameAr: 'قسم 4', order: 40);
      const catWithNonSectionPage = CustomCategory(id: 'c5', slug: 'c5', nameAr: 'قسم 5', order: 50);

      final entries = [
        CategoryEntry.fromMap('e1', {'categoryId': 'c1', 'titleAr': 'عنصر 1', 'visible': true}),
        CategoryEntry.fromMap('e2', {'categoryId': 'c4', 'titleAr': 'عنصر مخفي', 'visible': false}),
      ];

      final pages = [
        CustomPage.fromMap('p1', {
          'slug': 'page-sec',
          'titleAr': 'صفحة قسم',
          'categoryId': 'c2',
          'placement': 'section',
          'visible': true,
        }),
        CustomPage.fromMap('p2', {
          'slug': 'page-sec-hidden',
          'titleAr': 'صفحة قسم مخفية',
          'categoryId': 'c3',
          'placement': 'section',
          'visible': false,
        }),
        CustomPage.fromMap('p3', {
          'slug': 'page-link',
          'titleAr': 'صفحة رابط',
          'categoryId': 'c5',
          'placement': 'link',
          'visible': true,
        }),
        CustomPage.fromMap('p4', {
          'slug': 'page-nav',
          'titleAr': 'صفحة قائمة',
          'categoryId': 'c5',
          'placement': 'nav',
          'visible': true,
        }),
      ];

      expect(isCategoryNonEmpty(catWithEntry, entries, pages), isTrue);
      expect(isCategoryNonEmpty(catWithSectionPage, entries, pages), isTrue);
      expect(isCategoryNonEmpty(catEmpty, entries, pages), isFalse);
      expect(isCategoryNonEmpty(catWithHiddenEntry, entries, pages), isFalse);
      expect(isCategoryNonEmpty(catWithNonSectionPage, entries, pages), isFalse);

      final result = publicNonEmptyCategories(
        [catWithEntry, catWithSectionPage, catEmpty, catWithHiddenEntry, catWithNonSectionPage],
        entries,
        pages,
      );
      expect(result.map((c) => c.id), ['c1', 'c2']);
    });

    testWidgets('P1-18: DocEditor syncs nav showInNav and requires categoryId for section placement', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(_admin(DocEditor(
        title: 'Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async => saved = d,
        data: const {'slug': 'p', 'titleAr': 'صفحة', 'showInNav': true},
        dynamicChoices: const {
          'categories': [('k1', 'Youth trips')],
        },
      )));
      await tester.pumpAndSettle();

      // Legacy showInNav: true promotes placement to nav.
      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.collect()['placement'], PagePlacements.nav);
      expect(state.collect()['showInNav'], isTrue);
      expect(find.byKey(const ValueKey('field-categoryId')), findsNothing);

      // Switch to link -> showInNav becomes false
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link only').last);
      await tester.pumpAndSettle();
      expect(state.collect()['showInNav'], isFalse);

      // Switch to section -> categoryId appears and is required before save succeeds
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inside a section').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-categoryId')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: 'section placement requires categoryId');

      await tester.tap(find.byKey(const ValueKey('field-categoryId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Youth trips').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('field-featured')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['placement'], PagePlacements.section);
      expect(saved?['categoryId'], 'k1');
      expect(saved?['featured'], isTrue);
      expect(saved?['showInNav'], isFalse);
    });

    testWidgets('P1-18: section-placed & featured pages appear on CategoryPage/HomePage and hide when customPages is off',
        (tester) async {
      final (router, _) = await _pump(tester, '/section/youth-trips', size: const Size(320, 3000));
      expect(find.byKey(const Key('sectionPage-trips-faq')), findsOneWidget);
      expect(find.text('Trips guide'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.descendant(
        of: find.byKey(const Key('sectionPage-trips-faq')),
        matching: find.text('Learn more'),
      ));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/page/trips-faq');

      // Featured card renders on HomePage
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-featuredPages')), findsOneWidget);
      expect(find.byKey(const Key('featuredPage-trips-faq')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Feature switch off hides both section cards and featured home cards
      final (routerOff, _) = await _pump(
        tester,
        '/section/youth-trips',
        size: const Size(320, 3000),
        repo: _Repo({Sections.customPages: false}),
      );
      expect(find.byKey(const Key('sectionPage-trips-faq')), findsNothing);
      routerOff.go('/');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('featuredPage-trips-faq')), findsNothing);
    });

    testWidgets('PR #77 review fixes: persisted partial save locks auto-slug; categories loading/error/filter/unconfirmed; category page loading/error',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. doc_editor: partial chunked save sets _persisted = true; editing titleAr
      // before retry must not mutate the persisted slug.
      var saveCalls = 0;
      await tester.pumpWidget(_admin(DocEditor(
        title: 'New Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {
          saveCalls++;
          if (saveCalls == 2) throw StateError('blocks write failed');
        },
        newDefaults: const {
          'titleAr': 'عنوان أول',
          'blocks': ['paragraph\u001fنص\u001f\u001f\u001f\u001f\u001f'],
        },
      )));
      await tester.pumpAndSettle();
      final docState = tester.state<DocEditorState>(find.byType(DocEditor));
      final initialSlug = docState.collect()['slug'] as String;
      expect(isValidSlug(initialSlug), isTrue);

      await docState.save();
      await tester.pumpAndSettle();
      expect(saveCalls, 2);

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'عنوان مختلف تماما');
      await tester.pump();
      expect(docState.collect()['slug'], initialSlug);

      // 2. collection_list: entries stream loading & error states
      final entriesCtrl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(entriesCtrl.close);
      final loadingBackend = _StreamEntriesBackend(
        cats: [AdminDoc('k1', {'nameAr': 'رحلات', 'nameEn': 'Trips', 'slug': 'trips', 'order': 10})],
        entriesStream: entriesCtrl.stream,
      );
      await tester.pumpWidget(_admin(CollectionListScreen(repo: loadingBackend, def: collectionById('categories')!)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('emptyCategories')), findsNothing);

      entriesCtrl.addError('entries load boom');
      await tester.pump();
      expect(find.textContaining('entries load boom'), findsOneWidget);

      // 3. collection_list: Unconfirmed filter chip shown for entries.hasSample &
      // filter-hidden entries render noMatches instead of sectionEmptyItems.
      final filterBackend = _Backend(lists: {
        'categories': [
          AdminDoc('k1', {'nameAr': 'رحلات', 'nameEn': 'Trips', 'slug': 'trips', 'order': 10}),
          AdminDoc('k2', {'nameAr': 'مكتبة', 'nameEn': 'Library', 'slug': 'library', 'order': 20}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'k1', 'titleAr': 'الإسكندرية', 'titleEn': 'Alex', 'sample': false}),
          AdminDoc('e2', {'categoryId': 'k2', 'titleAr': 'كتاب', 'titleEn': 'Book', 'sample': true}),
        ],
      });
      await tester.pumpWidget(KeyedSubtree(
        key: const ValueKey('cat-filters'),
        child: _admin(CollectionListScreen(repo: filterBackend, def: collectionById('categories')!)),
      ));
      await tester.pumpAndSettle();

      // Search for k1's title ("Trips") which does not match entry e1 ("Alex").
      await tester.enterText(find.byKey(const Key('admin-search')), 'Trips');
      await tester.pump();
      final k1Tile = find.byKey(const ValueKey('k1'));
      expect(k1Tile, findsOneWidget);
      expect(find.descendant(of: k1Tile, matching: find.text('No matching items')), findsOneWidget);
      expect(find.descendant(of: k1Tile, matching: find.text('No items in this section yet')), findsNothing);

      await tester.enterText(find.byKey(const Key('admin-search')), '');
      await tester.pump();

      // Unconfirmed chip must appear and filter down to k2 + e2.
      final unconfirmedChip = find.widgetWithText(ChoiceChip, 'Unconfirmed');
      expect(unconfirmedChip, findsOneWidget);
      await tester.tap(unconfirmedChip);
      await tester.pump();
      expect(find.byKey(const ValueKey('k1')), findsNothing);
      expect(find.byKey(const ValueKey('k2')), findsOneWidget);
      expect(find.byKey(const ValueKey('entry-e2')), findsOneWidget);

      // 4. CategoryPage: loading & error states for customPagesProvider
      final pagesCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(pagesCtrl.close);
      final customPagesRepo = _ControlledPagesRepo(pagesCtrl.stream, entries: const []);
      await _pump(tester, '/section/youth-trips', repo: customPagesRepo, settle: false);
      await tester.pump();
      expect(find.text('No content in this section yet'), findsNothing);
      expect(find.byType(SkeletonList), findsOneWidget);

      pagesCtrl.addError(StateError('pages boom'));
      await tester.pump();
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('No content in this section yet'), findsNothing);
    });

    testWidgets('PR #77 review fix: CategoryPage keeps loaded entries visible when customPagesProvider errors',
        (tester) async {
      final pagesCtrl2 = StreamController<List<CustomPage>>.broadcast();
      addTearDown(pagesCtrl2.close);
      final mixedRepo = _ControlledPagesRepo(pagesCtrl2.stream, entries: _entries);
      await _pump(tester, '/section/youth-trips', repo: mixedRepo, settle: false);
      await tester.pump();
      expect(find.byKey(const Key('entry-e1')), findsOneWidget);
      pagesCtrl2.addError(StateError('pages boom 2'));
      await tester.pump();
      expect(find.byKey(const Key('entry-e1')), findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);
    });

    test('UX fix: CustomPage with stored categoryId and link/nav placement never appears in sectionPages', () {
      final pageMatchingExisting = CustomPage.fromMap('p-link-1', {
        'slug': 'link-1',
        'titleAr': 'رابط',
        'placement': PagePlacements.link,
        'categoryId': 'k1',
      });
      final pageMatchingDeleted = CustomPage.fromMap('p-link-2', {
        'slug': 'link-2',
        'titleAr': 'رابط مع قسم محذوف',
        'placement': PagePlacements.link,
        'categoryId': 'deleted-category-999',
      });
      final pageNavWithCategory = CustomPage.fromMap('p-nav-1', {
        'slug': 'nav-1',
        'titleAr': 'قائمة',
        'placement': PagePlacements.nav,
        'categoryId': 'k1',
      });

      expect(sectionPages('k1', [pageMatchingExisting, pageMatchingDeleted, pageNavWithCategory]), isEmpty);
      expect(sectionPages('deleted-category-999', [pageMatchingExisting, pageMatchingDeleted, pageNavWithCategory]), isEmpty);
    });

    testWidgets('UX fix: DocEditor preserves categoryId when switching to link, and re-selects it when switching back to section', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(_admin(DocEditor(
        title: 'Edit Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async => saved = d,
        data: const {
          'slug': 'trips-page',
          'titleAr': 'صفحة رحلات',
          'placement': 'section',
          'categoryId': 'k1',
        },
        dynamicChoices: const {
          'categories': [('k1', 'Youth trips'), ('k2', 'Library')],
        },
      )));
      await tester.pumpAndSettle();

      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.collect()['categoryId'], 'k1');

      // Switch placement to 'link'
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link only').last);
      await tester.pumpAndSettle();

      // categoryId field is hidden in UI
      expect(find.byKey(const ValueKey('field-categoryId')), findsNothing);

      // Save -> payload preserves categoryId: 'k1'
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['placement'], PagePlacements.link);
      expect(state.collect()['categoryId'], 'k1');

      // Switch placement back to 'section' -> categoryId appears and is still 'k1'
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inside a section').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-categoryId')), findsOneWidget);
      expect(state.collect()['categoryId'], 'k1');

      // Reopen editor with saved data where placement is 'link' and categoryId is 'k1'
      await tester.pumpWidget(_admin(DocEditor(
        key: const ValueKey('reopened-doc-editor'),
        title: 'Reopened Page',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {
          'slug': 'trips-page',
          'titleAr': 'صفحة رحلات',
          'placement': 'link',
          'categoryId': 'k1',
        },
        dynamicChoices: const {
          'categories': [('k1', 'Youth trips'), ('k2', 'Library')],
        },
      )));
      await tester.pumpAndSettle();

      final reopenedState = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(reopenedState.collect()['categoryId'], 'k1');
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inside a section').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-categoryId')), findsOneWidget);
      expect(reopenedState.collect()['categoryId'], 'k1');
    });

    testWidgets('UX fix: HomePage featured pages placement under SectionTitle and Reveal transitions to opacity 1 when customPagesProvider loads', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pagesCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(pagesCtrl.close);
      final asyncRepo = _ControlledPagesRepo(pagesCtrl.stream, entries: const []);

      await _pump(tester, '/', size: const Size(1200, 3000), repo: asyncRepo, settle: true);

      // Initially custom pages are not loaded, so featured pages are hidden (SizedBox.shrink)
      expect(find.byKey(const Key('featuredPage-featured-guide')), findsNothing);
      expect(find.byKey(const ValueKey('home-patrons')), findsOneWidget);

      // Now emit pages with a featured page
      pagesCtrl.add([
        const CustomPage(
          id: 'p-feat',
          slug: 'featured-guide',
          titleAr: 'دليل مميز',
          titleEn: 'Featured guide',
          featured: true,
        ),
      ]);
      await tester.pump();
      await tester.pumpAndSettle();

      // Featured pages block is now present
      expect(find.byKey(const Key('featuredPage-featured-guide')), findsOneWidget);
      expect(find.text('Featured pages'), findsOneWidget);

      // Verify placement order: featuredPages comes BEFORE patrons / discovery
      final featuredTop = tester.getTopLeft(find.byKey(const ValueKey('home-featuredPages'))).dy;
      final patronsTop = tester.getTopLeft(find.byKey(const ValueKey('home-patrons'))).dy;
      expect(featuredTop, lessThan(patronsTop));

      // Verify Reveal opacity is 1
      final reveal = find.ancestor(of: find.byKey(const ValueKey('home-featuredPages')), matching: find.byType(Reveal));
      expect(reveal, findsOneWidget);
      final opacities = tester.widgetList<Opacity>(find.descendant(of: reveal, matching: find.byType(Opacity)));
      expect(opacities, isNotEmpty);
      expect(opacities.first.opacity, 1.0);
    });

    testWidgets('UX fix: CustomPageCard renders CardCover when image is present and media is on, hides when off or image null', (tester) async {
      const pageWithImage = CustomPage(
        id: 'p-img',
        slug: 'img-page',
        titleAr: 'صفحة بصورة',
        titleEn: 'Image page',
        image: MediaImage.url('https://example.com/pic.webp'),
      );
      const pageNoImage = CustomPage(
        id: 'p-no-img',
        slug: 'no-img-page',
        titleAr: 'صفحة بلا صورة',
        titleEn: 'No image page',
      );

      // Media ON: pageWithImage has CardCover, pageNoImage has no CardCover
      await tester.pumpWidget(ProviderScope(
        overrides: [
          featuresProvider.overrideWithValue(FeatureSettings.fromMap(const {
            'sections': {Sections.media: true},
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  CustomPageCard(page: pageWithImage),
                  CustomPageCard(page: pageNoImage),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cardCover')), findsOneWidget);

      // Media OFF: CardCover is not rendered
      await tester.pumpWidget(ProviderScope(
        overrides: [
          featuresProvider.overrideWithValue(FeatureSettings.fromMap(const {
            'sections': {Sections.media: false},
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CustomPageCard(page: pageWithImage),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cardCover')), findsNothing);
    });

    testWidgets('UX fix: CustomPageView constrains hero and blocks to maxWidth 700 on 1280px width, heading fontSize >= 24', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pagesWithHero = [
        const CustomPage(
          id: 'p-wide',
          slug: 'wide-page',
          titleAr: 'صفحة مقال',
          titleEn: 'Article page',
          image: MediaImage.url('https://example.com/hero.webp'),
          blocks: [
            PageBlock(type: BlockTypes.heading, textAr: 'عنوان رئيسي', textEn: 'Main heading'),
            PageBlock(type: BlockTypes.paragraph, textAr: 'فقرة أولى', textEn: 'First paragraph'),
          ],
        ),
      ];
      final repo = _ControlledPagesRepo(Stream.value(pagesWithHero), entries: const []);

      await _pump(tester, '/page/wide-page', size: const Size(1280, 800), repo: repo);
      await tester.pumpAndSettle();

      final constrainedFinder = find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.maxWidth == 700);
      expect(constrainedFinder, findsOneWidget);

      final heroFinder = find.byKey(const Key('pageHero'));
      expect(heroFinder, findsOneWidget);
      expect(tester.getSize(heroFinder).width, lessThanOrEqualTo(700));

      final headingText = tester.widget<Text>(find.text('Main heading'));
      expect(headingText.style?.fontSize, greaterThanOrEqualTo(24));
    });

    testWidgets('UX fix: DocEditor collapsible blocks only mounts one expanded block at a time, supports add/switch/error auto-expand', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_admin(DocEditor(
        title: 'Blocks Test',
        fields: collectionById('pages')!.fields,
        def: collectionById('pages'),
        popOnSave: false,
        onSave: (d) async {},
        data: const {
          'slug': 'test-blocks',
          'titleAr': 'تجربة الفقرات',
          'blocks': [
            'heading\u001fع1\u001fH1\u001f\u001f\u001f\u001f',
            'paragraph\u001fف2\u001fP2\u001f\u001f\u001f\u001f',
            'link\u001f\u001f\u001fnot-a-valid-url\u001f\u001f\u001f',
          ],
        },
      )));
      await tester.pumpAndSettle();

      // Only 1 row expanded at a time: initially row 0 is expanded
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('ع1'), findsOneWidget);
      // Collapsed rows show summaries (formatted with '· ' prefix)
      expect(find.text('· ف2'), findsOneWidget);
      expect(find.text('· not-a-valid-url'), findsOneWidget);

      // Tap on row 1 (paragraph) summary to expand it
      await tester.tap(find.text('· ف2'));
      await tester.pumpAndSettle();

      // Now row 1 is expanded, still only 1 DropdownButtonFormField mounted
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // Tap Add row (+)
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add row'));
      await tester.pumpAndSettle();

      // New row (row 3) is automatically expanded
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // Switch back to row 0
      await tester.tap(find.text('· ع1'));
      await tester.pumpAndSettle();

      // Try saving -> invalid block error summary appears because collapsed block 3 has invalid url
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);

      // Tap the error link for block 3 -> auto expands row 2 (which is currently collapsed)
      final errorLink = find.textContaining('(3)');
      expect(errorLink, findsWidgets);
      await tester.tap(errorLink.first);
      await tester.pumpAndSettle();
      // DropdownButtonFormField is mounted for block 3
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('UX fix: DocEditor collapsed block rows wrap action buttons and do not overflow at 320px with 200% text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1000),
            textScaler: TextScaler.linear(2.0),
          ),
          child: _admin(DocEditor(
            title: 'Narrow Blocks',
            fields: collectionById('pages')!.fields,
            def: collectionById('pages'),
            popOnSave: false,
            onSave: (d) async {},
            data: const {
              'slug': 'narrow-blocks',
              'titleAr': 'فقرات شاشة ضيقة',
              'blocks': [
                'headingعنوان طويل للفقرة الأولى في شاشة ضيقةH1',
                'paragraphنص تجريبي طويل جدًا للفقرة الثانية للتأكد من عدم وجود أي تجاوز للشاشةP2',
              ],
            },
          )),
        ),
      );
      await tester.pumpAndSettle();

      // Row 0 is expanded by default; row 1 is collapsed.
      expect(find.text('2.'), findsOneWidget);
      // Collapsed row 1 action buttons (moveUp, moveDown, remove, expandBlock) are present without overflow errors.
      expect(tester.takeException(), isNull);

      // Tap on row 1 to expand it, which collapses row 0.
      await tester.ensureVisible(find.text('2.'));
      await tester.tap(find.text('2.'));
      await tester.pumpAndSettle();

      // Now row 0 is collapsed.
      expect(find.text('1.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Single featured page renders centered with ConstrainedBox(maxWidth: 560); multiple use ResponsiveGrid', (tester) async {
      final pagesCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(pagesCtrl.close);
      final asyncRepo = _ControlledPagesRepo(pagesCtrl.stream, entries: const []);

      await _pump(tester, '/', size: const Size(1280, 800), repo: asyncRepo, settle: true);

      final p1 = CustomPage(
        id: 'p1',
        slug: 'page-one',
        titleAr: 'صفحة أولى',
        titleEn: 'Page One',
        placement: PagePlacements.section,
        categoryId: 'k1',
        featured: true,
        visible: true,
        updatedAt: DateTime(2026, 11, 10, 10, 0),
      );

      // Emit single featured page
      pagesCtrl.add([p1]);
      await tester.pump();
      await tester.pumpAndSettle();

      // On 1280x800, scroll down to bring featured pages into viewport
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      final featuredFinder = find.byKey(const ValueKey('home-featuredPages'));
      expect(featuredFinder, findsOneWidget);
      final singleCardFinder = find.byKey(Key('featuredPage-${p1.slug}'));
      expect(singleCardFinder, findsOneWidget);

      // Should not be in ResponsiveGrid
      expect(find.descendant(of: featuredFinder, matching: find.byType(ResponsiveGrid)), findsNothing);

      // Card is inside Center and ConstrainedBox with maxWidth == 560
      final constrainedBoxFinder = find.ancestor(of: singleCardFinder, matching: find.byType(ConstrainedBox)).first;
      expect(tester.widget<ConstrainedBox>(constrainedBoxFinder).constraints.maxWidth, 560);
      expect(find.ancestor(of: singleCardFinder, matching: find.byType(Center)), findsWidgets);

      // Now emit 2 featured pages
      final p2 = CustomPage(
        id: 'p2',
        slug: 'page-two',
        titleAr: 'صفحة ثانية',
        titleEn: 'Page Two',
        placement: PagePlacements.section,
        categoryId: 'k1',
        featured: true,
        visible: true,
        updatedAt: DateTime(2026, 11, 12, 10, 0),
      );
      pagesCtrl.add([p1, p2]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.descendant(of: featuredFinder, matching: find.byType(ResponsiveGrid)), findsOneWidget);
      expect(find.byKey(Key('featuredPage-${p1.slug}')), findsOneWidget);
      expect(find.byKey(Key('featuredPage-${p2.slug}')), findsOneWidget);
    });

    testWidgets('Reveal viewportLead (+20) reveals item when top <= screen + 20', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Item placed at top = 810 (below 800px viewport, but within +20 lead of 820)
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 810),
                  Reveal(
                    key: ValueKey('reveal-near'),
                    child: SizedBox(width: 200, height: 100),
                  ),
                  SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final nearState = tester.state(find.byKey(const ValueKey('reveal-near')));
      expect((nearState as dynamic).viewportLead, 20.0);
      expect((nearState as dynamic).visibleInViewport, isTrue);

      // Now verify that if top is at 830 (beyond screen + 20 = 820), it is not visible
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 830),
                  Reveal(
                    key: ValueKey('reveal-far'),
                    child: SizedBox(width: 200, height: 100),
                  ),
                  SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final farState = tester.state(find.byKey(const ValueKey('reveal-far')));
      expect((farState as dynamic).visibleInViewport, isFalse);
    });

    testWidgets('CustomPageCard renders CardCover/FittedCover when image map is present on narrow 320px Home and /section/<slug> with zero overflow', (tester) async {
      const coverPage = CustomPage(
        id: 'p-cover',
        slug: 'cover-page',
        titleAr: 'صفحة بغلاف',
        titleEn: 'Page with cover',
        subtitleAr: 'وصف الغلاف',
        subtitleEn: 'Cover description',
        placement: PagePlacements.section,
        categoryId: 'k1',
        featured: true,
        visible: true,
        image: MediaImage(
          source: MediaSource.url,
          url: 'https://example.org/cover.jpg',
          alt: 'غلاف',
        ),
      );

      final customRepo = _ControlledPagesRepo(
        Stream.value([coverPage]),
        entries: const [],
        cats: const [
          CustomCategory(id: 'k1', slug: 'youth-trips', nameAr: 'رحلات الشباب', nameEn: 'Youth trips', visible: true),
        ],
      );

      // 1. Narrow 320px on Home: featured page card renders CardCover/FittedCover with zero layout overflow
      final (homeRouter, _) = await _pump(tester, '/', size: const Size(320, 3000), repo: customRepo);
      expect(find.byKey(const Key('featuredPage-cover-page')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('featuredPage-cover-page')),
          matching: find.byKey(const Key('cardCover')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // 2. Narrow 320px on /section/<slug>: section page card renders CardCover/FittedCover with zero layout overflow
      homeRouter.go('/section/youth-trips');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-cover-page')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('sectionPage-cover-page')),
          matching: find.byKey(const Key('cardCover')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Checklist 13 & 14 E2E: empty category hidden from menu and renders EmptyState + admin chip; linking section page shows it and clears chip; unlinking/hiding reverts to empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var currentPages = <CustomPage>[];
      final pagesCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(pagesCtrl.close);

      Stream<List<CustomPage>> pagesStream() async* {
        yield currentPages;
        yield* pagesCtrl.stream;
      }

      const testCat = CustomCategory(
        id: 'cat-special',
        slug: 'special-activities',
        nameAr: 'أنشطة خاصة',
        nameEn: 'Special activities',
        visible: true,
      );

      final repo = _ControlledPagesRepo(
        pagesStream(),
        entries: const [],
        cats: const [testCat],
      );

      const linkedPage = CustomPage(
        id: 'page-camp',
        slug: 'summer-camp',
        titleAr: 'معسكر الصيف',
        titleEn: 'Summer camp',
        placement: PagePlacements.section,
        categoryId: 'cat-special',
        visible: true,
      );

      const hiddenPage = CustomPage(
        id: 'page-camp',
        slug: 'summer-camp',
        titleAr: 'معسكر الصيف',
        titleEn: 'Summer camp',
        placement: PagePlacements.section,
        categoryId: 'cat-special',
        visible: false,
      );

      // ==========================================
      // PART A: PUBLIC PORTAL BEHAVIOR (/section/<slug> & public menu)
      // ==========================================

      // A.1 Newly created empty category:
      // Menu hides category
      expect(publicNonEmptyCategories([testCat], const [], const []).any((c) => c.id == 'cat-special'), isFalse);
      // /section/<slug> renders EmptyState
      await _pump(tester, '/section/special-activities', size: const Size(800, 1400), repo: repo);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(CustomPageCard), findsNothing);

      // A.2 Linking a visible page with placement: 'section':
      // Menu shows category
      expect(publicNonEmptyCategories([testCat], const [], [linkedPage]).any((c) => c.id == 'cat-special'), isTrue);
      // /section/<slug> displays page card
      currentPages = [linkedPage];
      pagesCtrl.add(currentPages);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-summer-camp')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      // A.3 Unlinking or hiding/deleting the page:
      // Menu hides category again
      expect(publicNonEmptyCategories([testCat], const [], [hiddenPage]).any((c) => c.id == 'cat-special'), isFalse);
      // /section/<slug> renders EmptyState again
      currentPages = [hiddenPage];
      pagesCtrl.add(currentPages);
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(CustomPageCard), findsNothing);

      // ==========================================
      // PART B: ADMIN COLLECTION LIST BEHAVIOR (chip appearance & disappearance)
      // ==========================================

      // B.1 Empty category -> shows chip
      final adminRepoEmpty = _Backend(lists: {
        'categories': [
          AdminDoc('cat-special', {
            'nameAr': 'أنشطة خاصة',
            'nameEn': 'Special activities',
            'slug': 'special-activities',
            'order': 10,
            'visible': true,
          }),
        ],
        'entries': const [],
        'pages': const [],
      });
      await tester.pumpWidget(_admin(CollectionListScreen(repo: adminRepoEmpty, def: collectionById('categories')!), locale: const Locale('ar')));
      await tester.pumpAndSettle();
      final catCardEmpty = find.byKey(const ValueKey('cat-special'));
      expect(catCardEmpty, findsOneWidget);
      expect(find.descendant(of: catCardEmpty, matching: find.text('فاضي، مش ظاهر للزوار')), findsOneWidget);

      // B.2 Linking visible section page -> chip disappears
      final adminRepoLinked = _Backend(lists: {
        'categories': [
          AdminDoc('cat-special', {
            'nameAr': 'أنشطة خاصة',
            'nameEn': 'Special activities',
            'slug': 'special-activities',
            'order': 10,
            'visible': true,
          }),
        ],
        'entries': const [],
        'pages': [
          AdminDoc('page-camp', {
            'categoryId': 'cat-special',
            'titleAr': 'معسكر الصيف',
            'titleEn': 'Summer camp',
            'slug': 'summer-camp',
            'placement': 'section',
            'visible': true,
          }),
        ],
      });
      await tester.pumpWidget(_admin(CollectionListScreen(repo: adminRepoLinked, def: collectionById('categories')!), locale: const Locale('ar')));
      await tester.pumpAndSettle();
      final catCardLinked = find.byKey(const ValueKey('cat-special'));
      expect(find.descendant(of: catCardLinked, matching: find.text('فاضي، مش ظاهر للزوار')), findsNothing);
      expect(find.descendant(of: catCardLinked, matching: find.byKey(const Key('sectionPageRow-page-camp'))), findsOneWidget);

      // B.3 Page hidden -> chip reappears
      final adminRepoHidden = _Backend(lists: {
        'categories': [
          AdminDoc('cat-special', {
            'nameAr': 'أنشطة خاصة',
            'nameEn': 'Special activities',
            'slug': 'special-activities',
            'order': 10,
            'visible': true,
          }),
        ],
        'entries': const [],
        'pages': [
          AdminDoc('page-camp', {
            'categoryId': 'cat-special',
            'titleAr': 'معسكر الصيف',
            'titleEn': 'Summer camp',
            'slug': 'summer-camp',
            'placement': 'section',
            'visible': false,
          }),
        ],
      });
      await tester.pumpWidget(_admin(CollectionListScreen(repo: adminRepoHidden, def: collectionById('categories')!), locale: const Locale('ar')));
      await tester.pumpAndSettle();
      final catCardReverted = find.byKey(const ValueKey('cat-special'));
      expect(find.descendant(of: catCardReverted, matching: find.text('فاضي، مش ظاهر للزوار')), findsOneWidget);
    });
  });

  group('Phase 4 PR2: BuiltInSections', () {
    test('collectTakenSlugs includes hidden and locally pending-delete docs, trims whitespace, excludes self and non-pending soft-deletes', () {
      final docs = [
        AdminDoc('p-self', {'slug': 'self-slug'}),
        AdminDoc('p-hidden', {'slug': 'hidden-slug', 'visible': false}),
        AdminDoc('p-pending', {'slug': 'pending-slug', 'deletedAt': DateTime.utc(2026, 11, 19)}),
        AdminDoc('p-soft', {'slug': 'old-deleted', 'deletedAt': DateTime.utc(2026, 11, 18)}),
        AdminDoc('p-ws', {'slug': '  trimmed-slug  '}),
        AdminDoc('p-blank', {'slug': '   '}),
      ];
      expect(
        collectTakenSlugs(
          docs,
          excludeId: 'p-self',
          isPendingDelete: (id) => id == 'p-pending',
        ),
        {'hidden-slug', 'pending-slug', 'trimmed-slug'},
      );
    });

    testWidgets(
        'CollectionListScreen(categories) enforces takenSlugs from live pages stream even if subsequent pages read fails, blocks hidden slugs, shows slugTaken in error summary, and resets cache on repo change',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final locale in [const Locale('en'), const Locale('ar')]) {
        final pages = [
          AdminDoc('p-act-1', {
            'slug': 'choir-guide',
            'titleAr': 'دليل الكورال',
            'placement': 'section',
            'categoryId': BuiltInSections.activities,
            'visible': true,
          }),
          AdminDoc('p-hidden', {
            'slug': 'new-building-donations',
            'titleAr': 'مبنى الكنيسة الجديد',
            'placement': 'link',
            'visible': false,
          }),
        ];
        final b = _FailSubsequentPagesReadBackend(lists: {
          'categories': const [],
          'entries': const [],
          'pages': pages,
        });

        await tester.pumpWidget(KeyedSubtree(
          key: ValueKey('taken-slugs-${locale.languageCode}'),
          child: _admin(CollectionListScreen(repo: b, def: collectionById('categories')!), locale: locale),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('sectionPageRow-p-act-1')));
        await tester.pumpAndSettle();
        expect(find.byType(DocEditor), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('group-advanced')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('field-slug')), 'new-building-donations');
        await tester.pump();
        await tester.tap(find.byKey(const Key('editor-save')));
        await tester.pumpAndSettle();

        expect(b.saves, isEmpty);
        final summaryEntry = find.byKey(const ValueKey('error-summary-slug'));
        expect(summaryEntry, findsOneWidget);
        final expectedSlugTaken =
            locale.languageCode == 'ar' ? 'هذا الرابط مستخدم بالفعل' : 'This address is already used';
        expect(
          find.descendant(of: summaryEntry, matching: find.textContaining(expectedSlugTaken)),
          findsOneWidget,
        );

        // Restoring own slug allows saving without self-conflict.
        await tester.enterText(find.byKey(const ValueKey('field-slug')), 'choir-guide');
        await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'دليل الكورال المحدّث');
        await tester.pump();
        await tester.tap(find.byKey(const Key('editor-save')));
        await tester.pumpAndSettle();
        expect(b.saves, hasLength(1));
        expect(b.saves.single.$1, 'pages');
        expect(b.saves.single.$2, 'p-act-1');
        expect(b.saves.single.$3['titleAr'], 'دليل الكورال المحدّث');

        // Re-pump with the same widget key and a fresh repo without p-hidden;
        // didUpdateWidget must clear _lastPages so the previously hidden slug is now free.
        final b2 = _Backend(lists: {
          'categories': const [],
          'entries': const [],
          'pages': [pages.first],
        });
        await tester.pumpWidget(KeyedSubtree(
          key: ValueKey('taken-slugs-${locale.languageCode}'),
          child: _admin(CollectionListScreen(repo: b2, def: collectionById('categories')!), locale: locale),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('sectionPageRow-p-act-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('group-advanced')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('field-slug')), 'new-building-donations');
        await tester.pump();
        await tester.tap(find.byKey(const Key('editor-save')));
        await tester.pumpAndSettle();

        expect(b2.saves, hasLength(1));
        expect(b2.saves.single.$3['slug'], 'new-building-donations');
        expect(tester.takeException(), isNull);
      }
    });

    test('BuiltInSections canonical keys, lookups, sectionPages, and isCategoryNonEmpty', () {
      expect(BuiltInSections.all.map((b) => b.id), [
        'builtin_schedule',
        'builtin_meetings',
        'builtin_activities',
        'builtin_clinics',
        'builtin_services',
        'builtin_about',
        'builtin_contact',
      ]);
      expect(BuiltInSections.byId(BuiltInSections.meetings)?.slug, 'church-education');
      expect(BuiltInSections.byId('builtin_education'), isNull);
      expect(BuiltInSections.byId('k1'), isNull);
      expect(BuiltInSections.isBuiltIn('builtin_activities'), isTrue);
      expect(BuiltInSections.isBuiltIn('k1'), isFalse);
      expect(BuiltInSections.pathFor('builtin_clinics'), '/clinics');
      expect(BuiltInSections.pathFor('unknown'), isNull);

      expect(BuiltInSections.idForPageKey('schedule'), BuiltInSections.schedule);
      expect(BuiltInSections.idForPageKey('education'), BuiltInSections.meetings);
      expect(BuiltInSections.idForPageKey('meetings'), BuiltInSections.meetings);
      expect(BuiltInSections.idForPageKey('activities'), BuiltInSections.activities);
      expect(BuiltInSections.idForPageKey('clinics'), BuiltInSections.clinics);
      expect(BuiltInSections.idForPageKey('services'), BuiltInSections.services);
      expect(BuiltInSections.idForPageKey('about'), BuiltInSections.about);
      expect(BuiltInSections.idForPageKey('contact'), BuiltInSections.contact);
      expect(BuiltInSections.idForPageKey('ask'), isNull);
      expect(BuiltInSections.idForPageKey('notifications'), isNull);

      final actCat = BuiltInSections.byId(BuiltInSections.activities)!;
      const visibleLinked = CustomPage(
        id: 'p-act',
        slug: 'summer-camp',
        titleAr: 'معسكر',
        titleEn: 'Camp',
        placement: PagePlacements.section,
        categoryId: BuiltInSections.activities,
        visible: true,
      );
      const hiddenLinked = CustomPage(
        id: 'p-act-hidden',
        slug: 'hidden-camp',
        titleAr: 'مخفي',
        placement: PagePlacements.section,
        categoryId: BuiltInSections.activities,
        visible: false,
      );
      const linkOnly = CustomPage(
        id: 'p-act-link',
        slug: 'link-camp',
        titleAr: 'رابط',
        placement: PagePlacements.link,
        categoryId: BuiltInSections.activities,
        visible: true,
      );

      expect(sectionPages(BuiltInSections.activities, [visibleLinked, hiddenLinked, linkOnly]).map((p) => p.id), ['p-act']);
      expect(isCategoryNonEmpty(actCat, const [], [visibleLinked, hiddenLinked, linkOnly]), isTrue);
      expect(isCategoryNonEmpty(actCat, const [], [hiddenLinked, linkOnly]), isFalse);
      expect(isCategoryNonEmpty(actCat, const [], const []), isFalse);

      expect(BuiltInSections.isNonEmpty(BuiltInSections.activities, [visibleLinked, hiddenLinked, linkOnly]), isTrue);
      expect(BuiltInSections.isNonEmpty(BuiltInSections.activities, [hiddenLinked, linkOnly]), isFalse);
      expect(BuiltInSections.isNonEmpty(BuiltInSections.activities, const []), isFalse);
      expect(BuiltInSections.isNonEmpty('k1', _pages), isFalse);

      // Backward compatibility: custom category IDs behave identically
      const customCat = CustomCategory(id: 'k1', slug: 'youth-trips', nameAr: 'رحلات');
      expect(sectionPages('k1', _pages).map((p) => p.id), ['p3']);
      expect(isCategoryNonEmpty(customCat, const [], _pages), isTrue);
    });

    testWidgets('DocEditor(pages) offers all 7 built-in sections + custom categories; DocEditor(entries) offers only custom categories',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final b = _Backend(lists: {
        'categories': [
          AdminDoc('k1', {'nameAr': 'رحلات الشباب', 'nameEn': 'Youth trips', 'slug': 'youth-trips', 'order': 10}),
        ],
        'pages': const [],
        'entries': const [],
      });

      // 1. Pages editor offers all 7 built-in sections + custom category
      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('pages')!)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addPage-blank')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'نادي الكنيسة');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inside a section').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('field-categoryId')));
      await tester.pumpAndSettle();

      for (final sec in BuiltInSections.all) {
        expect(find.text(sec.nameEn), findsWidgets, reason: 'Expected ${sec.id} in pages category dropdown');
      }
      expect(find.text('Youth trips'), findsWidgets);

      await tester.tap(find.text('Activities & choirs').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(b.saves, isNotEmpty);
      final savedPage = b.saves.first.$3;
      expect(savedPage['placement'], PagePlacements.section);
      expect(savedPage['categoryId'], BuiltInSections.activities);
      expect(b.watchedDocs.where((p) => p.contains('builtin_')), isEmpty);
      expect(b.updates.where((u) => u.$1 == 'categories' && u.$2.startsWith('builtin_')), isEmpty);
      expect(b.deletes.where((d) => d.$1 == 'categories' && d.$2.startsWith('builtin_')), isEmpty);

      // 2. Entries editor only offers custom categories (never built-in sections)
      await tester.pumpWidget(KeyedSubtree(
        key: const ValueKey('entries-list-check'),
        child: _admin(CollectionListScreen(repo: b, def: collectionById('entries')!)),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('field-categoryId')));
      await tester.pumpAndSettle();
      expect(find.text('Youth trips'), findsWidgets);
      for (final sec in BuiltInSections.all) {
        expect(find.text(sec.nameEn), findsNothing, reason: 'Entries must not offer ${sec.id}');
      }
    });

    testWidgets('Built-in section pages render linked CustomPageCards, hide when customPages is off, and suppress EmptyState when empty',
        (tester) async {
      final builtInPages = [
        for (final sec in BuiltInSections.all)
          CustomPage(
            id: 'page-${sec.id}',
            slug: 'extra-${sec.slug}',
            titleAr: 'صفحة ${sec.nameAr}',
            titleEn: 'Extra ${sec.nameEn}',
            subtitleAr: 'وصف مختصر',
            subtitleEn: 'Short subtitle',
            placement: PagePlacements.section,
            categoryId: sec.id,
            visible: true,
          ),
      ];

      final repoAll = _BuiltInSectionRepo(
        pagesList: builtInPages,
        sections: const {Sections.clinics: true},
      );

      final (router, _) = await _pump(tester, '/church-activities', size: const Size(420, 3000), repo: repoAll);
      expect(find.byKey(const Key('sectionPage-extra-church-activities')), findsOneWidget);
      expect(find.text('Extra Activities & choirs'), findsOneWidget);

      for (final sec in BuiltInSections.all) {
        router.go('/${sec.slug}');
        await tester.pumpAndSettle();
        expect(find.byKey(Key('sectionPage-extra-${sec.slug}')), findsOneWidget, reason: '/${sec.slug}');
        expect(tester.takeException(), isNull, reason: '/${sec.slug}');
      }

      // When customPages switch is off, CustomPageCards disappear
      await _pump(
        tester,
        '/church-activities',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(pagesList: builtInPages, sections: const {Sections.customPages: false}),
      );
      expect(find.byKey(const Key('sectionPage-extra-church-activities')), findsNothing);

      // Empty primary collection + visible linked page => shows CustomPageCard and suppresses EmptyState
      final emptyActRepo = _BuiltInSectionRepo(
        pagesList: builtInPages,
        activitiesList: const [],
        clinicsList: const [],
        sections: const {Sections.clinics: true},
      );
      final (emptyRouter, _) = await _pump(tester, '/church-activities', size: const Size(420, 3000), repo: emptyActRepo);
      expect(find.byKey(const Key('sectionPage-extra-church-activities')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      emptyRouter.go('/clinics');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-extra-clinics')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      // Empty primary collection + hidden/unlinked page => EmptyState renders
      final hiddenActRepo = _BuiltInSectionRepo(
        pagesList: const [
          CustomPage(
            id: 'page-hidden',
            slug: 'extra-church-activities',
            titleAr: 'مخفي',
            placement: PagePlacements.section,
            categoryId: BuiltInSections.activities,
            visible: false,
          ),
          CustomPage(
            id: 'page-unlinked',
            slug: 'extra-clinics',
            titleAr: 'رابط',
            placement: PagePlacements.link,
            categoryId: BuiltInSections.clinics,
            visible: true,
          ),
        ],
        activitiesList: const [],
        clinicsList: const [],
        sections: const {Sections.clinics: true},
      );
      final (hiddenRouter, _) = await _pump(tester, '/church-activities', size: const Size(420, 3000), repo: hiddenActRepo);
      expect(find.byKey(const Key('sectionPage-extra-church-activities')), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);

      hiddenRouter.go('/clinics');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-extra-clinics')), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);

      // Responsive layout check at 320, 400, 1400 px in RTL Arabic and LTR English
      for (final width in [320.0, 400.0, 1400.0]) {
        for (final locale in [const Locale('ar'), const Locale('en')]) {
          await _pump(
            tester,
            '/church-activities',
            size: Size(width, 3000),
            repo: emptyActRepo,
            locale: locale,
          );
          expect(find.byKey(const Key('sectionPage-extra-church-activities')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'width=$width locale=${locale.languageCode}');
        }
      }
    });

    testWidgets('Admin CollectionListScreen(categories) shows built-in section tiles with linked pages, toggle, and edit (no delete)',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final b = _Backend(lists: {
        'categories': const [],
        'entries': const [],
        'pages': [
          AdminDoc('p-act-1', {
            'slug': 'choir-guide',
            'titleAr': 'دليل الكورال',
            'titleEn': 'Choir guide',
            'placement': 'section',
            'categoryId': BuiltInSections.activities,
            'visible': true,
          }),
        ],
      });

      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('categories')!), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('emptyCategories')), findsNothing);
      final actTile = find.byKey(const ValueKey(BuiltInSections.activities));
      expect(actTile, findsOneWidget);
      expect(find.descendant(of: actTile, matching: find.text('قسم أساسي')), findsOneWidget);
      expect(find.descendant(of: actTile, matching: find.byKey(const Key('sectionPageRow-p-act-1'))), findsOneWidget);
      expect(find.descendant(of: actTile, matching: find.text('صفحة')), findsOneWidget);
      expect(find.descendant(of: actTile, matching: find.byKey(const ValueKey('openItem-${BuiltInSections.activities}'))), findsOneWidget);

      // No delete, category visibility, or addEntryIn controls on built-in section
      expect(find.byKey(const ValueKey('delete-${BuiltInSections.activities}')), findsNothing);
      expect(find.byKey(const ValueKey('visibility-${BuiltInSections.activities}')), findsNothing);
      expect(find.byKey(const ValueKey('addEntryIn-${BuiltInSections.activities}')), findsNothing);

      // Toggle page visibility
      await tester.tap(find.byKey(const ValueKey('visibilitySectionPage-p-act-1')));
      await tester.pumpAndSettle();
      expect(b.updates.single.$1, 'pages');
      expect(b.updates.single.$2, 'p-act-1');
      expect(b.updates.single.$3, {'visible': false});

      // Tap page row opens DocEditor with built-in section pre-selected
      await tester.tap(find.byKey(const Key('sectionPageRow-p-act-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);
      final editorState = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(editorState.collect()['categoryId'], BuiltInSections.activities);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Editing linked page from CollectionListScreen(categories) enforces takenSlugs against existing pages',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final b = _Backend(lists: {
        'categories': const [],
        'entries': const [],
        'pages': [
          AdminDoc('p-act-1', {
            'slug': 'choir-guide',
            'titleAr': 'دليل الكورال',
            'titleEn': 'Choir guide',
            'placement': 'section',
            'categoryId': BuiltInSections.activities,
            'visible': true,
          }),
          AdminDoc('p-other', {
            'slug': 'existing-slug',
            'titleAr': 'صفحة موجودة',
            'titleEn': 'Existing page',
            'placement': 'link',
            'visible': true,
          }),
        ],
      });

      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('categories')!)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sectionPageRow-p-act-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-advanced')));
      await tester.pumpAndSettle();

      // Duplicate slug from another page is rejected.
      await tester.enterText(find.byKey(const ValueKey('field-slug')), 'existing-slug');
      await tester.pump();
      expect(find.text('This address is already used'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(b.saves, isEmpty);

      // Unique slug saves cleanly.
      await tester.enterText(find.byKey(const ValueKey('field-slug')), 'unique-choir-slug');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(b.saves, hasLength(1));
      expect(b.saves.single.$1, 'pages');
      expect(b.saves.single.$2, 'p-act-1');
      expect(b.saves.single.$3['slug'], 'unique-choir-slug');
      expect(tester.takeException(), isNull);
    });

    testWidgets('CollectionListScreen(categories) counts built-in tiles, searches by slug, and fits 320px English',
        (tester) async {
      tester.view.physicalSize = const Size(320, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final b = _Backend(lists: {
        'categories': const [],
        'entries': const [],
        'pages': [
          AdminDoc('p-act-1', {
            'slug': 'choir-guide',
            'titleAr': 'دليل الكورال',
            'titleEn': 'Choir guide',
            'placement': 'section',
            'categoryId': BuiltInSections.activities,
            'visible': true,
          }),
          AdminDoc('p-cli-1', {
            'slug': 'clinics-guide',
            'titleAr': 'دليل العيادات',
            'titleEn': 'Clinics guide',
            'placement': 'section',
            'categoryId': BuiltInSections.clinics,
            'visible': true,
          }),
        ],
      });

      await tester.pumpWidget(_admin(CollectionListScreen(repo: b, def: collectionById('categories')!)));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey(BuiltInSections.activities)), findsOneWidget);
      expect(find.byKey(const ValueKey(BuiltInSections.clinics)), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Search by built-in section slug matches only that built-in tile.
      await tester.enterText(find.byKey(const Key('admin-search')), 'church-activities');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(BuiltInSections.activities)), findsOneWidget);
      expect(find.byKey(const ValueKey(BuiltInSections.clinics)), findsNothing);
      expect(find.textContaining('1 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ClinicsPage with initialSpecialty does not suppress EmptyState when filtered or empty',
        (tester) async {
      const linkedClinicPage = CustomPage(
        id: 'p-cli',
        slug: 'clinics-guide',
        titleAr: 'دليل العيادات',
        titleEn: 'Clinics guide',
        placement: PagePlacements.section,
        categoryId: BuiltInSections.clinics,
        visible: true,
      );

      // 1. 0 clinics + initialSpecialty='dental' + linked page => still shows EmptyState + CustomPageCard.
      await _pump(
        tester,
        '/clinics?specialty=dental',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: const [linkedClinicPage],
          clinicsList: const [],
          sections: const {Sections.clinics: true},
        ),
      );
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byKey(const Key('sectionPage-clinics-guide')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Non-dental clinic + initialSpecialty='dental' + linked page => shows EmptyState + CustomPageCard;
      // clearing filter shows the clinic and removes EmptyState.
      await _pump(
        tester,
        '/clinics?specialty=dental',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: const [linkedClinicPage],
          clinicsList: const [
            Clinic(
              id: 'c-eye',
              specialty: 'eye',
              specialtyAr: 'رمد',
              specialtyEn: 'Ophthalmology',
              doctorName: 'د. مينا',
              active: true,
              visible: true,
            ),
          ],
          sections: const {Sections.clinics: true},
        ),
      );
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byKey(const Key('sectionPage-clinics-guide')), findsOneWidget);

      await tester.tap(find.text('All specialties'));
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('د. مينا'), findsOneWidget);
      expect(find.byKey(const Key('sectionPage-clinics-guide')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BuiltInSectionPages shows ErrorState with retry, and AsyncSection avoids EmptyState flash while loading pages',
        (tester) async {
      // 1. While customPagesProvider is still loading on an empty built-in section, AsyncSection shows skeleton, not EmptyState.
      final loadingCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(loadingCtrl.close);
      await _pump(
        tester,
        '/church-activities',
        size: const Size(420, 3000),
        settle: false,
        repo: _BuiltInSectionRepo(
          pagesStream: loadingCtrl.stream,
          activitiesList: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      loadingCtrl.add(const [
        CustomPage(
          id: 'p-act',
          slug: 'act-guide',
          titleAr: 'دليل الأنشطة',
          titleEn: 'Activities guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.activities,
          visible: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-act-guide')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      // 2. customPagesProvider error without value renders ErrorState in BuiltInSectionPages; retry recovers.
      var failPages = true;
      final errorRepo = _BuiltInSectionRepo(
        activitiesList: const [],
        pagesProviderOverride: () => failPages
            ? Stream<List<CustomPage>>.error(Exception('network error'))
            : Stream.value(const [
                CustomPage(
                  id: 'p-act',
                  slug: 'act-guide',
                  titleAr: 'دليل الأنشطة',
                  titleEn: 'Activities guide',
                  placement: PagePlacements.section,
                  categoryId: BuiltInSections.activities,
                  visible: true,
                ),
              ]),
      );
      await _pump(tester, '/church-activities', size: const Size(420, 3000), repo: errorRepo);
      expect(find.byType(ErrorState), findsOneWidget);

      failPages = false;
      await tester.tap(find.descendant(of: find.byType(ErrorState), matching: find.byIcon(Icons.refresh)));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('sectionPage-act-guide')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Empty AboutPage, PublicServicesPage, and MassSchedulePage suppress EmptyState and orphaned headings with linked pages',
        (tester) async {
      const pages = [
        CustomPage(
          id: 'p-about',
          slug: 'about-guide',
          titleAr: 'عن الكنيسة',
          titleEn: 'About guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.about,
          visible: true,
        ),
        CustomPage(
          id: 'p-services',
          slug: 'services-guide',
          titleAr: 'دليل الخدمات',
          titleEn: 'Services guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.services,
          visible: true,
        ),
        CustomPage(
          id: 'p-schedule',
          slug: 'schedule-guide',
          titleAr: 'دليل القداسات',
          titleEn: 'Schedule guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.schedule,
          visible: true,
        ),
      ];

      // 1. Empty AboutPage: no EmptyState and no orphaned sub-section headings.
      await _pump(
        tester,
        '/about',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: pages,
          milestonesList: const [],
          saintsList: const [],
          priestsList: const [],
        ),
      );
      expect(find.byKey(const Key('sectionPage-about-guide')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byKey(const ValueKey('about-milestones')), findsNothing);
      expect(find.text('Patron saints'), findsNothing);
      expect(find.text('Our priests'), findsNothing);

      // 2. Partially populated AboutPage: serving priest appears without orphaned milestones/saints headings.
      await _pump(
        tester,
        '/about',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: pages,
          milestonesList: const [],
          saintsList: const [],
          priestsList: const [
            Priest(id: 'pr1', name: 'أبونا يوحنا', nameEn: 'Fr. John'),
          ],
        ),
      );
      expect(find.byKey(const ValueKey('aboutCard-pr1')), findsOneWidget);
      expect(find.text('Our priests'), findsOneWidget);
      expect(find.byKey(const Key('sectionPage-about-guide')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byKey(const ValueKey('about-milestones')), findsNothing);
      expect(find.text('Patron saints'), findsNothing);

      // 3. Empty PublicServicesPage: no orphaned facilities heading and no EmptyState.
      await _pump(
        tester,
        '/public-services',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: pages,
          facilitiesList: const [],
          sections: const {Sections.clinics: true},
        ),
      );
      expect(find.byKey(const Key('sectionPage-services-guide')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Facilities & services'), findsNothing);

      // 4. Empty MassSchedulePage: no EmptyState and no empty NextMassCard/schedule headings.
      await _pump(
        tester,
        '/mass-schedule',
        size: const Size(420, 3000),
        repo: _BuiltInSectionRepo(
          pagesList: pages,
          liturgiesList: const [],
          seasonsList: const [],
        ),
      );
      expect(find.byKey(const Key('sectionPage-schedule-guide')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Regular schedule'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MassSchedulePage waits on customPages loading without flashing NextMassCard or EmptyState',
        (tester) async {
      final loadingCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(loadingCtrl.close);
      await _pump(
        tester,
        '/mass-schedule',
        size: const Size(420, 3000),
        settle: false,
        repo: _BuiltInSectionRepo(
          pagesStream: loadingCtrl.stream,
          liturgiesList: const [],
          seasonsList: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(NextMassCard), findsNothing);
      expect(find.text('No upcoming liturgies this week'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);

      loadingCtrl.add(const [
        CustomPage(
          id: 'p-schedule',
          slug: 'schedule-guide',
          titleAr: 'دليل القداسات',
          titleEn: 'Schedule guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.schedule,
          visible: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-schedule-guide')), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(NextMassCard), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MassSchedulePage renders NextMassCard and EmptyState once empty customPages resolves',
        (tester) async {
      final emptyCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(emptyCtrl.close);
      await _pump(
        tester,
        '/mass-schedule',
        size: const Size(420, 3000),
        settle: false,
        repo: _BuiltInSectionRepo(
          pagesStream: emptyCtrl.stream,
          liturgiesList: const [],
          seasonsList: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(NextMassCard), findsNothing);
      expect(find.byType(EmptyState), findsNothing);

      emptyCtrl.add(const []);
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.byType(NextMassCard), findsOneWidget);
      expect(find.text('No upcoming liturgies this week'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.byType(EmptyState), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AboutPage waits on customPages loading without flashing Priests EmptyState', (tester) async {
      final loadingCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(loadingCtrl.close);
      await _pump(
        tester,
        '/about',
        size: const Size(420, 3000),
        settle: false,
        repo: _BuiltInSectionRepo(
          pagesStream: loadingCtrl.stream,
          priestsList: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Our priests'), findsNothing);

      loadingCtrl.add(const [
        CustomPage(
          id: 'p-about',
          slug: 'about-guide',
          titleAr: 'عن الكنيسة',
          titleEn: 'About guide',
          placement: PagePlacements.section,
          categoryId: BuiltInSections.about,
          visible: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sectionPage-about-guide')), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Our priests'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AboutPage renders Priests EmptyState once empty customPages resolves', (tester) async {
      final emptyCtrl = StreamController<List<CustomPage>>.broadcast();
      addTearDown(emptyCtrl.close);
      await _pump(
        tester,
        '/about',
        size: const Size(420, 3000),
        settle: false,
        repo: _BuiltInSectionRepo(
          pagesStream: emptyCtrl.stream,
          priestsList: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Our priests'), findsNothing);

      emptyCtrl.add(const []);
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.text('Our priests'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'AsyncSection with SectionTitle preserves header on error and unlinked loading, suppresses on linked loading',
        (tester) async {
      tester.view.physicalSize = const Size(420, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const linkedAboutPage = CustomPage(
        id: 'p-about',
        slug: 'about-guide',
        titleAr: 'عن الكنيسة',
        titleEn: 'About guide',
        placement: PagePlacements.section,
        categoryId: BuiltInSections.about,
        visible: true,
      );

      Widget harness(
        String id, {
        required Stream<List<String>> itemsStream,
        required _BuiltInSectionRepo repo,
        bool scoped = true,
      }) =>
          ProviderScope(
            key: ValueKey(id),
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              localeProvider.overrideWith(_English.new),
              _asyncSectionTestProvider.overrideWith((_) => itemsStream),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: PageBody(
                  header: scoped
                      ? const CustomizablePageHeader(pageKey: CustomizablePages.about, title: 'About')
                      : const PageHeader(title: 'Plain'),
                  children: [
                    AsyncSection<List<String>>(
                      provider: _asyncSectionTestProvider,
                      retry: _asyncSectionTestProvider,
                      header: const SectionTitle('Test Heading', key: Key('async-header')),
                      isEmpty: (d) => d.isEmpty,
                      builder: (_, items) => Column(children: [for (final s in items) Text(s)]),
                    ),
                  ],
                ),
              ),
            ),
          );

      // (a1) Provider error without linked pages preserves header + ErrorState.
      await tester.pumpWidget(harness(
        'err-unlinked',
        itemsStream: Stream<List<String>>.error(Exception('boom')),
        repo: _BuiltInSectionRepo(pagesList: const []),
        scoped: false,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('async-header')), findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);

      // (a2) Provider error with linked pages STILL preserves header + ErrorState.
      await tester.pumpWidget(harness(
        'err-linked',
        itemsStream: Stream<List<String>>.error(Exception('boom')),
        repo: _BuiltInSectionRepo(pagesList: const [linkedAboutPage]),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('async-header')), findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);

      // (b) Loading with no linked pages preserves header + SkeletonList.
      final unlinkedCtrl = StreamController<List<String>>.broadcast();
      addTearDown(unlinkedCtrl.close);
      await tester.pumpWidget(harness(
        'load-unscoped',
        itemsStream: unlinkedCtrl.stream,
        repo: _BuiltInSectionRepo(pagesList: const []),
        scoped: false,
      ));
      await tester.pump();
      expect(find.byKey(const Key('async-header')), findsOneWidget);
      expect(find.byType(SkeletonList), findsOneWidget);

      await tester.pumpWidget(harness(
        'load-scoped-empty-pages',
        itemsStream: unlinkedCtrl.stream,
        repo: _BuiltInSectionRepo(pagesList: const []),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('async-header')), findsOneWidget);
      expect(find.byType(SkeletonList), findsOneWidget);

      // (c) Loading with a linked custom page suppresses header so empty sub-section never flashes a heading.
      final linkedCtrl = StreamController<List<String>>.broadcast();
      addTearDown(linkedCtrl.close);
      await tester.pumpWidget(harness(
        'load-linked',
        itemsStream: linkedCtrl.stream,
        repo: _BuiltInSectionRepo(pagesList: const [linkedAboutPage]),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('async-header')), findsNothing);
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4 PR3: Preview & Duplicate', () {
    test('copies content, prefixes titles without double prefix, resets visible/featured to false, preserves placement/categoryId/order, strips metadata', () {
      final heading = const PageBlock(type: BlockTypes.heading, textAr: 'العنوان', textEn: 'Heading').encode();
      final donation = const PageBlock(type: BlockTypes.donation, account: 'CIB 123', textAr: 'ملاحظات').encode();
      final sourceBlocks = <dynamic>[heading, donation];
      final source = <String, dynamic>{
        'titleAr': 'دليل الكورال',
        'titleEn': 'Choir Guide',
        'subtitleAr': 'مقدمة',
        'subtitleEn': 'Intro',
        'slug': 'choir-guide',
        'blocks': sourceBlocks,
        'placement': PagePlacements.section,
        'categoryId': BuiltInSections.activities,
        'showInNav': false,
        'featured': true,
        'visible': true,
        'order': 20,
        'updatedAt': DateTime.utc(2026, 11, 19),
        'updatedBy': 'admin@example.org',
        'deletedAt': DateTime.utc(2026, 11, 19),
      };

      final res = buildDuplicatePageDefaults(source, takenSlugs: const {});
      final d = res.defaults;
      expect(res.droppedOwnedImage, isFalse);
      expect(d['titleAr'], 'نسخة من دليل الكورال');
      expect(d['titleEn'], 'Copy of Choir Guide');
      expect(d['subtitleAr'], 'مقدمة');
      expect(d['subtitleEn'], 'Intro');
      expect(d['slug'], 'choir-guide-copy');
      expect(d['blocks'], [heading, donation]);
      (d['blocks'] as List).add('extra');
      expect(sourceBlocks.length, 2);
      expect(d['placement'], PagePlacements.section);
      expect(d['categoryId'], BuiltInSections.activities);
      expect(d['showInNav'], isFalse);
      expect(d['featured'], isFalse);
      expect(d['visible'], isFalse);
      expect(d['order'], 20);
      expect(d.containsKey('updatedAt'), isFalse);
      expect(d.containsKey('updatedBy'), isFalse);
      expect(d.containsKey('deletedAt'), isFalse);

      // Already-prefixed page must not double-prefix; empty EN title stays empty; long titles clamp to 200.
      final alreadyPrefixed = buildDuplicatePageDefaults({
        'titleAr': 'نسخة من دليل الكورال',
        'titleEn': 'Copy of Choir Guide',
        'slug': 'choir-guide-copy',
        'showInNav': true,
      }, takenSlugs: const {'choir-guide-copy'});
      expect(alreadyPrefixed.defaults['titleAr'], 'نسخة من دليل الكورال');
      expect(alreadyPrefixed.defaults['titleEn'], 'Copy of Choir Guide');
      expect(alreadyPrefixed.defaults['placement'], PagePlacements.nav);
      expect(alreadyPrefixed.defaults['showInNav'], isTrue);

      final blankEn = buildDuplicatePageDefaults({'titleAr': 'صفحة', 'titleEn': '', 'slug': 'page-1'}, takenSlugs: const {});
      expect(blankEn.defaults['titleEn'], '');

      final long200 = 'أ' * 200;
      final long200En = 'A' * 200;
      final clamped = buildDuplicatePageDefaults({'titleAr': long200, 'titleEn': long200En, 'slug': 'long'}, takenSlugs: const {});
      expect((clamped.defaults['titleAr'] as String).length, 200);
      expect((clamped.defaults['titleAr'] as String).startsWith('نسخة من '), isTrue);
      expect((clamped.defaults['titleEn'] as String).length, 200);
      expect((clamped.defaults['titleEn'] as String).startsWith('Copy of '), isTrue);
    });

    test('generates unique valid slugs across collisions, -copy-copy avoidance, 60-char boundary hyphens, and blank/invalid source slugs', () {
      final col2 = buildDuplicatePageDefaults(
        {'titleAr': 'دليل الكورال', 'slug': 'choir-guide'},
        takenSlugs: const {'choir-guide', 'choir-guide-copy'},
      );
      expect(col2.defaults['slug'], 'choir-guide-copy-2');

      final noCopyCopy = buildDuplicatePageDefaults(
        {'titleAr': 'نسخة من دليل الكورال', 'slug': 'choir-guide-copy'},
        takenSlugs: const {'choir-guide', 'choir-guide-copy'},
      );
      expect(noCopyCopy.defaults['slug'], 'choir-guide-copy-2');

      final next3 = buildDuplicatePageDefaults(
        {'titleAr': 'نسخة من دليل الكورال', 'slug': 'choir-guide-copy-2'},
        takenSlugs: const {'choir-guide', 'choir-guide-copy', 'choir-guide-copy-2'},
      );
      expect(next3.defaults['slug'], 'choir-guide-copy-3');

      final slug60 = 'a' * 60;
      final res60 = buildDuplicatePageDefaults({'titleAr': 'طويل', 'slug': slug60}, takenSlugs: {slug60});
      final s60 = res60.defaults['slug'] as String;
      expect(isValidSlug(s60), isTrue);
      expect(s60.length, lessThanOrEqualTo(slugMaxLength));
      expect(s60.endsWith('-copy'), isTrue);
      expect(s60 == slug60, isFalse);

      final boundarySlug = '${'a' * 54}-bbbbb';
      expect(boundarySlug.length, 60);
      final resBoundary = buildDuplicatePageDefaults(
        {'titleAr': 'حد', 'slug': boundarySlug},
        takenSlugs: {boundarySlug},
      );
      expect(resBoundary.defaults['slug'], '${'a' * 54}-copy');
      expect(isValidSlug(resBoundary.defaults['slug'] as String), isTrue);

      final invalidSlug = buildDuplicatePageDefaults(
        {'titleAr': 'حجز رحلة', 'slug': 'INVALID SLUG!'},
        takenSlugs: const {'hgz-rhlh', 'nskh-mn-hgz-rhlh'},
      );
      final fallback = invalidSlug.defaults['slug'] as String;
      expect(isValidSlug(fallback), isTrue);
      expect(const {'hgz-rhlh', 'nskh-mn-hgz-rhlh'}.contains(fallback), isFalse);
    });

    test('copies external url cover image safely and drops owned inline/storage or invalid cover images', () {
      final ext = buildDuplicatePageDefaults({
        'titleAr': 'صورة خارجية',
        'slug': 'ext-img',
        'image': {'source': MediaSource.url, 'url': 'https://example.com/a.jpg', 'alt': 'Cover'},
      }, takenSlugs: const {});
      expect(ext.droppedOwnedImage, isFalse);
      expect(ext.defaults['image'], {'source': MediaSource.url, 'url': 'https://example.com/a.jpg', 'alt': 'Cover'});

      final inline = buildDuplicatePageDefaults({
        'titleAr': 'صورة مرفوعة',
        'slug': 'inline-img',
        'image': {'source': MediaSource.inline, 'mediaId': 'abc123', 'alt': 'Cover'},
      }, takenSlugs: const {});
      expect(inline.droppedOwnedImage, isTrue);
      expect(inline.defaults['image'], isNull);

      final storage = buildDuplicatePageDefaults({
        'titleAr': 'صورة تخزين',
        'slug': 'storage-img',
        'image': {'source': MediaSource.storage, 'url': 'https://example.com/a.jpg', 'mediaId': 'abc123'},
      }, takenSlugs: const {});
      expect(storage.droppedOwnedImage, isTrue);
      expect(storage.defaults['image'], isNull);

      final bad = buildDuplicatePageDefaults({
        'titleAr': 'رابط فاسد',
        'slug': 'bad-img',
        'image': {'source': MediaSource.url, 'url': 'javascript:alert(1)'},
      }, takenSlugs: const {});
      expect(bad.droppedOwnedImage, isFalse);
      expect(bad.defaults['image'], isNull);

      final none = buildDuplicatePageDefaults({'titleAr': 'بلا صورة', 'slug': 'no-img'}, takenSlugs: const {});
      expect(none.droppedOwnedImage, isFalse);
      expect(none.defaults['image'], isNull);
    });

    testWidgets('PageBlockView delegates button and link taps to onLinkTap when provided without navigating', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_admin(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageBlockView(
              block: const PageBlock(type: BlockTypes.button, textEn: 'Mass times', url: '/mass-schedule'),
              onLinkTap: tapped.add,
            ),
            PageBlockView(
              block: const PageBlock(type: BlockTypes.link, textEn: 'External link', url: 'https://example.com'),
              onLinkTap: tapped.add,
            ),
          ],
        ),
      ));
      await tester.tap(find.text('Mass times'));
      await tester.tap(find.text('External link'));
      await tester.pump();
      expect(tapped, ['/mass-schedule', 'https://example.com']);
    });
  });
}

final _asyncSectionTestProvider = StreamProvider<List<String>>((_) => const Stream.empty());

class _BuiltInSectionRepo extends _Repo {
  final List<CustomPage> pagesList;
  final Stream<List<CustomPage>>? pagesStream;
  final Stream<List<CustomPage>> Function()? pagesProviderOverride;
  final List<Activity>? activitiesList;
  final List<Clinic>? clinicsList;
  final List<Facility>? facilitiesList;
  final List<Milestone>? milestonesList;
  final List<Saint>? saintsList;
  final List<Priest>? priestsList;
  final List<Liturgy>? liturgiesList;
  final List<Season>? seasonsList;
  _BuiltInSectionRepo({
    this.pagesList = const [],
    this.pagesStream,
    this.pagesProviderOverride,
    this.activitiesList,
    this.clinicsList,
    this.facilitiesList,
    this.milestonesList,
    this.saintsList,
    this.priestsList,
    this.liturgiesList,
    this.seasonsList,
    Map<String, bool> sections = const {},
  }) : super(sections);

  @override
  Stream<List<CustomPage>> pages() =>
      pagesProviderOverride?.call() ?? pagesStream ?? Stream.value(pagesList);
  @override
  Stream<List<Activity>> activities() => activitiesList == null ? super.activities() : Stream.value(activitiesList!);
  @override
  Stream<List<Clinic>> clinics() => clinicsList == null ? super.clinics() : Stream.value(clinicsList!);
  @override
  Stream<List<Facility>> facilities() => facilitiesList == null ? super.facilities() : Stream.value(facilitiesList!);
  @override
  Stream<List<Milestone>> milestones() => milestonesList == null ? super.milestones() : Stream.value(milestonesList!);
  @override
  Stream<List<Saint>> saints() => saintsList == null ? super.saints() : Stream.value(saintsList!);
  @override
  Stream<List<Priest>> priests() => priestsList == null ? super.priests() : Stream.value(priestsList!);
  @override
  Stream<List<Liturgy>> liturgies() => liturgiesList == null ? super.liturgies() : Stream.value(liturgiesList!);
  @override
  Stream<List<Season>> seasons() => seasonsList == null ? super.seasons() : Stream.value(seasonsList!);
}

class _StreamEntriesBackend extends _Backend {
  final Stream<List<AdminDoc>> entriesStream;
  _StreamEntriesBackend({required List<AdminDoc> cats, required this.entriesStream})
      : super(lists: {'categories': cats});

  @override
  Stream<List<AdminDoc>> watch(String collection) =>
      collection == 'entries' ? entriesStream : super.watch(collection);
}

class _StreamContactBackend extends _Backend {
  final Stream<AdminDoc?> contactStream;
  _StreamContactBackend(this.contactStream);

  @override
  Stream<AdminDoc?> watchDoc(String path) => path == 'settings/contact' ? contactStream : super.watchDoc(path);
}

class _ControlledPagesRepo extends _Repo {
  final Stream<List<CustomPage>> _pagesStream;
  final List<CategoryEntry> _customEntries;
  final List<CustomCategory>? _customCats;
  _ControlledPagesRepo(this._pagesStream, {required List<CategoryEntry> entries, List<CustomCategory>? cats})
      : _customEntries = entries,
        _customCats = cats;

  @override
  Stream<List<CustomCategory>> categories() => Stream.value(_customCats ?? _cats);

  @override
  Stream<List<CategoryEntry>> entries() => Stream.value(_customEntries);

  @override
  Stream<List<CustomPage>> pages() => _pagesStream;
}

class _FailSubsequentPagesReadBackend extends _Backend {
  int _pagesWatchCount = 0;
  _FailSubsequentPagesReadBackend({super.lists});

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    if (collection == 'pages') {
      _pagesWatchCount++;
      if (_pagesWatchCount >= 2) {
        return Stream<List<AdminDoc>>.error(StateError('timeout'));
      }
    }
    return super.watch(collection);
  }
}

