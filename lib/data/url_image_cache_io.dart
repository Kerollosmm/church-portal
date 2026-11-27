// Native-only (Android/IO) disk & in-memory cache for remote image URLs.
// Enforces a 50 MB hard disk cap with amortized oldest-first (LRU) eviction so
// rotating Firebase Storage `?token=...` URLs do not leak disk space, and a
// 30-entry in-memory LRU cache in front of async disk I/O.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class UrlImageCache {
  /// Default hard cap on cached remote image bytes on disk (50 MB).
  static const int defaultMaxBytes = 50 * 1024 * 1024;

  /// Default maximum size accepted for a single cached image (5 MB).
  static const int defaultMaxSingleFileBytes = 5 * 1024 * 1024;

  /// Default HTTP request & body read timeout (25 s for slow mobile links).
  static const Duration fetchTimeout = Duration(seconds: 25);

  /// Default in-memory LRU entry count kept in front of disk storage.
  static const int defaultMemoryCapacity = 30;

  /// Number of disk writes between amortized LRU eviction scans.
  static const int defaultEvictInterval = 5;

  static const MethodChannel _defaultChannel = MethodChannel('church_portal/installer');

  static final UrlImageCache instance = UrlImageCache();

  final Directory? directory;
  final int maxBytes;
  final int maxSingleFileBytes;
  final int memoryCapacity;
  final int evictInterval;
  final Duration timeout;
  final http.Client? client;
  final MethodChannel channel;

  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  Directory? _resolvedDir;
  bool _hasCheckedInitialCap = false;
  int _writesSinceEvict = 0;
  int _bytesSinceEvict = 0;

  @visibleForTesting
  int evictPasses = 0;

  UrlImageCache({
    this.directory,
    this.maxBytes = defaultMaxBytes,
    int? maxSingleFileBytes,
    this.memoryCapacity = defaultMemoryCapacity,
    this.evictInterval = defaultEvictInterval,
    this.timeout = fetchTimeout,
    this.client,
    MethodChannel? channel,
  })  : maxSingleFileBytes = maxSingleFileBytes ?? math.min(defaultMaxSingleFileBytes, maxBytes),
        channel = channel ?? _defaultChannel;

  Future<Directory> _dir() async {
    if (_resolvedDir != null) {
      return _ensureDir(_resolvedDir!);
    }
    if (directory != null) {
      return _ensureDir(directory!);
    }
    String? basePath;
    try {
      basePath = await channel.invokeMethod<String>('getCacheDir');
    } catch (_) {}
    final root = (basePath != null && basePath.isNotEmpty) ? basePath : Directory.systemTemp.path;
    return _ensureDir(Directory('$root/url_images'));
  }

  Future<Directory> _ensureDir(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _resolvedDir = dir;
  }

  File _fileFor(Directory dir, String url) {
    final hash = sha256.convert(utf8.encode(url)).toString();
    return File('${dir.path}/$hash.bin');
  }

  void _remember(String url, Uint8List bytes) {
    if (memoryCapacity <= 0) return;
    _memory.remove(url);
    if (_memory.length >= memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
    _memory[url] = bytes;
  }

  /// Returns cached bytes immediately from memory or async disk cache; on a
  /// miss, streams over HTTPS within [timeout] and stores valid images.
  /// Failed attempts are never cached so subsequent calls retry cleanly.
  Future<Uint8List?> get(String url) {
    if (url.isEmpty) return Future.value(null);
    final mem = _memory.remove(url);
    if (mem != null) {
      _memory[url] = mem;
      return Future.value(mem);
    }
    return _inFlight[url] ??= _load(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  /// Evicts [url] from both the in-memory LRU cache and disk storage.
  Future<void> evict(String url) async {
    if (url.isEmpty) return;
    _memory.remove(url);
    try {
      final dir = await _dir();
      final file = _fileFor(dir, url);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<Uint8List?> _load(String url) async {
    try {
      final dir = await _dir();
      final file = _fileFor(dir, url);

      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && len <= maxSingleFileBytes) {
          try {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty && _looksLikeImageBytes(bytes)) {
              try {
                await file.setLastModified(DateTime.now());
              } catch (_) {}
              _remember(url, bytes);
              return bytes;
            }
          } catch (_) {}
        }
        // Corrupt, oversized, or 0-byte cached file: delete before network fetch.
        try {
          await file.delete();
        } catch (_) {}
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !uri.isScheme('https')) return null;

      final ownsClient = client == null;
      final httpClient = client ?? http.Client();
      try {
        final bytes = await _fetchBoundedImage(httpClient, uri);
        if (bytes == null) return null;
        await _writeAtomicAndMaybeEvict(dir, file, bytes);
        _remember(url, bytes);
        return bytes;
      } finally {
        if (ownsClient) httpClient.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _fetchBoundedImage(http.Client httpClient, Uri uri) async {
    final req = http.Request('GET', uri);
    final streamed = await httpClient.send(req).timeout(timeout);
    if (streamed.statusCode != 200) {
      await streamed.stream.listen(null).cancel();
      return null;
    }
    final ct = streamed.headers['content-type']?.split(';').first.trim().toLowerCase() ?? '';
    if (ct.isNotEmpty &&
        !ct.startsWith('image/') &&
        ct != 'application/octet-stream' &&
        ct != 'binary/octet-stream') {
      await streamed.stream.listen(null).cancel();
      return null;
    }
    final contentLen = streamed.contentLength;
    if (contentLen != null && (contentLen <= 0 || contentLen > maxSingleFileBytes)) {
      await streamed.stream.listen(null).cancel();
      return null;
    }

    final builder = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(timeout);
    await for (final chunk in streamed.stream.timeout(timeout)) {
      if (DateTime.now().isAfter(deadline)) return null;
      if (builder.length + chunk.length > maxSingleFileBytes) {
        return null;
      }
      builder.add(chunk);
    }

    final bytes = builder.takeBytes();
    if (bytes.isEmpty || bytes.length > maxSingleFileBytes) return null;
    if (!_looksLikeImageBytes(bytes)) return null;
    return bytes;
  }

  static bool _looksLikeImageBytes(Uint8List b) {
    if (b.length < 3) return false;
    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
    // BMP: 42 4D ("BM")
    if (b[0] == 0x42 && b[1] == 0x4D) return true;
    // GIF: "GIF8"
    if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return true;
    // PNG: 89 50 4E 47
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
    // ICO: 00 00 01 00
    if (b.length >= 4 && b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x01 && b[3] == 0x00) return true;
    // WebP: "RIFF....WEBP"
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    // AVIF / HEIF / ISOBMFF: "....ftyp"
    if (b.length >= 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true;
    return false;
  }

  Future<void> _writeAtomicAndMaybeEvict(Directory dir, File target, Uint8List bytes) async {
    await _ensureDir(dir);
    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return;
    }

    _writesSinceEvict++;
    _bytesSinceEvict += bytes.length;
    if (!_hasCheckedInitialCap || _writesSinceEvict >= evictInterval || _bytesSinceEvict >= maxBytes) {
      _hasCheckedInitialCap = true;
      _writesSinceEvict = 0;
      _bytesSinceEvict = 0;
      await _evictToCap(dir, keepPath: target.path);
    }
  }

  Future<void> _evictToCap(Directory dir, {required String keepPath}) async {
    if (!await dir.exists()) return;
    evictPasses++;
    final entries = <({File file, int size, DateTime mtime})>[];
    var total = 0;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.bin')) continue;
      try {
        final stat = await entity.stat();
        if (stat.size <= 0) {
          await entity.delete();
          continue;
        }
        total += stat.size;
        entries.add((file: entity, size: stat.size, mtime: stat.modified));
      } catch (_) {}
    }

    if (total <= maxBytes) return;

    entries.sort((a, b) => a.mtime.compareTo(b.mtime));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      if (entry.file.path == keepPath) continue;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  }
}
