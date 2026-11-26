// ADR-049 item 5: admin time / date pickers. Every FieldType.time / date /
// dateTime field (top-level and inside rows) can be typed directly or filled
// from showTimePicker (12-hour AM/PM, ص/م in Arabic) / showDatePicker; stored
// strictly as 24-hour "HH:mm", "YYYY-MM-DD" or the unchanged date-time
// instant. The field shows the friendly 12-hour reading under it.
import 'dart:async';

import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
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

    testWidgets('time and date fields remain directly editable; the clock opens a 12-hour AM/PM picker; saved 24h HH:mm', (tester) async {
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
        expect(tf.readOnly, isFalse, reason: k);
      }
      expect(find.byKey(const ValueKey('pick-start')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-start')), matching: find.byIcon(Icons.access_time_rounded)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-date')), matching: find.byIcon(Icons.calendar_month_rounded)),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pick-start')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(MediaQuery.of(tester.element(find.byType(TimePickerDialog))).alwaysUse24HourFormat, isFalse);
      final dialog = find.byType(TimePickerDialog);
      expect(find.descendant(of: dialog, matching: find.text('AM')), findsWidgets, reason: '12-hour: AM/PM shown');
      expect(find.descendant(of: dialog, matching: find.text('PM')), findsWidgets);
      await enterTimeInOpenPicker(tester, 6, 5); // 6:05 AM
      expect(_text(tester, 'start'), '06:05');
      expect(find.text('06:05 AM'), findsOneWidget, reason: '12-hour reading under the field');

      // The picker button opens the time picker for end without blocking direct field focus/typing.
      await tester.tap(find.byKey(const ValueKey('pick-end')));
      await tester.pumpAndSettle();
      await enterTimeInOpenPicker(tester, 23, 59); // 11:59 PM
      expect(_text(tester, 'end'), '23:59');
      expect(find.text('11:59 PM'), findsOneWidget);
      await pickTime(tester, 'end', 0, 0); // 12:00 AM
      expect(_text(tester, 'end'), '00:00');
      expect(find.text('12:00 AM'), findsOneWidget);
      await pickTime(tester, 'start', 12, 0); // 12:00 PM
      expect(_text(tester, 'start'), '12:00');
      expect(find.text('12:00 PM'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['start'], '12:00');
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
      expect(find.text('09:30 PM'), findsOneWidget, reason: 'reading of the stored 21:30');
      // The picker opens on the stored time (21:30 = 9:30 PM), OK keeps 21:30.
      await tester.tap(find.byKey(const ValueKey('pick-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      expect(tester.widget<TextField>(fields.at(0)).controller?.text, '9');
      expect(tester.widget<TextField>(fields.at(1)).controller?.text, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'end'), '21:30');
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

    testWidgets('Arabic RTL: the 12-hour picker shows ص/م and saves 24h HH:mm', (tester) async {
      await _pump(tester, DocEditor(title: 'قداس', fields: def.fields, def: def, popOnSave: false, onSave: (d) async {}),
          locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('field-start')))), TextDirection.rtl);
      await tester.tap(find.byKey(const ValueKey('pick-start')));
      await tester.pumpAndSettle();
      final dialog = find.byType(TimePickerDialog);
      expect(MediaQuery.of(tester.element(dialog)).alwaysUse24HourFormat, isFalse);
      expect(find.descendant(of: dialog, matching: find.text('ص')), findsWidgets);
      expect(find.descendant(of: dialog, matching: find.text('م')), findsWidgets);
      await enterTimeInOpenPicker(tester, 18, 30); // ٦:٣٠ م
      expect(_text(tester, 'start'), '18:30');
      expect(find.text('٠٦:٣٠ م'), findsOneWidget, reason: 'Arabic 12-hour reading');
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
      expect(MediaQuery.of(tester.element(find.byType(TimePickerDialog))).alwaysUse24HourFormat, isFalse);
      await enterTimeInOpenPicker(tester, 18, 30); // 6:30 PM
      expect(_text(tester, 'startsAt'), '2027-04-26 18:30');
      expect(find.text('26 Apr 2027, 06:30 PM'), findsOneWidget);
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

  group('PR 3F (P2-26): looseDate picker & labels without HH:mm', () {
    test('parseLooseDate and formatLooseDateValue handle year, year-month, full dates, and Arabic digits', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2025, 2), 28);
      expect(parseLooseDate(''), isNull);
      expect(parseLooseDate('95'), isNull);
      expect(parseLooseDate('1995'), (year: 1995, month: null, day: null));
      expect(parseLooseDate('١٩٩٥'), (year: 1995, month: null, day: null));
      expect(parseLooseDate('2009-03'), (year: 2009, month: 3, day: null));
      expect(parseLooseDate('٢٠٠٩-٠٣-٠٨'), (year: 2009, month: 3, day: 8));
      expect(parseLooseDate('2025-02-29'), isNull);

      expect(formatLooseDateValue(1995), '1995');
      expect(formatLooseDateValue(2009, 3), '2009-03');
      expect(formatLooseDateValue(2009, 3, 8), '2009-03-08');
      expect(formatLooseDateValue(2025, 2, 31), '2025-02-28');
    });

    test('no admin field label, hint, or string exposes "HH:mm"', () {
      for (final def in adminCollections) {
        for (final f in def.fields) {
          expect(f.labelAr, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}');
          expect(f.labelEn, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}');
          expect(f.hintAr, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}');
          expect(f.hintEn, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}');
          for (final sf in f.subFields) {
            expect(sf.labelAr, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}.${sf.key}');
            expect(sf.labelEn, isNot(contains('HH:mm')), reason: '${def.id}.${f.key}.${sf.key}');
          }
        }
      }
      for (final doc in [churchInfoDoc, todaySettingsDoc, seasonSettingsDoc, appInstallDoc]) {
        for (final f in doc.fields) {
          expect(f.labelAr, isNot(contains('HH:mm')), reason: '${doc.path}.${f.key}');
          expect(f.labelEn, isNot(contains('HH:mm')), reason: '${doc.path}.${f.key}');
          expect(f.hintAr, isNot(contains('HH:mm')), reason: '${doc.path}.${f.key}');
          expect(f.hintEn, isNot(contains('HH:mm')), reason: '${doc.path}.${f.key}');
        }
      }
      for (final e in adminStrings.entries) {
        expect(e.value[0], isNot(contains('HH:mm')), reason: e.key);
        expect(e.value[1], isNot(contains('HH:mm')), reason: e.key);
      }
    });

    testWidgets('priests looseDate shows Arabic months in picker, supports year-only & manual typing', (tester) async {
      final def = collectionById('priests')!;
      Map<String, dynamic>? saved;
      await _pump(
        tester,
        DocEditor(
          title: 'كاهن',
          fields: def.fields,
          def: def,
          popOnSave: false,
          data: const {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving'},
          onSave: (d) async => saved = {...?saved, ...d},
        ),
        locale: const Locale('ar'),
      );

      // looseDate remains directly editable alongside time/date fields.
      final ordField = tester.widget<TextField>(
          find.descendant(of: find.byKey(const ValueKey('field-ordinationDate')), matching: find.byType(TextField)));
      expect(ordField.readOnly, isFalse);

      // Open the picker and choose Year + Arabic Month + Day.
      await tester.tap(find.byKey(const ValueKey('pick-ordinationDate')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('looseDate-year')), '2009');
      await tester.tap(find.byKey(const ValueKey('looseDate-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مارس').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'بدون يوم'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('٨').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('looseDate-ok')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'ordinationDate'), '2009-03-08');

      // Typing a bare year still validates & saves cleanly.
      await tester.enterText(find.byKey(const ValueKey('field-hegumenDate')), '1995');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['ordinationDate'], '2009-03-08');
      expect(saved?['hegumenDate'], '1995');
    });

    testWidgets('looseDate picker preserves Feb 29 while typing a different leap year', (tester) async {
      final def = collectionById('priests')!;
      await _pump(
        tester,
        DocEditor(
          title: 'كاهن',
          fields: def.fields,
          def: def,
          popOnSave: false,
          data: const {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving', 'ordinationDate': '2000-02-29'},
          onSave: (_) async {},
        ),
        locale: const Locale('en'),
      );
      await tester.tap(find.byKey(const ValueKey('pick-ordinationDate')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('looseDate-year')), '200');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('looseDate-year')), '2004');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('looseDate-ok')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'ordinationDate'), '2004-02-29');
    });
  });

  group('PR 6C (P6C-2 & P6C-3): typed date/time, saving progress, hide docId', () {
    FieldDef field(FieldType type) => FieldDef('f', 'حقل', 'Field', type);

    test('validateFieldValue & parseFieldValue normalize Arabic-Indic digits and unpadded hours, and reject invalid dates/times', () {
      expect(validateFieldValue(field(FieldType.time), '٠٦:٣٠'), isNull);
      expect(parseFieldValue(field(FieldType.time), '٠٦:٣٠'), '06:30');
      expect(validateFieldValue(field(FieldType.time), '9:00'), isNull);
      expect(parseFieldValue(field(FieldType.time), '9:00'), '09:00');
      expect(validateFieldValue(field(FieldType.time), '25:00'), 'invalidTime');

      expect(validateFieldValue(field(FieldType.date), '٢٠٢٧-٠١-٠٦'), isNull);
      expect(parseFieldValue(field(FieldType.date), '٢٠٢٧-٠١-٠٦'), CairoTime.at(2027, 1, 6).toUtc());
      expect(validateFieldValue(field(FieldType.date), '2027-02-30'), 'invalidDate');

      expect(validateFieldValue(field(FieldType.dateTime), '٢٠٢٧-٠١-٠٦ ٢٠:٠٠'), isNull);
      expect(parseFieldValue(field(FieldType.dateTime), '٢٠٢٧-٠١-٠٦ ٢٠:٠٠'), DateTime.utc(2027, 1, 6, 18, 0));
      expect(validateFieldValue(field(FieldType.dateTime), '2027-01-06 25:00'), 'invalidDate');
    });

    testWidgets('DocEditor allows typing Arabic-Indic time without modal, shows saving label while pending, and hides docId',
        (tester) async {
      final def = collectionById('liturgies')!;
      final completer = Completer<void>();
      Map<String, dynamic>? saved;

      await _pump(
        tester,
        DocEditor(
          title: 'تعديل قداس',
          docId: 'lit-42',
          fields: def.fields,
          def: def,
          popOnSave: false,
          data: const {'type': 'mass', 'nameAr': 'قداس', 'weekday': 4, 'start': '07:00'},
          onSave: (d) async {
            saved = {...?saved, ...d};
            return completer.future;
          },
        ),
        locale: const Locale('ar'),
      );

      expect(find.textContaining('ID: lit-42'), findsNothing);

      final startField = tester.widget<TextField>(
          find.descendant(of: find.byKey(const ValueKey('field-start')), matching: find.byType(TextField)));
      expect(startField.readOnly, isFalse);

      await tester.enterText(find.byKey(const ValueKey('field-start')), '٠٩:٣٠');
      await tester.pump();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('٠٩:٣٠ ص'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pump();
      // Both DocEditor saveButton and UnsavedBar show the Arabic saving progress text.
      expect(find.text('جارٍ الحفظ…'), findsNWidgets(2));

      completer.complete();
      await tester.pumpAndSettle();
      expect(saved?['start'], '09:30');
    });

    testWidgets('DocEditor top-bar save shows Saving… while pending and object-list rows canonicalize Arabic digits',
        (tester) async {
      final completer = Completer<void>();
      Map<String, dynamic>? saved;

      await _pump(
        tester,
        DocEditor(
          title: 'Today',
          docId: 'features',
          fields: todaySettingsDoc.fields,
          popOnSave: true,
          data: const {
            'dayEvents': ['2027-04-29\u001f\u001f18:00\u001f\u001fبصخة\u001f'],
          },
          onSave: (d) async {
            saved = {...?saved, ...d};
            return completer.future;
          },
        ),
        locale: const Locale('en'),
      );

      expect(find.textContaining('ID: features'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('field-date')).first, '٢٠٢٧-٠٤-٣٠');
      await tester.enterText(find.byKey(const ValueKey('field-start')).first, '٩:٠٠');
      await tester.pump();

      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pump();
      // Top bar Action + UnsavedBar + saveButton all reflect Saving… while in flight.
      expect(find.text('Saving…'), findsNWidgets(3));

      completer.complete();
      await tester.pumpAndSettle();
      final row = (saved?['dayEvents'] as List).single as String;
      expect(row.split('\u001f').take(4).toList(), ['2027-04-30', '', '09:00', '']);
    });

    testWidgets('DocEditor dateTime preview + UTC serialization and invalid typed date/time block save',
        (tester) async {
      final def = collectionById('seasons')!;
      Map<String, dynamic>? saved;
      await _pump(
        tester,
        DocEditor(
          title: 'موسم',
          fields: def.fields,
          def: def,
          popOnSave: false,
          data: const {'key': 'nativity', 'nameAr': 'صوم الميلاد'},
          onSave: (d) async => saved = {...?saved, ...d},
        ),
        locale: const Locale('ar'),
      );

      // Invalid typed date (Feb 30) & invalid time (25:00) block save.
      await tester.enterText(find.byKey(const ValueKey('field-startsAt')), '2027-02-30 10:00');
      await tester.enterText(find.byKey(const ValueKey('field-endsAt')), '2027-01-06 25:00');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);

      // Valid typed Arabic-Indic dateTime updates 12h preview & saves Cairo UTC DateTime.
      await tester.enterText(find.byKey(const ValueKey('field-startsAt')), '٢٠٢٧-٠١-٠٦ ٢٠:٠٠');
      await tester.enterText(find.byKey(const ValueKey('field-endsAt')), '٢٠٢٧-٠١-٠٧ ٢٠:٠٠');
      await tester.pump();
      expect(find.textContaining('٠٨:٠٠ م'), findsWidgets);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved?['startsAt'], DateTime.utc(2027, 1, 6, 18, 0));
      expect(saved?['endsAt'], DateTime.utc(2027, 1, 7, 18, 0));
    });

    testWidgets('DocEditor replacesDayPreview parses typed Arabic-Indic date and times and ignores rolled invalid dates',
        (tester) async {
      final def = collectionById('liturgies')!;
      await _pump(
        tester,
        DocEditor(
          title: 'قداس عيد',
          fields: def.fields,
          def: def,
          popOnSave: false,
          existingDocs: const [
            AdminDoc('reg-sun', {
              'type': 'mass',
              'nameAr': 'قداس الأحد المعتاد',
              'weekday': 7,
              'start': '07:00',
              'end': '09:30',
              'visible': true,
            }),
          ],
          data: const {
            'type': 'mass',
            'nameAr': 'قداس أحد الشعانين',
            'replacesDay': true,
          },
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      );

      // Invalid calendar date 2027-02-30 must NOT silently roll over to March 2.
      await tester.enterText(find.byKey(const ValueKey('field-date')), '2027-02-30');
      await tester.enterText(find.byKey(const ValueKey('field-start')), '٠٩:٠٠');
      await tester.enterText(find.byKey(const ValueKey('field-end')), '١١:٠٠');
      await tester.pump();
      expect(find.textContaining('مارس'), findsNothing);

      // Typed Arabic-Indic Sunday 2027-04-25 previews Sunday's superseded mass.
      await tester.enterText(find.byKey(const ValueKey('field-date')), '٢٠٢٧-٠٤-٢٥');
      await tester.pump();
      final preview = find.byKey(const ValueKey('replacesDayPreview'));
      expect(preview, findsOneWidget);
      expect(find.descendant(of: preview, matching: find.textContaining('الأحد ٢٥ أبريل ٢٠٢٧')), findsOneWidget);
      expect(find.descendant(of: preview, matching: find.textContaining('قداس الأحد المعتاد')), findsOneWidget);
    });
  });
}
