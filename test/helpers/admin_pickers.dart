// Test helpers for the admin time / date pickers (ADR-049): the fields are
// read-only, so tests fill them through the real pickers. The time picker is
// 12-hour (AM/PM); the stored value stays 24-hour "HH:mm".
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

MaterialLocalizations _l(WidgetTester tester) => MaterialLocalizations.of(tester.element(find.byType(Dialog).last));

/// Opens the clock icon of field [key] ([index] for rows), enters the 24-hour
/// [hour] and [minute] on the 12-hour picker (hour 1–12 + AM/PM) in its
/// keyboard mode and confirms.
Future<void> pickTime(WidgetTester tester, String key, int hour, int minute, {int index = 0}) async {
  final icon = find.byKey(ValueKey('pick-$key')).at(index);
  await tester.ensureVisible(icon);
  await tester.tap(icon);
  await tester.pumpAndSettle();
  await enterTimeInOpenPicker(tester, hour, minute);
}

/// The localized AM / PM labels of the open picker ("AM"/"PM", «ص»/«م»).
(String, String) dayPeriodLabels(WidgetTester tester) =>
    (_l(tester).anteMeridiemAbbreviation, _l(tester).postMeridiemAbbreviation);

/// The 12-hour picker is open: switch to keyboard entry, choose AM / PM,
/// type the 12-hour hour and the minute, OK. [hour] is 24-hour (0–23).
Future<void> enterTimeInOpenPicker(WidgetTester tester, int hour, int minute) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final dialog = find.byType(Dialog).last;
  final (am, pm) = dayPeriodLabels(tester);
  await tester.tap(find.descendant(of: dialog, matching: find.text(hour < 12 ? am : pm)).last);
  await tester.pumpAndSettle();
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  final fields = find.descendant(of: dialog, matching: find.byType(TextField));
  await tester.enterText(fields.at(0), '$hour12');
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
