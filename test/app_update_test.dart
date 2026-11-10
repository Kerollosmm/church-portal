import 'package:flutter_test/flutter_test.dart';
import 'package:church_portal/domain/app_update.dart';

void main() {
  final sampleManifest = UpdateManifest.fromJson({
    'schema': 1,
    'version': '1.2.0',
    'build': 3,
    'minSupportedBuild': 1,
    'publishedAt': '2026-11-08T10:00:00Z',
    'notesAr': 'تحسينات جديدة',
    'notesEn': 'New improvements',
    'certSha256': 'AB:CD:EF:12:34:56',
    'apks': {
      'arm64-v8a': {
        'url': 'https://github.com/releases/download/v1.2.0/church-portal-arm64.apk',
        'sha256': '64hexstring',
        'size': 18500000,
      },
      'armeabi-v7a': {
        'url': 'https://github.com/releases/download/v1.2.0/church-portal-arm32.apk',
        'sha256': '32hexstring',
        'size': 16500000,
      },
    },
  });

  group('UpdateDecision logic', () {
    test('returns none when installApkBuild <= currentBuild', () {
      final decision = decideUpdate(
        currentBuild: 3,
        installApkBuild: 3,
        manifest: sampleManifest,
      );
      expect(decision.hasUpdate, isFalse);
    });

    test('returns update when installApkBuild > currentBuild and manifest matches', () {
      final decision = decideUpdate(
        currentBuild: 1,
        installApkBuild: 3,
        manifest: sampleManifest,
        abi: 'arm64-v8a',
      );
      expect(decision.hasUpdate, isTrue);
      expect(decision.forced, isFalse);
      expect(decision.targetBuild, 3);
      expect(decision.targetVersion, '1.2.0');
      expect(decision.asset!.size, 18500000);
      expect(decision.asset!.url, contains('church-portal-arm64.apk'));
    });

    test('returns none when manifest build does not equal installApkBuild', () {
      final decision = decideUpdate(
        currentBuild: 1,
        installApkBuild: 4, // admin saved 4, manifest is still build 3
        manifest: sampleManifest,
      );
      expect(decision.hasUpdate, isFalse);
    });

    test('respects user dismissal when not forced', () {
      final decision = decideUpdate(
        currentBuild: 1,
        installApkBuild: 3,
        manifest: sampleManifest,
        dismissedBuild: 3,
      );
      expect(decision.hasUpdate, isFalse);
    });

    test('ignores dismissal when currentBuild < minSupportedBuild (forced)', () {
      final forcedManifest = UpdateManifest.fromJson({
        ...sampleManifest.toJson(),
        'minSupportedBuild': 2,
      });

      final decision = decideUpdate(
        currentBuild: 1, // 1 < 2 -> forced
        installApkBuild: 3,
        manifest: forcedManifest,
        dismissedBuild: 3,
      );
      expect(decision.hasUpdate, isTrue);
      expect(decision.forced, isTrue);
    });

    test('picks correct ABI asset', () {
      final arm32Decision = decideUpdate(
        currentBuild: 1,
        installApkBuild: 3,
        manifest: sampleManifest,
        abi: 'armeabi-v7a',
      );
      expect(arm32Decision.hasUpdate, isTrue);
      expect(arm32Decision.asset!.url, contains('church-portal-arm32.apk'));
    });
  });
}
