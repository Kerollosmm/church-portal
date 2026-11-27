import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_portal/data/url_image_cache_io.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/ui/widgets/item_image.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('UrlImageCache (IO)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('url_image_cache_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('fetches by sha256(url) once and serves cached bytes offline', () async {
      const url = 'https://example.org/saint.jpg';
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 5]);
      var calls = 0;

      final onlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((req) async {
          calls++;
          expect(req.url.toString(), url);
          return http.Response.bytes(bytes, 200);
        }),
      );

      final got1 = await onlineCache.get(url);
      expect(got1, bytes);
      expect(calls, 1);

      final digest = sha256.convert(utf8.encode(url)).toString();
      expect(File('${tempDir.path}/$digest.bin').existsSync(), isTrue);

      // Offline instance against the same cache directory must return cached bytes.
      final offlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      final got2 = await offlineCache.get(url);
      expect(got2, bytes);
    });

    test('deletes 0-byte corrupt file and re-fetches or returns null cleanly', () async {
      const url = 'https://example.org/corrupt.jpg';
      final digest = sha256.convert(utf8.encode(url)).toString();
      final file = File('${tempDir.path}/$digest.bin')..writeAsBytesSync(const []);
      expect(file.existsSync(), isTrue);

      final offlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      expect(await offlineCache.get(url), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('touches mtime on cache hit and evicts oldest-first (LRU) above maxBytes', () async {
      const urlA = 'https://firebasestorage.googleapis.com/v0/b/app/img.jpg?alt=media&token=t1';
      const urlB = 'https://firebasestorage.googleapis.com/v0/b/app/img.jpg?alt=media&token=t2';
      const urlC = 'https://firebasestorage.googleapis.com/v0/b/app/img.jpg?alt=media&token=t3';
      final cache = UrlImageCache(
        directory: tempDir,
        maxBytes: 100,
        client: MockClient((_) async => http.Response.bytes(Uint8List(45)..setAll(0, [0xFF, 0xD8, 0xFF]), 200)),
      );

      await cache.get(urlA); // 45 B
      await cache.get(urlB); // 90 B total

      final fileA = File('${tempDir.path}/${sha256.convert(utf8.encode(urlA))}.bin');
      final fileB = File('${tempDir.path}/${sha256.convert(utf8.encode(urlB))}.bin');
      fileA.setLastModifiedSync(DateTime(2026, 1, 1, 10, 0));
      fileB.setLastModifiedSync(DateTime(2026, 1, 1, 10, 5));

      // Cache hit on urlA must update A's recency so B becomes the oldest-used entry.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await cache.get(urlA), hasLength(45));
      expect(fileA.lastModifiedSync().isAfter(fileB.lastModifiedSync()), isTrue);

      // Adding urlC (45 B -> 135 B > 100 B) evicts urlB (oldest), retaining A + C (90 B).
      await cache.get(urlC);
      final fileC = File('${tempDir.path}/${sha256.convert(utf8.encode(urlC))}.bin');
      expect(fileB.existsSync(), isFalse);
      expect(fileA.existsSync(), isTrue);
      expect(fileC.existsSync(), isTrue);
    });

    test('deduplicates concurrent requests for the same URL', () async {
      const url = 'https://example.org/hero.jpg';
      final completer = Completer<http.Response>();
      var calls = 0;
      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) {
          calls++;
          return completer.future;
        }),
      );

      final f1 = cache.get(url);
      final f2 = cache.get(url);
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 8, 7]);
      completer.complete(http.Response.bytes(jpegBytes, 200));

      final results = await Future.wait<Uint8List?>([f1, f2]);
      expect(calls, 1);
      expect(results[0], jpegBytes);
      expect(results[1], jpegBytes);
    });

    test('times out stalled HTTP requests after 8 s and returns null cleanly', () {
      fakeAsync((async) {
        final neverCompletes = Completer<http.Response>();
        final cache = UrlImageCache(
          directory: tempDir,
          client: MockClient((_) => neverCompletes.future),
        );

        Uint8List? got = Uint8List.fromList([1]);
        cache.get('https://example.org/slow.jpg').then((v) => got = v);

        async.elapse(const Duration(seconds: 7));
        expect(got, isNotNull);

        async.elapse(const Duration(seconds: 1, milliseconds: 10));
        expect(got, isNull);
      });
    });

    testWidgets('MediaImageView renders remote URL from offline disk cache on non-web platforms', (tester) async {
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      const url = 'https://example.org/offline-saint.png';
      final onlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => http.Response.bytes(png, 200)),
      );
      expect(await onlineCache.get(url), png);

      final offlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageView(
            image: const MediaImage(source: MediaSource.url, url: url, alt: 'Cached Saint'),
            semanticLabel: 'Cached Saint',
            urlLoader: offlineCache.get,
            placeholder: const SizedBox(key: Key('ph')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final img = tester.widget<Image>(find.byKey(const Key('itemImage')));
      expect(img.semanticLabel, 'Cached Saint');
      expect(img.image, isA<MemoryImage>());
    });

    test('recreates cache directory if OS purges cacheDir mid-session', () async {
      const urlA = 'https://example.org/a.jpg';
      const urlB = 'https://example.org/b.jpg';
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => http.Response.bytes(jpegBytes, 200)),
      );

      expect(await cache.get(urlA), jpegBytes);
      // Simulate OS storage manager clearing cacheDir while app stays alive.
      tempDir.deleteSync(recursive: true);
      expect(tempDir.existsSync(), isFalse);

      expect(await cache.get(urlB), jpegBytes);
      final digestB = sha256.convert(utf8.encode(urlB)).toString();
      expect(File('${tempDir.path}/$digestB.bin').existsSync(), isTrue);
    });

    test('rejects captive-portal 200 text/html and non-image responses without caching', () async {
      const htmlUrl = 'https://example.org/portal.jpg';
      final htmlBytes = utf8.encode('<html><body>Sign in</body></html>');
      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => http.Response.bytes(
              htmlBytes,
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            )),
      );

      expect(await cache.get(htmlUrl), isNull);
      final digest = sha256.convert(utf8.encode(htmlUrl)).toString();
      expect(File('${tempDir.path}/$digest.bin').existsSync(), isFalse);

      const spoofedUrl = 'https://example.org/spoofed.jpg';
      final spoofedCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => http.Response.bytes(
              htmlBytes,
              200,
              headers: {'content-type': 'application/octet-stream'},
            )),
      );
      expect(await spoofedCache.get(spoofedUrl), isNull);
      final spoofDigest = sha256.convert(utf8.encode(spoofedUrl)).toString();
      expect(File('${tempDir.path}/$spoofDigest.bin').existsSync(), isFalse);
    });

    testWidgets('MediaImageView evicts corrupt non-zero disk file on decode error', (tester) async {
      const url = 'https://example.org/corrupt-image.png';
      final digest = sha256.convert(utf8.encode(url)).toString();
      final badBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 1, 2]);
      final file = File('${tempDir.path}/$digest.bin')..writeAsBytesSync(badBytes);
      expect(file.existsSync(), isTrue);

      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageView(
            image: const MediaImage(source: MediaSource.url, url: url),
            urlLoader: cache.get,
            urlEvictor: cache.evict,
            placeholder: const SizedBox(key: Key('ph')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ph')), findsOneWidget);
      expect(file.existsSync(), isFalse);
    });
  });
}
