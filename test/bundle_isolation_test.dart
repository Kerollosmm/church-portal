import 'dart:io';
import 'dart:typed_data';

import 'package:church_portal/config/app_config.dart';
import 'package:church_portal/data/app_check_providers.dart';
import 'package:church_portal/data/firebase_bootstrap.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/cairo_tzdata.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _NoopFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Set<String> _extractMapKeys(String mapBody) =>
    RegExp(r"'([^']+)'\s*:").allMatches(mapBody).map((m) => m.group(1)!).toSet();

Set<String> _extractL10nBaseKeys() {
  final l10n = File('lib/core/l10n.dart').readAsStringSync();
  final match = RegExp(r'const Map<String, List<String>> _strings = \{(.*?)\n\};', dotAll: true).firstMatch(l10n);
  if (match == null) {
    throw StateError('Could not find _strings map in lib/core/l10n.dart');
  }
  return _extractMapKeys(match.group(1)!);
}

Set<String> _extractDeferredMapKeys(String dartSource) {
  final keys = <String>{};
  for (final match in RegExp(r'const Map<String, List<String>>\s+\w+\s*=\s*\{(.*?)\n\};', dotAll: true)
      .allMatches(dartSource)) {
    keys.addAll(_extractMapKeys(match.group(1)!));
  }
  return keys;
}

