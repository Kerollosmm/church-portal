import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/app_updater.dart';
import 'package:church_portal/domain/app_update.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/update_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HttpServer testServer;
  late List<int> samplePayload;
  late String sampleSha256;

  setUpAll(() async {
    samplePayload = utf8.encode('church-portal-test-apk-payload-content-1234567890');
    sampleSha256 = sha256.convert(samplePayload).toString();
  });

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    tempDir = await Directory.systemTemp.createTemp('church_portal_update_test_');
    testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await testServer.close(force: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppUpdater IO downloader and verification tests', () {
    test('downloadUpdate validates matching SHA-256 and renames .part to .apk', () async {
      testServer.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = samplePayload.length;
        request.response.add(samplePayload);
        request.response.close();
      });

      final updater = AppUpdater(
        cacheDirectory: tempDir,
      );

      final asset = ApkAsset(
        url: 'http://${testServer.address.host}:${testServer.port}/church-portal.apk',
        sha256: sampleSha256,
        size: samplePayload.length,
      );

      final progressEvents = await updater.downloadUpdate(asset, build: 101).toList();

      expect(progressEvents.isNotEmpty, isTrue);
      final lastProgress = progressEvents.last;
      expect(lastProgress.isDone, isTrue);
      expect(lastProgress.downloadedBytes, samplePayload.length);
      expect(lastProgress.totalBytes, samplePayload.length);
      expect(lastProgress.percent, 1.0);

      final updatesDir = Directory('${tempDir.path}/updates');
      final finalFile = File('${updatesDir.path}/church-portal-101.apk');
      final partFile = File('${updatesDir.path}/church-portal-101.apk.part');

      expect(finalFile.existsSync(), isTrue);
      expect(partFile.existsSync(), isFalse);
      expect(await finalFile.readAsBytes(), samplePayload);
    });

    test('downloadUpdate throws UpdateIntegrityException and deletes file on hash mismatch', () async {
      testServer.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(samplePayload);
        request.response.close();
      });

      final updater = AppUpdater(
        cacheDirectory: tempDir,
      );

      final mismatchAsset = ApkAsset(
        url: 'http://${testServer.address.host}:${testServer.port}/church-portal.apk',
        sha256: '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
        size: samplePayload.length,
      );

      expect(
        () => updater.downloadUpdate(mismatchAsset, build: 102).drain(),
        throwsA(isA<UpdateIntegrityException>()),
      );

      final updatesDir = Directory('${tempDir.path}/updates');
      final partFile = File('${updatesDir.path}/church-portal-102.apk.part');
      final finalFile = File('${updatesDir.path}/church-portal-102.apk');

      expect(partFile.existsSync(), isFalse);
      expect(finalFile.existsSync(), isFalse);
    });

    test('downloadUpdate generates HTTP Range header on partial file and resumes download', () async {
      final halfLength = samplePayload.length ~/ 2;
      final existingBytes = samplePayload.sublist(0, halfLength);
      final remainingBytes = samplePayload.sublist(halfLength);

      final updatesDir = Directory('${tempDir.path}/updates');
      await updatesDir.create(recursive: true);
      final partFile = File('${updatesDir.path}/church-portal-103.apk.part');
      await partFile.writeAsBytes(existingBytes, flush: true);

      String? receivedRangeHeader;

      testServer.listen((HttpRequest request) {
        receivedRangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        if (receivedRangeHeader != null && receivedRangeHeader!.startsWith('bytes=')) {
          request.response.statusCode = HttpStatus.partialContent; // 206
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $halfLength-${samplePayload.length - 1}/${samplePayload.length}',
          );
          request.response.add(remainingBytes);
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(samplePayload);
        }
        request.response.close();
      });

      final updater = AppUpdater(
        cacheDirectory: tempDir,
      );

      final asset = ApkAsset(
        url: 'http://${testServer.address.host}:${testServer.port}/church-portal.apk',
        sha256: sampleSha256,
        size: samplePayload.length,
      );

      final progressEvents = await updater.downloadUpdate(asset, build: 103).toList();

      expect(receivedRangeHeader, 'bytes=$halfLength-');
      expect(progressEvents.last.isDone, isTrue);

      final finalFile = File('${updatesDir.path}/church-portal-103.apk');
      expect(finalFile.existsSync(), isTrue);
      expect(partFile.existsSync(), isFalse);
      expect(await finalFile.readAsBytes(), samplePayload);
    });
  });

  group('Dismiss update persistence tests', () {
    test('dismissUpdate persists dismissed build to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final updater = AppUpdater(cacheDirectory: tempDir);

      await updater.dismissUpdate(42);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AppUpdater.dismissedKey), 42);
    });

    test('checkForUpdate respects dismissed build number and returns none', () async {
      SharedPreferences.setMockInitialValues({
        AppUpdater.dismissedKey: 50,
      });

      final manifestData = {
        'schema': 1,
        'version': '1.5.0',
        'build': 50,
        'minSupportedBuild': 1,
        'publishedAt': '2026-11-08T10:00:00Z',
        'notesAr': 'ملاحظات',
        'notesEn': 'Notes',
        'certSha256': '',
        'apks': {
          'arm64-v8a': {
            'url': 'https://example.com/app.apk',
            'sha256': 'abc',
            'size': 12345,
          },
        },
      };

      testServer.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(manifestData));
        request.response.close();
      });

      final updater = AppUpdater(
        cacheDirectory: tempDir,
        defaultManifestUrl: 'http://${testServer.address.host}:${testServer.port}/version.json',
      );

      final decision = await updater.checkForUpdate(
        currentBuild: 10,
        installApkBuild: 50,
      );

      expect(decision, isNotNull);
      expect(decision!.hasUpdate, isFalse);
    });
  });

  group('UpdateBanner widget tests', () {
    Widget buildBannerWrapper({
      required UpdateDecision decision,
      AppUpdater? customUpdater,
    }) {
      return ProviderScope(
        overrides: [
          if (customUpdater != null) appUpdaterProvider.overrideWithValue(customUpdater),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: UpdateBanner(
              decision: decision,
              autoStartDownload: false,
            ),
          ),
        ),
      );
    }

    testWidgets('renders banner with version and action buttons when update available', (tester) async {
      const decision = UpdateDecision(
        hasUpdate: true,
        forced: false,
        targetVersion: '2.1.0',
        targetBuild: 210,
        notesAr: 'تحسينات وإصلاحات جديدة',
        notesEn: 'New improvements and fixes',
        asset: ApkAsset(url: 'https://example.com/test.apk', sha256: 'abc', size: 1000),
      );

      await tester.pumpWidget(buildBannerWrapper(decision: decision));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appUpdateBanner')), findsOneWidget);
      expect(find.textContaining('2.1.0'), findsOneWidget);
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(find.byKey(const Key('dismissUpdateButton')), findsOneWidget);
    });

    testWidgets('forced update hides dismiss button', (tester) async {
      const forcedDecision = UpdateDecision(
        hasUpdate: true,
        forced: true,
        targetVersion: '2.1.0',
        targetBuild: 210,
        asset: ApkAsset(url: 'https://example.com/test.apk', sha256: 'abc', size: 1000),
      );

      await tester.pumpWidget(buildBannerWrapper(decision: forcedDecision));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appUpdateBanner')), findsOneWidget);
      expect(find.byKey(const Key('dismissUpdateButton')), findsNothing);
    });

    testWidgets('tapping dismiss hides banner and persists dismissal', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final updater = AppUpdater(cacheDirectory: tempDir);

      const decision = UpdateDecision(
        hasUpdate: true,
        forced: false,
        targetVersion: '2.1.0',
        targetBuild: 210,
        asset: ApkAsset(url: 'https://example.com/test.apk', sha256: 'abc', size: 1000),
      );

      await tester.pumpWidget(buildBannerWrapper(
        decision: decision,
        customUpdater: updater,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appUpdateBanner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismissUpdateButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appUpdateBanner')), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AppUpdater.dismissedKey), 210);
    });

    testWidgets('tapping update now button opens modal sheet with release notes', (tester) async {
      const decision = UpdateDecision(
        hasUpdate: true,
        forced: false,
        targetVersion: '2.1.0',
        targetBuild: 210,
        notesAr: 'ملاحظات الإصدار التجريبية',
        notesEn: 'Test release notes',
        asset: ApkAsset(url: 'https://example.com/test.apk', sha256: 'abc', size: 1000),
      );

      await tester.pumpWidget(buildBannerWrapper(decision: decision));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('updateNowButton')));
      await tester.pumpAndSettle();

      expect(find.byType(UpdateSheet), findsOneWidget);
      expect(find.text('تحديث التطبيق'), findsOneWidget);
      expect(find.text('v2.1.0'), findsOneWidget);
      expect(find.text('ملاحظات الإصدار التجريبية'), findsOneWidget);
      expect(find.byKey(const Key('startDownloadButton')), findsOneWidget);
    });
  });
}

class _RealHttpOverrides extends HttpOverrides {}
