// In-app update service for Android APK releases (ADR-058 / PR B §3.3).

import 'dart:async';
import 'package:flutter/services.dart';

import '../domain/app_update.dart';
import 'app_updater_stub.dart'
    if (dart.library.io) 'app_updater_io.dart' as impl;

export '../domain/app_update.dart'
    show UpdateDownloadProgress, UpdateIntegrityException, UpdateSignatureException;

/// Unified AppUpdater service available across all platforms.
class AppUpdater {
  static const String dismissedKey = 'church_portal_update_dismissed';

  final impl.PlatformAppUpdater _impl;

  AppUpdater({
    MethodChannel? channel,
    dynamic clientFactory,
    dynamic cacheDirectory,
    String? defaultManifestUrl,
  }) : _impl = impl.createPlatformAppUpdater(
          channel: channel,
          clientFactory: clientFactory,
          cacheDirectory: cacheDirectory,
          defaultManifestUrl: defaultManifestUrl,
        );

  /// True when running on native Android.
  bool get isSupported => _impl.isSupported;

  /// Queries the primary supported ABI (arm64-v8a or armeabi-v7a).
  Future<String> getSupportedAbi() => _impl.getSupportedAbi();

  /// True if unknown apps installation permission has been granted for this app.
  Future<bool> canRequestPackageInstalls() => _impl.canRequestPackageInstalls();

  /// Launches the system unknown apps permission settings screen for this app.
  Future<void> openManageUnknownApps() => _impl.openManageUnknownApps();

  /// Verifies that the downloaded APK's signing certificate matches the installed application.
  Future<bool> verifyApkSignature(String filePath, {String? expectedCertSha256}) =>
      _impl.verifyApkSignature(filePath, expectedCertSha256: expectedCertSha256);

  /// Launches the native package installer intent for the given APK file path.
  Future<void> installApk(String filePath) => _impl.installApk(filePath);

  /// Checks whether an in-app update should be offered.
  Future<UpdateDecision?> checkForUpdate({
    required int currentBuild,
    required int installApkBuild,
    String? manifestUrl,
  }) =>
      _impl.checkForUpdate(
        currentBuild: currentBuild,
        installApkBuild: installApkBuild,
        manifestUrl: manifestUrl,
      );

  /// Streams progress while downloading an APK update with HTTP Range resumption.
  Stream<UpdateDownloadProgress> downloadUpdate(
    ApkAsset asset, {
    required int build,
    void Function()? onCancel,
  }) =>
      _impl.downloadUpdate(asset, build: build, onCancel: onCancel);

  /// Verifies signature, checks install permissions, and triggers APK installation.
  Future<void> installDownloadedUpdate(String filePath, {String? expectedCertSha256}) =>
      _impl.installDownloadedUpdate(filePath, expectedCertSha256: expectedCertSha256);

  /// Persists user dismissal of the given build number.
  Future<void> dismissUpdate(int build) => _impl.dismissUpdate(build);
}
