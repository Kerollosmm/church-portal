import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// #143 (ADR-094): the public filtered queries need `visible` / `active` and
/// `deletedAt` present on every content document.
void main() {
  group('withPresenceKeys', () {
    test('adds deletedAt: null and visible: true to a new content doc', () {
      for (final col in publicVisibleCollections) {
        final out = withPresenceKeys(col, {'nameAr': 'x'});
        expect(out['deletedAt'], isNull, reason: col);
        expect(out.containsKey('deletedAt'), isTrue, reason: col);
        expect(out['visible'], isTrue, reason: col);
        expect(out.containsKey('active'), isFalse, reason: col);
      }
    });

    test('seasons get active instead of visible', () {
      final out = withPresenceKeys('seasons', {'key': 'fast'});
      expect(out, {'key': 'fast', 'deletedAt': null, 'active': true});
    });

    test('never overrides an explicit value', () {
      expect(withPresenceKeys('pages', {'visible': false})['visible'], isFalse);
      expect(withPresenceKeys('seasons', {'active': false})['active'], isFalse);
      final ts = DateTime.utc(2026);
      expect(withPresenceKeys('liturgies', {'deletedAt': ts})['deletedAt'], ts);
    });

    test('leaves other collections untouched', () {
      final data = {'status': 'new'};
      expect(identical(withPresenceKeys('contact_messages', data), data), isTrue);
      expect(withPresenceKeys('admins', {'role': 'editor'}).containsKey('deletedAt'), isFalse);
    });
  });

  test('every seeded content doc carries the keys the public queries filter on', () {
    final seed = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
    for (final entry in seed.entries) {
      if (entry.key == 'settings') continue;
      for (final doc in (entry.value as Map<String, dynamic>).entries) {
        final data = doc.value as Map<String, dynamic>;
        final where = '${entry.key}/${doc.key}';
        expect(data.containsKey('deletedAt') && data['deletedAt'] == null, isTrue, reason: where);
        if (entry.key == 'seasons') {
          expect(data['active'], isA<bool>(), reason: where);
        } else {
          expect(data['visible'], isA<bool>(), reason: where);
        }
      }
    }
  });
}
