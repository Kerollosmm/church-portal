import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_portal/domain/item_detail.dart';
import 'package:church_portal/ui/widgets/hero_ambient.dart';
import 'package:church_portal/ui/widgets/hero_ambient_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// ADR-037: PageSpeed (performance, best practices, agentic browsing) without
/// changing what visitors see.
void main() {
  group('hero ambient spec (web DOM layer = Flutter painter)', () {
    test('the rays keep the PR #15 geometry and shimmer', () {
      const size = Size(1350, 780);
      for (final shimmer in [0.0, 0.25, 0.6]) {
        final rays = HeroAmbientSpec.rays(size, shimmer: shimmer, strength: 0.6);
        expect(rays, hasLength(14));
        for (var i = 0; i < 14; i++) {
          // The formula LightRaysPainter used before the refactor.
          final t = i / 13;
          final angle = math.pi / 2 + (t - 0.5) * 1.5;
          final width = 0.035 + 0.02 * math.sin(i * 1.7);
          final phase = math.sin((shimmer * 2 * math.pi) + i * 0.9) * 0.5 + 0.5;
          final origin = Offset(size.width / 2, -size.height * 0.08);
          final reach = size.height * 1.05;
          expect(rays[i].alpha, closeTo((0.10 + 0.16 * phase) * 0.6, 1e-9));
          expect(rays[i].origin, origin);
          expect(rays[i].p1.dx, closeTo(origin.dx + math.cos(angle - width / 2) * reach, 1e-9));
          expect(rays[i].p2.dy, closeTo(origin.dy + math.sin(angle + width / 2) * reach, 1e-9));
          // RadialGradient(center: topCenter, radius: 1) over the circle of
          // `reach` around the origin: centred `reach` above it, radius 2 x reach.
          expect(rays[i].gradientCenter, Offset(origin.dx, origin.dy - reach));
          expect(rays[i].gradientRadius, 2 * reach);
        }
      }
      expect(HeroAmbientSpec.raySigma(const Size(200, 100)), 4);
      expect(HeroAmbientSpec.raySigma(size), closeTo(16.2, 1e-9));
    });

    test('phase weights crossfade neighbours and always sum to 1', () {
      const n = HeroAmbientSpec.shimmerPhases;
      for (var i = 0; i <= 200; i++) {
        final t = i / 200;
        final w = [for (var k = 0; k < n; k++) HeroAmbientSpec.phaseWeight(k, n, t)];
        expect(w.reduce((a, b) => a + b), closeTo(1, 1e-9), reason: 't=$t');
        expect(w.where((x) => x > 1e-9).length, lessThanOrEqualTo(2), reason: 't=$t');
      }
      for (var k = 0; k < n; k++) {
        expect(HeroAmbientSpec.phaseWeight(k, n, k / n), closeTo(1, 1e-9));
      }
      // Same cycles as the Flutter clock (60 s, shimmer 8x per cycle).
      expect(HeroAmbientSpec.clock.inMilliseconds / HeroAmbientSpec.shimmerCycle.inMilliseconds, 8);
    });

    test('tests and Android paint the ambient layers in Flutter (DOM layer is web-only)', () {
      expect(heroAmbientInDom, isFalse);
    });
  });

  group('web/index.html first paint', () {
    final html = File('web/index.html').readAsStringSync();

    test('static hero copy: poster (LCP, high priority), church name, fades out on the first frame', () {
      expect(html, contains('<h1>كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود</h1>'));
      expect(RegExp(r'<img src="assets/assets/art/hero_poster\.webp"[^>]*fetchpriority="high"').hasMatch(html), isTrue);
      expect(html, contains('srcset="assets/assets/art/hero_poster_tall.webp"'));
      expect(html, contains("s.classList.add('gone')"));
      // The 178 KB seal is no longer part of the first paint.
      expect(html, isNot(contains('branding/seal.png')));
      for (final f in ['assets/art/hero_poster.webp', 'assets/art/hero_poster_tall.webp']) {
        expect(File(f).lengthSync(), lessThan(40 * 1024), reason: f);
      }
    });

    test('Intl.v8BreakIterator is replaced by an Intl.Segmenter shim before Flutter loads', () {
      final shim = html.indexOf("Object.defineProperty(Intl, 'v8BreakIterator'");
      expect(shim, greaterThan(0));
      expect(html, contains("new Intl.Segmenter(undefined, { granularity: 'grapheme' })"));
      expect(shim, lessThan(html.indexOf('flutter_bootstrap.js')));
    });

    test('the in-app seal stays small', () {
      expect(File('assets/branding/seal.png').lengthSync(), lessThan(40 * 1024));
    });
  });

  group('agentic browsing', () {
    test('llms.txt follows the Lighthouse rules (H1, links, not too short)', () {
      final txt = File('web/llms.txt').readAsStringSync();
      expect(RegExp(r'^\s*#\s+.+', multiLine: true).hasMatch(txt), isTrue);
      expect(RegExp(r'\[.+\]\(.+\)').hasMatch(txt), isTrue);
      expect(txt.length, greaterThan(50));
      // Every page it lists is in the sitemap.
      final sitemap = File('web/sitemap.xml').readAsStringSync();
      for (final m in RegExp(r'\((https://maximos-domadios-church\.web\.app/[^)]*)\)').allMatches(txt)) {
        if (m.group(1)!.endsWith('.xml')) continue;
        expect(sitemap, contains('<loc>${m.group(1)}</loc>'), reason: m.group(1));
      }
    });

    test('Hosting rewrites app routes only: /.well-known/*, maps and missing files are real 404s', () {
      final cfg = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
      final app = (cfg['hosting'] as List).first as Map<String, dynamic>;
      final rewrites = (app['rewrites'] as List).cast<Map<String, dynamic>>();
      expect(rewrites, hasLength(2));
      for (final r in rewrites) {
        expect(r['destination'], '/index.html');
      }
      final res = [for (final r in rewrites) RegExp(r['regex'] as String)];
      bool rewritten(String path) => res.any((re) => re.hasMatch(path));
      for (final route in ['/', '/mass-schedule', '/section/youth-meeting', '/page/donations', '/clinics/AbC123xyz', '/admin', '/ask']) {
        expect(rewritten(route), isTrue, reason: route);
      }
      // Item / slug routes keep working when an id or slug contains a dot.
      for (final kind in DetailKind.values) {
        expect(rewritten('${kind.basePath}/item.v2'), isTrue, reason: kind.basePath);
      }
      for (final route in ['/section/a.b', '/page/st.mark']) {
        expect(rewritten(route), isTrue, reason: route);
      }
      for (final file in ['/.well-known/ard.json', '/main.dart.js.map', '/flutter.js.map', '/wp-login.php', '/assets/x.png']) {
        expect(rewritten(file), isFalse, reason: file);
      }
      final all = (app['headers'] as List).cast<Map<String, dynamic>>().firstWhere((h) => h['source'] == '**');
      final keys = {for (final h in (all['headers'] as List).cast<Map<String, dynamic>>()) h['key']: h['value']};
      expect(keys['Cross-Origin-Opener-Policy'], 'same-origin-allow-popups');
    });
  });
}
