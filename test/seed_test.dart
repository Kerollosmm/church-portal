import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);
  final seed = SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);

  test('seed covers every collection', () {
    for (final c in [
      'settings', 'alerts', 'seasons', 'liturgies', 'meetings', 'activities', //
      'clinics', 'facilities', 'priests', 'milestones', 'saints',
    ]) {
      expect(seed.collection(c), isNotEmpty, reason: c);
    }
    expect(seed.settings.addressAr, contains('شارع 45'));
    expect(seed.settings.mapsQuery, '31.260138,30.01129');
    expect(seed.milestones.first.year, 1980);
  });

  test('verified church data is real and marked as such', () {
    final s = seed.settings;
    expect(s.sample, isFalse);
    expect(s.nameAr, 'كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود');
    expect(s.addressAr, contains('العصافرة قبلي'));
    expect(s.lat, closeTo(31.260138, 1e-6));
    expect(s.lng, closeTo(30.01129, 1e-6));
    expect(s.phones.map((p) => p.number), ['035368888']);
    expect(s.facebook, contains('100070313048338'));
    expect(s.youtube, contains('UCJiZ4u0IiUbSvBnTrJnRZBA'));
    expect(s.instagram, contains('maximos_coptic_church'));
    expect(s.whatsappChannel, contains('0029Vb6Kmbs2UPBMUcrlVB0g'));
    // No leftover placeholder links anywhere in the seed.
    expect(File('assets/seed/seed.json').readAsStringSync(), isNot(contains('SAMPLE')));
    expect(seed.alerts.any((a) => a.link == s.whatsappChannel), isTrue);
  });

  test('clinics ship switched off until the church confirms them', () {
    expect(seed.features.enabled(Sections.clinics), isFalse);
    expect(seed.features.enabled(Sections.schedule), isTrue);
  });

  test('revivals are additive, feasts replace the regular schedule', () {
    bool replaces(String id) => seed.seasons.firstWhere((s) => s.id == id).replacesRegular;
    expect(replaces('nativity-2027'), isTrue);
    expect(replaces('holy-week-2027'), isTrue);
    expect(replaces('pascha-2027'), isTrue);
    expect(replaces('revival-maximus-2027'), isFalse);
    expect(replaces('revival-moses-2027'), isFalse);
  });

  test('unpublished schedules stay flagged as pending confirmation', () {
    expect(seed.liturgies.every((l) => l.sample), isTrue);
    expect(seed.meetings.every((m) => m.sample), isTrue);
    expect(seed.clinics.every((c) => c.sample), isTrue);
    // Never invent doctor names: only generic "to be announced" placeholders.
    expect(seed.clinics.every((c) => c.doctorName.contains('يُعلن لاحقًا')), isTrue);
  });

  test('priests: departed fathers are not listed as serving', () {
    final tadros = seed.priests.firstWhere((p) => p.id == 'tadros');
    expect(tadros.departed, isTrue);
    expect(tadros.departedDate, '2022-02-10');
    final maximus = seed.priests.firstWhere((p) => p.id == 'maximus');
    expect(maximus.departed, isTrue);
    expect(maximus.departedDate, '2021-02-04');
    final bemwa = seed.priests.firstWhere((p) => p.id == 'bemwa');
    expect(bemwa.rank, 'hegumen');
    expect(bemwa.sample, isFalse);
    expect(seed.priests.firstWhere((p) => p.id == 'saleeb').sample, isTrue);
  });

  test('retired seed ids are not part of the current seed', () {
    final retired = jsonDecode(File('tool/retired_seed_ids.json').readAsStringSync()) as Map<String, dynamic>;
    for (final e in retired.entries) {
      for (final id in (e.value as List)) {
        expect(seed.collection(e.key).containsKey(id), isFalse, reason: '${e.key}/$id');
      }
    }
  });

  test('every id ever seeded is either still seeded or retired (exhaustive)', () {
    final known = jsonDecode(File('tool/known_seed_ids.json').readAsStringSync()) as Map<String, dynamic>;
    final retired = jsonDecode(File('tool/retired_seed_ids.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in seed.raw.keys) {
      expect(known.containsKey(c), isTrue, reason: c);
      expect((known[c] as List).toSet(), containsAll(seed.collection(c).keys), reason: c);
    }
    for (final e in known.entries) {
      final gone = (e.value as List).toSet().difference(seed.collection(e.key).keys.toSet());
      expect(((retired[e.key] as List?) ?? const []).toSet(), containsAll(gone), reason: e.key);
    }
  });

  test('unconfirmed one-off services are tagged for the assistant', () {
    final oneOff = Liturgy(
        id: 'x', type: 'mass', nameAr: 'قداس خاص', nameEn: 'Special liturgy', start: '08:00', end: '10:00',
        date: DateTime.utc(2027, 3, 1), sample: true);
    final text = buildAssistantInstruction(
      settings: seed.settings,
      liturgies: [oneOff],
      seasons: const [],
      clinics: const [],
      meetings: const [],
      activities: const [],
      facilities: const [],
      now: CairoTime.at(2026, 11, 1, 600),
    );
    expect(text, contains('[UNCONFIRMED] 2027-03-01: Special liturgy'));
  });

  test('every liturgy has valid times and a weekday or date', () {
    for (final l in seed.liturgies) {
      expect(l.startMinutes, isNotNull, reason: l.id);
      if (l.end.isNotEmpty) expect(l.endMinutes, isNotNull, reason: l.id);
      expect(l.weekday != null || l.date != null, isTrue, reason: l.id);
      if (l.seasonKey != null) {
        expect(seed.seasons.any((s) => s.key == l.seasonKey), isTrue, reason: l.id);
      }
    }
  });

  test('next mass always resolves on seed data', () {
    // Every day from 1 Nov 2026 through 1 Nov 2027 (366 days), covering every
    // seeded season and revival.
    for (var d = 0; d < 366; d++) {
      final now = CairoTime.at(2026, 11, 1 + d, 12 * 60).toUtc();
      final r = computeNextMass(liturgies: seed.liturgies, seasons: seed.seasons, now: now);
      expect(r.next, isNotNull, reason: '${CairoTime.fromInstant(now)}');
    }
    expect(CairoTime.at(2026, 11, 1 + 365).day, 1); // the loop ends on 1 Nov 2027
    // Nativity eve 2027 (Wednesday) -> the feast liturgy replaces the regular schedule.
    final r = computeNextMass(
        liturgies: seed.liturgies, seasons: seed.seasons, now: CairoTime.at(2027, 1, 6, 12 * 60).toUtc());
    expect(r.next?.liturgy.id, 'nat-eve');
  });

  test('Holy Week 2027 dated services fall on their Cairo day (pre-DST +02:00)', () {
    DateTime day(String id) => CairoTime.calendarDate(seed.liturgies.firstWhere((l) => l.id == id).date!);
    expect(day('hw-palm'), DateTime(2027, 4, 25)); // Palm Sunday
    expect(day('hw-thursday'), DateTime(2027, 4, 29));
    expect(day('hw-friday'), DateTime(2027, 4, 30));
    expect(day('pascha-eve'), DateTime(2027, 5, 1));
  });

  test('assistant instruction includes schedule, clinics and contacts', () {
    final text = buildAssistantInstruction(
      settings: seed.settings,
      liturgies: seed.liturgies,
      seasons: seed.seasons,
      clinics: seed.clinics,
      meetings: seed.meetings,
      activities: seed.activities,
      facilities: seed.facilities,
      now: CairoTime.at(2026, 11, 1, 600),
    );
    expect(text, contains('Friday'));
    expect(text, contains('Pediatrics'));
    expect(text, contains(seed.settings.phones.first.number));
    expect(text.length, lessThan(30000));
  });
}
