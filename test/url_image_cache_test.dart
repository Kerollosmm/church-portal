import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_portal/data/url_image_cache_io.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/ui/widgets/item_image.dart';
import 'package:crypto/crypto.dart';
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

    test('fetches by sha256(url) once, serves memory hit without disk I/O, and serves disk offline', () async {
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
      final diskFile = File('${tempDir.path}/$digest.bin');
      expect(diskFile.existsSync(), isTrue);

      // New offline instance reads from disk and caches into memory without touching network.
      final offlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      final fromDisk = await offlineCache.get(url);
      expect(fromDisk, bytes);

      // Delete disk file behind the scenes: second call hits in-memory LRU cache.
      diskFile.deleteSync();
      final fromMemory = await offlineCache.get(url);
      expect(identical(fromMemory, fromDisk), isTrue);
    });

    test('deletes 0-byte corrupt file and retries when network returns', () async {
      const url = 'https://example.org/corrupt.jpg';
      final digest = sha256.convert(utf8.encode(url)).toString();
      final file = File('${tempDir.path}/$digest.bin')..writeAsBytesSync(const []);
      expect(file.existsSync(), isTrue);

      var failNetwork = true;
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9]);
      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async {
          if (failNetwork) throw const SocketException('offline');
          return http.Response.bytes(jpegBytes, 200);
        }),
      );

      // First attempt fails -> deletes 0-byte file, returns null, does NOT cache failure.
      expect(await cache.get(url), isNull);
      expect(file.existsSync(), isFalse);

      // Subsequent attempt once network recovers retries automatically and succeeds.
      failNetwork = false;
      expect(await cache.get(url), jpegBytes);
      expect(file.existsSync(), isTrue);
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

      // Fresh instance (disk hit) on urlA must update A's recency so B is oldest.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final diskHitCache = UrlImageCache(
        directory: tempDir,
        maxBytes: 100,
        client: MockClient((_) async => http.Response.bytes(Uint8List(45)..setAll(0, [0xFF, 0xD8, 0xFF]), 200)),
      );
      expect(await diskHitCache.get(urlA), hasLength(45));
      expect(fileA.lastModifiedSync().isAfter(fileB.lastModifiedSync()), isTrue);

      // Adding urlC pushes total > 100 B -> evicts urlB (oldest), retaining A + C.
      await diskHitCache.get(urlC);
      final fileC = File('${tempDir.path}/${sha256.convert(utf8.encode(urlC))}.bin');
      expect(fileB.existsSync(), isFalse);
      expect(fileA.existsSync(), isTrue);
      expect(fileC.existsSync(), isTrue);
    });

    test('amortizes eviction across evictInterval writes when under cap', () async {
      final cache = UrlImageCache(
        directory: tempDir,
        maxBytes: 1024,
        evictInterval: 3,
        client: MockClient((_) async => http.Response.bytes(Uint8List(60)..setAll(0, [0xFF, 0xD8, 0xFF]), 200)),
      );

      // Write 1 runs initial session cap check; writes 2 & 3 skip scanning; write 4 triggers 2nd scan.
      await cache.get('https://example.org/1.jpg');
      expect(cache.evictPasses, 1);

      await cache.get('https://example.org/2.jpg');
      await cache.get('https://example.org/3.jpg');
      expect(cache.evictPasses, 1);

      await cache.get('https://example.org/4.jpg');
      expect(cache.evictPasses, 2);
    });

    test('rejects single image exceeding maxSingleFileBytes via Content-Length', () async {
      const url = 'https://example.org/huge.jpg';
      expect(UrlImageCache.defaultMaxSingleFileBytes, 5 * 1024 * 1024);

      var streamedRead = false;
      final cache = UrlImageCache(
        directory: tempDir,
        maxSingleFileBytes: 64,
        client: MockClient.streaming((req, _) async {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              () {
                streamedRead = true;
                return Uint8List(128)..setAll(0, [0xFF, 0xD8, 0xFF]);
              }(),
            ]),
            200,
            contentLength: 128,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      expect(await cache.get(url), isNull);
      final digest = sha256.convert(utf8.encode(url)).toString();
      expect(File('${tempDir.path}/$digest.bin').existsSync(), isFalse);
      expect(streamedRead, isTrue); // MockClient evaluates stream arg, real socket skips reading body.
    });

    test('rejects > 5 MB streamed response without Content-Length and cancels stream early', () async {
      const url = 'https://example.org/chunked-huge.jpg';
      const chunkSize = 1024 * 1024; // 1 MB
      const totalChunks = 8; // 8 MB > 5 MB default cap
      const totalBytes = chunkSize * totalChunks;

      var chunksPulled = 0;
      var bytesPulled = 0;
      var cancelled = false;
      var calls = 0;
      final smallJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1]);

      Stream<List<int>> oversizedStream() async* {
        try {
          for (var i = 0; i < totalChunks; i++) {
            chunksPulled++;
            bytesPulled += chunkSize;
            final chunk = Uint8List(chunkSize);
            if (i == 0) chunk.setAll(0, [0xFF, 0xD8, 0xFF]);
            yield chunk;
          }
        } finally {
          cancelled = true;
        }
      }

      final cache = UrlImageCache(
        directory: tempDir,
        client: MockClient.streaming((req, _) async {
          calls++;
          if (calls == 1) {
            return http.StreamedResponse(
              oversizedStream(),
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.StreamedResponse(
            Stream<List<int>>.value(smallJpeg),
            200,
            contentLength: smallJpeg.length,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      expect(await cache.get(url), isNull);
      expect(cancelled, isTrue);
      expect(chunksPulled, lessThan(totalChunks));
      expect(bytesPulled, lessThan(totalBytes));

      final digest = sha256.convert(utf8.encode(url)).toString();
      expect(File('${tempDir.path}/$digest.bin').existsSync(), isFalse);

      // Nothing was stored in the memory cache either; subsequent get hits network again.
      expect(await cache.get(url), smallJpeg);
      expect(calls, 2);
    });

    test('rejected responses (non-200, wrong content-type, oversized Content-Length) do not consume body', () async {
      Future<void> verifyNotConsumed({
        required String url,
        required int statusCode,
        required Map<String, String> headers,
        int? contentLength,
      }) async {
        var bytesConsumed = 0;
        var cancelled = false;
        late StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onListen: () {
            Future<void>.microtask(() {
              if (cancelled || controller.isClosed) return;
              final chunk = Uint8List(128)..setAll(0, [0xFF, 0xD8, 0xFF]);
              bytesConsumed += chunk.length;
              controller.add(chunk);
              controller.close();
            });
          },
          onCancel: () {
            cancelled = true;
          },
        );

        final cache = UrlImageCache(
          directory: tempDir,
          maxSingleFileBytes: 64,
          client: MockClient.streaming((req, _) async {
            return http.StreamedResponse(
              controller.stream,
              statusCode,
              contentLength: contentLength,
              headers: headers,
            );
          }),
        );

        expect(await cache.get(url), isNull);
        expect(cancelled, isTrue);
        expect(bytesConsumed, 0);
        final digest = sha256.convert(utf8.encode(url)).toString();
        expect(File('${tempDir.path}/$digest.bin').existsSync(), isFalse);
      }

      await verifyNotConsumed(
        url: 'https://example.org/not-found.jpg',
        statusCode: 404,
        headers: {'content-type': 'image/jpeg'},
      );
      await verifyNotConsumed(
        url: 'https://example.org/wrong-type.jpg',
        statusCode: 200,
        headers: {'content-type': 'text/html'},
      );
      await verifyNotConsumed(
        url: 'https://example.org/oversized-header.jpg',
        statusCode: 200,
        contentLength: 128,
        headers: {'content-type': 'image/jpeg'},
      );
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

    test('defaults timeout to 25 s and times out stalled HTTP requests cleanly', () async {
      expect(UrlImageCache.fetchTimeout, const Duration(seconds: 25));

      final neverCompletes = Completer<http.Response>();
      final cache = UrlImageCache(
        directory: tempDir,
        timeout: const Duration(milliseconds: 50),
        client: MockClient((_) => neverCompletes.future),
      );

      final got = await cache.get('https://example.org/slow.jpg');
      expect(got, isNull);
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

    testWidgets('MediaImageView renders remote URL from offline async disk cache and retries/evicts on decode error',
        (tester) async {
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      const goodUrl = 'https://example.org/offline-saint.png';
      await tester.runAsync(() async {
        final onlineCache = UrlImageCache(
          directory: tempDir,
          client: MockClient((_) async => http.Response.bytes(png, 200)),
        );
        expect(await onlineCache.get(goodUrl), png);
      });

      final offlineCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      late Future<Uint8List?> pendingLoad;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageView(
            image: const MediaImage(source: MediaSource.url, url: goodUrl, alt: 'Cached Saint'),
            semanticLabel: 'Cached Saint',
            urlLoader: (u) => pendingLoad = Zone.root.run(() => offlineCache.get(u)),
            placeholder: const SizedBox(key: Key('ph')),
          ),
        ),
      );
      await tester.runAsync(() => pendingLoad);
      await tester.pumpAndSettle();

      final img = tester.widget<Image>(find.byKey(const Key('itemImage')));
      expect(img.semanticLabel, 'Cached Saint');
      expect(img.image, isA<MemoryImage>());

      // Now test decode error -> evicts corrupt non-zero disk file cleanly.
      const badUrl = 'https://example.org/corrupt-image.png';
      final badDigest = sha256.convert(utf8.encode(badUrl)).toString();
      final badFile = File('${tempDir.path}/$badDigest.bin')
        ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 1, 2]);
      expect(badFile.existsSync(), isTrue);

      Future<void>? pendingEvict;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageView(
            image: const MediaImage(source: MediaSource.url, url: badUrl),
            urlLoader: (u) => pendingLoad = Zone.root.run(() => offlineCache.get(u)),
            urlEvictor: (u) {
              final f = Zone.root.run(() => offlineCache.evict(u));
              pendingEvict = f;
              return f;
            },
            placeholder: const SizedBox(key: Key('ph')),
          ),
        ),
      );
      await tester.runAsync(() => pendingLoad);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (pendingEvict != null) await pendingEvict;
      });

      expect(find.byKey(const Key('ph')), findsOneWidget);
      expect(badFile.existsSync(), isFalse);

      // Failed remote fetch on first build retries automatically when widget rebuilds cleanly.
      const retryUrl = 'https://example.org/retry-saint.png';
      var failRetry = true;
      final retryCache = UrlImageCache(
        directory: tempDir,
        client: MockClient((_) async {
          if (failRetry) throw const SocketException('offline');
          return http.Response.bytes(png, 200);
        }),
      );
      Widget buildRetryView() => MaterialApp(
            home: MediaImageView(
              image: const MediaImage(source: MediaSource.url, url: retryUrl),
              urlLoader: (u) => pendingLoad = Zone.root.run(() => retryCache.get(u)),
              placeholder: const SizedBox(key: Key('ph')),
            ),
          );

      await tester.pumpWidget(buildRetryView());
      await tester.runAsync(() => pendingLoad);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ph')), findsOneWidget);

      failRetry = false;
      await tester.pumpWidget(buildRetryView());
      await tester.runAsync(() => pendingLoad);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('itemImage')), findsOneWidget);
    });
  });
}
