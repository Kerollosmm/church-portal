// Android/IO implementation of PlatformAppUpdater (ADR-058 / PR B §3.3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_update.dart';

export '../domain/app_update.dart'
    show UpdateDownloadProgress, UpdateIntegrityException, UpdateSignatureException;

PlatformAppUpdater createPlatformAppUpdater({
  MethodChannel? channel,
  dynamic clientFactory,
  dynamic cacheDirectory,
  String? defaultManifestUrl,
}) =>
    PlatformAppUpdater(
      channel: channel,
      clientFactory: clientFactory as HttpClient Function()?,
      cacheDirectory: cacheDirectory as Directory?,
      defaultManifestUrl: defaultManifestUrl ?? 'https://maximos-domadios-church.web.app/app/android/version.json',
    );

/// Service managing in-app APK updates on Android.
class PlatformAppUpdater {
  static const MethodChannel _defaultChannel = MethodChannel('church_portal/installer');
  static const String dismissedKey = 'church_portal_update_dismissed';

  final MethodChannel channel;
  final HttpClient Function()? clientFactory;
  final Directory? cacheDirectory;
  final String defaultManifestUrl;

  PlatformAppUpdater({
    MethodChannel? channel,
    this.clientFactory,
    this.cacheDirectory,
    this.defaultManifestUrl = 'https://maximos-domadios-church.web.app/app/android/version.json',
  }) : channel = channel ?? _defaultChannel;

  /// True when running on native Android.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Queries the primary supported ABI (arm64-v8a or armeabi-v7a).
  Future<String> getSupportedAbi() async {
    try {
      final abi = await channel.invokeMethod<String>('supportedAbi');
      if (abi != null && abi.isNotEmpty) return shippedApkAbi(abi);
    } catch (_) {}
    return 'arm64-v8a';
  }

  /// True if unknown apps installation permission has been granted for this app.
  Future<bool> canRequestPackageInstalls() async {
    try {
      final canInstall = await channel.invokeMethod<bool>('canRequestPackageInstalls');
      if (canInstall != null) return canInstall;
    } catch (_) {}
    return true;
  }

  /// Launches the system unknown apps permission settings screen for this app.
  Future<void> openManageUnknownApps() async {
    try {
      await channel.invokeMethod<void>('openManageUnknownApps');
    } catch (_) {}
  }

  /// Verifies that the downloaded APK's signing certificate matches the installed application.
  Future<bool> verifyApkSignature(String filePath, {String? expectedCertSha256}) async {
    try {
      final match = await channel.invokeMethod<bool>('verifyApkSignature', {
        'filePath': filePath,
        'expectedCertSha256': ?expectedCertSha256,
      });
      return match ?? false;
    } catch (_) {
      // Fail closed (PR B §3.3): no proven certificate match → never launch the installer.
      return false;
    }
  }

  /// Launches the native package installer intent for the given APK file path.
  Future<void> installApk(String filePath) async {
    await channel.invokeMethod<void>('installApk', {'filePath': filePath});
  }

  /// Resolves the local cache directory used for update files.
  Future<Directory> getUpdatesDirectory() async {
    if (cacheDirectory != null) {
      final dir = Directory('${cacheDirectory!.path}/updates');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
    try {
      final cachePath = await channel.invokeMethod<String>('getCacheDir');
      if (cachePath != null && cachePath.isNotEmpty) {
        final dir = Directory('$cachePath/updates');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return dir;
      }
    } catch (_) {}
    final dir = Directory('${Directory.systemTemp.path}/updates');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Checks whether an in-app update should be offered.
  Future<UpdateDecision?> checkForUpdate({
    required int currentBuild,
    required int installApkBuild,
    String? manifestUrl,
  }) async {
    if (installApkBuild <= currentBuild) {
      return UpdateDecision.none;
    }

    final targetUrl = manifestUrl ?? defaultManifestUrl;
    UpdateManifest? manifest;

    try {
      final client = clientFactory != null ? clientFactory!() : HttpClient();
      try {
        final uri = Uri.parse(targetUrl);
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode == HttpStatus.ok) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          manifest = UpdateManifest.fromJson(json);
        }
      } finally {
        if (clientFactory == null) {
          client.close();
        }
      }
    } catch (_) {
      return UpdateDecision.none;
    }

    if (manifest == null) {
      return UpdateDecision.none;
    }

    int? dismissedBuild;
    try {
      final prefs = await SharedPreferences.getInstance();
      dismissedBuild = prefs.getInt(dismissedKey);
    } catch (_) {}

    final abi = await getSupportedAbi();

    return decideUpdate(
      currentBuild: currentBuild,
      installApkBuild: installApkBuild,
      manifest: manifest,
      dismissedBuild: dismissedBuild,
      abi: abi,
    );
  }

