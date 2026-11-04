import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Follow-ups from the live check of 4 Nov 2026 (ADR-038).
void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('image text alternative per language', () {
    test('English site: an Arabic-only alt gives way to the English name', () {
      expect(
        imageAltFor('أيقونة القديس الأنبا موسى الأسود', 'St. Moses the Black', english: true),
        'St. Moses the Black',
      );
    });
    test('Arabic site keeps the admin alt', () {
      expect(
        imageAltFor('أيقونة القديس الأنبا موسى الأسود', 'الأنبا موسى', english: false),
        'أيقونة القديس الأنبا موسى الأسود',
      );
    });
    test('an English alt, or no English name to use, keeps the alt', () {
      expect(imageAltFor('Icon of St. Moses', 'St. Moses the Black', english: true), 'Icon of St. Moses');
      expect(imageAltFor('أيقونة', 'الأنبا موسى', english: true), 'أيقونة'); // name has no English form
      expect(imageAltFor('أيقونة', '', english: true), 'أيقونة');
    });
    test('no alt: the label', () {
      expect(imageAltFor('  ', 'St. Moses', english: true), 'St. Moses');
    });
  });

  group('footer quick links before the section switches arrive', () {
    Future<void> pump(WidgetTester tester, {required bool ready}) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
            featuresReadyProvider.overrideWithValue(ready),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: Footer())),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('clinics (off on the live site) is not offered while the switches load', (tester) async {
      await pump(tester, ready: false);
      expect(find.text('Clinics'), findsNothing);
      expect(find.text('Contact us'), findsWidgets); // the other quick links stay
    });

    testWidgets('clinics shows once the switches say it is on', (tester) async {
      await pump(tester, ready: true);
      expect(find.text('Clinics'), findsOneWidget);
    });
  });
}
