// PR #13: public item detail pages, parent-aware back navigation, card
// integration, custom page headers / intro notes and the upgraded footer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/document_lang.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/item_detail.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A real 1×1 PNG so Image.memory can decode it in widget tests.
final _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _FakeMedia implements MediaRepository {
  final loaded = <String>[];
  @override
  String get source => MediaSource.inline;
  @override
  Future<Uint8List?> load(String mediaId) async {
    loaded.add(mediaId);
    return _tinyPng;
  }

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) => throw UnimplementedError();
  @override
  Future<void> delete(String mediaId) async {}
}

/// An item stream that fails, and `settings/features` that never arrives.
class _ErrorRepository extends SeedRepository {
  _ErrorRepository(super.seed);
  @override
  Stream<List<Clinic>> clinics() => Stream.error(StateError('offline'));
}

class _PendingFeaturesRepository extends SeedRepository {
  _PendingFeaturesRepository(super.seed);
  final _never = StreamController<FeatureSettings>();
  @override
  Stream<FeatureSettings> features() => _never.stream;
}

class _FixedLocale extends LocaleNotifier {
  final Locale locale;
  _FixedLocale(this.locale);
  @override
  Locale build() => locale;
}

/// Detail fields every fixture item gets when [enabled].
Map<String, dynamic> _detailFields({bool enabled = true, Map<String, dynamic> extra = const {}}) => {
      'detailsEnabled': enabled,
      'detailsAr': 'تفاصيل طويلة عن الخدمة',
      'detailsEn': 'Long-form details about this service',
      'extraFields': [
        {'titleAr': 'المسؤول', 'titleEn': 'Coordinator', 'valueAr': 'أ. مينا', 'valueEn': 'Mr. Mina'},
      ],
      'gallery': [
        {'source': 'inline', 'mediaId': 'g1', 'alt': 'Gallery one'},
        {'source': 'inline', 'mediaId': 'g2', 'alt': 'Gallery two'},
      ],
      'contactNoteAr': 'التسجيل بعد القداس',
      'contactNoteEn': 'Register after the liturgy',
      'facebookUrl': 'https://facebook.com/example',
      'youtubeUrl': 'https://youtube.com/@example',
      'instagramUrl': 'https://instagram.com/example',
      'whatsappUrl': 'https://chat.whatsapp.com/example',
      'externalUrl': 'https://example.org/register',
      'externalLabelAr': 'استمارة التسجيل',
      'externalLabelEn': 'Registration form',
      ...extra,
    };

/// One fixture item per detail kind (ids `d-<kind>`), plus [patch] edits.
SeedData _seed({
  Map<String, bool> sections = const {},
  Map<String, Object?> features = const {},
  bool enabled = true,
  Map<String, dynamic> extra = const {},
  void Function(Map<String, dynamic> raw)? patch,
}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  f['sections'] = {...(f['sections'] as Map), 'clinics': true, ...sections};
  f.addAll(features);
  raw['settings']['features'] = f;
  final d = _detailFields(enabled: enabled, extra: extra);
  (raw['meetings'] as Map)['d-meeting'] = {
    'stage': 'youth', 'nameAr': 'اجتماع تجربة', 'nameEn': 'Test meeting', 'weekday': 5, //
    'start': '19:00', 'end': '20:30', 'hallAr': 'القاعة الكبرى', 'hallEn': 'Main hall', 'order': 999, ...d,
  };
  (raw['activities'] as Map)['d-activity'] = {
    'category': 'choir', 'titleAr': 'نشاط تجربة', 'titleEn': 'Test activity', 'descAr': 'وصف', //
    'descEn': 'Description', 'contactPhone': '01001234567', 'order': 999, ...d,
    'link': 'https://example.org/activity',
  };
  (raw['clinics'] as Map)['d-clinic'] = {
    'specialty': 'dental', 'specialtyAr': 'أسنان', 'specialtyEn': 'Dental', 'doctorName': 'د. تجربة', //
    'days': [1, 3], 'start': '17:00', 'end': '20:00', 'bookingPhone': '034000000', 'active': true, 'order': 999, ...d,
  };
  (raw['facilities'] as Map)['d-facility'] = {
    'type': 'library', 'nameAr': 'مرفق تجربة', 'nameEn': 'Test facility', 'descAr': 'وصف', 'descEn': 'Description', //
    'phone': '034111111', 'order': 999, ...d,
  };
  (raw['priests'] as Map)['d-priest'] = {
    'name': 'القس تجربة', 'nameEn': 'Fr. Test', 'rank': 'priest', 'status': 'serving', //
    'ordinationDate': '2010-01-01', 'order': 999, ...d,
  };
  (raw['priests'] as Map)['d-departed'] = {
    'name': 'القمص المتنيح تجربة', 'nameEn': 'Fr. Departed Test', 'rank': 'hegumen', 'status': 'departed', //
    'departedDate': '1990-05-01', 'order': 1999, ...d,
  };
  (raw['saints'] as Map)['d-saint'] = {
    'nameAr': 'قديس تجربة', 'nameEn': 'Test saint', 'feastCopticAr': '١ توت', 'feastCopticEn': '1 Thout', //
    'bioAr': 'سيرة', 'bioEn': 'Biography', 'order': 999, ...d,
  };
  (raw['milestones'] as Map)['d-milestone'] = {
    'titleAr': 'محطة تجربة', 'titleEn': 'Test milestone', 'year': 1999, 'descAr': 'وصف', 'descEn': 'Description', //
    'order': 999, ...d,
  };
  patch?.call(raw);
  return SeedData(raw);
}

