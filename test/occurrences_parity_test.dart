import 'dart:convert';
import 'dart:io';

import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('60-day calendar parity suite (ADR-060)', () {
    final fixtureFile = File('test/fixtures/occurrences_parity_60d.json');
    late List<dynamic> fixture;

    setUpAll(() {
      expect(fixtureFile.existsSync(), isTrue, reason: 'fixture file must exist');
      fixture = jsonDecode(fixtureFile.readAsStringSync()) as List<dynamic>;
    });

    test('fixture contains expected occurrences across 60 days', () {
      expect(fixture.length, 21);
    });

    test('topicKey, sourceOf, and CairoTime match 100% with fixture data', () {
      for (final item in fixture.cast<Map<String, dynamic>>()) {
        final rawKey = item['rawEventKey'] as String;
        final expectedTopicKey = item['topicKey'] as String;
        final expectedSource = item['source'] as String;
        final cairoDate = item['cairoDate'] as String;
        final start = item['start'] as String;
        final expectedUtc = item['startsAtUtc'] as String;

        // 1. Topic key parity
        expect(topicKey(rawKey), equals(expectedTopicKey), reason: 'topicKey mismatch for $rawKey');

        // 2. Source mapping parity
        expect(PushSettings.sourceOf(rawKey), equals(expectedSource), reason: 'source mismatch for $rawKey');

        // 3. Cairo wall-time to UTC instant parity
        final parts = cairoDate.split('-').map(int.parse).toList();
        final timeParts = start.split(':').map(int.parse).toList();
        final cairoInstant = CairoTime.at(parts[0], parts[1], parts[2], timeParts[0] * 60 + timeParts[1]);
        expect(cairoInstant.toUtc().toIso8601String(), equals(expectedUtc),
            reason: 'UTC instant mismatch on $cairoDate $start (DST check)');
      }
    });

    test('DST transition verification: pre-DST vs post-DST UTC shifts', () {
      final preDst = fixture.firstWhere((it) => it['cairoDate'] == '2027-04-23' && it['start'] == '06:30');
      final postDst = fixture.firstWhere((it) => it['cairoDate'] == '2027-04-30' && it['start'] == '06:30');

      expect(preDst['startsAtUtc'], equals('2027-04-23T04:30:00.000Z'));
      expect(postDst['startsAtUtc'], equals('2027-04-30T03:30:00.000Z'));
    });
  });
}
