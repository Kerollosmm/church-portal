import 'dart:async';

import 'package:church_portal/data/content_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the microtask / event queues so stream events are delivered.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('guardSeeded (seed fallback recovery, BUG-05)', () {
    late StreamController<List<int>> live;
    late List<bool> marks;
    late List<List<int>> got;

    setUp(() {
      live = StreamController<List<int>>();
      marks = [];
      got = [];
    });
    tearDown(() => live.close());

    StreamSubscription<List<int>> listen(SeedGate gate) => guardSeeded<List<int>>(
          gate: gate,
          live: () => live.stream,
          fallback: const [0],
          confirms: (v) => v.isNotEmpty,
          onSeed: marks.add,
        ).listen(got.add);

    test('seeded database: live values straight away', () async {
      final sub = listen(SeedGate(() async => true));
      await _settle();
      live.add([1]);
      await _settle();
      expect(got, [
        [1]
      ]);
      expect(marks, [false]);
      await sub.cancel();
    });

    test('a "not seeded yet" answer is re-checked, so seeding while the app is open is picked up', () async {
      var exists = false;
      var reads = 0;
      final sub = listen(SeedGate(() async {
        reads++;
        return exists;
      }));
      await _settle();
      expect(got, [
        [0]
      ]); // the bundled seed first
      live.add([7]); // a non-empty collection does NOT vouch for a known-unseeded database
      await _settle();
      expect(got, [
        [0]
      ]);
      exists = true; // seeding finished (settings/church written last)
      live.add([8]);
      await _settle();
      expect(got.last, [8]);
      expect(marks, [true, false]);
      expect(reads, 3);
      await sub.cancel();
    });

    test('a timed-out check keeps the live subscription and trusts real data', () async {
      final sub = listen(SeedGate(() async => throw TimeoutException('slow')));
      await _settle();
      expect(got, [
        [0]
      ]);
      live.add([]); // empty cache snapshot proves nothing
      await _settle();
      expect(got, [
        [0]
      ]);
      live.add([5]);
      await _settle();
      expect(got.last, [5]);
      expect(marks, [true, false]);
      await sub.cancel();
    });

    test('one stream confirming its own data does not vouch for another stream', () async {
      final gate = SeedGate(() async => throw TimeoutException('slow'));
      final other = StreamController<List<int>>();
      final otherGot = <List<int>>[];
      final a = listen(gate);
      final b = guardSeeded<List<int>>(
        gate: gate,
        live: () => other.stream,
        fallback: const [0],
        confirms: (v) => v.isNotEmpty,
        onSeed: (_) {},
      ).listen(otherGot.add);
      await _settle();
      live.add([5]);
      await _settle();
      other.add([]); // a collection the seed has not written yet
      await _settle();
      expect(otherGot, [
        [0]
      ]);
      await a.cancel();
      await b.cancel();
      await other.close();
    });

    test('a stream error falls back to the seed', () async {
      final sub = listen(SeedGate(() async => true));
      await _settle();
      live.add([1]);
      await _settle();
      live.addError(StateError('permission-denied'));
      await _settle();
      expect(got, [
        [1],
        [0]
      ]);
      expect(marks, [false, true]);
      await sub.cancel();
    });

    test('cancelling a stream that is on the seed clears its fallback mark', () async {
      final sub = listen(SeedGate(() async => false));
      await _settle();
      expect(marks, [true]);
      await sub.cancel();
      expect(marks, [true, false]);
    });
  });
}
