import 'dart:convert';
import 'dart:io';

import 'package:church_portal/ui/widgets/coptic_cross.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _fullAr = 'كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود';
const _newSite = 'https://maximos-domadios-church.web.app';

void main() {
  test('web title, manifest and share tags use the church name and new domain', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>$_fullAr</title>'));
    expect(html, contains('$_newSite/og-image.jpg'));
    expect(html, isNot(contains('كنيسة العصافرة')));
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['name'], _fullAr);
    expect(manifest['short_name'], 'كنيسة مكسيموس ودوماديوس');
    // Installed-PWA launch surface matches the HTML splash background.
    expect(manifest['background_color'], '#FBF6EC');
    for (final f in ['web/favicon.png', 'web/favicon.ico', 'web/og-image.jpg', 'web/icons/apple-touch-icon.png',
        'assets/branding/seal.png']) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
  });

  test('old Hosting site 301-redirects every path to the new domain', () {
    final cfg = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
    final sites = (cfg['hosting'] as List).cast<Map<String, dynamic>>();
    final app = sites.firstWhere((s) => s['target'] == 'app');
    expect(app['public'], 'build/web');
    final legacy = sites.firstWhere((s) => s['target'] == 'legacy-redirect');
    final r = (legacy['redirects'] as List).single as Map<String, dynamic>;
    expect(r['type'], 301);
    expect(r['destination'], '$_newSite/:1');
    final rc = jsonDecode(File('.firebaserc').readAsStringSync()) as Map<String, dynamic>;
    final targets = rc['targets']['asafra-church-portal']['hosting'] as Map<String, dynamic>;
    expect(targets['app'], ['maximos-domadios-church']);
    expect(targets['legacy-redirect'], ['asafra-church-portal']);
  });

  testWidgets('ChurchSeal renders the seal asset', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ChurchSeal(size: 48))));
    final img = tester.widget<Image>(find.byType(Image));
    expect((img.image as AssetImage).assetName, ChurchSeal.asset);
    expect(tester.getSize(find.byType(ChurchSeal)), const Size(48, 48));
  });
}
