import 'dart:io';

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

    test('a 32-bit abi name does not fall through to the arm64 apk', () {
      final decision = decideUpdate(
        currentBuild: 1,
        installApkBuild: 3,
        manifest: sampleManifest,
        abi: 'armeabi',
      );
      expect(decision.asset!.url, contains('church-portal-arm32.apk'));
    });
  });

  test('shippedApkAbi keeps a 64-bit phone on the higher versionCode split', () {
    expect(shippedApkAbi('arm64-v8a'), 'arm64-v8a');
    expect(shippedApkAbi(' ARM64-V8A '), 'arm64-v8a');
    expect(shippedApkAbi('armeabi-v7a'), 'armeabi-v7a');
    expect(shippedApkAbi('armeabi'), 'armeabi-v7a');
    expect(shippedApkAbi('x86_64'), 'arm64-v8a');
  });

  test('applicationId is stable and a release keystore cannot fall back to debug', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.asafrachurch.church_portal"'));
    expect(gradle, contains('versionCode = flutter.versionCode'));
    expect(gradle, contains('ANDROID_REQUIRE_RELEASE_SIGNING'));
    expect(gradle, contains('Refusing to sign with the debug keystore'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final build = RegExp(r'^version:\s*[0-9.]+\+(\d+)', multiLine: true).firstMatch(pubspec);
    expect(int.parse(build!.group(1)!), greaterThan(3), reason: 'build must rise past the published 1.0.2+3');
  });
}