final _now = CairoTime.at(2026, 11, 1, 12 * 60).toUtc(); // Sunday 1 Nov 2026, 12:00 Cairo

Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester tester, {
  SeedData? seed,
  Size size = const Size(400, 2400),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
  MediaRepository? media,
  String initial = '/',
  ContentRepository? repo,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  MediaCache.instance.clear();
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo ?? SeedRepository(seed ?? _seed())),
    nowProvider.overrideWith((ref) => Stream.value(_now)),
    localeProvider.overrideWith(() => _FixedLocale(locale)),
    mediaRepositoryProvider.overrideWithValue(media ?? _FakeMedia()),
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
  if (!settle) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (router, container);
  }
  await tester.pumpAndSettle();
  if (initial != '/') {
    router.go(initial);
    await tester.pumpAndSettle();
  }
  return (router, container);
}

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

const _detailRoutes = {
  DetailKind.meeting: ('/church-education/d-meeting', 'Test meeting', '/church-education'),
  DetailKind.activity: ('/church-activities/d-activity', 'Test activity', '/church-activities'),
  DetailKind.clinic: ('/clinics/d-clinic', 'Dental', '/clinics'),
  DetailKind.facility: ('/public-services/d-facility', 'Test facility', '/public-services'),
  DetailKind.priest: ('/about/priests/d-priest', 'Fr. Test', '/about'),
  DetailKind.saint: ('/about/saints/d-saint', 'Test saint', '/about'),
  DetailKind.milestone: ('/about/milestones/d-milestone', 'Test milestone', '/'),
};

