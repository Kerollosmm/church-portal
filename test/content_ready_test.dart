import 'dart:async';

import 'package:church_portal/core/content_ready.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/home_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('first content / loading screen (ADR-038, PR 6G)', () {
    final settings = AsyncData<ChurchSettings>(ChurchSettings.fromMap(const {'nameAr': 'x'}));

    test('waits only for settings and section switches (does not gate on daily verses)', () {
      expect(firstContentArrived(settings: settings, featuresReady: true), isTrue);
      expect(firstContentArrived(settings: const AsyncLoading(), featuresReady: true), isFalse);
      expect(firstContentArrived(settings: settings, featuresReady: false), isFalse);
    });

    test('a failed input never holds the page', () {
      expect(
        firstContentArrived(
          settings: AsyncError(StateError('x'), StackTrace.empty),
          featuresReady: true,
        ),
        isTrue,
      );
    });

    test('signal is idempotent and releases whenIdle', () async {
      var idle = false;
      ContentReady.whenIdle.then((_) => idle = true);
      expect(ContentReady.signalled, isFalse);
      ContentReady.signal();
      ContentReady.signal();
      expect(ContentReady.signalled, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(idle, isTrue);
    });

    testWidgets(
        'HeroVerse renders cleanly without crash or overflow when dailyVersesProvider resolves after contentReadyProvider (320/400/1400 AR/EN & toggle)',
        (tester) async {
      CairoTime.ensureInitialized();
      for (final width in [320.0, 400.0, 1400.0]) {
        for (final localeCode in ['ar', 'en']) {
          for (final enabled in [true, false]) {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final completer = Completer<List<Verse>>();
            final features = FeatureSettings.defaults.copyWith(
              sections: {
                ...FeatureSettings.defaults.sections,
                Sections.dailyVerse: enabled,
              },
            );

            await tester.pumpWidget(
              ProviderScope(
                key: ValueKey('$width-$localeCode-$enabled'),
                overrides: [
                  repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
                  settingsProvider.overrideWithValue(
                    const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A')),
                  ),
                  featuresStreamProvider.overrideWithValue(AsyncData(features)),
                  nowProvider.overrideWithValue(AsyncData(CairoTime.at(2026, 11, 26, 10 * 60))),
                  dailyVersesProvider.overrideWith((ref) => completer.future),
                ],
                child: MaterialApp(
                  locale: Locale(localeCode),
                  supportedLocales: const [Locale('ar'), Locale('en')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  home: Scaffold(
                    body: Consumer(
                      builder: (context, ref, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ready=${ref.watch(contentReadyProvider)}'),
                          const HeroVerse(),
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const Key('heroCtaButton'),
                            onPressed: () {},
                            child: const Text('CTA'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            // contentReadyProvider is already true while dailyVersesProvider is still loading.
            expect(find.text('ready=true'), findsOneWidget);
            expect(find.byKey(const Key('heroVerse')), findsNothing);
            expect(find.byKey(const Key('heroVerseLoading')), enabled ? findsOneWidget : findsNothing);
            final ctaBeforeY = tester.getTopLeft(find.byKey(const Key('heroCtaButton'))).dy;
            expect(tester.takeException(), isNull);

            completer.complete(const [
              Verse(
                textAr: 'الرب نوري وخلاصي',
                textEn: 'The Lord is my light and my salvation',
                refAr: 'مزمور ٢٧: ١',
                refEn: 'Psalm 27:1',
              ),
            ]);
            await tester.pump();
            await tester.pump();

            expect(tester.takeException(), isNull);
            final ctaAfterY = tester.getTopLeft(find.byKey(const Key('heroCtaButton'))).dy;
            expect((ctaAfterY - ctaBeforeY).abs(), lessThanOrEqualTo(32.0));
            if (enabled) {
              expect(find.byKey(const Key('heroVerse')), findsOneWidget);
              expect(
                find.text(localeCode == 'ar' ? '« الرب نوري وخلاصي »' : '“The Lord is my light and my salvation”'),
                findsOneWidget,
              );
            } else {
              expect(find.byKey(const Key('heroVerse')), findsNothing);
            }
          }
        }
      }
    });
  });
}
