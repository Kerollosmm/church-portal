import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/document_lang.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/pages/about_page.dart';
import 'package:church_portal/ui/pages/activities_page.dart';
import 'package:church_portal/ui/pages/education_page.dart';
import 'package:church_portal/ui/pages/home_page.dart';
import 'package:church_portal/ui/pages/public_services_page.dart';
import 'package:church_portal/ui/widgets/remind_me.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

SeedData _seed({Map<String, bool> sections = const {}, Map<String, dynamic> featuresExtra = const {}}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  f['sections'] = {...(f['sections'] as Map), ...sections};
  f.addAll(featuresExtra);
  raw['settings']['features'] = f;
  return SeedData(raw);
}

class _FixedLocale extends LocaleNotifier {
  final Locale locale;
  _FixedLocale(this.locale);
  @override
  Locale build() => locale;
}

class _AuditRepo extends SeedRepository {
  bool failSettingsOnce = false;
  int settingsCalls = 0;
  final ChurchSettings? overrideSettings;
  final List<CustomCategory>? overrideCategories;
  final List<CategoryEntry>? overrideEntries;
  final List<Meeting>? overrideMeetings;
  final List<Activity>? overrideActivities;
  final List<Facility>? overrideFacilities;

  _AuditRepo(
    super.seed, {
    this.failSettingsOnce = false,
    this.overrideSettings,
    this.overrideCategories,
    this.overrideEntries,
    this.overrideMeetings,
    this.overrideActivities,
    this.overrideFacilities,
  });

  @override
  Stream<ChurchSettings> settings() {
    settingsCalls++;
    if (failSettingsOnce && settingsCalls == 1) {
      return Stream.error(StateError('settings unavailable'));
    }
    return Stream.value(overrideSettings ?? super.seed.settings);
  }

  @override
  Stream<List<CustomCategory>> categories() =>
      overrideCategories != null ? Stream.value(overrideCategories!) : super.categories();

  @override
  Stream<List<CategoryEntry>> entries() =>
      overrideEntries != null ? Stream.value(overrideEntries!) : super.entries();

  @override
  Stream<List<Meeting>> meetings() =>
      overrideMeetings != null ? Stream.value(overrideMeetings!) : super.meetings();

  @override
  Stream<List<Activity>> activities() =>
      overrideActivities != null ? Stream.value(overrideActivities!) : super.activities();

  @override
  Stream<List<Facility>> facilities() =>
      overrideFacilities != null ? Stream.value(overrideFacilities!) : super.facilities();
}

