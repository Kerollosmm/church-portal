import 'dart:async';

import 'package:church_portal/data/content_repository.dart';
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

  group('guardTimeSensitive', () {
    test('holds empty isFromCache snapshot, emits onMissError on cache miss (never seed), recovers on late live', () {
      fakeAsync((async) {
        final raw = StreamController<({List<String> value, bool isFromCache})>();
        final seedMarks = <bool>[];
        final values = <List<String>>[];
        final errors = <Object>[];

        final sub = guardTimeSensitive<String>(
          raw: raw.stream,
          gate: SeedGate(() async => true),
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          unseededFallback: const ['seed-mass'],
          onSeed: seedMarks.add,
          onMissError: () => TimeoutException('liturgies timed out'),
        ).listen(values.add, onError: errors.add);

        // Cold persistence emits empty cache snapshot right away: must NOT count as live `[]`.
        raw.add((value: const [], isFromCache: true));
        async.flushMicrotasks();
        expect(values, isEmpty);
        expect(errors, isEmpty);

        async.elapse(const Duration(seconds: 8));
        expect(values, isEmpty);
        expect(errors, hasLength(1));
        expect(errors.single, isA<TimeoutException>());
        expect(seedMarks, isNot(contains(true)));

        raw.add((value: const ['live-mass'], isFromCache: false));
        async.flushMicrotasks();
        expect(values, [
          ['live-mass'],
        ]);

        sub.cancel();
        raw.close();
      });
    });

    test('empty isFromCache snapshot held back -> cache hit after timeout emits cached items without seed', () {
      fakeAsync((async) {
        final raw = StreamController<({List<String> value, bool isFromCache})>();
        final values = <List<String>>[];
        final seedMarks = <bool>[];

        final sub = guardTimeSensitive<String>(
          raw: raw.stream,
          gate: SeedGate(() async => true),
          timeout: const Duration(seconds: 8),
          readCache: () async => const ['cached-mass'],
          unseededFallback: const ['seed-mass'],
          onSeed: seedMarks.add,
          onMissError: () => TimeoutException('timeout'),
        ).listen(values.add);

        raw.add((value: const [], isFromCache: true));
        async.elapse(const Duration(seconds: 8));

        expect(values, [
          ['cached-mass'],
        ]);
        expect(seedMarks, isNot(contains(true)));

        sub.cancel();
        raw.close();
      });
    });

    test('empty server snapshot on known-unseeded DB (markerAbsent) emits unseededFallback and clears mark on cancel', () {
      fakeAsync((async) {
        final raw = StreamController<({List<String> value, bool isFromCache})>();
        final values = <List<String>>[];
        final seedMarks = <bool>[];

        final sub = guardTimeSensitive<String>(
          raw: raw.stream,
          gate: SeedGate(() async => false),
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          unseededFallback: const ['seed-mass'],
          onSeed: seedMarks.add,
          onMissError: () => TimeoutException('timeout'),
        ).listen(values.add);

        raw.add((value: const [], isFromCache: false));
        async.flushMicrotasks();

        expect(values, [
          ['seed-mass'],
        ]);
        expect(seedMarks, [true]);

        sub.cancel();
        async.flushMicrotasks();
        expect(seedMarks, [true, false]);

        raw.close();
      });
    });

    test('empty server snapshot held on uncertain gate is released once whenSeeded fires', () {
      fakeAsync((async) {
        final raw = StreamController<({List<String> value, bool isFromCache})>();
        final gate = SeedGate(() async => throw TimeoutException('settings read stalled'));
        final values = <List<String>>[];
        final errors = <Object>[];

        final sub = guardTimeSensitive<String>(
          raw: raw.stream,
          gate: gate,
          timeout: const Duration(seconds: 8),
          readCache: () async => null,
          unseededFallback: const ['seed-season'],
          onSeed: (_) {},
          onMissError: () => TimeoutException('timeout'),
        ).listen(values.add, onError: errors.add);

        raw.add((value: const [], isFromCache: false));
        async.flushMicrotasks();
        expect(values, isEmpty);

        // Settings listener later proves the DB is seeded (ADR-038): held empty `[]` releases immediately.
        gate.markSeeded();
        async.flushMicrotasks();
        expect(values, [<String>[]]);
        expect(errors, isEmpty);

        // Watchdog timer was satisfied by `[]`, so advancing past 8s does not emit TimeoutException.
        async.elapse(const Duration(seconds: 10));
        expect(errors, isEmpty);

        sub.cancel();
        raw.close();
      });
    });
  });
}
