import 'package:church_portal/core/theme.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/time_format.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('Western-digit ص/م bidi-isolated time formatting (Q2)', () {
    test('formatTimeArabic uses Western digits with ص/م', () {
      expect(formatTimeArabic('06:30'), '06:30 ص');
      expect(formatTimeArabic('18:30'), '06:30 م');
      expect(formatTimeArabic('00:00'), '12:00 ص');
      expect(formatTimeArabic('12:00'), '12:00 م');
    });

    test('formatRangeArabic returns plain text with Western digits and ص/م (no bidi marks)', () {
      expect(formatRangeArabic('08:00', '09:30'), '08:00 ص – 09:30 ص');
      expect(formatRangeArabic('08:00', ''), '08:00 ص');
      expect(formatRangeArabic('08:00', '   '), '08:00 ص');
      expect(formatRangeArabic('', ''), '');
    });

    test('formatRangeLatin returns plain text (no bidi marks)', () {
      expect(formatRangeLatin('08:00', '09:30'), '08:00 AM – 09:30 AM');
      expect(formatRangeLatin('08:00', ''), '08:00 AM');
      expect(formatRangeLatin('08:00', '   '), '08:00 AM');
      expect(formatRangeLatin('', ''), '');
    });

    testWidgets('TimeRangeText renders single-line Western digits ص/م in Arabic without duplicate line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: const Scaffold(body: TimeRangeText('08:00', '09:30')),
        ),
      );
      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(TimeRangeText), matching: find.byType(Text)))
          .map((t) => t.data!)
          .toList();
      expect(texts, ['\u206708:00 ص – 09:30 ص\u2069']);
      expect(texts.join(), isNot(matches(RegExp('[\u0660-\u0669]'))));
      expect(find.textContaining('AM'), findsNothing);
    });

    testWidgets('TimeRangeText renders single-time Arabic isolated and collapses when blank', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('ar')),
          home: const Scaffold(
            body: Column(children: [TimeRangeText('08:00', '   '), TimeRangeText('', '')]),
          ),
        ),
      );
      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(TimeRangeText), matching: find.byType(Text)))
          .map((t) => t.data!)
          .toList();
      expect(texts, ['\u206708:00 ص\u2069']);
    });

    testWidgets('TimeRangeText renders single-line LTR-isolated range in English', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(const Locale('en')),
          home: const Scaffold(body: TimeRangeText('08:00', '09:30')),
        ),
      );
      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(TimeRangeText), matching: find.byType(Text)))
          .map((t) => t.data!)
          .toList();
      expect(texts, ['\u206608:00 AM – 09:30 AM\u2069']);
    });
  });
}
