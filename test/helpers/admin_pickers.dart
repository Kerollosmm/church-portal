// Test helpers for the admin time / date pickers (ADR-048): the fields are
// read-only, so tests fill them through the real pickers.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

MaterialLocalizations _l(WidgetTester tester) => MaterialLocalizations.of(tester.element(find.byType(Dialog).last));

/// Opens the clock icon of field [key] ([index] for rows), types [hour] and
/// [minute] in the picker's keyboard mode and confirms.
Future<void> pickTime(WidgetTester tester, String key, int hour, int minute, {int index = 0}) async {
  final icon = find.byKey(ValueKey('pick-$key')).at(index);
  await tester.ensureVisible(icon);
  await tester.tap(icon);
  await tester.pumpAndSettle();
  await enterTimeInOpenPicker(tester, hour, minute);
}

/// The time picker is open: switch to keyboard entry, type, OK.
Future<void> enterTimeInOpenPicker(WidgetTester tester, int hour, int minute) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(of: find.byType(Dialog).last, matching: find.byType(TextField));
  await tester.enterText(fields.at(0), '$hour');
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_l(tester).okButtonLabel));
  await tester.pumpAndSettle();
}

/// Opens the calendar icon of field [key], taps [day] of the month shown
/// (the current value's month, else this month) and confirms.
Future<void> pickDay(WidgetTester tester, String key, int day, {int index = 0}) async {
  final icon = find.byKey(ValueKey('pick-$key')).at(index);
  await tester.ensureVisible(icon);
  await tester.tap(icon);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byType(Dialog).last, matching: find.text(_l(tester).formatDecimal(day))).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(_l(tester).okButtonLabel));
  await tester.pumpAndSettle();
}
