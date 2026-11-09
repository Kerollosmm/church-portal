import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/calendar_ics.dart';

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  group('RFC 5545 calendar_ics', () {
    test('escapeIcsText escapes special characters and newlines', () {
      expect(escapeIcsText('Hello, world; with \\ backslash\nand newline'),
          r'Hello\, world\; with \\ backslash\nand newline');
      expect(escapeIcsText('Clean text 123'), 'Clean text 123');
    });

    test('foldIcsLine folds lines > 75 UTF-8 octets without breaking characters', () {
      // Long ASCII line
      final longAscii = 'SUMMARY:${'A' * 80}';
      final folded = foldIcsLine(longAscii);
      final lines = folded.split('\r\n');
      expect(lines.length, greaterThan(1));
      for (var i = 0; i < lines.length; i++) {
        final lineBytes = utf8.encode(lines[i]).length;
        expect(lineBytes, lessThanOrEqualTo(75), reason: 'Line $i exceeds 75 octets: ${lines[i]}');
        if (i > 0) {
          expect(lines[i].startsWith(' '), isTrue, reason: 'Continuation line must start with space');
        }
      }

      // Long Arabic line (Arabic characters are multi-byte UTF-8, typically 2 bytes each)
      const arabicText = 'SUMMARY:صلوات البصخة المقدسة ليوم الجمعة العظيمة بكنيسة القديسين مكسيموس ودوماديوس';
      final foldedArabic = foldIcsLine(arabicText);
      final arabicLines = foldedArabic.split('\r\n');
      for (var i = 0; i < arabicLines.length; i++) {
        final lineBytes = utf8.encode(arabicLines[i]).length;
        expect(lineBytes, lessThanOrEqualTo(75), reason: 'Arabic line $i exceeds 75 octets');
        if (i > 0) {
          expect(arabicLines[i].startsWith(' '), isTrue);
        }
      }
    });

    test('buildReminderIcs generates valid one-off event with VALARM', () {
      final startsAt = DateTime.utc(2026, 11, 15, 8, 30);
      final nowUtc = DateTime.utc(2026, 11, 9, 12, 0);

      final ics = buildReminderIcs(
        uid: 'rem-lit-1-20261115',
        title: 'قداس الأحد الأول',
        startsAt: startsAt,
        leadMinutes: 60,
        description: 'القداس الإلهي',
        location: 'المذبح الأوسط',
        nowUtc: nowUtc,
      );

      expect(ics, contains('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('VERSION:2.0\r\n'));
      expect(ics, contains('PRODID:-//Maximos Domadios Church//Portal//AR\r\n'));
      expect(ics, contains('CALSCALE:GREGORIAN\r\n'));
      expect(ics, contains('METHOD:PUBLISH\r\n'));
      expect(ics, contains('BEGIN:VEVENT\r\n'));
      expect(ics, contains('UID:rem-lit-1-20261115\r\n'));
      expect(ics, contains('DTSTAMP:20261109T120000Z\r\n'));
      expect(ics, contains('DTSTART:20261115T083000Z\r\n'));
      expect(ics, contains('DTEND:20261115T093000Z\r\n'));
      expect(ics, contains('SUMMARY:قداس الأحد الأول\r\n'));
      expect(ics, contains('DESCRIPTION:القداس الإلهي\r\n'));
      expect(ics, contains('LOCATION:المذبح الأوسط\r\n'));
      expect(ics, contains('BEGIN:VALARM\r\n'));
      expect(ics, contains('ACTION:DISPLAY\r\n'));
      expect(ics, contains('TRIGGER:-PT60M\r\n'));
      expect(ics, contains('END:VALARM\r\n'));
      expect(ics, contains('END:VEVENT\r\n'));
      expect(ics, contains('END:VCALENDAR\r\n'));
    });

    test('buildReminderIcs uses -PT0S trigger when leadMinutes <= 0', () {
      final startsAt = DateTime.utc(2026, 11, 15, 8, 30);
      final ics = buildReminderIcs(
        uid: 'rem-0',
        title: 'القداس',
        startsAt: startsAt,
        leadMinutes: 0,
      );
      expect(ics, contains('TRIGGER:-PT0S\r\n'));
    });

    test('buildReminderIcs generates weekly recurring event with Cairo wall time & RRULE', () {
      // 2026-11-15 is Sunday (weekday 7 in ISO, so BYDAY=SU)
      final startsAtCairo = CairoTime.at(2026, 11, 15, 8 * 60 + 30);
      final ics = buildReminderIcs(
        uid: 'rem-weekly-sun',
        title: 'قداس الأحد الأسبوعي',
        startsAt: startsAtCairo,
        leadMinutes: 15,
        recurringWeekly: true,
      );

      expect(ics, contains('DTSTART;TZID=Africa/Cairo:20261115T083000\r\n'));
      expect(ics, contains('DTEND;TZID=Africa/Cairo:20261115T093000\r\n'));
      expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=SU\r\n'));
      expect(ics, contains('TRIGGER:-PT15M\r\n'));
    });

    test('singleCalendarUrl formats Google Calendar template link in Cairo time', () {
      final startsAt = DateTime.utc(2026, 11, 15, 6, 30); // 08:30 Cairo winter (UTC+2)
      final url = singleCalendarUrl(
        title: 'قداس خاص',
        startsAt: startsAt,
        details: 'تفاصيل الخدمة',
        location: 'الكنيسة الرئيسية',
      );

      expect(url, startsWith('https://calendar.google.com/calendar/render?'));
      expect(url, contains('action=TEMPLATE'));
      expect(url, contains('text=%D9%82%D8%AF%D8%A7%D8%B3+%D8%AE%D8%A7%D8%B5'));
      expect(url, contains('dates=20261115T083000%2F20261115T093000'));
      expect(url, contains('ctz=Africa%2FCairo'));
      expect(url, contains('details='));
      expect(url, contains('location='));
    });
  });
}
