// Native-only (Android/IO) disk cache for remote image URLs.
// Enforces a 50 MB hard cap with oldest-first (LRU) eviction so rotating
// Firebase Storage `?token=...` URLs do not leak disk space.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class UrlImageCache {
  /// Default hard cap on cached remote image bytes (50 MB).
  static const int defaultMaxBytes = 50 * 1024 * 1024;
  static const Duration fetchTimeout = Duration(seconds: 8);
  static const MethodChannel _defaultChannel = MethodChannel('church_portal/installer');

  static final UrlImageCache instance = UrlImageCache();

  final Directory? directory;
  final int maxBytes;
  final http.Client? client;
  final MethodChannel channel;
  final Map<String, Future<Uint8List?>> _inFlight = {};
  Directory? _resolvedDir;

  UrlImageCache({
    this.directory,
    this.maxBytes = defaultMaxBytes,
    this.client,
    MethodChannel? channel,
  }) : channel = channel ?? _defaultChannel;

  Future<Directory> _dir() async {
    if (_resolvedDir != null) {
      return _ensureDirSync(_resolvedDir!);
    }
    if (directory != null) {
      return _ensureDirSync(directory!);
    }
    String? basePath;
    try {
      basePath = await channel.invokeMethod<String>('getCacheDir');
    } catch (_) {}
    final root = (basePath != null && basePath.isNotEmpty) ? basePath : Directory.systemTemp.path;
    return _ensureDirSync(Directory('$root/url_images'));
  }

  File _fileFor(Directory dir, String url) {
    final hash = sha256.convert(utf8.encode(url)).toString();
    return File('${dir.path}/$hash.bin');
  }

  /// Returns cached bytes immediately if valid on disk; otherwise fetches over
  /// HTTP (8 s timeout), stores atomically, and enforces [maxBytes] LRU cap.
  Future<Uint8List?> get(String url) {
    if (url.isEmpty) return Future.value(null);
    return _inFlight[url] ??= _load(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  /// Deletes any cached file for [url] (e.g. after [Image.memory] decode failure).
  Future<void> evict(String url) async {
    if (url.isEmpty) return;
    try {
      final dir = _resolvedDir != null
          ? _ensureDirSync(_resolvedDir!)
          : (directory != null ? _ensureDirSync(directory!) : await _dir());
      final file = _fileFor(dir, url);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  Future<Uint8List?> _load(String url) async {
    try {
      final dir = _resolvedDir != null
          ? _ensureDirSync(_resolvedDir!)
          : (directory != null ? _ensureDirSync(directory!) : await _dir());
      final file = _fileFor(dir, url);

      if (file.existsSync()) {
        final len = file.lengthSync();
        if (len > 0) {
          try {
            final bytes = file.readAsBytesSync();
            if (bytes.isNotEmpty && _looksLikeImageBytes(bytes)) {
              try {
                file.setLastModifiedSync(DateTime.now());
              } catch (_) {}
              return bytes;
            }
          } catch (_) {}
        }
        // Corrupt or 0-byte cached file: delete before trying network.
        try {
          file.deleteSync();
        } catch (_) {}
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !uri.isScheme('https')) return null;

      final ownsClient = client == null;
      final httpClient = client ?? http.Client();
      try {
        final res = await httpClient.get(uri).timeout(fetchTimeout);
        if (!_isAcceptedImageResponse(res)) return null;
        final bytes = res.bodyBytes;
        if (bytes.length <= maxBytes) {
          _writeAtomicAndEvict(dir, file, bytes);
        }
        return bytes;
      } finally {
        if (ownsClient) httpClient.close();
      }
    } catch (_) {
      return null;
    }
  }

  static bool _isAcceptedImageResponse(http.Response res) {
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
    final ct = res.headers['content-type']?.split(';').first.trim().toLowerCase() ?? '';
    if (ct.isNotEmpty &&
        !ct.startsWith('image/') &&
        ct != 'application/octet-stream' &&
        ct != 'binary/octet-stream') {
      return false;
    }
    return _looksLikeImageBytes(res.bodyBytes);
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

  Directory _ensureDirSync(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _resolvedDir = dir;
  }

  void _writeAtomicAndEvict(Directory dir, File target, Uint8List bytes) {
    _ensureDirSync(dir);
    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      tmp.writeAsBytesSync(bytes, flush: true);
      if (target.existsSync()) {
        target.deleteSync();
      }
      tmp.renameSync(target.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      return;
    }

    _evictToCap(dir, keepPath: target.path);
  }

  void _evictToCap(Directory dir, {required String keepPath}) {
    if (!dir.existsSync()) return;
    final entries = <({File file, int size, DateTime mtime})>[];
    var total = 0;

    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.bin')) continue;
      try {
        final stat = entity.statSync();
        if (stat.size <= 0) {
          entity.deleteSync();
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
        entry.file.deleteSync();
        total -= entry.size;
      } catch (_) {}
    }
  }
}