void main() {
  setUpAll(CairoTime.ensureInitialized);
  tearDown(() => debugOnRouteMeta = null);

  group('Task 3.1: detail sub-routes & parent-aware back navigation', () {
    test('parentRouteOf: detail routes go to their section, everything else home', () {
      expect(parentRouteOf('/church-education/angels'), '/church-education');
      expect(parentRouteOf('/church-activities/x'), '/church-activities');
      expect(parentRouteOf('/clinics/dental-1/'), '/clinics');
      expect(parentRouteOf('/public-services/library?lang=en'), '/public-services');
      expect(parentRouteOf('/about/priests/bemwa'), '/about');
      expect(parentRouteOf('/about/saints/moses-black'), '/about');
      expect(parentRouteOf('/about/milestones/since-1980'), '/'); // listed on Home
      for (final top in ['/', '/clinics', '/about', '/contact', '/ask', '/nope/x/y', '/about/priests']) {
        expect(parentRouteOf(top), '/', reason: top);
      }
    });

    test('detail paths round-trip and match the admin "open public page" links', () {
      for (final k in DetailKind.values) {
        final p = detailPathFor(k, 'a b');
        expect(parseDetailPath(p), (k, 'a b'));
        expect(parentRouteOf(p), k.parentPath);
        expect(detailKindForCollection(k.collection), k);
        expect(sectionsForPath(p), isNotNull, reason: 'gated like its section: $p');
      }
      expect(parseDetailPath('/clinics'), isNull);
      expect(parseDetailPath('/clinics/a/b'), isNull);
      expect(parseDetailPath('/clinics/%ZZ'), (DetailKind.clinic, '%ZZ')); // malformed escape: no throw
      expect(parentRouteOf('/clinics/%ZZ'), '/clinics');
    });

    testWidgets('a malformed or unknown id shows "not available", never a crash', (tester) async {
      final (router, _) = await _pump(tester, initial: '/clinics/%ZZ');
      expect(tester.takeException(), isNull);
      expect(find.byType(AppShell), findsOneWidget);
      router.go('/about/milestones/does-not-exist');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemUnavailable')), findsOneWidget);
    });

    testWidgets('all 7 sub-routes resolve inside the shell (no 404)', (tester) async {
      final (router, _) = await _pump(tester);
      for (final e in _detailRoutes.entries) {
        router.go(e.value.$1);
        await tester.pumpAndSettle();
        expect(find.text('Page not found'), findsNothing, reason: e.value.$1);
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byKey(const Key('itemDetailPage')), findsOneWidget, reason: e.value.$1);
      }
    });

    testWidgets('phone: Back on a detail page returns to the parent section', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(400, 1600));
      for (final e in _detailRoutes.values) {
        router.go(e.$1);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('backHome')), findsNothing);
        await tester.tap(find.byKey(const Key('backParent')));
        await tester.pumpAndSettle();
        expect(_path(router), e.$3, reason: e.$1);
      }
      // Top-level pages keep the Back-to-Home arrow.
      router.go('/clinics');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backParent')), findsNothing);
      await tester.tap(find.byKey(const Key('backHome')));
      await tester.pumpAndSettle();
      expect(_path(router), '/');
    });

    testWidgets('wide screens: no back arrow on detail pages either', (tester) async {
      await _pump(tester, size: const Size(1400, 2400), initial: '/clinics/d-clinic');
      expect(find.byKey(const Key('backParent')), findsNothing);
      expect(find.byKey(const Key('backHome')), findsNothing);
    });

    testWidgets('a switched-off section closes its detail routes too', (tester) async {
      await _pump(tester, seed: _seed(sections: const {'clinics': false}), initial: '/clinics/d-clinic');
      expect(find.byKey(const Key('sectionUnavailable')), findsOneWidget);
      expect(find.byKey(const Key('itemDetailPage')), findsNothing);
    });
  });

  group('Task 3.2: detail page gating (pure)', () {
    const on = ItemDetails(detailsEnabled: true);
    const f = FeatureSettings();
    test('missing, hidden or detailsEnabled off: unavailable', () {
      expect(detailStateFor(null, features: f), DetailState.unavailable);
      expect(detailStateFor(on, features: f, visible: false), DetailState.unavailable);
      expect(detailStateFor(const ItemDetails(detailsEnabled: false), features: f), DetailState.unavailable);
      expect(detailStateFor(on, features: f), DetailState.available);
    });

    test('priests: the section matching their status must be on', () {
      const noDeparted = FeatureSettings(sections: {Sections.departedPriests: false});
      const noServing = FeatureSettings(sections: {Sections.priests: false});
      expect(detailStateFor(on, features: noDeparted, priestDeparted: true), DetailState.sectionOff);
      expect(detailStateFor(on, features: noDeparted, priestDeparted: false), DetailState.available);
      expect(detailStateFor(on, features: noServing, priestDeparted: false), DetailState.sectionOff);
      expect(detailStateFor(on, features: noServing, priestDeparted: true), DetailState.available);
    });

    test('item socials need their own switch and the socials section', () {
      expect(itemSocialsShown(on, f), isTrue);
      expect(itemSocialsShown(const ItemDetails(showSocials: false), f), isFalse);
      expect(itemSocialsShown(on, const FeatureSettings(sections: {Sections.socials: false})), isFalse);
    });
  });

  group('Task 3.2: ItemDetailPage', () {
    testWidgets('rich layout: facts, long text, custom fields, contacts, links + indexable SEO', (tester) async {
      final specs = <DocumentHeadSpec>[];
      debugOnRouteMeta = specs.add;
      await _pump(tester, initial: '/clinics/d-clinic');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(find.text('Dental'), findsWidgets);
      expect(find.text('د. تجربة'), findsWidgets);
      expect(find.byKey(const Key('detailBackLink')), findsOneWidget);
      final text = tester.widget<SelectableText>(find.byKey(const Key('detailText')));
      expect(text.data, 'Long-form details about this service');
      expect(text.style?.height, 1.8);
      expect(find.text('Coordinator'), findsOneWidget);
      expect(find.text('Mr. Mina'), findsOneWidget);
      expect(find.byKey(const Key('detailCall')), findsOneWidget);
      expect(find.text('Register after the liturgy'), findsOneWidget);
      for (final k in ['detailWhatsappGroup', 'detailFacebook', 'detailYoutube', 'detailInstagram', 'detailExternal']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Registration form'), findsOneWidget); // custom external label
      expect(find.bySemanticsLabel('Facebook — Dental'), findsOneWidget);
      expect(specs.last.canonicalUrl, '$kCanonicalOrigin/clinics/d-clinic');
      expect(specs.last.noIndex, isFalse);
    });

    testWidgets('Arabic: content picked in Arabic, external label falls back to "open page"', (tester) async {
      await _pump(tester,
          locale: const Locale('ar'),
          seed: _seed(extra: const {'externalLabelAr': '', 'externalLabelEn': ''}),
          initial: '/church-education/d-meeting');
      expect(find.text('اجتماع تجربة'), findsWidgets);
      expect(find.text('تفاصيل طويلة عن الخدمة'), findsOneWidget);
      expect(find.text('المسؤول'), findsOneWidget);
      expect(find.text('افتح الصفحة'), findsOneWidget);
    });

    testWidgets('details off, hidden or unknown id: "not available", noindex, back to the section', (tester) async {
      final specs = <DocumentHeadSpec>[];
      debugOnRouteMeta = specs.add;
      final (router, _) = await _pump(tester,
          seed: _seed(enabled: false, patch: (raw) {
            (raw['saints'] as Map)['hidden'] = {'nameAr': 'مخفي', 'nameEn': 'Hidden', 'visible': false, ..._detailFields()};
          }),
          initial: '/clinics/d-clinic');
      expect(find.byKey(const Key('itemUnavailable')), findsOneWidget);
      expect(find.byKey(const Key('itemDetailPage')), findsNothing);
      expect(specs.last.noIndex, isTrue);
      expect(specs.last.canonicalUrl, isNull);
      for (final p in ['/about/saints/hidden', '/about/saints/nope']) {
        router.go(p);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('itemUnavailable')), findsOneWidget, reason: p);
        expect(specs.last.noIndex, isTrue, reason: p);
      }
      await tester.tap(find.byKey(const Key('unavailableBack')));
      await tester.pumpAndSettle();
      expect(_path(router), '/about');
    });

    testWidgets('a failed item stream shows the error state and is not indexable', (tester) async {
      final specs = <DocumentHeadSpec>[];
      debugOnRouteMeta = specs.add;
      await _pump(tester, repo: _ErrorRepository(_seed()), initial: '/clinics/d-clinic');
      expect(find.text('Could not load data'), findsOneWidget);
      expect(specs.last.noIndex, isTrue);
      expect(specs.last.canonicalUrl, isNull);
    });

    testWidgets('dual priest gating: a departed father needs departedPriests', (tester) async {
      final specs = <DocumentHeadSpec>[];
      debugOnRouteMeta = specs.add;
      final (router, _) = await _pump(tester,
          seed: _seed(sections: const {'departedPriests': false}), initial: '/about/priests/d-departed');
      expect(find.byKey(const Key('sectionUnavailable')), findsOneWidget);
      expect(specs.last.noIndex, isTrue);
      router.go('/about/priests/d-priest'); // serving: still open
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(specs.last.noIndex, isFalse);
    });

    testWidgets('gallery: media fetched only when the detail page opens; thumbnails zoom', (tester) async {
      final media = _FakeMedia();
      final (router, _) = await _pump(tester,
          media: media,
          seed: _seed(extra: const {
            'image': {'source': 'inline', 'mediaId': 'c1', 'alt': 'Cover'}
          }));
      router.go('/church-activities'); // list page: covers only, never gallery bytes
      await tester.pumpAndSettle();
      expect(media.loaded, isNot(contains('g1')));
      router.go('/church-activities/d-activity');
      await tester.pumpAndSettle();
      expect(media.loaded, containsAll(['g1', 'g2']));
      expect(find.byKey(const Key('detailCover')), findsOneWidget);
      expect(find.byKey(const ValueKey('galleryThumb-1')), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('galleryThumb-0')), matching: find.byKey(const Key('itemImageTap'))));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    for (final (name, seed) in [
      ('showDetailImages off', () => _seed(extra: const {'showDetailImages': false})),
      ('images section off', () => _seed(sections: const {'media': false})),
    ]) {
      testWidgets('no cover / gallery when $name', (tester) async {
        final media = _FakeMedia();
        await _pump(tester, media: media, seed: seed(), initial: '/about/saints/d-saint');
        expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
        expect(find.byKey(const ValueKey('galleryThumb-0')), findsNothing);
        expect(media.loaded, isEmpty);
      });
    }

    testWidgets('showContacts off hides calls and the contact note; showSocials off hides links', (tester) async {
      await _pump(tester,
          seed: _seed(extra: const {'showContacts': false, 'showSocials': false}),
          initial: '/church-activities/d-activity');
      for (final k in ['detailCall', 'detailWhatsapp', 'detailContactNote', 'detailFacebook', 'detailExternal']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.byKey(const Key('detailText')), findsOneWidget);
    });

    testWidgets('socials section off hides every item link', (tester) async {
      await _pump(tester, seed: _seed(sections: const {'socials': false}), initial: '/public-services/d-facility');
      expect(find.byKey(const Key('detailCall')), findsOneWidget);
      for (final k in ['detailWhatsappGroup', 'detailFacebook', 'detailYoutube', 'detailInstagram', 'detailExternal']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('activity mobile phone doubles as WhatsApp; clinic without phones offers the office', (tester) async {
      final (router, _) = await _pump(tester,
          seed: _seed(patch: (raw) {
            final c = (raw['clinics'] as Map)['d-clinic'] as Map;
            c['bookingPhone'] = '';
            c['whatsapp'] = '';
          }),
          initial: '/church-activities/d-activity');
      expect(find.byKey(const Key('detailWhatsapp')), findsOneWidget);
      router.go('/clinics/d-clinic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detailCall')), findsNothing);
      expect(find.byKey(const Key('detailCallOffice')), findsOneWidget);
    });

    for (final lang in const ['ar', 'en']) {
      testWidgets('320 px at 200% text: every detail page lays out without overflow ($lang)', (tester) async {
        final (router, _) = await _pump(tester,
            size: const Size(320, 800),
            textScale: 2.0,
            locale: Locale(lang),
            seed: _seed(extra: const {
              'image': {'source': 'inline', 'mediaId': 'c1'}
            }));
        final failures = <String>[];
        for (final r in _detailRoutes.values) {
          router.go(r.$1);
          await tester.pumpAndSettle();
          final e = tester.takeException();
          if (e != null) failures.add('${r.$1}: $e');
          if (find.byKey(const Key('itemDetailPage')).evaluate().isEmpty) failures.add('${r.$1}: no page');
        }
        expect(failures, isEmpty);
      });
    }
  });

  group('Task 3.3: list cards', () {
    const lists = {
      DetailKind.meeting: '/church-education',
      DetailKind.activity: '/church-activities',
      DetailKind.clinic: '/clinics',
      DetailKind.facility: '/public-services',
      DetailKind.priest: '/about',
      DetailKind.saint: '/about',
      DetailKind.milestone: '/',
    };
    const image = {
      'image': {'source': 'inline', 'mediaId': 'c1', 'alt': 'Cover'}
    };

    testWidgets('detailsEnabled switched off: that card has no Details link, its image still enlarges', (tester) async {
      final (router, _) =
          await _pump(tester, size: const Size(1400, 6000), seed: _seed(enabled: false, extra: image));
      for (final e in lists.entries) {
        router.go(e.value);
        await tester.pumpAndSettle();
        final id = e.key == DetailKind.priest ? 'd-priest' : 'd-${e.key.name}';
        expect(find.byKey(ValueKey('detailsLink-$id')), findsNothing, reason: e.value);
        if (e.key == DetailKind.priest || e.key == DetailKind.saint) {
          // /about shows both a priest and a saint fixture: each card must still enlarge its own image.
          final card = find.byKey(ValueKey('aboutCard-$id'));
          expect(find.descendant(of: card, matching: find.byKey(const Key('itemImageTap'))), findsOneWidget,
              reason: '$id: fixture image enlarges');
        } else {
          expect(find.byKey(const Key('itemImageTap')), findsWidgets, reason: '${e.value}: fixture image enlarges');
        }
      }
    });

    testWidgets('detailsEnabled on: every list card links to its detail page', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(1400, 6000), seed: _seed(extra: image));
      for (final e in lists.entries) {
        router.go(e.value);
        await tester.pumpAndSettle();
        final id = e.key == DetailKind.priest ? 'd-priest' : 'd-${e.key.name}';
        final link = find.byKey(ValueKey('detailsLink-$id'));
        expect(link, findsOneWidget, reason: e.value);
        // Full-size zoom lives on the detail page: the small avatar no longer enlarges.
        expect(find.byKey(const Key('itemImageTap')), findsNothing, reason: e.value);
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(_path(router), detailPathFor(e.key, id));
        expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      }
    });

    testWidgets('tapping the card surface opens the detail page; Details link is labelled', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(1400, 6000), initial: '/church-activities');
      expect(find.bySemanticsLabel('Details — Test activity'), findsOneWidget);
      final title = find.text('Test activity');
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(_path(router), '/church-activities/d-activity');
    });

    testWidgets('card buttons respect showContacts / showSocials and the socials section', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(1400, 6000), initial: '/church-activities');
      expect(find.bySemanticsLabel('Call — Test activity'), findsOneWidget);
      expect(find.bySemanticsLabel('Open page — Test activity'), findsOneWidget);
      router.go('/church-education');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Facebook — Test meeting'), findsOneWidget);

      final (router2, _) = await _pump(tester,
          size: const Size(1400, 6000),
          seed: _seed(extra: const {'showContacts': false, 'showSocials': false}),
          initial: '/church-activities');
      expect(find.bySemanticsLabel('Call — Test activity'), findsNothing);
      expect(find.bySemanticsLabel('Open page — Test activity'), findsNothing);
      router2.go('/clinics');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Call • Book — Dental$')), findsNothing);

      final (router3, _) = await _pump(tester,
          size: const Size(1400, 6000), seed: _seed(sections: const {'socials': false}), initial: '/church-education');
      expect(find.bySemanticsLabel('Facebook — Test meeting'), findsNothing);
      router3.go('/church-activities');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Open page — Test activity'), findsNothing);
      expect(find.bySemanticsLabel('Call — Test activity'), findsOneWidget);
    });

    testWidgets('meeting, clinic and facility cards show an optional image', (tester) async {
      final (router, _) = await _pump(tester,
          size: const Size(1400, 6000), media: _FakeMedia(), seed: _seed(enabled: false, extra: image));
      for (final p in ['/church-education', '/clinics', '/public-services']) {
        router.go(p);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('itemImage')), findsOneWidget, reason: p);
      }
    });
  });

  group('Task 3.3: custom page headers & intro notes', () {
    const pages = {
      CustomizablePages.about: '/about',
      CustomizablePages.schedule: '/mass-schedule',
      CustomizablePages.education: '/church-education',
      CustomizablePages.activities: '/church-activities',
      CustomizablePages.clinics: '/clinics',
      CustomizablePages.services: '/public-services',
      CustomizablePages.contact: '/contact',
      CustomizablePages.ask: '/ask',
    };
    Map<String, dynamic> header(String k) => {
          'titleAr': 'عنوان $k', 'titleEn': 'Custom $k', 'subtitleAr': '', 'subtitleEn': 'Sub $k', //
          'introAr': '', 'introEn': 'Intro $k',
        };

    testWidgets('every customizable page uses the admin title, subtitle and intro', (tester) async {
      final (router, _) = await _pump(tester,
          size: const Size(1400, 4000),
          seed: _seed(features: {
            'pageHeaders': {for (final k in pages.keys) k: header(k)}
          }));
      for (final e in pages.entries) {
        router.go(e.value);
        await tester.pumpAndSettle();
        expect(find.text('Custom ${e.key}'), findsOneWidget, reason: e.value);
        expect(find.text('Sub ${e.key}'), findsOneWidget, reason: e.value);
        expect(find.text('Intro ${e.key}'), findsOneWidget, reason: e.value);
      }
    });

    testWidgets('empty overrides keep the built-in header and show no intro', (tester) async {
      final (router, _) = await _pump(tester,
          seed: _seed(features: {
            'pageHeaders': {
              'clinics': {...header('clinics'), 'titleEn': '', 'subtitleEn': '', 'introEn': ''},
            }
          }),
          initial: '/clinics');
      expect(find.text('Charity specialty clinics'), findsWidgets);
      expect(find.byKey(const Key('pageIntro')), findsNothing);
      // Arabic-only title: English visitors keep the English built-in title.
      expect(find.text('عنوان clinics'), findsNothing);
      router.go('/about');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pageIntro')), findsNothing);
    });
  });

  group('Task 3.3: footer (FR-G-04)', () {
    Finder inFooter(Finder f) => find.descendant(of: find.byType(Footer), matching: f);

    testWidgets('defaults: phones, socials and quick links; no note', (tester) async {
      await _pump(tester, size: const Size(1400, 6500));
      expect(inFooter(find.byKey(const Key('footerPhone-035368888'))), findsOneWidget);
      for (final s in ['whatsappChannel', 'facebook', 'youtube', 'instagram']) {
        expect(inFooter(find.byKey(Key('footerSocial-$s'))), findsOneWidget, reason: s);
      }
      expect(inFooter(find.byKey(const Key('footerQuickLinks'))), findsOneWidget);
      expect(inFooter(find.byKey(const Key('footerNote'))), findsNothing);
    });

    testWidgets('admin switches hide phones, socials and quick links; note shown', (tester) async {
      await _pump(tester,
          size: const Size(1400, 6500),
          seed: _seed(features: {
            'footer': {
              'showPhones': false, 'showSocials': false, 'showQuickLinks': false, //
              'noteAr': 'ملاحظة', 'noteEn': 'Footer note',
            }
          }));
      expect(inFooter(find.byKey(const Key('footerPhone-035368888'))), findsNothing);
      expect(inFooter(find.byKey(const Key('footerSocial-facebook'))), findsNothing);
      expect(inFooter(find.byKey(const Key('footerQuickLinks'))), findsNothing);
      expect(inFooter(find.text('Footer note')), findsOneWidget);
    });

    testWidgets('no phones or social icons until settings/features has arrived', (tester) async {
      await _pump(tester, size: const Size(1400, 6500), repo: _PendingFeaturesRepository(_seed()), settle: false);
      expect(find.byType(Footer), findsWidgets);
      expect(inFooter(find.byKey(const Key('footerPhone-035368888'))), findsNothing);
      expect(inFooter(find.byKey(const Key('footerSocial-facebook'))), findsNothing);
    });

    testWidgets('sections win: contact info off hides phones, socials off hides icons', (tester) async {
      await _pump(tester,
          size: const Size(1400, 6500), seed: _seed(sections: const {'contactInfo': false, 'socials': false}));
      expect(inFooter(find.byKey(const Key('footerPhone-035368888'))), findsNothing);
      expect(inFooter(find.byKey(const Key('footerSocial-facebook'))), findsNothing);
      expect(inFooter(find.byKey(const Key('footerQuickLinks'))), findsOneWidget);
    });
  });

  group('PR #14: detail pages on by default + richer page', () {
    void dropFlag(Map<String, dynamic> raw) => ((raw['meetings'] as Map)['d-meeting'] as Map).remove('detailsEnabled');

    testWidgets('untouched item (no detailsEnabled field): card links, page shows ALL admin details', (tester) async {
      final (router, _) = await _pump(tester,
          size: const Size(1400, 6000), seed: _seed(patch: dropFlag), initial: '/church-education');
      final link = find.byKey(const ValueKey('detailsLink-d-meeting'));
      expect(link, findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(_path(router), '/church-education/d-meeting');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(find.text('Long-form details about this service'), findsOneWidget);
      expect(find.text('Coordinator'), findsOneWidget);
      expect(find.text('Mr. Mina'), findsOneWidget);
      expect(find.byKey(const ValueKey('galleryThumb-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('galleryThumb-1')), findsOneWidget);
      expect(find.text('Register after the liturgy'), findsOneWidget);
    });

    testWidgets('a seeded meeting with no detail fields at all still gets a card link and a page', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(1400, 6000), initial: '/church-education');
      final link = find.byKey(const ValueKey('detailsLink-youth'));
      expect(link, findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(_path(router), '/church-education/youth');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(find.byKey(const Key('detailFacts')), findsOneWidget);
    });

    testWidgets('an explicit detailsEnabled:false still hides the link and the page', (tester) async {
      final (router, _) =
          await _pump(tester, size: const Size(1400, 6000), seed: _seed(enabled: false), initial: '/church-education');
      expect(find.byKey(const ValueKey('detailsLink-d-meeting')), findsNothing);
      router.go('/church-education/d-meeting');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemUnavailable')), findsOneWidget);
    });

    testWidgets('key facts are labelled rows (day, time, place)', (tester) async {
      await _pump(tester, initial: '/church-education/d-meeting');
      final facts = find.byKey(const Key('detailFacts'));
      expect(facts, findsOneWidget);
      for (final t in ['Day', 'Time', 'Place', 'Friday', 'Main hall']) {
        expect(find.descendant(of: facts, matching: find.text(t)), findsOneWidget, reason: t);
      }
    });

    testWidgets('quick actions: calendar for weekly items, directions for on-site items, share everywhere',
        (tester) async {
      final (router, _) = await _pump(tester, size: const Size(400, 3000));
      const calendar = {
        '/church-education/d-meeting': true, '/clinics/d-clinic': true, '/church-activities/d-activity': false, //
        '/about/saints/d-saint': false, '/about/milestones/d-milestone': false, '/about/priests/d-priest': false,
      };
      const directions = {
        '/church-education/d-meeting': true, '/clinics/d-clinic': true, '/church-activities/d-activity': true, //
        '/public-services/d-facility': true, '/about/saints/d-saint': false, '/about/priests/d-priest': false,
      };
      for (final e in calendar.entries) {
        router.go(e.key);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detailAddToCalendar')), e.value ? findsOneWidget : findsNothing, reason: e.key);
        expect(find.byKey(const Key('detailShare')), findsOneWidget, reason: e.key);
      }
      for (final e in directions.entries) {
        router.go(e.key);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detailDirections')), e.value ? findsOneWidget : findsNothing, reason: e.key);
      }
    });

    testWidgets('no directions when the church has no map destination (CodeRabbit review)', (tester) async {
      await _pump(tester,
          seed: _seed(patch: (raw) {
            final c = raw['settings']['church'] as Map;
            for (final k in ['mapsQuery', 'mapsUrl', 'addressAr', 'addressEn', 'lat', 'lng']) {
              c.remove(k);
            }
          }),
          initial: '/church-education/d-meeting');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(find.byKey(const Key('detailDirections')), findsNothing);
    });

    testWidgets('share: a refused clipboard shows the link instead of failing silently (CodeRabbit review)',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') throw PlatformException(code: 'denied');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, initial: '/church-education/d-meeting');
      await tester.ensureVisible(find.byKey(const Key('detailShare')));
      await tester.tap(find.byKey(const Key('detailShare')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Link copied'), findsNothing);
      expect(find.text('Could not copy the link: $kCanonicalOrigin/church-education/d-meeting?lang=en'), findsOneWidget);
    });

    testWidgets('directions follow the contact-info section', (tester) async {
      await _pump(tester, seed: _seed(sections: const {'contactInfo': false}), initial: '/church-education/d-meeting');
      expect(find.byKey(const Key('detailDirections')), findsNothing);
    });

    testWidgets('share copies the canonical link (with ?lang=en in English) and confirms', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, initial: '/church-education/d-meeting');
      await tester.ensureVisible(find.byKey(const Key('detailShare')));
      await tester.tap(find.byKey(const Key('detailShare')));
      await tester.pump();
      expect(copied, ['$kCanonicalOrigin/church-education/d-meeting?lang=en']);
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('"More in this section" links to other items, same stage group first', (tester) async {
      final (router, _) = await _pump(tester, size: const Size(400, 3000), initial: '/church-education/d-meeting');
      final related = find.byKey(const Key('detailRelated'));
      expect(related, findsOneWidget);
      // d-meeting is a youth meeting: youth / university / graduates come first.
      final youth = find.byKey(const ValueKey('relatedLink-youth'));
      expect(youth, findsOneWidget);
      expect(find.byKey(const ValueKey('relatedLink-d-meeting')), findsNothing);
      expect(find.byKey(const ValueKey('relatedLink-angels')), findsNothing);
      await tester.ensureVisible(youth);
      await tester.tap(youth);
      await tester.pumpAndSettle();
      expect(_path(router), '/church-education/youth');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
    });

    testWidgets('related links skip items whose page is off or whose section is off (Codex review)', (tester) async {
      await _pump(tester,
          size: const Size(400, 3000),
          seed: _seed(patch: (raw) => ((raw['meetings'] as Map)['youth'] as Map)['detailsEnabled'] = false),
          initial: '/church-education/d-meeting');
      expect(find.byKey(const Key('detailRelated')), findsOneWidget);
      expect(find.byKey(const ValueKey('relatedLink-youth')), findsNothing, reason: 'its page is switched off');
      expect(find.byKey(const ValueKey('relatedLink-university')), findsOneWidget);
    });

    testWidgets('a departed father never suggests serving priests while their section is off', (tester) async {
      await _pump(tester,
          size: const Size(400, 3000), seed: _seed(sections: const {'priests': false}), initial: '/about/priests/d-departed');
      expect(find.byKey(const Key('itemDetailPage')), findsOneWidget);
      expect(find.byKey(const ValueKey('relatedLink-tadros')), findsOneWidget);
      expect(find.byKey(const ValueKey('relatedLink-bemwa')), findsNothing, reason: 'serving priests section is off');
    });

    testWidgets('320 px at 200% text in Arabic: rich page lays out without overflow', (tester) async {
      await _pump(tester,
          size: const Size(320, 6000),
          textScale: 2.0,
          locale: const Locale('ar'),
          initial: '/church-education/d-meeting');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('detailFacts')), findsOneWidget);
      expect(find.byKey(const Key('detailShare')), findsOneWidget);
    });
  });
}