void main() {
  group('ADR-077 bundle isolation & invariants', () {
    test('CairoTime generated tzdata matches package:timezone latest_10y for Africa/Cairo', () {
      CairoTime.ensureInitialized();
      final cairoOnly = CairoTime.location;
      final cairoZones = cairoOnly.zones.map((z) => (z.offset, z.isDst, z.abbreviation)).toList();
      final cairoTransitionAt = List<int>.from(cairoOnly.transitionAt);
      final cairoTransitionZone = List<int>.from(cairoOnly.transitionZone);
      final cairoOffsets = <int, (int offset, bool isDst, String abbr)>{};
      for (var year = 2023; year <= 2036; year++) {
        for (final probe in [
          DateTime.utc(year, 1, 15, 12),
          DateTime.utc(year, 4, 24, 21, 59),
          DateTime.utc(year, 4, 24, 22, 0),
          DateTime.utc(year, 5, 1, 12),
          DateTime.utc(year, 7, 1, 12),
          DateTime.utc(year, 10, 24, 20, 59),
          DateTime.utc(year, 10, 24, 21, 0),
          DateTime.utc(year, 11, 15, 12),
        ]) {
          final dt = tz.TZDateTime.from(probe, cairoOnly);
          cairoOffsets[probe.millisecondsSinceEpoch] = (
            dt.timeZoneOffset.inMinutes,
            dt.timeZone.isDst,
            dt.timeZoneName,
          );
        }
      }

      // Now load the full latest_10y database and verify Africa/Cairo is identical.
      tzdata.initializeTimeZones();
      final fullCairo = tz.getLocation('Africa/Cairo');

      expect(cairoTzVersion, isNotEmpty);
      expect(cairoTzData, isNotEmpty);
      expect(cairoOnly.name, fullCairo.name);
      expect(cairoTransitionAt, fullCairo.transitionAt);
      expect(cairoTransitionZone, fullCairo.transitionZone);
      expect(cairoZones.length, fullCairo.zones.length);
      for (var i = 0; i < cairoZones.length; i++) {
        expect(cairoZones[i].$1, fullCairo.zones[i].offset);
        expect(cairoZones[i].$2, fullCairo.zones[i].isDst);
        expect(cairoZones[i].$3, fullCairo.zones[i].abbreviation);
      }
      for (final entry in cairoOffsets.entries) {
        final fullDt = tz.TZDateTime.from(DateTime.fromMillisecondsSinceEpoch(entry.key, isUtc: true), fullCairo);
        expect(entry.value.$1, fullDt.timeZoneOffset.inMinutes, reason: 'UTC ms=${entry.key}');
        expect(entry.value.$2, fullDt.timeZone.isDst, reason: 'UTC ms=${entry.key}');
        expect(entry.value.$3, fullDt.timeZoneName, reason: 'UTC ms=${entry.key}');
      }

      // Restore the minimal Africa/Cairo-only database for subsequent tests in this isolate.
      tz.initializeDatabase(Uint8List.fromList(cairoTzData));
    });

    test('tool/gen_cairo_tz.dart --check confirms generated file matches latest_10y', () {
      final result = Process.runSync('dart', ['run', 'tool/gen_cairo_tz.dart', '--check']);
      expect(result.exitCode, 0, reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}');
    });

    test('all public tr() / trOrNull() calls outside lib/ui/admin resolve to l10n.dart or their deferred table', () {
      final baseKeys = _extractL10nBaseKeys();
      final deadKeys = [
        'factRank',
        'heroKicker',
        'readLife',
        'allContactWays',
        'unscheduled',
        'overviewHint',
        'alertsShort',
        'imageUploading',
        'checkHighlighted',
        'assistantStatusNote',
        'offlineReadingsError',
        'verseTab',
        'katamerosTab',
      ];
      for (final dead in deadKeys) {
        expect(baseKeys.contains(dead), isFalse, reason: 'Dead key $dead should stay removed from l10n.dart');
      }

      final missing = <String>[];
      final literalTr = RegExp(r'''\btr(?:OrNull)?\(\s*['"]([^'"]+)['"]''');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll('\\', '/');
        if (rel.startsWith('lib/ui/admin/') || rel == 'lib/core/l10n.dart') continue;

        final source = entity.readAsStringSync();
        final localKeys = source.contains('registerStrings(') ? _extractDeferredMapKeys(source) : const <String>{};

        for (final match in literalTr.allMatches(source)) {
          final key = match.group(1)!;
          if (key.contains(r'$')) continue; // dynamic interpolations verified separately below
          if (!baseKeys.contains(key) && !localKeys.contains(key)) {
            missing.add('$rel: $key');
          }
        }
      }
      expect(missing, isEmpty, reason: 'Missing public localization keys:\n${missing.join('\n')}');

      // Explicit check for public dynamic keys (`accent_$pageKey`, ternary literals, choice/section/nav labels).
      for (final requiredDynamic in [
        'hegumen',
        'priest',
        'nextPrayer',
        'nextMass',
        'privacyNoticeAnon',
        'privacyNotice',
        'consentLabelAnon',
        'consentLabel',
        'sending',
        'send',
        'tonightProgramme',
        'todayProgramme',
        'accent_about',
        'accent_schedule',
        'accent_education',
        'accent_activities',
        'accent_services',
        'accent_contact',
        'accent_ask',
        'accent_saint',
        'accent_priest',
        'accent_milestone',
        'accent_item',
        'dir_about',
        'dir_mass',
        'dir_edu',
        'dir_act',
        'dir_services',
        'dir_contact',
        'dir_ask',
        'opt_donate',
        'opt_volunteer',
        'opt_info',
        'opt_star',
        'opt_church',
        'opt_people',
      ]) {
        expect(baseKeys.contains(requiredDynamic), isTrue, reason: 'Dynamic public key missing: $requiredDynamic');
      }
    });

    test('main bundle files never import firebase_auth, latest_10y, firebase_app_check, or admin_repository', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final providersSource = File('lib/state/providers.dart').readAsStringSync();
      final bootstrapSource = File('lib/data/firebase_bootstrap.dart').readAsStringSync();
      final cairoSource = File('lib/domain/cairo_time.dart').readAsStringSync();
      final updateBannerStub = File('lib/ui/widgets/update_banner_stub.dart').readAsStringSync();
      final updateBannerRouter = File('lib/ui/widgets/update_banner.dart').readAsStringSync();

      expect(mainSource, isNot(contains('firebase_auth')));
      expect(mainSource, isNot(contains('admin_repository.dart')));
      expect(mainSource, isNot(contains('adminRepositoryProvider')));
      expect(mainSource, contains('createPublicMediaRepository'));

      expect(providersSource, isNot(contains('admin_repository.dart')));
      expect(providersSource, isNot(contains('adminRepositoryProvider')));

      expect(bootstrapSource, isNot(matches(RegExp(r'^import\s+.*firebase_app_check', multiLine: true))));
      expect(bootstrapSource, isNot(matches(RegExp(r'^import\s+.*app_check_providers\.dart', multiLine: true))));
      expect(bootstrapSource, contains('isAppCheckConfigured'));

      expect(cairoSource, isNot(contains('latest_10y')));
      expect(cairoSource, isNot(contains('latest_all')));
      expect(cairoSource, contains('cairoTzData'));

      expect(updateBannerRouter, contains("if (dart.library.io) 'update_banner_io.dart'"));
      expect(updateBannerStub, isNot(contains('l10n.dart')));
      expect(updateBannerStub, isNot(contains('appUpdaterProvider')));
      expect(updateBannerStub, contains('this.autoStart = true'));
    });

    test('isAppCheckConfigured matches selectAppCheckPlan.activate across all build/platform inputs', () {
      const dummyKey = '6LcTestEnterpriseKey1234567890';
      for (final isWeb in [false, true]) {
        for (final debug in [false, true]) {
          for (final siteKey in ['', 'PLACEHOLDER', 'YOUR_KEY', dummyKey, AppConfig.recaptchaSiteKey]) {
            final expected = selectAppCheckPlan(isWeb: isWeb, debug: debug, siteKey: siteKey).activate;
            final actual = isAppCheckConfigured(isWeb: isWeb, debug: debug, siteKey: siteKey);
            expect(actual, expected, reason: 'Mismatch for isWeb=$isWeb debug=$debug siteKey="$siteKey"');
          }
        }
      }
    });

    test('ReadOnlyMediaRepository refuses mutations so public bootstrap never writes empty createdBy', () {
      final repo = ReadOnlyMediaRepository(_NoopFirestore());
      final dummyImg = EncodedImage(Uint8List.fromList([1, 2, 3]), 'image/webp', 10, 10);

      expect(() => repo.upload(dummyImg, alt: 'test'), throwsUnsupportedError);
      expect(() => repo.delete('media-1'), throwsUnsupportedError);
    });
  });
}
