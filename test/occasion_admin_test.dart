// Admin side of occasion themes (ADR-025): the editor in Settings, what a
// save writes, and that colour edits are stored auto-corrected for contrast.
// The hero video library (ADR-026) was removed (ADR-036): no admin card, and
// a library already stored in settings/features is ignored and never written.
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/admin/occasion_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Hosts an editor and keeps its value, like FeaturesEditor does.
class _Host extends StatefulWidget {
  final FeatureSettings initial;
  final Widget Function(FeatureSettings, void Function(FeatureSettings Function(FeatureSettings))) build;
  final ValueChanged<FeatureSettings> onValue;
  const _Host(this.initial, this.build, this.onValue);
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late FeatureSettings f = widget.initial;
  @override
  Widget build(BuildContext context) => widget.build(f, (edit) {
        final n = edit(f);
        setState(() => f = n);
        widget.onValue(n);
      });
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('saves', () {
    test('defaults write nothing new; legacy burgundy is rewritten as goldenHour', () {
      final w = featuresSaveWrites(FeatureSettings.fromMap(const {'theme': 'burgundy'}), const {'theme': 'burgundy'});
      expect(w, hasLength(2)); // base + pageHeaders (not stored yet)
      expect(w.first['theme'], ThemePresets.goldenHour);
      for (final x in w) {
        expect(x.keys, isNot(contains('occasions')));
        expect(x.keys, isNot(contains('themeColors')));
        expect(x.keys, isNot(contains('heroVideos')));
      }
    });

    test('occasions and colours go in their own writes, colours corrected for contrast', () {
      final next = FeatureSettings.defaults.copyWith(
        theme: ThemePresets.holyWeek,
        occasions: const OccasionConfig(
          auto: true,
          schedule: [ThemeRange(theme: 'nativity', start: '2026-12-25', end: '2027-01-08')],
          custom: {
            'goldenHour': {'ink': '#FFFFFF'}, // white body text on cream: unreadable
          },
        ),
      );
      final w = featuresSaveWrites(next, const {'theme': 'burgundy', 'pageHeaders': {}});
      final occ = w.firstWhere((x) => x.containsKey('occasions'))['occasions'] as Map;
      expect(occ['auto'], isTrue);
      expect(occ['schedule'], {'r1': 'nativity|2026-12-25|2027-01-08'});
      final colors = w.firstWhere((x) => x.containsKey('themeColors'))['themeColors'] as Map;
      final ink = parseHexColor((colors['goldenHour'] as String).split('|')[6])!;
      expect(contrastRatio(ink, ThemePresets.palettes['goldenHour']!.surface), greaterThanOrEqualTo(4.5));
      expect(w.any((x) => x.containsKey('heroVideos')), isFalse);
      expect(w.every((x) => x.length == 1 || x.containsKey('theme')), isTrue);
      // Saved again unchanged: only the base write.
      final stored = <String, dynamic>{'pageHeaders': const <String, dynamic>{}, for (final x in w) ...x};
      expect(featuresSaveWrites(FeatureSettings.fromMap(stored), stored), hasLength(1));
    });
  });

  group('OccasionThemeEditor', () {
    testWidgets('pick a preset, switch automatic, add a range; shows the theme in force', (tester) async {
      await tall(tester);
      FeatureSettings? last;
      await tester.pumpWidget(_app(_Host(
        FeatureSettings.defaults,
        (f, on) => OccasionThemeEditor(value: f, onChanged: on, today: DateTime(2027, 4, 26)),
        (f) => last = f,
      )));
      expect(find.textContaining('In force today: Golden hour'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-marian')));
      await tester.pump();
      expect(last!.theme, 'marian');
      await tester.tap(find.byKey(const ValueKey('occasions-auto')));
      await tester.pump();
      expect(last!.occasions.auto, isTrue);
      // 26 Apr 2027 is in Holy Week (Coptic Easter 2 May 2027).
      expect(find.textContaining('In force today: Holy Week'), findsOneWidget);
      expect(find.textContaining('2027-04-25 → 2027-05-01'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('occasions-addRange')));
      await tester.pump();
      expect(last!.occasions.schedule.single,
          const ThemeRange(theme: 'marian', start: '2027-04-26', end: '2027-05-02'));
      expect(find.textContaining('In force today: Marian'), findsOneWidget); // the range wins
      await tester.tap(find.byKey(const ValueKey('occasions-range-0-remove')));
      await tester.pump();
      expect(last!.occasions.schedule, isEmpty);
    });

    testWidgets('colour edits: an unreadable colour is flagged and previewed corrected', (tester) async {
      await tall(tester);
      FeatureSettings? last;
      await tester.pumpWidget(_app(_Host(
        FeatureSettings.defaults,
        (f, on) => OccasionThemeEditor(value: f, onChanged: on, today: DateTime(2026, 11, 3)),
        (f) => last = f,
      )));
      await tester.tap(find.byKey(const ValueKey('occasions-colors')));
      await tester.pumpAndSettle();
      expect(find.text('All text is readable (contrast at least 4.5:1).'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('occasions-hex-ink')), '#FBF3E4');
      await tester.pump();
      expect(last!.occasions.custom['goldenHour'], {'ink': '#FBF3E4'});
      expect(find.textContaining('Will be saved corrected for readability'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('occasions-hex-ink')), '#zz');
      await tester.pump();
      expect(find.text('Use #RRGGBB'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('occasions-resetColors')));
      await tester.pump();
      expect(last!.occasions.custom, isEmpty);
    });
  });

  group('hero video library removed (ADR-036)', () {
    const stored = <String, dynamic>{
      'theme': 'goldenHour',
      'pageHeaders': <String, dynamic>{},
      // A library saved before the removal stays in the live document.
      'heroVideos': {
        'items': {'v1': 'Clouds|https://www.youtube.com/watch?v=aaaaaaaaaaa'},
        'active': 'v1',
      },
    };

    test('a stored library is read without error and never written back', () {
      final f = FeatureSettings.fromMap(stored);
      expect(f.toMap().keys, isNot(contains('heroVideos')));
      final w = featuresSaveWrites(f.copyWith(heroMotion: false), stored);
      expect(w.any((x) => x.containsKey('heroVideos')), isFalse, reason: 'saves never touch the stored field');
      expect(w.first['heroMotion'], isFalse);
    });

    testWidgets('Sections & home page has no hero video library card', (tester) async {
      tester.view.physicalSize = const Size(1000, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: FeaturesEditor(initial: FeatureSettings.fromMap(stored), onSave: (f) async {})),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hero video library (YouTube)'), findsNothing);
      expect(find.byKey(const ValueKey('heroVideo-builtin')), findsNothing);
      expect(find.byKey(const ValueKey('heroVideo-add')), findsNothing);
      // The hero motion switch (bundled clip on / off) stays.
      expect(find.byKey(const ValueKey('features-heroMotion')), findsOneWidget);
      expect(find.text('Site theme & occasions'), findsOneWidget);
    });
  });
}
