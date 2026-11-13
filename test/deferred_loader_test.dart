import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/data/error_reporting.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/deferred_chunk_policy.dart';
import 'package:church_portal/ui/widgets/deferred_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('DeferredLoader error reporting telemetry', () {
    late Map<String, String>? capturedTags;
    late Object? capturedError;

    setUp(() {
      capturedTags = null;
      capturedError = null;
      ErrorReporting.debugSink = (error, stack, tags) {
        capturedError = error;
        capturedTags = tags;
      };
    });

    tearDown(() {
      ErrorReporting.debugSink = null;
    });

    testWidgets('captures loadLibrary failure with source and section', (tester) async {
      final failException = Exception('Simulated chunk failure');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeferredLoader(
              source: 'test_chunk_source',
              loadLibrary: () => Future.error(failException),
              builder: (_) => const Text('loaded'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(capturedError, failException);
      expect(capturedTags?['section'], 'deferred_chunk');
      expect(capturedTags?['source'], 'test_chunk_source');
      expect(find.text('loaded'), findsNothing);
    });

    testWidgets('a deferred-part mismatch shows the retry card on non-web', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeferredLoader(
              loadLibrary: () => Future<void>.error(DeferredLoadException('part not loaded')),
              builder: (_) => const Text('loaded'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('loaded'), findsNothing);
    });
  });

  test('a stale deferred part reloads once per tab', () {
    const mismatch = 'Loading https://maximos-domadios-church.web.app/main.dart.js_15.part.js failed: '
        'Success callback invoked but part main.dart.js_15.part.js not loaded.';
    expect(shouldReloadDeferredChunk(DeferredLoadException(mismatch), null), isTrue);
    expect(shouldReloadDeferredChunk(DeferredLoadException(mismatch), '1'), isFalse);
    expect(
      shouldReloadDeferredChunk(DeferredLoadException('Loading https://x/main.dart.js_15.part.js failed: Failed to fetch'), null),
      isFalse,
    );
    expect(shouldReloadDeferredChunk(Exception('network'), null), isFalse);
  });

  test('unhashed Flutter bundles revalidate after the long-lived js rule', () {
    final cfg = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
    final app = (cfg['hosting'] as List).cast<Map<String, dynamic>>().firstWhere((s) => s['target'] == 'app');
    final headers = (app['headers'] as List).cast<Map<String, dynamic>>();
    String cache(String source) {
      final rule = headers.firstWhere((h) => h['source'] == source);
      final list = (rule['headers'] as List).cast<Map<String, dynamic>>();
      return list.firstWhere((h) => h['key'] == 'Cache-Control')['value'] as String;
    }

    final sources = [for (final h in headers) h['source'] as String];
    expect(sources.indexOf('**/*.@(js|mjs|wasm)'), lessThan(sources.indexOf('/main.dart.@(js|mjs|wasm)')));
    expect(sources.indexOf('**/*.@(js|mjs|wasm)'), lessThan(sources.indexOf('/main.dart.js_*.part.js')));
    expect(cache('/main.dart.@(js|mjs|wasm)'), 'no-cache');
    expect(cache('/main.dart.js_*.part.js'), 'no-cache');
    expect(cache('canvaskit/**'), 'public, max-age=604800');
    expect(cache('**/*.@(png|jpg|jpeg|webp|gif|svg|ico|otf|ttf|woff|woff2)'), 'public, max-age=604800');
  });
}
