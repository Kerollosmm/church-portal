import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_portal/data/image_processing.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/pages/about_page.dart';
import 'package:church_portal/ui/widgets/item_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// A real 1×1 PNG so Image.memory can decode it in widget tests.
final _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _FakeMedia implements MediaRepository {
  final Map<String, Uint8List> docs = {};
  final List<String> deleted = [];
  int loads = 0;
  int _next = 0;

  @override
  String get source => MediaSource.inline;

  @override
  Future<Uint8List?> load(String mediaId) async {
    loads++;
    return docs[mediaId];
  }

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) async {
    final id = 'm${_next++}';
    docs[id] = img.bytes;
    return MediaImage(source: MediaSource.inline, mediaId: id, alt: alt, w: img.w, h: img.h);
  }

  @override
  Future<void> delete(String mediaId) async {
    deleted.add(mediaId);
    docs.remove(mediaId);
  }
}

/// Fake decoded image whose encoded size depends on edge and quality.
class _FakeDecoded implements DecodedImage {
  final int Function(int edge, double q) sizeFor;
  final calls = <String>[];
  _FakeDecoded(this.sizeFor);
  @override
  int get width => 4000;
  @override
  int get height => 3000;
  @override
  Future<EncodedImage> encode(int maxEdge, double quality) async {
    calls.add('$maxEdge@$quality');
    final t = fitWithin(width, height, maxEdge);
    return EncodedImage(Uint8List(sizeFor(maxEdge, quality)), 'image/jpeg', t.w, t.h);
  }

  @override
  void close() {}
}

