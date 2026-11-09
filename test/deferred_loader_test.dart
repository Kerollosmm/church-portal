import 'package:church_portal/data/error_reporting.dart';
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
  });
}
