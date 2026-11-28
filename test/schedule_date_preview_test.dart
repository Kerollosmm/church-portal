import 'package:church_portal/core/theme.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
import 'package:church_portal/ui/admin/schedule_date_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

void main() {
  registerAdminStrings();

  const regular = Liturgy(
    id: 'regular-sun',
    type: 'mass',
    nameAr: 'القداس الأسبوعي',
    nameEn: 'Weekly liturgy',
    weekday: 7,
    start: '07:00',
    end: '09:00',
  );
  final nativity = Season(
    id: 'nat',
    key: 'nativity',
    nameAr: 'الميلاد',
    nameEn: 'Nativity',
    startsAt: DateTime.utc(2026, 11, 29),
    endsAt: DateTime.utc(2026, 12, 7),
    active: false,
    replacesRegular: true,
  );
  const feast = Liturgy(
    id: 'feast-mass',
    type: 'mass',
    nameAr: 'قداس العيد',
    nameEn: 'Feast liturgy',
    weekday: 7,
    start: '08:00',
    end: '10:00',
    seasonKey: 'nativity',
  );

  group('seasonsForVisitorPreview', () {
    test('leaves inactive seasons off unless includeInactive is set', () {
      final asIs = seasonsForVisitorPreview([nativity], includeInactive: false);
      expect(asIs.single.active, isFalse);
      expect(isSeasonActiveAt(asIs.single, cairo(2026, 11, 29, 8)), isFalse);

      final forced = seasonsForVisitorPreview([nativity], includeInactive: true);
      expect(forced.single.active, isTrue);
      expect(forced.single.startsAt, nativity.startsAt);
      expect(isSeasonActiveAt(forced.single, cairo(2026, 11, 29, 8)), isTrue);
      expect(isSeasonActiveAt(forced.single, cairo(2026, 11, 28, 8)), isFalse);
    });

    test('on the first day, forcing an inactive replacing season hides regular masses', () {
      final day = cairo(2026, 11, 29);
      final off = occurrencesForDay(
        liturgies: const [regular, feast],
        seasons: seasonsForVisitorPreview([nativity], includeInactive: false),
        day: day,
        dayOffset: 0,
      );
      expect(off.map((o) => o.liturgy.id).toList(), ['regular-sun']);

      final on = occurrencesForDay(
        liturgies: const [regular, feast],
        seasons: seasonsForVisitorPreview([nativity], includeInactive: true),
        day: day,
        dayOffset: 0,
      );
      expect(on.map((o) => o.liturgy.id).toList(), ['feast-mass']);
    });
  });

  group('ScheduleDatePreviewSheet', () {
    testWidgets('shows regular services, then the forced season programme', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(const Locale('en')),
        home: Scaffold(
          body: ScheduleDatePreviewSheet(
            liturgies: const [regular, feast],
            seasons: [nativity],
            initialDate: DateTime(2026, 11, 29),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Preview as a visitor'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-hit-regular-sun')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-hit-feast-mass')), findsNothing);
      expect(find.byKey(const Key('preview-no-seasons')), findsOneWidget);

      await tester.tap(find.byKey(const Key('preview-include-inactive')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('preview-season-nat')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-hit-feast-mass')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-hit-regular-sun')), findsNothing);
    });
  });
}
