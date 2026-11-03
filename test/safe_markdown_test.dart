import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:church_portal/domain/simple_markdown.dart';
import 'package:church_portal/ui/widgets/safe_markdown.dart';

const _arabicReply = '**مواعيد القداسات:**\n'
    '* الجمعة: **07:00 ص**\n'
    '* الأحد: *08:00 ص*\n'
    '1. اتصل بـ [مكتب الكنيسة](tel:+2035551234)\n'
    '2. أو زر [صفحة القداسات](/mass)\n'
    'رابط غير آمن: [اضغط هنا](javascript:alert(1)) و ![صورة](https://x.org/a.png) <b>نص</b>';

List<TextSpan> _spans(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final rt in tester.widgetList<RichText>(find.descendant(of: find.byType(SafeMarkdown), matching: find.byType(RichText)))) {
    rt.text.visitChildren((s) {
      if (s is TextSpan) out.add(s);
      return true;
    });
  }
  return out;
}

String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.descendant(of: find.byType(SafeMarkdown), matching: find.byType(RichText)))
    .map((r) => r.text.toPlainText())
    .join('\n');

Future<void> _pump(WidgetTester tester, String data) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SafeMarkdown(data, style: const TextStyle(color: Color(0xFF3A2416)))),
  ));
}

void main() {
  group('parseSimpleMarkdown', () {
    test('bold, italics, bullets and numbered items; no stray asterisks', () {
      final b = parseSimpleMarkdown(_arabicReply);
      expect(b.map((x) => x.kind).toList(), [
        MdBlockKind.paragraph,
        MdBlockKind.bullet,
        MdBlockKind.bullet,
        MdBlockKind.numbered,
        MdBlockKind.numbered,
        MdBlockKind.paragraph,
      ]);
      expect(b[0].spans.single.bold, isTrue);
      expect(b[1].spans.last.text, '07:00 ص');
      expect(b[1].spans.last.bold, isTrue);
      expect(b[2].spans.last.italic, isTrue);
      expect(b[3].marker, '1.');
      for (final x in b) {
        expect(x.plainText, isNot(contains('*')));
      }
    });

    test('only http(s), tel: and internal routes are links; images and HTML are dropped', () {
      final b = parseSimpleMarkdown(_arabicReply);
      expect(b[3].spans.last.link, 'tel:+2035551234');
      expect(b[4].spans.last.link, '/mass');
      final last = b[5];
      expect(last.spans.where((s) => s.link != null), isEmpty);
      expect(last.plainText, 'رابط غير آمن: اضغط هنا و صورة نص');
      for (final bad in ['javascript:alert(1)', 'data:text/html,x', '//evil.org', 'file:///etc', 'ftp://x.org', 'https:/x']) {
        expect(safeLinkTarget(bad), isNull, reason: bad);
      }
      for (final ok in ['https://maximos-domadios-church.web.app', 'http://x.org/a', 'tel:+203555', '/clinics']) {
        expect(safeLinkTarget(ok), ok, reason: ok);
      }
    });

    test('snake_case and unpaired markers', () {
      expect(parseInline('a_b_c').single.text, 'a_b_c');
      expect(parseInline('5 * 3 and **open').map((s) => s.text).join(), '5  3 and open');
      expect(startsRtl('**مرحبا** hello'), isTrue);
      expect(startsRtl('Hi مرحبا'), isFalse);
    });
  });

  group('SafeMarkdown widget', () {
    testWidgets('an Arabic reply with ** and * bullets renders with no literal asterisks, RTL', (tester) async {
      await _pump(tester, _arabicReply);
      final text = _allText(tester);
      expect(text, isNot(contains('*')));
      expect(text, contains('مواعيد القداسات:'));
      expect(text, isNot(contains('<b>')));
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      final bold = _spans(tester).where((s) => s.text == '07:00 ص').single;
      expect(bold.style?.fontWeight, FontWeight.w700);
      final dir = tester.widget<Directionality>(
          find.ancestor(of: find.byType(SelectionArea), matching: find.byType(Directionality)).first);
      expect(dir.textDirection, TextDirection.rtl);
      expect(find.byType(SelectionArea), findsOneWidget); // selection / copy kept
    });

    testWidgets('safe links are tappable; an unsafe link scheme is not', (tester) async {
      await _pump(tester, _arabicReply);
      final spans = _spans(tester);
      expect(spans.firstWhere((s) => s.text == 'مكتب الكنيسة').recognizer, isA<TapGestureRecognizer>());
      expect(spans.firstWhere((s) => s.text == 'صفحة القداسات').recognizer, isA<TapGestureRecognizer>());
      final unsafe = spans.firstWhere((s) => (s.text ?? '').contains('اضغط هنا'));
      expect(unsafe.recognizer, isNull);
      expect(unsafe.style?.decoration, isNot(TextDecoration.underline));
      expect(spans.where((s) => s.recognizer != null), hasLength(2));
    });

    testWidgets('an English reply stays LTR', (tester) async {
      await _pump(tester, 'Mass is at **7 AM**:\n- Friday\n- Sunday');
      expect(_allText(tester), isNot(contains('*')));
      final dir = tester.widget<Directionality>(
          find.ancestor(of: find.byType(SelectionArea), matching: find.byType(Directionality)).first);
      expect(dir.textDirection, TextDirection.ltr);
    });
  });
}
