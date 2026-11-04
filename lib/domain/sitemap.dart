// sitemap.xml from the published content (ADR-038). Pure Dart: the Deploy
// workflow exports the public collections read-only
// (tool/export_public_content.js) and tool/gen_sitemap.dart turns them into
// build/web/sitemap.xml with these rules, so the sitemap lists exactly the
// URLs the app itself treats as indexable (setDocumentRouteMeta).

import 'custom_content.dart';
import 'features.dart';
import 'item_detail.dart';
import 'models.dart';

/// Canonical origin of the live site (index.html / document_lang.dart).
const sitemapOrigin = 'https://maximos-domadios-church.web.app';

/// The fixed public pages, in sitemap order. `/ask` (the assistant) is left
/// out like before: its page also depends on App Check and the model.
const sitemapStaticPaths = [
  '/',
  '/about',
  '/mass-schedule',
  '/church-education',
  '/church-activities',
  '/clinics',
  '/public-services',
  '/contact',
];

/// Everything [sitemapPaths] needs: the section switches and the raw
/// (unfiltered) collections as `fromMap` reads them.
class SitemapContent {
  final FeatureSettings features;
  final List<Meeting> meetings;
  final List<Activity> activities;
  final List<Clinic> clinics;
  final List<Facility> facilities;
  final List<Priest> priests;
  final List<Saint> saints;
  final List<Milestone> milestones;
  final List<CustomCategory> categories;
  final List<CustomPage> pages;

  const SitemapContent({
    required this.features,
    this.meetings = const [],
    this.activities = const [],
    this.clinics = const [],
    this.facilities = const [],
    this.priests = const [],
    this.saints = const [],
    this.milestones = const [],
    this.categories = const [],
    this.pages = const [],
  });

  /// Detail-page items of each kind, in collection order.
  Map<DetailKind, List<Object>> get detailItems => {
        DetailKind.meeting: meetings,
        DetailKind.activity: activities,
        DetailKind.clinic: clinics,
        DetailKind.facility: facilities,
        DetailKind.priest: priests,
        DetailKind.saint: saints,
        DetailKind.milestone: milestones,
      };
}

/// The indexable public paths, without duplicates, in a stable order:
/// - fixed pages whose section is on ([FeatureSettings.routeEnabled], the
///   same check as `FeatureGate`);
/// - `/section/<slug>` for each public category ([publicCategories]: visible,
///   usable, first of a slug) and `/page/<slug>` for each public custom page
///   ([publicPages]) while their section switch is on. A page kept out of the
///   menu (`showInNav: false`) is still indexable, exactly like the app
///   (`CustomPageView` is indexable whenever the page exists);
/// - the detail page of every item whose page opens ([detailItemOpens]:
///   listed, `detailsEnabled` not false, its section — for priests the one
///   matching their status — on).
///
/// Category items (`entries`) have no page of their own, so only their
/// category's URL is listed.
List<String> sitemapPaths(SitemapContent c) {
  final f = c.features;
  final out = <String>[];
  final seen = <String>{};
  void add(String p) {
    if (seen.add(p)) out.add(p);
  }

  for (final p in sitemapStaticPaths) {
    if (f.routeEnabled(p)) add(p);
  }
  for (final cat in publicCategories(c.categories)) {
    if (f.routeEnabled(cat.path)) add(cat.path);
  }
  for (final page in publicPages(c.pages)) {
    if (f.routeEnabled(page.path)) add(page.path);
  }
  c.detailItems.forEach((kind, items) {
    for (final o in items) {
      final path = detailPathFor(kind, detailItemId(o));
      if (f.routeEnabled(path) && detailItemOpens(o, f)) add(path);
    }
  });
  return out;
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// A sitemaps.org `<urlset>` of [paths] on [origin].
String sitemapXml(Iterable<String> paths, {String origin = sitemapOrigin}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!-- Generated at deploy time from Firestore by tool/gen_sitemap.dart (ADR-038). -->')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
  for (final p in paths) {
    b.writeln('  <url><loc>${_xmlEscape('$origin$p')}</loc></url>');
  }
  b.writeln('</urlset>');
  return b.toString();
}

List<T> _exported<T>(Map<String, dynamic> export, String name, T Function(String, Map<String, dynamic>) f) {
  final raw = export[name];
  if (raw is! List) throw FormatException('export has no "$name" list');
  return [
    for (final d in raw)
      if (d is Map && d['id'] is String)
        f(d['id'] as String, Map<String, dynamic>.from((d['data'] as Map?) ?? const {})),
  ];
}

/// [SitemapContent] from a read-only export (tool/export_public_content.js):
/// `{"features": {...} | null, "<collection>": [{"id", "data"}], ...}`. A
/// missing `settings/features` uses [seedFeatures] (the bundled seed's copy),
/// like the app. Throws [FormatException] when a collection is missing.
SitemapContent sitemapContentFromExport(Map<String, dynamic> export, {Map<String, dynamic>? seedFeatures}) {
  final stored = export['features'];
  return SitemapContent(
    features: FeatureSettings.fromMap(stored is Map ? Map<String, dynamic>.from(stored) : seedFeatures),
    meetings: _exported(export, 'meetings', Meeting.fromMap),
    activities: _exported(export, 'activities', Activity.fromMap),
    clinics: _exported(export, 'clinics', Clinic.fromMap),
    facilities: _exported(export, 'facilities', Facility.fromMap),
    priests: _exported(export, 'priests', Priest.fromMap),
    saints: _exported(export, 'saints', Saint.fromMap),
    milestones: _exported(export, 'milestones', Milestone.fromMap),
    categories: _exported(export, 'categories', CustomCategory.fromMap),
    pages: _exported(export, 'pages', CustomPage.fromMap),
  );
}
