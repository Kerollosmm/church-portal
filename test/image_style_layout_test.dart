// ADR-023 (image display styles) and the card/grid layout rules of the
// "Golden hour" redesign: cards size to their content, optional fields
// collapse, 1/2/3-column grid, no overflow at 320 px or 200 % text.
import 'dart:convert';
import 'dart:typed_data';

import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/image_style.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/about_page.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/item_image.dart';
import 'package:church_portal/ui/widgets/styled_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _Media implements MediaRepository {
  @override
  String get source => MediaSource.inline;
  @override
  Future<Uint8List?> load(String mediaId) async => _png;
  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) => throw UnimplementedError();
  @override
  Future<void> delete(String mediaId) async {}
}

const _img = {'source': 'inline', 'mediaId': 'm1'};

Widget _app(Widget child, {FeatureSettings features = FeatureSettings.defaults, double textScale = 1, String lang = 'en'}) =>
    ProviderScope(
      overrides: [
        featuresProvider.overrideWithValue(features),
        mediaRepositoryProvider.overrideWithValue(_Media()),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: c!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

Future<void> _size(WidgetTester tester, double w, [double h = 2400]) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Priest _priest(String id, {bool image = false, String style = '', bool bio = false}) => Priest.fromMap(id, {
      'name': 'القس $id',
      'nameEn': 'Fr. $id',
      if (image) 'image': _img,
      if (style.isNotEmpty) 'imageStyle': style,
      if (bio) 'bioEn': 'Served the parish for many years, teaching and visiting families across El-Asafra.',
    });

Saint _saint(String id, {bool image = false, String style = '', bool bio = true}) => Saint.fromMap(id, {
      'nameAr': 'القديس $id',
      'nameEn': 'St $id',
      'feastCopticEn': '17 Tobi',
      if (bio) 'bioEn': 'A monk of the desert of Scetis, son of a king, who chose the narrow way.',
      if (image) 'image': _img,
      if (style.isNotEmpty) 'imageStyle': style,
    });

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('ImageStyles.resolve', () {
    test('built-in defaults per section', () {
      expect(ImageStyles.resolve('priests'), ImageStyles.avatar);
      expect(ImageStyles.resolve('saints'), ImageStyles.card);
      for (final c in ['activities', 'milestones', 'meetings', 'alerts', 'seasons', 'facilities']) {
        expect(ImageStyles.resolve(c), ImageStyles.card, reason: c);
      }
      expect(ImageStyles.resolve('unknown'), ImageStyles.card);
    });

    test('item style beats the section default; invalid values are ignored', () {
      expect(ImageStyles.resolve('priests', sectionStyle: 'banner'), 'banner');
      expect(ImageStyles.resolve('priests', itemStyle: 'card', sectionStyle: 'banner'), 'card');
      expect(ImageStyles.resolve('priests', itemStyle: 'round', sectionStyle: 'nope'), 'avatar');
      expect(ImageStyles.resolve('priests', itemStyle: ''), 'avatar'); // missing = section default
    });

    test('settings/features.imageStyles parse, round-trip and drop junk', () {
      final f = FeatureSettings.fromMap({
        'imageStyles': {'priests': 'card', 'saints': 'banner', 'liturgies': 'card', 'alerts': 'round', 'meetings': 3},
      });
      expect(f.imageStyles, {'priests': 'card', 'saints': 'banner'});
      expect(f.imageStyleFor('priests', ''), 'card');
      expect(f.imageStyleFor('priests', 'avatar'), 'avatar');
      expect(f.imageStyleFor('activities', ''), 'card');
      expect(FeatureSettings.fromMap(f.toMap()).imageStyles, f.imageStyles);
      expect(parseImageStyles('card'), isEmpty);
    });

    test('models read imageStyle, missing = empty (section default)', () {
      expect(_priest('a').imageStyle, '');
      expect(_priest('a', style: 'banner').imageStyle, 'banner');
      expect(Activity.fromMap('x', {'titleAr': 'x', 'imageStyle': 'card'}).imageStyle, 'card');
      expect(Season.fromMap('x', {'key': 'pascha', 'nameAr': 'x'}).imageStyle, '');
    });
  });

  group('card image widgets', () {
    testWidgets('priest defaults to a halo avatar; card / banner put the picture on top', (tester) async {
      await _size(tester, 1000);
      await tester.pumpWidget(_app(Column(children: [
        PriestCard(_priest('a', image: true), key: const ValueKey('a')),
        PriestCard(_priest('b', image: true, style: 'card'), key: const ValueKey('b')),
        PriestCard(_priest('c', image: true, style: 'banner'), key: const ValueKey('c')),
        PriestCard(_priest('d'), key: const ValueKey('d')),
      ])));
      await tester.pumpAndSettle();
      Finder within(String id, String key) =>
          find.descendant(of: find.byKey(ValueKey(id)), matching: find.byKey(Key(key)));
      expect(within('a', 'cardAvatar'), findsOneWidget);
      expect(within('a', 'cardCover'), findsNothing);
      expect(within('b', 'cardCover'), findsOneWidget);
      expect(within('b', 'cardAvatar'), findsNothing);
      expect(within('c', 'cardBanner'), findsOneWidget);
      // No image: the person placeholder, no cover / avatar at all.
      expect(within('d', 'cardAvatar'), findsNothing);
      expect(within('d', 'cardCover'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('d')), matching: find.byIcon(Icons.person)), findsOneWidget);
    });

    testWidgets('the admin section default applies when the item has none', (tester) async {
      await _size(tester, 1000);
      await tester.pumpWidget(_app(
        Column(children: [
          PriestCard(_priest('a', image: true), key: const ValueKey('a')),
          PriestCard(_priest('b', image: true, style: 'avatar'), key: const ValueKey('b')),
        ]),
        features: const FeatureSettings(imageStyles: {'priests': 'banner'}),
      ));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byKey(const Key('cardBanner'))),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byKey(const Key('cardAvatar'))),
          findsOneWidget);
    });

    testWidgets('saint card style is a portrait cover showing the whole picture (contain)', (tester) async {
      await _size(tester, 600);
      await tester.pumpWidget(_app(SizedBox(width: 360, child: SaintCard(_saint('m', image: true)))));
      await tester.pumpAndSettle();
      final cover = find.byKey(const Key('cardCover'));
      expect(cover, findsOneWidget);
      final s = tester.getSize(cover);
      expect(s.height, greaterThan(s.width)); // portrait
      final views = tester.widgetList<MediaImageView>(find.descendant(of: cover, matching: find.byType(MediaImageView)));
      expect(views.map((i) => i.fit), containsAll([BoxFit.contain, BoxFit.cover])); // picture + blurred fill
    });

    testWidgets('images switched off: no cover, no avatar, cards look as before', (tester) async {
      await _size(tester, 1000);
      await tester.pumpWidget(_app(
        Column(children: [PriestCard(_priest('a', image: true)), SaintCard(_saint('b', image: true))]),
        features: const FeatureSettings(sections: {Sections.media: false}),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cardAvatar')), findsNothing);
      expect(find.byKey(const Key('cardCover')), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('detail cover follows the style', (tester) async {
      await _size(tester, 1000);
      const img = MediaImage(source: MediaSource.inline, mediaId: 'm1');
      for (final style in ImageStyles.all) {
        await tester.pumpWidget(_app(DetailCover(style: style, image: img, label: 'x')));
        await tester.pumpAndSettle();
        expect(find.byType(HaloAvatar), style == ImageStyles.avatar ? findsOneWidget : findsNothing, reason: style);
        expect(find.byType(FittedCover), style == ImageStyles.avatar ? findsNothing : findsOneWidget, reason: style);
      }
    });
  });

  group('layout', () {
    test('grid columns: phone 1, tablet 2, desktop 3', () {
      expect(gridColumns(288), 1);
      expect(gridColumns(358), 1);
      expect(gridColumns(720), 2);
      expect(gridColumns(1152), 3);
      expect(gridColumns(1152, maxColumns: 2), 2);
      expect(kMaxContentWidth, 1200);
    });

    for (final width in [320.0, 390.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('cards with and without subtitle / image fit at $width px, ${scale}x text', (tester) async {
          await _size(tester, width, 6000);
          await tester.pumpWidget(_app(
            ResponsiveGrid(children: [
              PriestCard(_priest('plain'), key: const ValueKey('plain')),
              PriestCard(_priest('bio', bio: true), key: const ValueKey('bio')),
              PriestCard(_priest('avatar', image: true, bio: true), key: const ValueKey('avatar')),
              PriestCard(_priest('banner', image: true, style: 'banner'), key: const ValueKey('banner')),
              SaintCard(_saint('nobio', bio: false), key: const ValueKey('nobio')),
              SaintCard(_saint('card', image: true), key: const ValueKey('card')),
            ]),
            textScale: scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull); // no RenderFlex overflow
          // Cards size to their content: an absent subtitle / image reserves nothing.
          final plain = tester.getSize(find.byKey(const ValueKey('plain'))).height;
          final bio = tester.getSize(find.byKey(const ValueKey('bio'))).height;
          final noBio = tester.getSize(find.byKey(const ValueKey('nobio'))).height;
          final withCard = tester.getSize(find.byKey(const ValueKey('card'))).height;
          expect(plain, lessThan(bio));
          expect(noBio, lessThan(withCard));
          // Grid: 1 column on phones, 3 on desktop.
          final a = tester.getTopLeft(find.byKey(const ValueKey('plain')));
          final b = tester.getTopLeft(find.byKey(const ValueKey('bio')));
          if (width < 600) {
            expect(a.dx, b.dx);
          } else {
            expect(a.dy, b.dy);
          }
        });
      }
    }

    testWidgets('RTL: cards start at the right edge', (tester) async {
      await _size(tester, 1440);
      await tester.pumpWidget(_app(
        ResponsiveGrid(children: [PriestCard(_priest('a'), key: const ValueKey('a'))]),
        lang: 'ar',
      ));
      await tester.pumpAndSettle();
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('a')))), TextDirection.rtl);
      final r = tester.getTopRight(find.byKey(const ValueKey('a')));
      expect(r.dx, closeTo(1440 - 16, 1));
    });
  });
}