Widget _app(Widget child, {List overrides = const [], FeatureSettings features = FeatureSettings.defaults}) =>
    ProviderScope(
      overrides: [
        featuresProvider.overrideWithValue(features),
        ...overrides.cast(),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('MediaImage parsing', () {
    test('absent, malformed or unusable maps are "no image"', () {
      expect(MediaImage.fromMap(null), isNull);
      expect(MediaImage.fromMap('https://x.org/a.jpg'), isNull);
      expect(MediaImage.fromMap({'source': 'ftp', 'url': 'https://x.org/a.jpg'}), isNull);
      expect(MediaImage.fromMap({'source': 'url', 'url': 'http://x.org/a.jpg'}), isNull); // https only
      expect(MediaImage.fromMap({'source': 'inline'}), isNull); // needs a media id
      expect(MediaImage.fromMap({'source': 'inline', 'mediaId': 'a/b'}), isNull);
      expect(MediaImage.fromMap({'source': 'storage', 'mediaId': 'x.jpg'}), isNull); // storage renders from url
    });

    test('url and inline images round-trip', () {
      final u = MediaImage.fromMap({'source': 'url', 'url': 'https://x.org/a.jpg', 'alt': 'Fr. Bemwa', 'w': 800})!;
      expect(u.isRemote, isTrue);
      expect(u.ownedMediaId, isNull);
      expect(u.alt, 'Fr. Bemwa');
      expect(MediaImage.fromMap(u.toMap()), u);
      final i = MediaImage.fromMap({'source': 'inline', 'mediaId': 'Abc_12-x', 'w': 800, 'h': 600.0})!;
      expect(i.isRemote, isFalse);
      expect(i.ownedMediaId, 'Abc_12-x');
      expect(i.h, 600);
      expect(i.aspectRatio, closeTo(800 / 600, 1e-9));
      expect(i.toMap(), {'source': 'inline', 'mediaId': 'Abc_12-x', 'w': 800, 'h': 600});
    });

    test('content models read the optional image (absent = null)', () {
      final img = {'source': 'inline', 'mediaId': 'm1'};
      expect(Priest.fromMap('p', {'name': 'أبونا'}).image, isNull);
      expect(Priest.fromMap('p', {'name': 'أبونا', 'image': img}).image?.mediaId, 'm1');
      expect(Saint.fromMap('s', {'nameAr': 'x', 'image': img}).image, isNotNull);
      expect(Milestone.fromMap('m', {'titleAr': 'x', 'image': img}).image, isNotNull);
      expect(Activity.fromMap('a', {'titleAr': 'x', 'image': img}).image, isNotNull);
      expect(Alert.fromMap('a', {'titleAr': 'x', 'image': img}).image, isNotNull);
      expect(Season.fromMap('s', {'key': 'pascha', 'image': img}).image, isNotNull);
      expect(Activity.fromMap('a', {'titleAr': 'x', 'image': 'broken'}).image, isNull);
    });

    test('priests fall back to a legacy https photoUrl', () {
      expect(Priest.fromMap('p', {'name': 'x', 'photoUrl': ''}).displayImage, isNull);
      expect(Priest.fromMap('p', {'name': 'x', 'photoUrl': 'http://x.org/a.jpg'}).displayImage, isNull);
      expect(Priest.fromMap('p', {'name': 'x', 'photoUrl': 'https://x.org/a.jpg'}).displayImage?.url,
          'https://x.org/a.jpg');
      final both = Priest.fromMap('p', {
        'name': 'x',
        'photoUrl': 'https://x.org/old.jpg',
        'image': {'source': 'inline', 'mediaId': 'm9'}
      });
      expect(both.displayImage?.mediaId, 'm9');
    });

    test('every seeded document has no image', () {
      final seed = SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);
      expect([...seed.priests.map((p) => p.displayImage), ...seed.saints.map((s) => s.image)], everyElement(isNull));
    });
  });

  group('validators', () {
    test('image URLs: https with a host, no spaces, ≤ 500 chars', () {
      expect(isValidImageUrl('https://example.org/a.jpg'), isTrue);
      expect(isValidImageUrl('https://cdn.example.org/p/a.webp?w=800#x'), isTrue);
      expect(isValidImageUrl('http://example.org/a.jpg'), isFalse);
      expect(isValidImageUrl('https://localhost/a.jpg'), isFalse);
      expect(isValidImageUrl('https://example.org/a b.jpg'), isFalse);
      expect(isValidImageUrl('javascript:alert(1)'), isFalse);
      expect(isValidImageUrl('/images/a.jpg'), isFalse);
      expect(isValidImageUrl('https://example.org/${'a' * 500}'), isFalse);
    });

    test('compressed size limits fit the rules cap', () {
      expect(validateMediaBytes(0), 'imageEmpty');
      expect(validateMediaBytes(MediaLimits.targetBytes), isNull);
      expect(validateMediaBytes(MediaLimits.maxBytes), isNull);
      expect(validateMediaBytes(MediaLimits.maxBytes + 1), 'imageTooLarge');
      expect(base64Length(MediaLimits.maxBytes), lessThanOrEqualTo(MediaLimits.maxBase64Chars));
      expect(base64Length(3), 4);
    });

    test('resize keeps the aspect ratio and never upscales', () {
      expect(fitWithin(4000, 3000), (w: 800, h: 600));
      expect(fitWithin(1000, 4000), (w: 200, h: 800));
      expect(fitWithin(640, 480), (w: 640, h: 480));
      expect(fitWithin(4000, 3000, 640), (w: 640, h: 480));
    });

    test('orphaned media ids after an edit or delete', () {
      final a = {'source': 'inline', 'mediaId': 'a'};
      final b = {'source': 'inline', 'mediaId': 'b'};
      final u = {'source': 'url', 'url': 'https://x.org/a.jpg'};
      expect(orphanedMediaIds(a, b), ['a']);
      expect(orphanedMediaIds(a, null), ['a']);
      expect(orphanedMediaIds(a, u), ['a']);
      expect(orphanedMediaIds(a, {...a, 'alt': 'new alt'}), isEmpty);
      expect(orphanedMediaIds(u, null), isEmpty);
      expect(orphanedMediaIds(null, b), isEmpty);
    });
  });

  group('compression', () {
    test('stops at the first quality under the target', () async {
      final d = _FakeDecoded((edge, q) => q >= 0.7 ? 400000 : 200000);
      final out = await compressDecoded(d);
      expect(out.length, 200000);
      expect(d.calls, ['800@0.8', '800@0.7', '800@0.6']);
      expect([out.w, out.h], [800, 600]);
    });

    test('falls back to a smaller edge, then keeps the smallest result under 700 KB', () async {
      final d = _FakeDecoded((edge, q) => edge == 800 ? 600000 : 300000);
      final out = await compressDecoded(d);
      expect(out.length, 300000);
      expect([out.w, out.h], [640, 480]);
    });

    test('rejects when nothing fits 700 KB', () async {
      final d = _FakeDecoded((edge, q) => 800000);
      expect(() => compressDecoded(d), throwsA(isA<ImageTooLargeException>()));
    });

    test('real pipeline: a large PNG becomes a ≤ 800 px JPEG under the target', () async {
      final src = img.Image(width: 1600, height: 1200, numChannels: 4);
      for (final p in src) {
        p
          ..r = (p.x * 7) % 256
          ..g = (p.y * 3) % 256
          ..b = (p.x + p.y) % 256
          ..a = p.x < 50 ? 0 : 255;
      }
      final out = await prepareUpload(img.encodePng(src));
      expect(out.contentType, 'image/jpeg');
      expect([out.w, out.h], [800, 600]);
      expect(out.length, lessThanOrEqualTo(MediaLimits.targetBytes));
      expect(img.decodeJpg(out.bytes), isNotNull);
    });

    test('garbage bytes are refused', () async {
      expect(() => prepareUpload(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<ImageDecodeException>()));
      expect(() => prepareUpload(Uint8List(0)), throwsA(isA<ImageDecodeException>()));
    });
  });

  group('media cache', () {
    test('loads each id once, evicts least recently used, retries failures', () async {
      final cache = MediaCache(capacity: 2);
      var calls = 0;
      Future<Uint8List?> loader(String id) async {
        calls++;
        if (id == 'bad') throw StateError('offline');
        return Uint8List.fromList([1]);
      }

      await cache.get('a', loader);
      await cache.get('a', loader);
      expect(calls, 1);
      await cache.get('b', loader);
      await cache.get('a', loader); // a is now most recent
      await cache.get('c', loader); // evicts b
      expect(cache.contains('b'), isFalse);
      expect(cache.contains('a'), isTrue);
      expect(await cache.get('bad', loader), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(cache.contains('bad'), isFalse); // next request retries
    });

    test('decodes media documents defensively', () {
      expect(decodeMediaDoc(null), isNull);
      expect(decodeMediaDoc({'dataBase64': 'AQID', 'contentType': 'image/gif'}), isNull);
      expect(decodeMediaDoc({'dataBase64': '!!', 'contentType': 'image/jpeg'}), isNull);
      expect(decodeMediaDoc({'dataBase64': 'AQID', 'contentType': 'image/jpeg'}), [1, 2, 3]);
    });
  });

  group('feature toggle', () {
    test('images are on by default and can be switched off', () {
      expect(FeatureSettings.defaults.showImages, isTrue);
      expect(Sections.all, contains(Sections.media));
      expect(FeatureSettings.fromMap({'sections': {'media': false}}).showImages, isFalse);
      expect(FeatureSettings.fromMap({'sections': {'media': false}}).toMap()['sections']['media'], isFalse);
    });

    test('the assistant prompt never carries image data', () {
      final seed = SeedData(jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>);
      final act = Activity.fromMap('x', {
        'titleAr': 'كورال',
        'titleEn': 'Choir',
        'image': {'source': 'url', 'url': 'https://img.example.org/secret-photo.jpg', 'alt': 'ALT-TEXT-123'},
      });
      final text = buildAssistantInstruction(
        settings: seed.settings,
        liturgies: const [],
        seasons: [
          Season.fromMap('s', {
            'key': 'pascha',
            'nameAr': 'القيامة',
            'image': {'source': 'inline', 'mediaId': 'MEDIA-ID-777'}
          })
        ],
        clinics: const [],
        meetings: const [],
        activities: [act],
        facilities: const [],
        now: CairoTime.at(2026, 11, 1, 600),
      );
      expect(text, contains('Choir'));
      expect(text, isNot(contains('secret-photo')));
      expect(text, isNot(contains('ALT-TEXT-123')));
      expect(text, isNot(contains('MEDIA-ID-777')));
    });
  });

  group('public cards', () {
    const placeholderKey = Key('ph');
    const inline = MediaImage(source: MediaSource.inline, mediaId: 'm1', alt: 'Photo of the choir');

    testWidgets('no image: exactly the placeholder', (tester) async {
      await tester.pumpWidget(_app(const ItemImage(image: null, size: 48, placeholder: SizedBox(key: placeholderKey))));
      expect(find.byKey(placeholderKey), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('itemImageTap')), findsNothing);
    });

    testWidgets('inline image is loaded lazily, cached, shown and enlargeable', (tester) async {
      final media = _FakeMedia()..docs['m1'] = _tinyPng;
      MediaCache.instance.clear();
      await tester.pumpWidget(_app(
        const ItemImage(image: inline, size: 48, placeholder: SizedBox(key: placeholderKey)),
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemImage')), findsOneWidget);
      expect(tester.widget<Image>(find.byKey(const Key('itemImage'))).semanticLabel, 'Photo of the choir');
      await tester.tap(find.byKey(const Key('itemImageTap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemImage')), findsNWidgets(2)); // card + viewer
      expect(media.loads, 1); // cached
    });

    testWidgets('missing media doc falls back to the placeholder', (tester) async {
      MediaCache.instance.clear();
      await tester.pumpWidget(_app(
        const ItemImage(image: inline, size: 48, placeholder: SizedBox(key: placeholderKey)),
        overrides: [mediaRepositoryProvider.overrideWithValue(_FakeMedia())],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(placeholderKey), findsOneWidget);
      expect(find.byKey(const Key('itemImage')), findsNothing);
    });

    testWidgets('images switched off in settings/features: placeholder only', (tester) async {
      final media = _FakeMedia()..docs['m1'] = _tinyPng;
      MediaCache.instance.clear();
      await tester.pumpWidget(_app(
        const ItemImage(image: inline, size: 48, placeholder: SizedBox(key: placeholderKey)),
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
        features: const FeatureSettings(sections: {'media': false}),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(placeholderKey), findsOneWidget);
      expect(find.byKey(const Key('itemImage')), findsNothing);
      expect(media.loads, 0);
    });

    testWidgets('priest card: person icon without a photo, the photo with one', (tester) async {
      final media = _FakeMedia()..docs['m1'] = _tinyPng;
      MediaCache.instance.clear();
      await tester.pumpWidget(_app(
        Column(children: [
          PriestCard(Priest.fromMap('a', {'name': 'القمص بموا'})),
          PriestCard(Priest.fromMap('b', {
            'name': 'القس بيجول',
            'image': {'source': 'inline', 'mediaId': 'm1'}
          })),
        ]),
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byKey(const Key('itemImage')), findsOneWidget);
      // alt falls back to the name
      expect(tester.widget<Image>(find.byKey(const Key('itemImage'))).semanticLabel, 'القس بيجول');
    });
  });

  group('admin image field', () {
    final def = collectionById('saints')!;
    final enc = EncodedImage(_tinyPng, 'image/webp', 800, 600);

    Widget editor({required _FakeMedia media, Map<String, dynamic>? data, required void Function(Map<String, dynamic>) onSaved}) =>
        _app(DocEditor(
          title: 'Saint',
          fields: def.fields,
          def: def,
          data: data,
          docId: data == null ? null : 's1',
          popOnSave: false,
          media: media,
          pickImage: () async => _tinyPng,
          prepareImage: (_) async => enc,
          onSave: (d) async => onSaved(d),
        ));

    testWidgets('is optional, uploads a picked image on save', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      expect(def.fields.any((f) => f.type == FieldType.image), isTrue);
      final media = _FakeMedia();
      Map<String, dynamic>? saved;
      await tester.pumpWidget(editor(media: media, onSaved: (d) => saved = d));
      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'القديس');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved!['image'], isNull); // no image is fine
      expect(media.docs, isEmpty);

      saved = null;
      await tester.pumpWidget(editor(media: media, onSaved: (d) => saved = d));
      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'القديس');
      await tester.tap(find.byKey(const Key('imageUploadBtn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imagePreviewPending')), findsOneWidget);
      expect(media.docs, isEmpty); // nothing stored before save
      await tester.enterText(find.byKey(const Key('imageAltInput')), 'Icon of the saint');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved!['image'], {'source': 'inline', 'mediaId': 'm0', 'alt': 'Icon of the saint', 'w': 800, 'h': 600});
      expect(media.docs.keys, ['m0']);
    });

    testWidgets('replacing an inline image with a URL deletes the old media doc', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final media = _FakeMedia()..docs['old'] = _tinyPng;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(editor(
        media: media,
        data: {
          'nameAr': 'القديس',
          'image': {'source': 'inline', 'mediaId': 'old'}
        },
        onSaved: (d) => saved = d,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('imageUrlBtn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('imageUrlInput')), 'http://insecure.example.org/a.jpg');
      await tester.tap(find.byKey(const Key('imageUrlOk')));
      await tester.pumpAndSettle();
      expect(find.text('Invalid link (must start with https://)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('imageUrlInput')), 'https://img.example.org/a.jpg');
      await tester.tap(find.byKey(const Key('imageUrlOk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, {
        'image': {'source': 'url', 'url': 'https://img.example.org/a.jpg'}
      }); // only the changed field
      expect(media.deleted, ['old']);
    });

    testWidgets('remove image writes null; a failed save rolls the upload back', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final media = _FakeMedia()..docs['old'] = _tinyPng;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(editor(
        media: media,
        data: {
          'nameAr': 'القديس',
          'image': {'source': 'inline', 'mediaId': 'old'}
        },
        onSaved: (d) => saved = d,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('imageRemoveBtn')));
      await tester.pumpAndSettle();
      expect(find.text('No image (optional)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, {'image': null});
      expect(media.deleted, ['old']);

      // Failing save: the uploaded media doc is removed again.
      final media2 = _FakeMedia();
      await tester.pumpWidget(_app(DocEditor(
        key: const Key('failing'),
        title: 'Saint',
        fields: def.fields,
        def: def,
        popOnSave: false,
        media: media2,
        pickImage: () async => _tinyPng,
        prepareImage: (_) async => enc,
        onSave: (d) async => throw StateError('permission-denied'),
      )));
      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'القديس');
      await tester.tap(find.byKey(const Key('imageUploadBtn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(media2.deleted, ['m0']);
      expect(find.byKey(const Key('imagePreviewPending')), findsOneWidget); // can retry
    });

    testWidgets('too-large images are refused with a message', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(DocEditor(
        title: 'Saint',
        fields: def.fields,
        def: def,
        popOnSave: false,
        media: _FakeMedia(),
        pickImage: () async => _tinyPng,
        prepareImage: (_) async => throw const ImageTooLargeException(),
        onSave: (d) async {},
      )));
      await tester.tap(find.byKey(const Key('imageUploadBtn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Image too large'), findsOneWidget);
      expect(find.byKey(const Key('imagePreviewPending')), findsNothing);
    });
  });
}
