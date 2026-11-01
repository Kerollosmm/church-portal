import 'cairo_time.dart';
import 'features.dart';
import 'models.dart';
import 'rules.dart';
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
  FeatureSettings features = FeatureSettings.defaults,
  List<Alert> alerts = const [],
  List<Priest> priests = const [],
  List<Saint> saints = const [],
}) {
  final f = features;
  final b = StringBuffer()
    ..writeln(
      'You are the friendly information desk of ${_bi(settings.nameAr, settings.nameEn)}, a Coptic Orthodox church'
      '${f.enabled(Sections.contactInfo) ? _at(_bi(settings.addressAr, settings.addressEn)) : ''}.',
    )
    ..writeln(
      'Answer ONLY from the church data below. If the answer is not in the data, say you do not know '
      'and suggest calling the church. Never invent times, names or phone numbers.',
    )
    ..writeln(
      'Reply in the language of the question (Egyptian-friendly Modern Standard Arabic or English). '
      'Keep answers short (max ~6 lines), use bullet points for lists, and give times like 06:30 AM.',
    )
    ..writeln(
      'All times are Africa/Cairo local time. Today in Cairo: ${_ymd(now)} '
      '(${weekdayNamesEn[now.weekday]}). Each question starts with the exact current Cairo time.',
    )
    ..writeln(
      'Do not give medical, legal or spiritual-direction advice beyond pointing to the right clinic, '
      'meeting or priest. Do not collect personal data.',
    )
    ..writeln('Topics without a section below are not offered on this portal: say so briefly.')
    ..writeln()
    ..writeln('## Contacts');
  if (f.enabled(Sections.contactInfo)) {
    b
      ..writeln('Address: ${_bi(settings.addressAr, settings.addressEn)}')
      ..writeln('Directions: ${_bi(settings.transportAr, settings.transportEn)}')
      ..writeln('Google Maps: ${settings.mapsUrl}');
    for (final p in settings.phones) {
      b.writeln('Phone - ${_bi(p.labelAr, p.labelEn)}: ${p.number}');
    }
  }
  if (f.enabled(Sections.socials)) {
    if (settings.whatsapp.isNotEmpty) b.writeln('WhatsApp: ${settings.whatsapp}');
    if (settings.facebook.isNotEmpty) b.writeln('Facebook: ${settings.facebook}');
    if (settings.youtube.isNotEmpty) b.writeln('YouTube (live): ${settings.youtube}');
    if (settings.whatsappChannel.isNotEmpty) b.writeln('WhatsApp channel (announcements): ${settings.whatsappChannel}');
    if (settings.instagram.isNotEmpty) b.writeln('Instagram: ${settings.instagram}');
  }
  b.writeln(
    'Items marked [UNCONFIRMED] are provisional placeholders the church has not published yet: '
    'say so clearly and ask the visitor to confirm with the church (phone or the WhatsApp channel).',
  );

  if (f.enabled(Sections.alerts)) {
    final current = visibleAlerts(alerts, now);
    if (current.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Current announcements');
      for (final a in current) {
        final body = _bi(a.bodyAr, a.bodyEn);
        b.writeln(
          '- ${_bi(a.titleAr, a.titleEn)}${body.isNotEmpty ? ': $body' : ''}'
          '${(a.link ?? '').isNotEmpty ? ' Link: ${a.link}' : ''}',
        );
      }
    }
  }

  if (f.enabled(Sections.schedule)) {
    b
      ..writeln()
      ..writeln('## Weekly liturgy schedule (regular)');
    final regular = liturgies.where((l) => l.seasonKey == null && l.weekday != null).toList()
      ..sort((a, b) {
        final w = a.weekday!.compareTo(b.weekday!);
        return w != 0 ? w : (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
      });
    for (final l in regular) {
      b.writeln(
        '- ${l.sample ? '[UNCONFIRMED] ' : ''}${weekdayNamesEn[l.weekday!]}: ${_liturgyLine(l)}',
      );
    }

    // One-off services that belong to no season (date only).
    final oneOff = liturgies.where((l) => l.seasonKey == null && l.weekday == null && l.date != null).toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
    if (oneOff.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Special one-off services');
      for (final l in oneOff) {
        b.writeln(
          '- ${l.sample ? '[UNCONFIRMED] ' : ''}${_ymd(l.date!)}: ${_liturgyLine(l)}',
        );
      }
    }

    final seasonal = seasonalSchedule(seasons, liturgies);
    if (seasonal.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Holy seasons')
        ..writeln(
          'A season marked [REPLACES regular schedule] replaces the regular services on the days it has services. '
          'A season marked [ADDITIVE] adds its services: the regular morning masses continue, except a regular mass '
          'on a day the season has its own mass, and regular vespers/praise overlapping a season service.',
        );
      for (final e in seasonal.entries) {
        final s = e.key;
        b.writeln(
          '### ${_bi(s.nameAr, s.nameEn)} ${s.startsAt?.toIso8601String() ?? ''} -> ${s.endsAt?.toIso8601String() ?? ''}'
          ' ${s.replacesRegular ? '[REPLACES regular schedule]' : '[ADDITIVE — regular morning masses continue]'}'
          '${isSeasonActiveAt(s, now) ? ' [ACTIVE NOW]' : ''}',
        );
        for (final l in e.value) {
          final when = l.date != null ? _ymd(l.date!) : (l.weekday != null ? weekdayNamesEn[l.weekday!] : 'every day');
          b.writeln(
            '- ${l.sample ? '[UNCONFIRMED] ' : ''}$when: ${_liturgyLine(l)}',
          );
        }
      }
    }
  }

  if (f.enabled(Sections.clinics)) {
    b
      ..writeln()
      ..writeln('## Clinics (book by phone or WhatsApp)');
    for (final c in clinics.where((c) => c.active)) {
      b.writeln(
        '- ${c.sample ? '[UNCONFIRMED] ' : ''}${_bi(c.specialtyAr, c.specialtyEn)}: ${c.doctorName}'
        '${_bi(c.degreeAr, c.degreeEn).isNotEmpty ? ', ${_bi(c.degreeAr, c.degreeEn)}' : ''}; '
        '${c.days.map((d) => weekdayNamesEn[d]).join(', ')} ${formatRangeLatin(c.start, c.end)}'
        '${c.bookingPhone.isNotEmpty ? '; booking ${c.bookingPhone}' : ''}'
        '${c.whatsapp.isNotEmpty ? '; WhatsApp ${c.whatsapp}' : ''}',
      );
    }
  }

  if (f.enabled(Sections.meetings)) {
    b
      ..writeln()
      ..writeln('## Sunday school & meetings');
    for (final m in meetings) {
      final day = m.weekday != null ? weekdayNamesEn[m.weekday!] : 'no fixed day (ask the church)';
      b.writeln(
        '- ${m.sample ? '[UNCONFIRMED] ' : ''}${_bi(m.nameAr, m.nameEn)} [${m.stage}]: $day '
        '${formatRangeLatin(m.start, m.end)}${_at(_bi(m.hallAr, m.hallEn))}'
        '${m.notes.isNotEmpty ? '; notes: ${m.notes}' : ''}'
        '${m.facebookUrl.isNotEmpty ? '; Facebook ${m.facebookUrl}' : ''}'
        '${m.whatsappUrl.isNotEmpty ? '; WhatsApp ${m.whatsappUrl}' : ''}',
      );
    }
  }

  if (f.enabled(Sections.activities)) {
    b
      ..writeln()
      ..writeln('## Activities');
    for (final a in activities) {
      b.writeln(
        '- ${a.sample ? '[UNCONFIRMED] ' : ''}${_bi(a.titleAr, a.titleEn)}: ${_bi(a.descAr, a.descEn)}'
        '${_bi(a.scheduleAr, a.scheduleEn).isNotEmpty ? ' Schedule: ${_bi(a.scheduleAr, a.scheduleEn)}.' : ''}'
        '${a.ageRange.isNotEmpty ? ' Ages: ${a.ageRange}.' : ''}'
        '${a.contactPhone.isNotEmpty ? ' Contact ${a.contactPhone}.' : ''}'
        '${a.link.isNotEmpty ? ' Link: ${a.link}' : ''}',
      );
    }
  }

  if (f.enabled(Sections.services)) {
    b
      ..writeln()
      ..writeln('## Public services');
    for (final f in facilities) {
      final hours = _bi(f.hoursAr, f.hoursEn);
      b.writeln(
        '- ${f.sample ? '[UNCONFIRMED] ' : ''}${_bi(f.nameAr, f.nameEn)}: ${_bi(f.descAr, f.descEn)}'
        '${hours.isNotEmpty ? ' Hours: $hours.' : ''}${f.phone.isNotEmpty ? ' Phone ${f.phone}.' : ''}',
      );
    }
  }

  if (f.enabled(Sections.history)) {
    // Each language is clipped on its own so both fit.
    final history = _bi(_clip(settings.historyAr, 700), _clip(settings.historyEn, 700));
    final bishop = _bi(settings.bishopAr, settings.bishopEn);
    if (history.isNotEmpty || bishop.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## About the church');
      if (bishop.isNotEmpty) b.writeln('Bishop: $bishop');
      if (history.isNotEmpty) b.writeln('History (summary): $history');
    }
  }

  final serving = f.enabled(Sections.priests) ? priests.where((p) => !p.departed).toList() : const <Priest>[];
  if (serving.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Priests serving the church');
    for (final p in serving) {
      b.writeln('- ${p.sample ? '[UNCONFIRMED] ' : ''}${_priestLine(p)}');
    }
  }
  final departed = f.enabled(Sections.departedPriests) ? priests.where((p) => p.departed).toList() : const <Priest>[];
  if (departed.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Departed priests of the church');
    for (final p in departed) {
      b.writeln(
        '- ${p.sample ? '[UNCONFIRMED] ' : ''}${_priestLine(p)}'
        '${p.departedDate.isNotEmpty ? '; departed ${p.departedDate}' : ''}',
      );
    }
  }

  if (f.enabled(Sections.saints) && saints.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Patron saints');
    for (final s in saints) {
      final feast = [
        _bi(s.feastCopticAr, s.feastCopticEn),
        _bi(s.feastGregorianAr, s.feastGregorian),
      ].where((x) => x.isNotEmpty).join(' / ');
      final bio = _bi(_clip(s.bioAr, 400), _clip(s.bioEn, 400));
      b.writeln(
        '- ${_bi(s.nameAr, s.nameEn)}${feast.isNotEmpty ? '; feast: $feast' : ''}'
        '${bio.isNotEmpty ? '. $bio' : ''}',
      );
    }
  }

  return b.toString();
}

/// Bilingual value that never comes out blank when an editor filled only
/// one language: "English (Arabic)", or whichever one is set.
String _bi(String ar, String en) => en.isNotEmpty && ar.isNotEmpty ? '$en ($ar)' : (en.isNotEmpty ? en : ar);

String _at(String place) => place.isNotEmpty ? ' at $place' : '';

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

String _liturgyLine(Liturgy l) {
  final audience = _bi(l.audienceAr, l.audienceEn);
  return '${_bi(l.nameAr, l.nameEn)} [${l.type}] ${formatRangeLatin(l.start, l.end)}'
      '${_at(_bi(l.placeAr, l.placeEn))}${audience.isNotEmpty ? ' - $audience' : ''}';
}

String _priestLine(Priest p) =>
    '${_bi(p.name, p.nameEn)} (${p.rank})'
    '${p.ordinationDate.isNotEmpty ? '; ordained ${p.ordinationDate}' : ''}'
    '${p.hegumenDate.isNotEmpty ? '; hegumen since ${p.hegumenDate}' : ''}'
    '${_bi(p.bioAr, p.bioEn).isNotEmpty ? '. ${_bi(_clip(p.bioAr, 300), _clip(p.bioEn, 300))}' : ''}';

/// Cairo calendar date as YYYY-MM-DD (UTC instants are converted first).
String _ymd(DateTime d) {
  final c = CairoTime.calendarDate(d);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${c.year}-${two(c.month)}-${two(c.day)}';
}
