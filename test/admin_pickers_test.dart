// ADR-048 item 5: admin time / date pickers. Every FieldType.time / date /
// dateTime field (top-level and inside rows) is read-only and filled from
// showTimePicker (24-hour) / showDatePicker; stored strictly as "HH:mm",
// "YYYY-MM-DD" or the unchanged date-time instant.
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/admin_pickers.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

Future<void> _pump(WidgetTester tester, Widget w, {Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(w, locale: locale));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key, {int index = 0}) =>
    tester.widget<TextFormField>(find.byKey(ValueKey('field-$key')).at(index)).controller!.text;

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('formatters', () {
    test('time: zero-padded HH:mm, 00:00 and 23:59, clamped', () {
      expect(formatPickedTime(0, 0), '00:00');
      expect(formatPickedTime(23, 59), '23:59');
      expect(formatPickedTime(6, 5), '06:05');
      expect(formatPickedTime(9, 0), '09:00');
      expect(formatPickedTime(24, 60), '23:59');
      for (var h = 0; h < 24; h++) {
        for (final m in const [0, 1, 30, 59]) {
          expect(timeRe.hasMatch(formatPickedTime(h, m)), isTrue, reason: '$h:$m');
        }
      }
    });

    test('date: YYYY-MM-DD; date-time: YYYY-MM-DD HH:mm', () {
      expect(formatPickedDate(2027, 1, 6), '2027-01-06');
      expect(formatPickedDate(2027, 12, 31), '2027-12-31');
      expect(isValidDate(formatPickedDate(2028, 2, 29)), isTrue);
      expect(formatPickedDateTime(2027, 4, 25, 0, 0), '2027-04-25 00:00');
      expect(formatPickedDateTime(2027, 5, 1, 18, 0), '2027-05-01 18:00');
      expect(isValidDateTime(formatPickedDateTime(2027, 5, 1, 23, 59)), isTrue);
    });

    test('prefill parsing: legacy unpadded and Arabic-Indic digits load; bad values do not', () {
      expect(parseFieldTime('06:30'), (6, 30));
      expect(parseFieldTime('9:00'), (9, 0));
      expect(parseFieldTime('٠٩:٣٠'), (9, 30));
      expect(parseFieldTime('00:00'), (0, 0));
      expect(parseFieldTime('23:59'), (23, 59));
      expect(parseFieldTime('24:00'), isNull);
      expect(parseFieldTime(''), isNull);
      expect(parseFieldDateTime('2027-04-25 18:30'), (2027, 4, 25, 18, 30));
      expect(parseFieldDateTime('2027-04-25'), (2027, 4, 25, 0, 0));
      expect(parseFieldDateTime('2027-02-30'), isNull);
      expect(parseFieldDateTime(''), isNull);
    });
  });

  group('liturgy form', () {
    final def = collectionById('liturgies')!;

    testWidgets('time fields are read-only; the clock opens a 24-hour picker; saved HH:mm', (tester) async {
      Map<String, dynamic>? saved;
      await _pump(
          tester,
          DocEditor(
              title: 'Liturgy',
              fields: def.fields,
              def: def,
              popOnSave: false,
              data: const {'type': 'mass', 'nameAr': 'قداس', 'weekday': 4},
              onSave: (d) async => saved = {...?saved, ...d}));
      for (final k in ['start', 'end', 'date']) {
        final tf = tester.widget<TextField>(find.descendant(of: find.byKey(ValueKey('field-$k')), matching: find.byType(TextField)));
        expect(tf.readOnly, isTrue, reason: k);
      }
      expect(find.byKey(const ValueKey('pick-start')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-start')), matching: find.byIcon(Icons.access_time_rounded)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-date')), matching: find.byIcon(Icons.calendar_month_rounded)),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pick-start')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(MediaQuery.of(tester.element(find.byType(TimePickerDialog))).alwaysUse24HourFormat, isTrue);
      expect(find.text('AM'), findsNothing, reason: '24-hour: no AM/PM');
      await enterTimeInOpenPicker(tester, 6, 5);
      expect(_text(tester, 'start'), '06:05');

      // Tapping the field itself opens the picker too.
      await tester.tap(find.byKey(const ValueKey('field-end')));
      await tester.pumpAndSettle();
      await enterTimeInOpenPicker(tester, 23, 59);
      expect(_text(tester, 'end'), '23:59');
      await pickTime(tester, 'end', 0, 0);
      expect(_text(tester, 'end'), '00:00');

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['start'], '06:05');
      expect(saved?['end'], '00:00');
    });

    testWidgets('prefills the current value; date saved as the same stored instant; optional clears', (tester) async {
      Map<String, dynamic>? saved;
      await _pump(
          tester,
          DocEditor(
            title: 'Liturgy',
            fields: def.fields,
            def: def,
            popOnSave: false,
            data: {
              'type': 'mass',
              'nameAr': 'قداس',
              'date': CairoTime.at(2027, 1, 6).toUtc(),
              'start': '9:00', // legacy unpadded value still loads
              'end': '21:30',
            },
            onSave: (d) async => saved = {...?saved, ...d},
          ));
      expect(_text(tester, 'date'), '2027-01-06');
      // The picker opens on the stored time (21:30), OK keeps it padded.
      await tester.tap(find.byKey(const ValueKey('pick-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      expect(tester.widget<TextField>(fields.at(0)).controller?.text, '21');
      expect(tester.widget<TextField>(fields.at(1)).controller?.text, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Legacy "9:00" → padded on pick.
      await pickTime(tester, 'start', 9, 0);
      expect(_text(tester, 'start'), '09:00');
      // Date: the calendar opens on January 2027; pick the 15th.
      await pickDay(tester, 'date', 15);
      expect(_text(tester, 'date'), '2027-01-15');
      // Optional end can be cleared; required start has no clear button.
      expect(find.byKey(const ValueKey('clear-start')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('clear-end')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'end'), '');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['date'], CairoTime.at(2027, 1, 15).toUtc(), reason: 'stored type unchanged (instant)');
      expect(saved?['start'], '09:00');
      expect(saved?['end'], '');
    });

    testWidgets('Arabic RTL: the 24-hour picker opens and saves HH:mm', (tester) async {
      await _pump(tester, DocEditor(title: 'قداس', fields: def.fields, def: def, popOnSave: false, onSave: (d) async {}),
          locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('field-start')))), TextDirection.rtl);
      await pickTime(tester, 'start', 18, 30);
      expect(_text(tester, 'start'), '18:30');
    });
  });

  group('date-time and row fields', () {
    testWidgets('season startsAt: date then time; saved as the same Cairo instant (DateTime)', (tester) async {
      final def = collectionById('seasons')!;
      Map<String, dynamic>? saved;
      await _pump(
          tester,
          DocEditor(
            title: 'Season',
            fields: def.fields,
            def: def,
            popOnSave: false,
            data: {
              'key': 'holy_week',
              'nameAr': 'أسبوع الآلام',
              'startsAt': CairoTime.at(2027, 4, 25).toUtc(),
              'endsAt': CairoTime.at(2027, 5, 1, 18 * 60).toUtc(),
            },
            onSave: (d) async => saved = {...?saved, ...d},
          ));
      expect(_text(tester, 'startsAt'), '2027-04-25 00:00');
      expect(_text(tester, 'endsAt'), '2027-05-01 18:00');
      await tester.tap(find.byKey(const ValueKey('pick-startsAt')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('26')).last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(MediaQuery.of(tester.element(find.byType(TimePickerDialog))).alwaysUse24HourFormat, isTrue);
      await enterTimeInOpenPicker(tester, 18, 30);
      expect(_text(tester, 'startsAt'), '2027-04-26 18:30');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['startsAt'], isA<DateTime>());
      expect(saved?['startsAt'], CairoTime.at(2027, 4, 26, 18 * 60 + 30).toUtc());
    });

    testWidgets('Today settings: dayStartsAt (time), liveEndsAt (date-time), church-event rows (date / time)',
        (tester) async {
      Map<String, dynamic>? saved;
      await _pump(
          tester,
          DocEditor(
            title: 'Today',
            fields: todaySettingsDoc.fields,
            popOnSave: false,
            data: {
              'dayEvents': ['2027-04-29\u001f\u001f18:00\u001f\u001fبصخة ليلة الجمعة\u001f'],
            },
            onSave: (d) async => saved = {...?saved, ...d},
          ));
      await pickTime(tester, 'dayStartsAt', 17, 45);
      expect(_text(tester, 'dayStartsAt'), '17:45');
      expect(find.byKey(const ValueKey('pick-liveEndsAt')), findsOneWidget);
      expect(_text(tester, 'start', index: 0), isNot(''), reason: 'row prefilled');
      await pickTime(tester, 'end', 21, 0);
      await pickDay(tester, 'date', 30); // opens on the row's April 2027
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['dayStartsAt'], '17:45');
      final row = (saved?['dayEvents'] as List).single as String;
      final parts = row.split('\u001f');
      expect(parts.take(4).toList(), ['2027-04-30', '', '18:00', '21:00']);
    });
  });
}
