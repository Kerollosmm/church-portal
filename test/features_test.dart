import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('FeatureSettings', () {
    test('missing doc / empty map = everything on, default layout', () {
      for (final f in [FeatureSettings.fromMap(null), FeatureSettings.fromMap(const {}), FeatureSettings.defaults]) {
        for (final s in Sections.all) {
          expect(f.enabled(s), isTrue, reason: s);
        }
        expect(f.homeOrder, HomeBlocks.defaultOrder);
        expect(f.theme, 'burgundy');
        expect(f.disabledCount, 0);
        // Banner is opt-in: off until enabled with text.
        expect(f.visibleHomeBlocks, isNot(contains(HomeBlocks.banner)));
      }
    });

    test('tolerant parsing: junk values ignored, unknown blocks dropped, missing blocks appended', () {
      final f = FeatureSettings.fromMap({
        'sections': {'clinics': false, 'schedule': 'nope', 'meetings': true},
        'homeOrder': ['map', 'map', 'hero', 'directory'],
        'homeHidden': ['milestones', 'bogus'],
        'theme': 'neon',
      });
      expect(f.enabled(Sections.clinics), isFalse);
      expect(f.enabled(Sections.schedule), isTrue); // non-bool -> default on
      expect(f.homeOrder.take(2), ['map', 'directory']);
      expect(f.homeOrder.toSet(), HomeBlocks.defaultOrder.toSet());
      expect(f.homeOrder.length, HomeBlocks.defaultOrder.length);
      expect(f.homeHidden, {'milestones'});
      expect(f.theme, 'burgundy');
    });

    test('round-trips through toMap', () {
      final f = FeatureSettings.fromMap({
        'sections': {'clinics': false, 'assistant': false},
        'homeOrder': ['directory', 'map'],
        'homeHidden': ['quickContacts'],
        'bannerEnabled': true,
        'bannerAr': 'إعلان',
        'theme': 'navy',
      });
      final again = FeatureSettings.fromMap(f.toMap());
      expect(again.toMap(), f.toMap());
      expect(f.toMap()['sections'], hasLength(Sections.all.length));
    });

    test('disabled sections guard their routes', () {
      final f = FeatureSettings.fromMap({
        'sections': {'clinics': false, 'schedule': false, 'assistant': false},
      });
      expect(f.routeEnabled('/clinics'), isFalse);
      expect(f.routeEnabled('/clinics/'), isFalse);
      expect(f.routeEnabled('/mass-schedule'), isFalse);
      expect(f.routeEnabled('/ask'), isFalse);
      expect(f.routeEnabled('/'), isTrue);
      expect(f.routeEnabled('/admin'), isTrue);
      expect(f.routeEnabled('/church-education'), isTrue);
    });

    test('pages built from several sections stay up while any one is on', () {
      var f = FeatureSettings.fromMap({
        'sections': {'history': false, 'saints': false, 'priests': false},
      });
      expect(f.routeEnabled('/about'), isTrue); // departed fathers still on
      f = f.copyWith(sections: {...f.sections, Sections.departedPriests: false});
      expect(f.routeEnabled('/about'), isFalse);

      var c = FeatureSettings.fromMap({
        'sections': {'contactInfo': false, 'socials': false},
      });
      expect(c.routeEnabled('/contact'), isTrue); // the form is still on
      c = c.copyWith(sections: {...c.sections, Sections.contactForm: false});
      expect(c.routeEnabled('/contact'), isFalse);
    });

    test('home blocks follow order, hidden set and their sections', () {
      final f = FeatureSettings.fromMap({
        'sections': {'schedule': false, 'milestones': false},
        'homeOrder': ['map', 'directory', 'nextMass', 'quickContacts', 'alerts', 'milestones', 'banner'],
        'homeHidden': ['alerts'],
        'bannerEnabled': true,
        'bannerEn': 'Christmas schedule is out',
      });
      expect(f.visibleHomeBlocks, ['map', 'directory', 'quickContacts', 'banner']);
      // Banner needs text.
      expect(f.copyWith(bannerEn: '  ').showHomeBlock(HomeBlocks.banner), isFalse);
      // Contact info off removes the phones card and the map.
      final g = f.copyWith(sections: {...f.sections, Sections.contactInfo: false});
      expect(g.visibleHomeBlocks, ['directory', 'banner']);
    });
  });

  group('publicItems', () {
    test('drops hidden items and sorts stably by order', () {
      const items = [
        Saint(id: 'a', nameAr: 'a', nameEn: 'a', order: 2),
        Saint(id: 'b', nameAr: 'b', nameEn: 'b', order: 1),
        Saint(id: 'c', nameAr: 'c', nameEn: 'c', order: 1, visible: false),
        Saint(id: 'd', nameAr: 'd', nameEn: 'd', order: 1),
        Saint(id: 'e', nameAr: 'e', nameEn: 'e', order: 0),
      ];
      expect(publicItems(items).map((s) => s.id), ['e', 'b', 'd', 'a']);
    });

    test('visible flag defaults to true and is read from data', () {
      expect(Clinic.fromMap('x', const {'specialty': 'dental'}).visible, isTrue);
      expect(Clinic.fromMap('x', const {'visible': false}).visible, isFalse);
      expect(Facility.fromMap('x', const {'visible': 'no'}).visible, isTrue);
      expect(Activity.fromMap('x', const {'order': 7}).order, 7);
    });
  });

  group('seed', () {
    final seed = SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);

    test('ships settings/features with every section on (offline fallback respects defaults)', () {
      expect(seed.collection('settings').containsKey('features'), isTrue);
      final f = seed.features;
      for (final s in Sections.all) {
        expect(f.enabled(s), isTrue, reason: s);
        expect((seed.raw['settings']['features']['sections'] as Map).containsKey(s), isTrue, reason: s);
      }
      expect(f.homeOrder, HomeBlocks.defaultOrder);
      // Clinics on, but every clinic stays flagged as unconfirmed.
      expect(f.enabled(Sections.clinics), isTrue);
      expect(seed.clinics.every((c) => c.sample), isTrue);
    });

    test('seed bishop line is present', () {
      expect(seed.settings.bishopAr, contains('بافلي'));
      expect(seed.settings.bishopEn, contains('Pavly'));
    });
  });

  group('assistant context respects toggles', () {
    final seed = SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);
    String build(FeatureSettings f) => buildAssistantInstruction(
          settings: seed.settings,
          liturgies: seed.liturgies,
          seasons: seed.seasons,
          clinics: seed.clinics,
          meetings: seed.meetings,
          activities: seed.activities,
          facilities: seed.facilities,
          now: CairoTime.at(2026, 11, 1, 600),
          features: f,
        );

    test('all on: every section present', () {
      final t = build(FeatureSettings.defaults);
      for (final h in ['## Clinics', '## Weekly liturgy schedule', '## Sunday school', '## Activities', '## Public services']) {
        expect(t, contains(h));
      }
    });

    test('switched-off sections are left out', () {
      final t = build(FeatureSettings.fromMap({
        'sections': {'clinics': false, 'meetings': false, 'socials': false, 'services': false},
      }));
      expect(t, isNot(contains('## Clinics')));
      expect(t, isNot(contains('Pediatrics')));
      expect(t, isNot(contains('## Sunday school')));
      expect(t, isNot(contains('## Public services')));
      expect(t, isNot(contains('Facebook: ')));
      expect(t, contains('## Weekly liturgy schedule'));
    });
  });
}
