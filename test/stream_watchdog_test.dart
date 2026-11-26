import 'dart:async';

import 'package:church_portal/data/stream_watchdog.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('watchWithFallback', () {
    test('1. live emits before timeout -> emits live value, cache not read', () {
      fakeAsync((async) {
        final live = StreamController<String>();
        var cacheReads = 0;
        final values = <String>[];
        final errors = <Object>[];

        final sub = watchWithFallback<String>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async {
            cacheReads++;
            return 'cached';
          },
          fallback: 'seed',
        ).listen(values.add, onError: errors.add);

        async.elapse(const Duration(seconds: 3));
        live.add('live-1');
        async.elapse(const Duration(seconds: 10));

        expect(values, ['live-1']);
        expect(errors, isEmpty);
        expect(cacheReads, 0);

        sub.cancel();
        live.close();
      });
    });

    test('2. silent live stream + cache hit -> after timeout emits cached value', () {
      fakeAsync((async) {
        final live = StreamController<String>();
        var cacheReads = 0;
        final values = <String>[];
        final fallbackMarks = <bool>[];

        final sub = watchWithFallback<String>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async {
            cacheReads++;
            return 'cached-1';
          },
          fallback: 'seed',
          onFallback: fallbackMarks.add,
        ).listen(values.add);

        async.elapse(const Duration(seconds: 7));
        expect(values, isEmpty);
        expect(cacheReads, 0);

        async.elapse(const Duration(seconds: 1));
        expect(cacheReads, 1);
        expect(values, ['cached-1']);
        // Cache hit is real stored data, not bundled seed fallback.
        expect(fallbackMarks, isEmpty);

        sub.cancel();
        live.close();
      });
    });

    test('3. silent live stream + cache miss with fallback != null -> after timeout emits fallback and onFallback(true)', () {
      fakeAsync((async) {
        final live = StreamController<String>();
        final values = <String>[];
        final fallbackMarks = <bool>[];

        final sub = watchWithFallback<String>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          fallback: 'seed',
          onFallback: fallbackMarks.add,
        ).listen(values.add);

        async.elapse(const Duration(seconds: 8));
        expect(values, ['seed']);
        expect(fallbackMarks, [true]);

        sub.cancel();
        live.close();
      });
    });

    test('4. silent live stream + cache miss with fallback == null and onMissError != null -> emits error and keeps live subscribed', () {
      fakeAsync((async) {
        final live = StreamController<List<String>>();
        final values = <List<String>>[];
        final errors = <Object>[];

        final sub = watchWithFallback<List<String>>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          onMissError: () => TimeoutException('liturgies timed out'),
        ).listen(values.add, onError: errors.add);

        async.elapse(const Duration(seconds: 8));
        expect(values, isEmpty);
        expect(errors, hasLength(1));
        expect(errors.single, isA<TimeoutException>());
        expect(live.hasListener, isTrue);

        // Late live emission still recovers automatically after error.
        live.add(['live-liturgy']);
        async.flushMicrotasks();
        expect(values, [
          ['live-liturgy'],
        ]);

        sub.cancel();
        live.close();
      });
    });

    test('5. silent live stream emits late after fallback -> emits late live value and calls onFallback(false)', () {
      fakeAsync((async) {
        final live = StreamController<String>();
        final values = <String>[];
        final fallbackMarks = <bool>[];

        final sub = watchWithFallback<String>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          fallback: 'seed',
          onFallback: fallbackMarks.add,
        ).listen(values.add);

        async.elapse(const Duration(seconds: 8));
        expect(values, ['seed']);
        expect(fallbackMarks, [true]);

        live.add('live-recovered');
        async.flushMicrotasks();
        expect(values, ['seed', 'live-recovered']);
        expect(fallbackMarks, [true, false]);

        sub.cancel();
        live.close();
      });
    });

    test('6. stream cancelled before timeout -> timer cancelled, no emissions or errors', () {
      fakeAsync((async) {
        final live = StreamController<String>();
        var cacheReads = 0;
        final values = <String>[];
        final errors = <Object>[];

        final sub = watchWithFallback<String>(
          live: live.stream,
          timeout: const Duration(seconds: 8),
          readCache: () async {
            cacheReads++;
            return 'cached';
          },
          onMissError: () => TimeoutException('should not fire'),
        ).listen(values.add, onError: errors.add);

        async.elapse(const Duration(seconds: 4));
        sub.cancel();
        async.elapse(const Duration(seconds: 10));

        expect(cacheReads, 0);
        expect(values, isEmpty);
        expect(errors, isEmpty);
        expect(live.hasListener, isFalse);

        live.close();
      });
    });
  });
}