  /// Streams progress while downloading an APK update with HTTP Range resumption.
  Stream<UpdateDownloadProgress> downloadUpdate(
    ApkAsset asset, {
    required int build,
    void Function()? onCancel,
  }) async* {
    final updatesDir = await getUpdatesDirectory();
    final partFile = File('${updatesDir.path}/church-portal-$build.apk.part');
    final finalFile = File('${updatesDir.path}/church-portal-$build.apk');

    // If final verified file is already cached, return immediately
    if (finalFile.existsSync() && finalFile.lengthSync() == asset.size) {
      final calculatedHash = await _calculateFileSha256(finalFile);
      if (calculatedHash.toLowerCase() == asset.sha256.trim().toLowerCase()) {
        yield UpdateDownloadProgress(
          downloadedBytes: asset.size,
          totalBytes: asset.size,
          percent: 1.0,
          isDone: true,
          filePath: finalFile.path,
        );
        return;
      } else {
        try {
          finalFile.deleteSync();
        } catch (_) {}
      }
    }

    int existingBytes = 0;
    if (partFile.existsSync()) {
      existingBytes = partFile.lengthSync();
      if (existingBytes >= asset.size) {
        try {
          partFile.deleteSync();
        } catch (_) {}
        existingBytes = 0;
      }
    }

    final client = clientFactory != null ? clientFactory!() : HttpClient();
    client.autoUncompress = true;

    try {
      final uri = Uri.parse(asset.url);
      final request = await client.getUrl(uri);
      request.followRedirects = true;

      final bool isResume = existingBytes > 0;
      if (isResume) {
        request.headers.add(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      final bool serverAcceptsRange = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Download failed with status ${response.statusCode}: ${response.reasonPhrase}',
          uri: uri,
        );
      }

      int downloadedBytes = 0;
      final digestAccumulator = _DigestAccumulator();
      final hashInput = sha256.startChunkedConversion(digestAccumulator);
      IOSink fileSink;

      if (serverAcceptsRange && isResume) {
        downloadedBytes = existingBytes;
        final existingStream = partFile.openRead();
        await for (final chunk in existingStream) {
          hashInput.add(chunk);
        }
        fileSink = partFile.openWrite(mode: FileMode.append);
        yield UpdateDownloadProgress(
          downloadedBytes: downloadedBytes,
          totalBytes: asset.size,
          percent: downloadedBytes / asset.size,
        );
      } else {
        downloadedBytes = 0;
        fileSink = partFile.openWrite(mode: FileMode.write);
      }

      try {
        await for (final chunk in response) {
          hashInput.add(chunk);
          fileSink.add(chunk);
          downloadedBytes += chunk.length;
          yield UpdateDownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: asset.size,
            percent: (downloadedBytes / asset.size).clamp(0.0, 1.0),
          );
        }
      } finally {
        await fileSink.flush();
        await fileSink.close();
        hashInput.close();
      }

      final fileLength = await partFile.length();
      final actualHash = digestAccumulator.value.toString().toLowerCase();
      final expectedHash = asset.sha256.trim().toLowerCase();

      if (fileLength != asset.size || actualHash != expectedHash) {
        if (partFile.existsSync()) {
          try {
            await partFile.delete();
          } catch (_) {}
        }
        throw UpdateIntegrityException(
          'Integrity check failed: size=$fileLength (expected ${asset.size}), hash=$actualHash (expected $expectedHash)',
        );
      }

      if (finalFile.existsSync()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }
      await partFile.rename(finalFile.path);

      yield UpdateDownloadProgress(
        downloadedBytes: asset.size,
        totalBytes: asset.size,
        percent: 1.0,
        isDone: true,
        filePath: finalFile.path,
      );
    } finally {
      if (clientFactory == null) {
        client.close();
      }
    }
  }

  static Future<String> _calculateFileSha256(File file) async {
    final digestAccumulator = _DigestAccumulator();
    final hashInput = sha256.startChunkedConversion(digestAccumulator);
    await for (final chunk in file.openRead()) {
      hashInput.add(chunk);
    }
    hashInput.close();
    return digestAccumulator.value.toString();
  }

  /// Verifies signature, checks install permissions, and triggers APK installation.
  Future<void> installDownloadedUpdate(String filePath, {String? expectedCertSha256}) async {
    final validSignature = await verifyApkSignature(filePath, expectedCertSha256: expectedCertSha256);
    if (!validSignature) {
      throw const UpdateSignatureException('APK signature does not match installed application');
    }

    final canInstall = await canRequestPackageInstalls();
    if (!canInstall) {
      await openManageUnknownApps();
      return;
    }

    await installApk(filePath);
  }

  /// Persists user dismissal of the given build number.
  Future<void> dismissUpdate(int build) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(dismissedKey, build);
  }
}

class _DigestAccumulator implements Sink<Digest> {
  Digest? _digest;
  Digest get value => _digest!;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
