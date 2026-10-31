import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
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
    expect(seed.settings.mapsQuery, 'شارع 45 العصافرة بحري الإسكندرية');
    expect(seed.milestones.first.titleAr, contains('45'));
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
    for (var d = 0; d < 14; d++) {
      final now = CairoTime.at(2026, 11, 1 + d, 12 * 60).toUtc();
      expect(computeNextMass(liturgies: seed.liturgies, seasons: seed.seasons, now: now).next, isNotNull);
    }
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
