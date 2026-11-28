import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/site_search.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('normalizeSearchText', () {
    test('unifies alef variants, teh marbuta, alef maksura, and digits', () {
      expect(normalizeSearchText('أحمد'), 'احمد');
      expect(normalizeSearchText('إبراهيم'), 'ابراهيم');
      expect(normalizeSearchText('صلاة'), 'صلاه');
      expect(normalizeSearchText(' موسى '), 'موسي');
      expect(normalizeSearchText('١٢٣'), '123');
    });

    test('strips tashkeel and tatweel, lower-cases Latin, collapses space', () {
      expect(normalizeSearchText('اَلْقُدَّاس'), 'القداس');
      expect(normalizeSearchText('القدــــاس'), 'القداس');
      expect(normalizeSearchText('  Youth   Meeting '), 'youth meeting');
    });
  });

  group('searchTokens / matchesSearchTokens', () {
    test('every token must appear', () {
      final hay = normalizeSearchText('اجتماع الشباب الاسبوعي');
      expect(matchesSearchTokens(hay, searchTokens('شباب')), isTrue);
      expect(matchesSearchTokens(hay, searchTokens('اجتماع شباب')), isTrue);
      expect(matchesSearchTokens(hay, searchTokens('شباب قداس')), isFalse);
      expect(searchTokens('   '), isEmpty);
    });
  });

  group('searchSite', () {
    const meetings = [
      Meeting(id: 'y', stage: 'youth', nameAr: 'اجتماع الشباب', nameEn: 'Youth meeting', visible: true),
      Meeting(id: 'h', stage: 'family', nameAr: 'اجتماع مخفي', nameEn: 'Hidden', visible: false),
    ];
    const activities = [
      Activity(id: 'c', titleAr: 'كورال', titleEn: 'Choir', category: 'choir', visible: true),
    ];

    test('matches visible meetings by Arabic or English title and skips hidden', () {
      final groups = searchSite('شباب', const SiteSearchInput(meetings: meetings, activities: activities));
      expect(groups.single.kind, SearchResultKind.meeting);
      expect(groups.single.items.single.id, 'y');
      expect(groups.single.items.single.route, '/church-education/y');

      final en = searchSite('youth', const SiteSearchInput(meetings: meetings));
      expect(en.single.items.single.id, 'y');

      expect(searchSite('مخفي', const SiteSearchInput(meetings: meetings)), isEmpty);
    });

    test('respects feature flags and groups by kind', () {
      final off = FeatureSettings.defaults.copyWith(sections: const {Sections.meetings: false});
      expect(searchSite('شباب', SiteSearchInput(features: off, meetings: meetings)), isEmpty);

      final groups = searchSite('كورال', const SiteSearchInput(meetings: meetings, activities: activities));
      expect(groups.single.kind, SearchResultKind.activity);
      expect(groups.single.items.single.id, 'c');
    });

    test('empty or whitespace query returns no groups', () {
      expect(searchSite('  ', const SiteSearchInput(meetings: meetings)), isEmpty);
    });
  });

  group('SearchPage', () {
    testWidgets('shows hint, then results, then navigates to the hit route', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      final container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(_SearchSeedRepo(SeedData(raw))),
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
      router.go('/search');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const Key('site-search-field')), findsOneWidget);
      expect(find.text('Type a word to search the content already loaded on your device.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('site-search-field')), 'ZZYouthUnique');
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final hit = find.byKey(const ValueKey('search-hit-meeting-search-youth'));
      expect(hit, findsOneWidget);
      await tester.tap(hit);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(router.routerDelegate.currentConfiguration.uri.path, '/church-education/search-youth');
    });
  });
}

class _FixedLocale extends LocaleNotifier {
  final Locale locale;
  _FixedLocale(this.locale);
  @override
  Locale build() => locale;
}

class _SearchSeedRepo extends SeedRepository {
  _SearchSeedRepo(super.seed);

  @override
  Stream<List<Meeting>> meetings() => Stream.value(const [
        Meeting(
          id: 'search-youth',
          stage: 'youth',
          nameAr: 'اجتماع تجربة',
          nameEn: 'ZZYouthUnique meeting',
        ),
      ]);
}
