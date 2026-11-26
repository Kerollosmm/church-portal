import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  baseOverrides() => [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        liturgiesProvider.overrideWithValue(const AsyncData(<Liturgy>[
          Liturgy(
            id: 'l1',
            type: 'mass',
            nameAr: 'قداس الأحد',
            nameEn: 'Sunday Mass',
            weekday: 7,
            start: '07:00',
            end: '09:30',
          ),
        ])),
        seasonsProvider.overrideWithValue(const AsyncData(<Season>[])),
        nowProvider.overrideWithValue(AsyncData(CairoTime.at(2026, 11, 22, 6 * 60))),
        settingsProvider.overrideWithValue(
            const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A'))),
        featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
        customPagesProvider.overrideWithValue(const AsyncData(<CustomPage>[])),
      ];

  testWidgets(
      'NextMassCard shows Full schedule by default outside GoRouter and on /, and hides it when disabled or on /mass-schedule',
      (tester) async {
    // 1. Outside GoRouter -> shows link by default without throwing; explicit false hides it.
    for (final showLink in [true, false]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: NextMassCard(showFullScheduleLink: showLink)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('الجدول الكامل'), showLink ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }

    // 2. Inside GoRouter at '/' -> shows link; at '/mass-schedule' (both MassSchedulePage & bare NextMassCard) -> hides link.
    for (final path in ['/', '/mass-schedule']) {
      for (final width in [320.0, 400.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final router = GoRouter(
          initialLocation: path,
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: NextMassCard())),
            GoRoute(path: '/mass-schedule', builder: (_, _) => const Scaffold(body: MassSchedulePage())),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: MaterialApp.router(
              locale: width == 320.0 ? const Locale('en') : const Locale('ar'),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expectedLabel = width == 320.0 ? 'Full schedule' : 'الجدول الكامل';
        expect(
          find.text(expectedLabel),
          path == '/' ? findsOneWidget : findsNothing,
          reason: 'path=$path width=$width',
        );
        expect(tester.takeException(), isNull);
      }
    }

    // 3. Bare NextMassCard() inside GoRouter at /mass-schedule also hides the link via GoRouterState.maybeOf.
    final directRouter = GoRouter(
      initialLocation: '/mass-schedule',
      routes: [
        GoRoute(path: '/mass-schedule', builder: (_, _) => const Scaffold(body: NextMassCard())),
      ],
    );
    addTearDown(directRouter.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp.router(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: directRouter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الجدول الكامل'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
