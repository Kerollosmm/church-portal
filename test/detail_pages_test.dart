// PR #13: public item detail pages, parent-aware back navigation, card
// integration, custom page headers / intro notes and the upgraded footer.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  MediaCache.instance.clear();
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(seed ?? _seed())),
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
      expect(detailStateFor(const ItemDetails(), features: f), DetailState.unavailable);
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
}
