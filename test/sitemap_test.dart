import 'dart:convert';
import 'dart:io';

import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/item_detail.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/sitemap.dart';
import 'package:flutter_test/flutter_test.dart';

FeatureSettings _features([Map<String, bool> off = const {}]) => FeatureSettings.fromMap({
      'sections': {for (final s in Sections.all) s: !off.containsKey(s)},
    });

void main() {
  group('sitemap (ADR-038)', () {
    test('fixed pages follow their section switches like FeatureGate', () {
      final paths = sitemapPaths(SitemapContent(features: _features({Sections.clinics: false})));
      expect(paths, ['/', '/about', '/mass-schedule', '/church-education', '/church-activities', '/public-services', '/contact']);
      expect(sitemapPaths(SitemapContent(features: _features())), contains('/clinics'));
    });

    test('detail pages: listed, details on, section on — each of the 7 prefixes', () {
      final c = SitemapContent(
        features: _features(),
        meetings: [Meeting.fromMap('m1', {'nameAr': 'اجتماع'}), Meeting.fromMap('m2', {'nameAr': 'x', 'visible': false})],
        activities: [Activity.fromMap('a1', {'titleAr': 'كورال', 'detailsEnabled': false}), Activity.fromMap('a2', {'titleAr': 'y'})],
        clinics: [
          Clinic.fromMap('c1', {'specialtyAr': 'أسنان'}),
          Clinic.fromMap('c2', {'specialtyAr': 'z', 'active': false}),
        ],
        facilities: [Facility.fromMap('f 1', {'nameAr': 'حضانة'})],
        priests: [Priest.fromMap('p1', {'nameAr': 'أبونا'})],
        saints: [Saint.fromMap('s1', {'nameAr': 'القديس'})],
        milestones: [Milestone.fromMap('ms1', {'titleAr': 'تأسيس'})],
      );
      final paths = sitemapPaths(c);
      expect(paths, containsAll(['/church-education/m1', '/church-activities/a2', '/clinics/c1', '/public-services/f%201', '/about/priests/p1', '/about/saints/s1', '/about/milestones/ms1']));
      expect(paths, isNot(contains('/church-education/m2'))); // hidden
      expect(paths, isNot(contains('/church-activities/a1'))); // detailsEnabled: false
      expect(paths, isNot(contains('/clinics/c2'))); // inactive clinic is not listed
      for (final kind in DetailKind.values) {
        expect(paths.any((p) => p.startsWith('${kind.basePath}/')), isTrue, reason: kind.name);
      }
    });

    test('a switched-off section drops its list page and its detail pages', () {
      final c = SitemapContent(
        features: _features({Sections.clinics: false, Sections.saints: false}),
        clinics: [Clinic.fromMap('c1', {'specialtyAr': 'أسنان'})],
        saints: [Saint.fromMap('s1', {'nameAr': 'القديس'})],
      );
      final paths = sitemapPaths(c);
      expect(paths, isNot(contains('/clinics')));
      expect(paths, isNot(contains('/clinics/c1')));
      expect(paths, isNot(contains('/about/saints/s1')));
      expect(paths, contains('/about')); // other /about sections still on
    });

    test('priests follow the section matching their status', () {
      final priests = [
        Priest.fromMap('serving', {'nameAr': 'أ'}),
        Priest.fromMap('departed', {'nameAr': 'ب', 'status': 'departed'}),
      ];
      final noDeparted = sitemapPaths(SitemapContent(features: _features({Sections.departedPriests: false}), priests: priests));
      expect(noDeparted, contains('/about/priests/serving'));
      expect(noDeparted, isNot(contains('/about/priests/departed')));
      final noServing = sitemapPaths(SitemapContent(features: _features({Sections.priests: false}), priests: priests));
      expect(noServing, isNot(contains('/about/priests/serving')));
      expect(noServing, contains('/about/priests/departed'));
    });

    test('custom sections and pages: public ones only, nav-hidden pages stay indexable, switches respected', () {
      final cats = [
        CustomCategory.fromMap('k1', {'slug': 'youth', 'nameAr': 'الشباب'}),
        CustomCategory.fromMap('k2', {'slug': 'hidden', 'nameAr': 'مخفي', 'visible': false}),
        CustomCategory.fromMap('k3', {'slug': 'Bad Slug', 'nameAr': 'خطأ'}),
        CustomCategory.fromMap('k4', {'slug': 'youth', 'nameAr': 'مكرر', 'order': 5}),
      ];
      final pages = [
        CustomPage.fromMap('g1', {'slug': 'donate', 'titleAr': 'تبرع', 'showInNav': false}),
        CustomPage.fromMap('g2', {'slug': 'draft', 'titleAr': 'مسودة', 'visible': false}),
        CustomPage.fromMap('g3', {'slug': 'no-title'}),
      ];
      final paths = sitemapPaths(SitemapContent(features: _features(), categories: cats, pages: pages));
      expect(paths.where((p) => p.startsWith('/section/')), ['/section/youth']);
      expect(paths.where((p) => p.startsWith('/page/')), ['/page/donate']);

      final off = sitemapPaths(SitemapContent(
          features: _features({Sections.customSections: false, Sections.customPages: false}),
          categories: cats,
          pages: pages));
      expect(off.where((p) => p.startsWith('/section/') || p.startsWith('/page/')), isEmpty);
    });

    test('detailItemOpens matches detailStateFor for every kind', () {
      final f = _features();
      expect(detailItemOpens(Meeting.fromMap('m', {'nameAr': 'x'}), f), isTrue);
      expect(detailItemOpens(Clinic.fromMap('c', {'specialtyAr': 'x', 'active': false}), f), isFalse);
      expect(detailItemOpens(Priest.fromMap('p', {'nameAr': 'x', 'status': 'departed'}), _features({Sections.departedPriests: false})),
          isFalse);
      expect(detailItemId(Saint.fromMap('s9', {'nameAr': 'x'})), 's9');
      expect(detailItemOpens('not an item', f), isFalse);
    });

    test('valid sitemaps.org XML, escaped, no duplicates', () {
      final xml = sitemapXml(['/', '/page/a', '/clinics/a%26b', '/page/a&b']);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
      expect(xml, contains('<loc>https://maximos-domadios-church.web.app/</loc>'));
      expect(xml, contains('/page/a&amp;b</loc>'));
      expect(xml, isNot(contains('a&b<')));
      expect('<url>'.allMatches(xml).length, 4);
      final c = SitemapContent(features: _features(), meetings: [Meeting.fromMap('m', {'nameAr': 'x'}), Meeting.fromMap('m', {'nameAr': 'x'})]);
      final paths = sitemapPaths(c);
      expect(paths.toSet().length, paths.length);
    });

    test('the static fallback sitemap lists the fixed pages the seed keeps on', () {
      final seed = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      final features = FeatureSettings.fromMap(((seed['settings'] as Map)['features'] as Map).cast<String, dynamic>());
      final staticXml = File('web/sitemap.xml').readAsStringSync();
      final listed = RegExp(r'<loc>https://maximos-domadios-church\.web\.app([^<]*)</loc>')
          .allMatches(staticXml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ''))
          .map((m) => m[1]!)
          .toList();
      expect(listed, sitemapPaths(SitemapContent(features: features)));
    });

    test('robots.txt keeps pointing to the sitemap', () {
      expect(File('web/robots.txt').readAsStringSync(), contains('Sitemap: https://maximos-domadios-church.web.app/sitemap.xml'));
    });

    test('an export (seed features when the doc is missing) becomes the sitemap content', () {
      final seed = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      final seedFeatures = ((seed['settings'] as Map)['features'] as Map).cast<String, dynamic>();
      final export = jsonDecode(jsonEncode({
        'features': null,
        'meetings': [
          {'id': 'm1', 'data': {'nameAr': 'اجتماع', 'startsAt': '2026-11-04T10:00:00.000Z'}}
        ],
        'activities': [],
        'clinics': [
          {'id': 'c1', 'data': {'specialtyAr': 'أسنان'}}
        ],
        'facilities': [],
        'priests': [],
        'saints': [],
        'milestones': [],
        'categories': [
          {'id': 'k', 'data': {'slug': 'youth', 'nameAr': 'الشباب'}}
        ],
        'pages': [
          {'id': 'g', 'data': {'slug': 'donate', 'titleAr': 'تبرع'}}
        ],
      })) as Map<String, dynamic>;
      final paths = sitemapPaths(sitemapContentFromExport(export, seedFeatures: seedFeatures));
      expect(paths, containsAll(['/church-education/m1', '/section/youth', '/page/donate']));
      expect(paths.where((p) => p.startsWith('/clinics')), isEmpty); // clinics off in the seed's features
      // A stored doc wins over the seed.
      export['features'] = {
        'sections': {Sections.clinics: true},
      };
      expect(sitemapPaths(sitemapContentFromExport(export, seedFeatures: seedFeatures)), contains('/clinics/c1'));
      expect(() => sitemapContentFromExport({'features': null}), throwsFormatException);
    });
  });
}