class _AuditAdminBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> collections;
  final Map<String, Map<String, dynamic>> docs;
  final List<({String collection, String? id, Map<String, dynamic> data})> savedCollectionDocs = [];
  final List<({String path, Map<String, dynamic> data})> savedSingleDocs = [];

  _AuditAdminBackend({
    Map<String, List<AdminDoc>>? collections,
    Map<String, Map<String, dynamic>>? docs,
  })  : collections = collections ?? {},
        docs = docs ?? {};

  @override
  String get actor => 'owner@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(collections[collection] ?? const []);

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final d = docs[path];
    return Stream.value(d == null ? null : AdminDoc(path.split('/').last, d));
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    savedCollectionDocs.add((collection: collection, id: id, data: Map<String, dynamic>.from(data)));
    return id ?? 'new-id';
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    savedSingleDocs.add((path: path, data: Map<String, dynamic>.from(data)));
    docs[path] = {...?docs[path], ...data};
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
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  Widget child, {
  required ContentRepository repo,
  Locale locale = const Locale('en'),
  Size size = const Size(1200, 3000),
  DateTime? now,
  PushSettings? pushSettings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    nowProvider.overrideWith((ref) => Stream.value(now ?? CairoTime.at(2026, 11, 6, 12 * 60).toUtc())),
    localeProvider.overrideWith(() => _FixedLocale(locale)),
    if (pushSettings != null) pushSettingsProvider.overrideWithValue(pushSettings),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('1. Home hero error state', () {
    testWidgets('shows ErrorState with retry when settings fail and recovers on retry', (tester) async {
      final repo = _AuditRepo(_seed(), failSettingsOnce: true);
      await _pumpPage(tester, const HomePage(), repo: repo, size: const Size(1000, 2400));

      expect(find.byKey(const Key('heroError')), findsOneWidget);
      expect(find.byKey(const Key('heroTitle')), findsNothing);

      await tester.tap(find.descendant(of: find.byKey(const Key('heroError')), matching: find.byIcon(Icons.refresh)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('heroError')), findsNothing);
      expect(find.byKey(const Key('heroTitle')), findsOneWidget);
    });
  });

  group('2. Home directory custom sections', () {
    testWidgets('includes non-empty custom sections in directory and hides when customSections is off', (tester) async {
      const cats = [
        CustomCategory(id: 'c1', slug: 'trips', nameAr: 'رحلات', nameEn: 'Parish trips', introEn: 'Monthly trips'),
        CustomCategory(id: 'c2', slug: 'empty', nameAr: 'فارغ', nameEn: 'Empty cat'),
        CustomCategory(id: 'c3', slug: 'hidden', nameAr: 'مخفي', nameEn: 'Hidden cat', visible: false),
      ];
      const entries = [
        CategoryEntry(id: 'e1', categoryId: 'c1', titleAr: 'رحلة', titleEn: 'Trip 1'),
      ];

      final repoOn = _AuditRepo(_seed(), overrideCategories: cats, overrideEntries: entries);
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(repoOn),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 6, 12 * 60).toUtc())),
        localeProvider.overrideWith(() => _FixedLocale(const Locale('en'))),
      ]);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('en')),
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dir-cat-trips')), findsOneWidget);
      expect(find.byKey(const ValueKey('dir-cat-empty')), findsNothing);
      expect(find.byKey(const ValueKey('dir-cat-hidden')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('dir-cat-trips')));
      await tester.tap(find.byKey(const ValueKey('dir-cat-trips')));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/section/trips');

      // Turned off -> omitted
      final repoOff = _AuditRepo(
        _seed(sections: {Sections.customSections: false}),
        overrideCategories: cats,
        overrideEntries: entries,
      );
      await _pumpPage(tester, const HomePage(), repo: repoOff, size: const Size(1200, 4000));
      expect(find.byKey(const ValueKey('dir-cat-trips')), findsNothing);
    });
  });

  group('3. /about empty card & milestones route gate', () {
    testWidgets('omits empty history card when bishop and history are blank', (tester) async {
      final repo = _AuditRepo(
        _seed(),
        overrideSettings: const ChurchSettings(
          nameAr: 'كنيسة',
          nameEn: 'Church',
          addressAr: 'عنوان',
          addressEn: 'Address',
          altars: [Altar(nameAr: 'المذبح الرئيسي', nameEn: 'Main altar', kind: 'main')],
        ),
      );
      await _pumpPage(tester, const AboutPage(), repo: repo);
      expect(find.byKey(const Key('aboutHistoryCard')), findsNothing);
      expect(find.text('Main altar'), findsOneWidget);
    });

    test('routeEnabled(/about) respects milestones and aboutMilestones', () {
      const onlyMilestones = FeatureSettings(sections: {
        Sections.history: false,
        Sections.saints: false,
        Sections.priests: false,
        Sections.departedPriests: false,
        Sections.milestones: true,
      });
      expect(onlyMilestones.routeEnabled('/about'), isTrue);
      expect(onlyMilestones.copyWith(aboutMilestones: false).routeEnabled('/about'), isFalse);
      expect(sectionsForPath('/about'), contains(Sections.milestones));
    });
  });

  group('4. /church-education RemindMeButton', () {
    testWidgets('renders RemindMeButton on weekly meeting cards with weekday and start', (tester) async {
      final repo = _AuditRepo(
        _seed(),
        overrideMeetings: const [
          Meeting(id: 'm1', stage: 'youth', nameAr: 'اجتماع الشباب', nameEn: 'Youth meeting', weekday: 5, start: '19:00', end: '21:00'),
          Meeting(id: 'm2', stage: 'youth', nameAr: 'بدون وقت', nameEn: 'No start time', weekday: 5, start: ''),
        ],
      );
      await _pumpPage(
        tester,
        const EducationPage(),
        repo: repo,
        pushSettings: const PushSettings(enabled: true, reminderSources: {'lit', 'mtg'}),
      );
      expect(find.byType(RemindMeButton), findsOneWidget);
      final btn = tester.widget<RemindMeButton>(find.byType(RemindMeButton));
      expect(btn.eventKey, 'meeting-m1');
      expect(btn.recurring, isTrue);
      // The calendar entry ends at the meeting's real end (19:00–21:00), not +1 h.
      expect(btn.endsAt!.difference(btn.startsAt), const Duration(hours: 2));
    });
  });

  group('5. /church-activities category headers & filter chips', () {
    testWidgets('shows category headers and filters via chips', (tester) async {
      final repo = _AuditRepo(
        _seed(),
        overrideActivities: const [
          Activity(id: 'a1', category: 'scouts', titleAr: 'الكشافة', titleEn: 'Scouts group'),
          Activity(id: 'a2', category: 'deacons', titleAr: 'الشمامسة', titleEn: 'Deacons class'),
          Activity(id: 'a3', category: 'bible', titleAr: 'درس الكتاب', titleEn: 'Bible class'),
        ],
      );
      await _pumpPage(tester, const ActivitiesPage(), repo: repo, locale: const Locale('en'));

      expect(find.byKey(const Key('activityCat-all')), findsOneWidget);
      expect(find.byKey(const Key('activityCat-scouts')), findsOneWidget);
      expect(find.byKey(const Key('activityCat-deacons')), findsOneWidget);
      expect(find.byKey(const Key('activityCat-bible')), findsOneWidget);
      expect(find.byKey(const Key('activityHeader-scouts')), findsOneWidget);
      expect(find.byKey(const Key('activityHeader-deacons')), findsOneWidget);
      expect(find.byKey(const Key('activityHeader-bible')), findsOneWidget);

      await tester.tap(find.byKey(const Key('activityCat-scouts')));
      await tester.pumpAndSettle();
      expect(find.text('Scouts group'), findsOneWidget);
      expect(find.text('Deacons class'), findsNothing);
      expect(find.byKey(const Key('activityHeader-deacons')), findsNothing);

      await tester.tap(find.byKey(const Key('activityCat-all')));
      await tester.pumpAndSettle();
      expect(find.text('Deacons class'), findsOneWidget);
      expect(find.text('Bible class'), findsOneWidget);
    });
  });

  group('6. /public-services WhatsApp button', () {
    testWidgets('shows WhatsApp for mobile phone or explicit whatsapp, not for landline alone', (tester) async {
      final repo = _AuditRepo(
        _seed(),
        overrideFacilities: const [
          Facility(id: 'f1', type: 'service', nameAr: 'خدمة موبايل', nameEn: 'Mobile svc', phone: '01012345678'),
          Facility(id: 'f2', type: 'nursery', nameAr: 'أرضي فقط', nameEn: 'Landline only', phone: '035551234'),
          Facility(
            id: 'f3',
            type: 'halls',
            nameAr: 'واتساب مخصص',
            nameEn: 'Explicit WA',
            phone: '035559999',
            details: ItemDetails(whatsapp: '01234567890'),
          ),
        ],
      );
      await _pumpPage(tester, const PublicServicesPage(), repo: repo);

      final cards = find.byType(Card);
      expect(cards, findsNWidgets(3));
      expect(find.descendant(of: cards.at(0), matching: find.text('WhatsApp')), findsOneWidget);
      expect(find.descendant(of: cards.at(1), matching: find.text('WhatsApp')), findsNothing);
      expect(find.descendant(of: cards.at(1), matching: find.textContaining('Call')), findsOneWidget);
      expect(find.descendant(of: cards.at(2), matching: find.text('WhatsApp')), findsOneWidget);
    });
  });

  group('7. /readings route meta & ?tab= sync', () {
    testWidgets('sets route meta and syncs tab selection to ?tab= preserving lang=en', (tester) async {
      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-11-08': jsonEncode({
          'date': '2026-11-08',
          'coptic': '29/2/1743',
          'titleAr': 'يوم',
          'titleEn': 'Day',
          'sections': [],
        }),
      });
      final applied = <DocumentHeadSpec>[];
      debugOnRouteMeta = applied.add;
      addTearDown(() => debugOnRouteMeta = null);

      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(_seed())),
        nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 8, 12 * 60).toUtc())),
        localeProvider.overrideWith(() => _FixedLocale(const Locale('en'))),
      ]);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('en')),
          routerConfig: router,
        ),
      ));
      router.go('/readings/2026-11-08?lang=en');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(applied.last.canonicalUrl, 'https://maximos-domadios-church.web.app/readings/2026-11-08');
      expect(applied.last.noIndex, isFalse);

      await tester.tap(find.byKey(const Key('verseTabButton')));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/readings/2026-11-08?lang=en&tab=verse');

      await tester.tap(find.byKey(const Key('katamerosTabButton')));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/readings/2026-11-08?lang=en&tab=katameros');

      // Invalid date -> noindex
      router.go('/readings/not-a-date?lang=en');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(applied.last.noIndex, isTrue);
      expect(applied.last.canonicalUrl, isNull);
    });
  });

  group('8. Alerts editor warns when endsAt is blank on active alert', () {
    testWidgets('shows non-blocking warning when active is true and endsAt is empty', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final alertsDef = collectionById('alerts')!;
      var saved = false;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: DocEditor(
            title: alertsDef.labelEn,
            fields: alertsDef.fields,
            def: alertsDef,
            data: const {'titleAr': 'تنويه هام', 'active': false, 'visible': true},
            onSave: (_) async {
              saved = true;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alert-no-endsAt-warning')), findsNothing);

      // Enable active -> warning appears
      await tester.tap(find.byKey(const ValueKey('field-active')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-no-endsAt-warning')), findsOneWidget);

      // Saving still succeeds (non-blocking)
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
    });
  });

  group('9. Season settings warns before deleting in-use venue/audience key', () {
    testWidgets('prompts confirmation when deleting an in-use venue key and keeps on cancel', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AuditAdminBackend(
        docs: {
          'settings/features': {
            'venues': [
              'main\u001fالكنيسة الكبرى\u001fMain church',
              'unused\u001fغير مستخدم\u001fUnused hall',
            ],
          },
        },
        collections: {
          'liturgies': [
            AdminDoc('l1', {'nameAr': 'قداس', 'venue': 'main'}),
          ],
        },
      );

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AdminDashboard(
            repo: repo,
            uid: 'u-own',
            email: 'owner@church.org',
            role: AdminRoles.owner,
            initial: 'seasonSettings',
            onSignOut: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Remove unused venue -> immediate removal without dialog
      final removeButtons = find.widgetWithText(TextButton, 'Remove');
      expect(removeButtons, findsNWidgets(2));
      await tester.ensureVisible(removeButtons.at(1));
      await tester.tap(removeButtons.at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programOptionInUseDialog')), findsNothing);
      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);

      // Remove in-use 'main' venue -> dialog appears
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Remove').first);
      await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programOptionInUseDialog')), findsOneWidget);

      // Cancel keeps the row
      await tester.tap(find.byKey(const Key('programOptionInUse-cancel')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);

      // Confirm removes the row
      await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('programOptionInUse-confirm')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Remove'), findsNothing);
    });
  });

  group('10. Advanced owner tab switching preserves unsaved APK edits', () {
    testWidgets('switching tabs keeps APK edits and UnsavedGuard dirty state', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AuditAdminBackend(docs: {
        'settings/features': {'errorReporting': true, 'installApkVersion': '1.0.0'},
      });

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AdminDashboard(
            repo: repo,
            uid: 'u-own',
            email: 'owner@church.org',
            role: AdminRoles.owner,
            initial: 'advanced',
            onSignOut: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('adv-tab-apk')));
      await tester.pumpAndSettle();

      final versionField = find.widgetWithText(TextFormField, '1.0.0');
      expect(versionField, findsOneWidget);
      await tester.enterText(versionField, '1.2.3');
      await tester.pump();

      // Switch to System tab and back -> edit is preserved
      await tester.tap(find.byKey(const ValueKey('adv-tab-system')));
      await tester.pumpAndSettle();

      // Navigating away from Advanced while on System tab still prompts UnsavedGuard for APK edits
      await tester.tap(find.byKey(const ValueKey('nav-overview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-keep')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('adv-tab-apk')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '1.2.3'), findsOneWidget);
    });
  });
}
