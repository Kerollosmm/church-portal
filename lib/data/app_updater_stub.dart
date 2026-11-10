// Stub implementation of PlatformAppUpdater for web and unsupported platforms (ADR-058).

import 'dart:async';
import 'package:flutter/services.dart';
import '../domain/app_update.dart';

PlatformAppUpdater createPlatformAppUpdater({
  MethodChannel? channel,
  dynamic clientFactory,
  dynamic cacheDirectory,
  String? defaultManifestUrl,
}) =>
    const PlatformAppUpdater();

class PlatformAppUpdater {
  const PlatformAppUpdater();

  bool get isSupported => false;

  Future<String> getSupportedAbi() async => 'arm64-v8a';

  Future<bool> canRequestPackageInstalls() async => false;

  Future<void> openManageUnknownApps() async {}

  Future<bool> verifyApkSignature(String filePath, {String? expectedCertSha256}) async => false;

  Future<void> installApk(String filePath) async {}

  Future<UpdateDecision?> checkForUpdate({
    required int currentBuild,
    required int installApkBuild,
    String? manifestUrl,
  }) async =>
      null;

  Stream<UpdateDownloadProgress> downloadUpdate(
    ApkAsset asset, {
    required int build,
    void Function()? onCancel,
  }) =>
      const Stream.empty();

  Future<void> installDownloadedUpdate(String filePath, {String? expectedCertSha256}) async {}

  Future<void> dismissUpdate(int build) async {}
}
