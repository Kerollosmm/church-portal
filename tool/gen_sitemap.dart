// Builds sitemap.xml from a read-only content export (ADR-038).
//
//   dart run tool/gen_sitemap.dart <export.json> <out.xml> [--seed assets/seed/seed.json]
//
// <export.json> comes from tool/export_public_content.js. A missing
// `settings/features` falls back to the bundled seed's copy, like the app.
// Exits non-zero (and writes nothing) on any problem, so the Deploy workflow
// keeps the static web/sitemap.xml.

import 'dart:convert';
import 'dart:io';

import 'package:church_portal/domain/sitemap.dart';

void main(List<String> args) {
  final seedIdx = args.indexOf('--seed');
  final seedPath = seedIdx >= 0 && seedIdx + 1 < args.length ? args[seedIdx + 1] : 'assets/seed/seed.json';
  final files = [
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && !(seedIdx >= 0 && i == seedIdx + 1)) args[i],
  ];
  if (files.length < 2) {
    stderr.writeln('usage: dart run tool/gen_sitemap.dart <export.json> <out.xml> [--seed seed.json]');
    exit(2);
  }
  try {
    final export = (jsonDecode(File(files[0]).readAsStringSync()) as Map).cast<String, dynamic>();
    final seed = (jsonDecode(File(seedPath).readAsStringSync()) as Map).cast<String, dynamic>();
    final seedFeatures = (seed['settings'] as Map?)?['features'];
    final content = sitemapContentFromExport(export,
        seedFeatures: seedFeatures is Map ? Map<String, dynamic>.from(seedFeatures) : null);
    final paths = sitemapPaths(content);
    if (!paths.contains('/')) throw StateError('home page missing from the sitemap');
    File(files[1]).writeAsStringSync(sitemapXml(paths));
    final details = paths.where((p) => p.split('/').length > 2).length;
    stdout.writeln('sitemap.xml: ${paths.length} URLs ($details detail / section / page URLs)');
  } catch (e) {
    stderr.writeln('gen_sitemap failed: $e');
    exit(1);
  }
}
