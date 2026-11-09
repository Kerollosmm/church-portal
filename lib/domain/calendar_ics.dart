// Pure Dart RFC 5545 iCalendar (.ics) generator and calendar link helper (ADR-060).
// Zero Flutter / web imports: pure Dart, fully unit-tested.

import 'dart:convert' show utf8;

import 'cairo_time.dart';

const _rruleDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Escapes a TEXT property value per RFC 5545 §3.3.11.
///
/// Backslashes, semicolons, commas, and newlines must be backslash-escaped.
String escapeIcsText(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    switch (ch) {
      case r'\':
        buf.write(r'\\');
      case ';':
        buf.write(r'\;');
      case ',':
        buf.write(r'\,');
      case '\r':
        break;
      case '\n':
        buf.write(r'\n');
      default:
        buf.write(ch);
    }
  }
  return buf.toString();
}

/// Folds a single content line at <= 75 UTF-8 octets per RFC 5545 §3.1.
///
/// Multi-byte UTF-8 sequences are never split across fold boundaries.
String foldIcsLine(String line) {
  final chars = line.runes;
  final result = StringBuffer();
  var currentLineByteCount = 0;

  for (final rune in chars) {
    final charStr = String.fromCharCode(rune);
    final charByteLength = utf8.encode(charStr).length;

    if (currentLineByteCount > 0 && currentLineByteCount + charByteLength > 75) {
      result.write('\r\n ');
      currentLineByteCount = 1;
    }
    result.write(charStr);
    currentLineByteCount += charByteLength;
  }
  return result.toString();
}

String _formatUtc(DateTime d) {
  final u = d.toUtc();
  return '${u.year}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

String _formatCairoWall(DateTime d) {
  final c = CairoTime.fromInstant(d);
  return '${c.year}${_two(c.month)}${_two(c.day)}T${_two(c.hour)}${_two(c.minute)}${_two(c.second)}';
}

/// Builds an RFC 5545 compliant `.ics` calendar string for an event reminder.
///
/// If [recurringWeekly] is true, emits a `TZID=Africa/Cairo` DTSTART and an
/// `RRULE:FREQ=WEEKLY;BYDAY=...` so recurring weekly events preserve wall time
/// across Cairo DST transitions. One-off events use UTC timestamps (`...Z`).
///
/// Includes an RFC 5545 `VALARM` displaying [title] with a trigger offset of
/// [leadMinutes] (e.g. `-PT60M`, or `-PT0S` when [leadMinutes] <= 0).
String buildReminderIcs({
  String? uid,
  required String title,
  required DateTime startsAt,
  DateTime? endsAt,
  required int leadMinutes,
  bool recurringWeekly = false,
  String description = '',
  String location = '',
  DateTime? nowUtc,
}) {
  final effectiveUid = uid ?? 'rem_${startsAt.millisecondsSinceEpoch}@maximos-domadios';
  final effectiveEndsAt = endsAt ?? startsAt.add(const Duration(hours: 1));
  final stamp = _formatUtc(nowUtc ?? DateTime.now().toUtc());

  final rawLines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Maximos Domadios Church//Portal//AR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$effectiveUid',
    'DTSTAMP:$stamp',
  ];

  if (recurringWeekly) {
    final cairoStart = CairoTime.fromInstant(startsAt);
    final byDay = _rruleDays[cairoStart.weekday - 1];
    rawLines.add('DTSTART;TZID=Africa/Cairo:${_formatCairoWall(startsAt)}');
    rawLines.add('DTEND;TZID=Africa/Cairo:${_formatCairoWall(effectiveEndsAt)}');
    rawLines.add('RRULE:FREQ=WEEKLY;BYDAY=$byDay');
  } else {
    rawLines.add('DTSTART:${_formatUtc(startsAt)}');
    rawLines.add('DTEND:${_formatUtc(effectiveEndsAt)}');
  }

  rawLines.add('SUMMARY:${escapeIcsText(title)}');
  if (description.isNotEmpty) {
    rawLines.add('DESCRIPTION:${escapeIcsText(description)}');
  }
  if (location.isNotEmpty) {
    rawLines.add('LOCATION:${escapeIcsText(location)}');
  }

  // VALARM section
  final trigger = leadMinutes <= 0 ? '-PT0S' : '-PT${leadMinutes}M';
  rawLines.addAll([
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    'DESCRIPTION:${escapeIcsText(title)}',
    'TRIGGER:$trigger',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ]);

  final foldedLines = rawLines.map(foldIcsLine);
  return '${foldedLines.join('\r\n')}\r\n';
}

/// Google Calendar "add event" link for a one-off event.
///
/// Uses Cairo local wall time with `ctz=Africa/Cairo` so the user's calendar
/// converts correctly to local time wherever they are.
String singleCalendarUrl({
  required String title,
  required DateTime startsAt,
  DateTime? endsAt,
  String details = '',
  String location = '',
}) {
  final startCairo = CairoTime.fromInstant(startsAt);
  final endCairo = CairoTime.fromInstant(endsAt ?? startsAt.add(const Duration(hours: 1)));
  final startStamp =
      '${startCairo.year}${_two(startCairo.month)}${_two(startCairo.day)}T${_two(startCairo.hour)}${_two(startCairo.minute)}00';
  final endStamp =
      '${endCairo.year}${_two(endCairo.month)}${_two(endCairo.day)}T${endCairo.hour.toString().padLeft(2, '0')}${_two(endCairo.minute)}00';

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '$startStamp/$endStamp',
    'ctz': 'Africa/Cairo',
    if (details.isNotEmpty) 'details': details,
    if (location.isNotEmpty) 'location': location,
  }).toString();
}
