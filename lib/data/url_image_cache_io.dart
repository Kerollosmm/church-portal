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
    if (_resolvedDir != null) return _resolvedDir!;
    if (directory != null) {
      if (!directory!.existsSync()) directory!.createSync(recursive: true);
      return _resolvedDir = directory!;
    }
    String? basePath;
    try {
      basePath = await channel.invokeMethod<String>('getCacheDir');
    } catch (_) {}
    final root = (basePath != null && basePath.isNotEmpty) ? basePath : Directory.systemTemp.path;
    final dir = Directory('$root/url_images');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _resolvedDir = dir;
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

  Future<Uint8List?> _load(String url) async {
    try {
      final dir = _resolvedDir ?? (directory != null ? _ensureDirSync(directory!) : await _dir());
      final file = _fileFor(dir, url);

      if (file.existsSync()) {
        final len = file.lengthSync();
        if (len > 0) {
          try {
            final bytes = file.readAsBytesSync();
            if (bytes.isNotEmpty) {
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
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
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

  Directory _ensureDirSync(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _resolvedDir = dir;
  }

  void _writeAtomicAndEvict(Directory dir, File target, Uint8List bytes) {
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
