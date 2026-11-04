import 'dart:async';

import 'package:church_portal/data/content_repository.dart';
import 'package:fake_async/fake_async.dart';
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

  group('footer "bundled content" note: proof of seeding arriving later (ADR-038)', () {
    // Live repro (4 Nov 2026): the one-shot settings/church check timed out
    // (8 s) / failed "client is offline" on a slow cold start while the
    // listeners went on to deliver server data. A missing optional doc (code
    // defaults, e.g. settings/contact) or an empty collection gets exactly
    // one snapshot, which cannot vouch for itself, so it stayed on the seed
    // forever and the footer kept saying "Showing bundled content".
    late StreamController<List<int>> live;
    late List<bool> marks;
    late List<List<int>> got;

    setUp(() {
      live = StreamController<List<int>>();
      marks = [];
      got = [];
    });
    // Not awaited: some tests never listen to [live] (close() would wait).
    tearDown(() => unawaited(live.close()));

    StreamSubscription<List<int>> listen(SeedGate gate, {Duration? fallbackDelay}) => guardSeeded<List<int>>(
          gate: gate,
          live: () => live.stream,
          fallback: const [0],
          confirms: (v) => v.isNotEmpty,
          fallbackDelay: fallbackDelay,
          onSeed: marks.add,
        ).listen(got.add);

    test('an empty collection held on the seed is released once settings/church is seen', () async {
      final gate = SeedGate(() async => throw TimeoutException('slow cold start'));
      final sub = listen(gate);
      await _settle();
      live.add([]); // the collection is legitimately empty: its only snapshot
      await _settle();
      expect(got, [
        [0]
      ]);
      expect(marks.last, isTrue); // the note would show
      gate.markSeeded(); // the settings/church listener saw the marker
      await _settle();
      expect(got.last, isEmpty); // the real (empty) list replaces the bundled copy
      expect(marks, [true, false]);
      live.add([3]); // and later values pass straight through
      await _settle();
      expect(got.last, [3]);
      await sub.cancel();
    });

    test('a missing optional doc (value equal to the fallback) is released the same way', () async {
      final gate = SeedGate(() async => throw StateError('client is offline'));
      final values = <String>[];
      final m = <bool>[];
      final docs = StreamController<String>();
      const defaults = 'code defaults';
      final sub = guardSeeded<String>(
        gate: gate,
        live: () => docs.stream,
        fallback: defaults,
        confirms: (v) => !identical(v, defaults),
        onSeed: m.add,
      ).listen(values.add);
      await _settle();
      docs.add(defaults); // settings/contact does not exist: the code defaults
      await _settle();
      expect(m, [true]);
      gate.markSeeded();
      await _settle();
      expect(values, [defaults, defaults]);
      expect(m, [true, false]);
      await sub.cancel();
      unawaited(docs.close());
    });

    test('a proof arriving while a re-check is still in flight wins over its timeout', () async {
      var calls = 0;
      final slow = Completer<bool>();
      final gate = SeedGate(() {
        calls++;
        if (calls == 1) return Future<bool>.error(TimeoutException('first'));
        return slow.future; // the re-check hangs
      });
      final sub = listen(gate);
      await _settle();
      live.add([]);
      await _settle(); // re-check in flight
      gate.markSeeded();
      await _settle();
      slow.completeError(TimeoutException('second'));
      await _settle();
      await _settle();
      expect(got.last, isEmpty);
      expect(marks.last, isFalse);
      expect(gate.isSeeded, isTrue);
      await sub.cancel();
    });

    test('a negative read that lands after the proof does not undo it', () async {
      final read = Completer<bool>();
      final gate = SeedGate(() => read.future);
      final pending = gate.check();
      gate.markSeeded();
      read.complete(false);
      expect(await pending, isTrue);
      expect(gate.markerAbsent, isFalse);
      expect(await gate.check(), isTrue);
    });

    test('a known-unseeded database switches to live data once seeding writes the marker', () async {
      final gate = SeedGate(() async => false);
      final sub = listen(gate);
      await _settle();
      live.add([4]); // non-empty, but the marker is absent: still the seed
      await _settle();
      expect(got, [
        [0]
      ]);
      gate.markSeeded();
      await _settle();
      expect(got.last, [4]);
      expect(marks, [true, false]);
      await sub.cancel();
    });

    test('custom content: the proof cancels the delayed empty fallback', () {
      fakeAsync((async) {
        final gate = SeedGate(() async => throw TimeoutException('slow'));
        final sub = listen(gate, fallbackDelay: const Duration(seconds: 13));
        async.flushMicrotasks();
        gate.markSeeded();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        expect(got, isEmpty); // never "not available" while seeded
        expect(marks, isEmpty);
        live.add([]);
        async.flushMicrotasks();
        expect(got, [<int>[]]);
        expect(marks, [false]);
        sub.cancel();
      });
    });

    test('the live query starts before the seeding check answers (live check)', () {
      fakeAsync((async) {
        final read = Completer<bool>();
        var listened = false;
        final ctl = StreamController<List<int>>(onListen: () => listened = true);
        final sub = guardSeeded<List<int>>(
          gate: SeedGate(() => read.future),
          live: () => ctl.stream,
          fallback: const [0],
          onSeed: marks.add,
        ).listen(got.add);
        async.flushMicrotasks();
        expect(listened, isTrue); // subscribed while the check is still pending
        ctl.add([5]);
        async.flushMicrotasks();
        expect(got, isEmpty); // held until the gate answers
        read.complete(true);
        async.flushMicrotasks();
        expect(got, [
          [5],
        ]);
        expect(marks, [false]);
        sub.cancel();
        unawaited(ctl.close());
      });
    });

    test('custom content: "not available" comes fallbackDelay after opening, not after check + delay', () {
      fakeAsync((async) {
        // The check times out at 8 s (cold start); before, the 13 s delay
        // started only then (21 s of skeletons).
        final gate = SeedGate(
          () => Future<bool>.delayed(const Duration(seconds: 8), () => throw TimeoutException('8 s')),
        );
        final sub = listen(gate, fallbackDelay: const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 12));
        expect(got, isEmpty);
        async.elapse(const Duration(seconds: 1, milliseconds: 10));
        expect(got, [
          [0],
        ]);
        sub.cancel();
      });
    });

    test('custom content: a check slower than the delay settles as soon as it fails', () {
      fakeAsync((async) {
        final gate = SeedGate(
          () => Future<bool>.delayed(const Duration(seconds: 15), () => throw TimeoutException('slow')),
        );
        final sub = listen(gate, fallbackDelay: const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 14));
        expect(got, isEmpty); // the gate has not answered: never decide early
        async.elapse(const Duration(seconds: 1, milliseconds: 10));
        expect(got, [
          [0],
        ]);
        sub.cancel();
      });
    });

    test('custom content on a seeded database never falls back to the empty list', () {
      fakeAsync((async) {
        final sub = listen(SeedGate(() async => true), fallbackDelay: const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 30));
        expect(got, isEmpty); // waits for the live (settleFirst) value
        live.add([]);
        async.flushMicrotasks();
        expect(got, [<int>[]]);
        sub.cancel();
      });
    });

    test('with a working check nothing is ever marked as bundled', () async {
      final sub = listen(SeedGate(() async => true));
      await _settle();
      live.add([]);
      await _settle();
      expect(marks, [false]);
      await sub.cancel();
    });
  });
}
