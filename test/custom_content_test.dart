// ADR-027 / ADR-028: admin-defined categories and their items, custom pages
// (blocks, donation info, link targets), contact categories (bookings,
// anonymous complaints / suggestions) and the admin inbox.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart' show Sections;
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/contact_admin.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/widgets/feature_gate.dart';
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
      showInNav: true, blocks: [
        PageBlock(type: BlockTypes.heading, textAr: 'المبنى الجديد', textEn: 'The new building'),
        PageBlock(type: BlockTypes.paragraph, textAr: 'نص', textEn: 'Every gift helps.'),
        PageBlock(type: BlockTypes.button, textEn: 'Contact us', url: '/contact'),
        PageBlock(type: BlockTypes.link, textEn: 'Diocese site', url: 'https://example.org'),
        PageBlock(type: BlockTypes.donation, account: 'CIB 1000200030004', instapay: 'church@instapay', wallet: '01012345678',
            textEn: 'Write "building" in the note.'),
        PageBlock(type: BlockTypes.button, textEn: 'No link'), // empty: not rendered
      ]),
  CustomPage(id: 'p2', slug: 'draft', titleAr: 'مسودة', visible: false),
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

Future<(GoRouter, _Repo)> _pump(WidgetTester tester, String path, {Size size = const Size(420, 3000), _Repo? repo}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Repo();
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(r),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 1, 12 * 60).toUtc())),
    localeProvider.overrideWith(_English.new),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  router.go(path);
  await tester.pumpAndSettle();
  return (router, r);
}

/// In-memory admin backend.
class _Backend extends AdminBackend {
  _Backend({Map<String, List<AdminDoc>> lists = const {}, Map<String, Map<String, dynamic>> docs = const {}})
      : _lists = {...lists},
        _docs = {...docs};
  final Map<String, List<AdminDoc>> _lists;
  final Map<String, Map<String, dynamic>> _docs;
  final updates = <(String, String, Map<String, dynamic>)>[];
  final deletes = <(String, String)>[];
  final savedDocs = <String, Map<String, dynamic>>{};

  @override
  String get actor => 'admin@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(_lists[collection] ?? const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) =>
      Stream.value(_docs[path] == null ? null : AdminDoc(path.split('/').last, _docs[path]!));
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
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

Widget _admin(Widget child) => MaterialApp(
      locale: const Locale('en'),
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
      expect(publicPages(_pages).map((p) => p.slug), ['donate']);
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
      await tester.tap(find.byTooltip('Delete'));
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
      await tester.enterText(find.byKey(const ValueKey('field-slug')), 'donate-2');
      await tester.pump();
      expect(find.text('This address is already used'), findsOneWidget);
    });
  });
}
