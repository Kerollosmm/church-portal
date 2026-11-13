// Pure domain models and decision logic for in-app APK updates (ADR-058 / PR B §3.3).

class ApkAsset {
  final String url;
  final String sha256;
  final int size;

  const ApkAsset({
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory ApkAsset.fromJson(Map<String, dynamic> json) => ApkAsset(
        url: json['url'] as String? ?? '',
        sha256: json['sha256'] as String? ?? '',
        size: json['size'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'sha256': sha256,
        'size': size,
      };
}

class UpdateManifest {
  final int schema;
  final String version;
  final int build;
  final int minSupportedBuild;
  final String publishedAt;
  final String notesAr;
  final String notesEn;
  final String certSha256;
  final Map<String, ApkAsset> apks;

  const UpdateManifest({
    required this.schema,
    required this.version,
    required this.build,
    required this.minSupportedBuild,
    required this.publishedAt,
    required this.notesAr,
    required this.notesEn,
    required this.certSha256,
    required this.apks,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final rawApks = json['apks'];
    final Map<String, ApkAsset> apksMap = {};
    if (rawApks is Map) {
      for (final entry in rawApks.entries) {
        if (entry.value is Map<String, dynamic>) {
          apksMap[entry.key.toString()] = ApkAsset.fromJson(entry.value as Map<String, dynamic>);
        } else if (entry.value is Map) {
          apksMap[entry.key.toString()] =
              ApkAsset.fromJson(Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }

    return UpdateManifest(
      schema: json['schema'] as int? ?? 1,
      version: json['version'] as String? ?? '',
      build: json['build'] as int? ?? 0,
      minSupportedBuild: json['minSupportedBuild'] as int? ?? 0,
      publishedAt: json['publishedAt'] as String? ?? '',
      notesAr: json['notesAr'] as String? ?? '',
      notesEn: json['notesEn'] as String? ?? '',
      certSha256: json['certSha256'] as String? ?? '',
      apks: Map.unmodifiable(apksMap),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'version': version,
        'build': build,
        'minSupportedBuild': minSupportedBuild,
        'publishedAt': publishedAt,
        'notesAr': notesAr,
        'notesEn': notesEn,
        'certSha256': certSha256,
        'apks': apks.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class UpdateDecision {
  final bool hasUpdate;
  final bool forced;
  final ApkAsset? asset;
  final int targetBuild;
  final String targetVersion;
  final String notesAr;
  final String notesEn;
  final String certSha256;

  const UpdateDecision({
    required this.hasUpdate,
    this.forced = false,
    this.asset,
    this.targetBuild = 0,
    this.targetVersion = '',
    this.notesAr = '',
    this.notesEn = '',
    this.certSha256 = '',
  });

  bool get isForced => forced;

  static const none = UpdateDecision(hasUpdate: false);
}

/// Download progress state for in-app APK updates.
class UpdateDownloadProgress {
  final int downloadedBytes;
  final int totalBytes;
  final double percent;
  final bool isDone;
  final String? filePath;

  const UpdateDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.percent,
    this.isDone = false,
    this.filePath,
  });

  @override
  String toString() =>
      'UpdateDownloadProgress($downloadedBytes / $totalBytes, ${(percent * 100).toStringAsFixed(1)}%, done=$isDone)';
}

/// Thrown when a downloaded APK fails SHA-256 or size integrity check.
class UpdateIntegrityException implements Exception {
  final String message;
  const UpdateIntegrityException([this.message = 'Downloaded file integrity check failed']);

  @override
  String toString() => 'UpdateIntegrityException: $message';
}

/// Thrown when a downloaded APK signing certificate does not match the installed app.
class UpdateSignatureException implements Exception {
  final String message;
  const UpdateSignatureException([this.message = 'Downloaded APK signature mismatch']);

  @override
  String toString() => 'UpdateSignatureException: $message';
}

/// Manifest key for the APK this device should download.
///
/// `flutter build apk --split-per-abi` sets versionCode to
/// `abiDigit * 1000 + pubspecBuild` (arm64 → 2xxx, arm32 → 1xxx). Installing
/// the arm32 split over an arm64 install is a downgrade, and Android refuses
/// it. Prefer arm64 whenever that is the abi we were given; only the 32-bit
/// names select the arm32 file.
String shippedApkAbi(String raw) {
  final a = raw.trim().toLowerCase();
  if (a == 'arm64-v8a' || a == 'arm64') return 'arm64-v8a';
  if (a == 'armeabi-v7a' || a == 'armeabi' || a == 'arm32') return 'armeabi-v7a';
  // x86_64 emulators and an empty/unknown answer: the 64-bit split. A 32-bit
  // phone reports armeabi-v7a, so this does not hand it a 64-bit APK.
  return 'arm64-v8a';
}

/// Evaluates whether an update banner should be shown to the user.
UpdateDecision decideUpdate({
  required int currentBuild,
  required int installApkBuild,
  UpdateManifest? manifest,
  int? dismissedBuild,
  String abi = 'arm64-v8a',
}) {
  // If the admin haven't bumped the build above our current build, nothing to do.
  if (installApkBuild <= currentBuild) {
    return UpdateDecision.none;
  }

  // If manifest is missing or its build does not match the admin-announced build,
  // the release files are not live yet.
  if (manifest == null || manifest.build != installApkBuild) {
    return UpdateDecision.none;
  }

  final isForced = currentBuild < manifest.minSupportedBuild;

  // If dismissed for this build and not forced, respect user dismissal.
  if (!isForced && dismissedBuild != null && dismissedBuild == manifest.build) {
    return UpdateDecision.none;
  }

  // Pick the split this device can install over the one it already has.
  final key = shippedApkAbi(abi);
  final asset = manifest.apks[key] ??
      (key == 'armeabi-v7a' ? null : manifest.apks['arm64-v8a']) ??
      manifest.apks['armeabi-v7a'];

  if (asset == null || asset.url.isEmpty) {
    return UpdateDecision.none;
  }

  return UpdateDecision(
    hasUpdate: true,
    forced: isForced,
    asset: asset,
    targetBuild: manifest.build,
    targetVersion: manifest.version,
    notesAr: manifest.notesAr,
    notesEn: manifest.notesEn,
    certSha256: manifest.certSha256,
  );
}
