import 'models.dart';
import 'schedule.dart';
import 'time_format.dart';

/// Builds the grounding system instruction for the "Ask the church"
/// assistant from the current portal content.
String buildAssistantInstruction({
  required ChurchSettings settings,
  required List<Liturgy> liturgies,
  required List<Season> seasons,
  required List<Clinic> clinics,
  required List<Meeting> meetings,
  required List<Activity> activities,
  required List<Facility> facilities,
  required DateTime now,
}) {
  final b = StringBuffer()
    ..writeln('You are the friendly information desk of ${settings.nameEn} (${settings.nameAr}), '
        'a Coptic Orthodox church at ${settings.addressEn} (${settings.addressAr}).')
    ..writeln('Answer ONLY from the church data below. If the answer is not in the data, say you do not know '
        'and suggest calling the church. Never invent times, names or phone numbers.')
    ..writeln('Reply in the language of the question (Egyptian-friendly Modern Standard Arabic or English). '
        'Keep answers short (max ~6 lines), use bullet points for lists, and give times like 06:30 AM.')
    ..writeln('All times are Africa/Cairo local time. Current Cairo time: ${now.toIso8601String()} '
        '(${weekdayNamesEn[now.weekday]}).')
    ..writeln('Do not give medical, legal or spiritual-direction advice beyond pointing to the right clinic, '
        'meeting or priest. Do not collect personal data.')
    ..writeln()
    ..writeln('## Contacts')
    ..writeln('Address: ${settings.addressEn} / ${settings.addressAr}')
    ..writeln('Directions: ${settings.transportEn}')
    ..writeln('Google Maps: ${settings.mapsUrl}');
  for (final p in settings.phones) {
    b.writeln('Phone - ${p.labelEn} / ${p.labelAr}: ${p.number}');
  }
  if (settings.whatsapp.isNotEmpty) b.writeln('WhatsApp: ${settings.whatsapp}');
  if (settings.facebook.isNotEmpty) b.writeln('Facebook: ${settings.facebook}');
  if (settings.youtube.isNotEmpty) b.writeln('YouTube (live): ${settings.youtube}');

  b
    ..writeln()
    ..writeln('## Weekly liturgy schedule (regular)');
  final regular = liturgies.where((l) => l.seasonKey == null && l.weekday != null).toList()
    ..sort((a, b) {
      final w = a.weekday!.compareTo(b.weekday!);
      return w != 0 ? w : (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    });
  for (final l in regular) {
    b.writeln('- ${weekdayNamesEn[l.weekday!]}: ${l.nameEn} (${l.nameAr}) [${l.type}] '
        '${formatRangeLatin(l.start, l.end)} at ${l.placeEn}${l.audienceEn.isNotEmpty ? ' - ${l.audienceEn}' : ''}');
  }

  final seasonal = seasonalSchedule(seasons, liturgies);
  if (seasonal.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Holy seasons (these REPLACE the regular schedule on the days they cover)');
    for (final e in seasonal.entries) {
      final s = e.key;
      b.writeln('### ${s.nameEn} (${s.nameAr}) ${s.startsAt?.toIso8601String() ?? ''} -> ${s.endsAt?.toIso8601String() ?? ''}'
          '${isSeasonActiveAt(s, now) ? ' [ACTIVE NOW]' : ''}');
      for (final l in e.value) {
        final when = l.date != null
            ? l.date!.toIso8601String().substring(0, 10)
            : weekdayNamesEn[l.weekday ?? 0];
        b.writeln('- $when: ${l.nameEn} ${formatRangeLatin(l.start, l.end)} at ${l.placeEn}');
      }
    }
  }

  b
    ..writeln()
    ..writeln('## Clinics (book by phone or WhatsApp)');
  for (final c in clinics.where((c) => c.active)) {
    b.writeln('- ${c.specialtyEn} (${c.specialtyAr}): ${c.doctorName}, ${c.degreeAr}; '
        '${c.days.map((d) => weekdayNamesEn[d]).join(', ')} ${formatRangeLatin(c.start, c.end)}; booking ${c.bookingPhone}');
  }

  b
    ..writeln()
    ..writeln('## Sunday school & meetings');
  for (final m in meetings) {
    b.writeln('- ${m.nameEn} (${m.nameAr}) [${m.stage}]: ${weekdayNamesEn[m.weekday ?? 0]} '
        '${formatRangeLatin(m.start, m.end)} at ${m.hallEn}; Facebook ${m.facebookUrl}; WhatsApp ${m.whatsappUrl}');
  }

  b
    ..writeln()
    ..writeln('## Activities');
  for (final a in activities) {
    b.writeln('- ${a.titleEn} (${a.titleAr}): ${a.descEn} Schedule: ${a.scheduleEn}. Ages: ${a.ageRange}.'
        '${a.contactPhone.isNotEmpty ? ' Contact ${a.contactPhone}.' : ''}');
  }

  b
    ..writeln()
    ..writeln('## Public services');
  for (final f in facilities) {
    b.writeln('- ${f.nameEn} (${f.nameAr}): ${f.descEn} Hours: ${f.hoursEn}.${f.phone.isNotEmpty ? ' Phone ${f.phone}.' : ''}');
  }
  return b.toString();
}
