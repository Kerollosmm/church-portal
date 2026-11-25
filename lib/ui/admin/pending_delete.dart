import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../data/admin_repository.dart';
import '../../data/error_reporting.dart';
import '../../data/media_repository.dart';
import '../../domain/media.dart';
import '../../domain/models.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';

/// Buffers destructive deletions for a reversible grace window (default 10 s).
///
/// Deletion immediately marks the document in Firestore with `deletedAt`,
/// removing it from public views and sitemap. If the grace window elapses without
/// undo, the document is hard-deleted from the backend. If the admin leaves or
/// closes the screen during the window, the local timer cancels and the soft-deleted
/// document is safely purged on subsequent admin opens via [purgeExpiredSoftDeletes].
class PendingDelete {
  final Duration window;

  PendingDelete({this.window = const Duration(seconds: 10)});

  final Map<String, _PendingCommit> _pending = {};
  int _nextHoldSeq = 0;

  bool get hasPending => _pending.isNotEmpty;
  Set<String> get pendingIds => _pending.keys.toSet();
  bool isPending(String id) => _pending.containsKey(id);

  void schedule(String id, Future<void> Function() commit) {
    _pending[id]?.cancel();
    late final _PendingCommit item;
    item = _PendingCommit(
      Timer(window, () => _onTimerFired(id, item)),
      commit,
    );
    _pending[id] = item;
  }

  Future<void> _onTimerFired(String id, _PendingCommit item) async {
    if (!identical(_pending[id], item)) return;
    if (item.holdCount > 0) {
      item.expiredWhileHeld = true;
      return;
    }
    await _commitItem(id);
  }

  /// Suspends timer expiry for [ids] with per-hold identity tokens whose [window]
  /// anchor starts at hold acquisition (matching the `deletedAt` timestamp written
  /// for the batch) so successful renewals align expiry with backend `deletedAt + window`.
  Map<String, Object> holdAll(Iterable<String> ids) {
    final tokens = <String, Object>{};
    for (final id in ids) {
      final item = _pending[id];
      if (item == null) continue;
      if (item.activeHolds.isEmpty) {
        item.expiredWhileHeld = false;
        item.extendingHold?.anchorTimer.cancel();
        item.extendingHold = null;
      }
      late final _PendingHold hold;
      hold = _PendingHold(
        ++_nextHoldSeq,
        Timer(window, () => _onHoldAnchorFired(id, item, hold)),
      );
      item.activeHolds.add(hold);
      tokens[id] = hold;
    }
    return tokens;
  }

  void _onHoldAnchorFired(String id, _PendingCommit item, _PendingHold hold) {
    hold.anchorExpired = true;
    if (!identical(_pending[id], item)) return;
    // Adopted as active item timer either via item.timer or via pending extendingHold.
    if (identical(item.timer, hold.anchorTimer)) {
      if (item.activeHolds.isNotEmpty) {
        item.expiredWhileHeld = true;
      } else {
        unawaited(_commitItem(id));
      }
      return;
    }
    if (item.activeHolds.isEmpty && identical(item.extendingHold, hold)) {
      item.extendingHold = null;
      unawaited(_commitItem(id));
    }
  }

  /// Releases one hold on [id] matching [token]: ignores stale tokens from undone/replaced
  /// entries, preserves the newest extending hold across out-of-order completions, and when
  /// the last hold releases either adopts the winning hold's anchor timer (committing
  /// immediately if its anchor already elapsed) or keeps/commits the original deadline.
  Future<void> releaseHold(String id, {required bool extend, Object? token}) async {
    final item = _pending[id];
    if (item == null) return;
    _PendingHold? released;
    if (token != null) {
      final idx = item.activeHolds.indexWhere((h) => identical(h, token));
      if (idx == -1) return;
      released = item.activeHolds.removeAt(idx);
    } else if (item.activeHolds.isNotEmpty) {
      released = item.activeHolds.removeLast();
    } else {
      return;
    }
    if (extend) {
      final prev = item.extendingHold;
      if (prev == null || released.seq > prev.seq) {
        prev?.anchorTimer.cancel();
        item.extendingHold = released;
      } else {
        released.anchorTimer.cancel();
      }
    } else {
      released.anchorTimer.cancel();
    }
    if (item.activeHolds.isNotEmpty) return;
    final winner = item.extendingHold;
    final expired = item.expiredWhileHeld;
    item.expiredWhileHeld = false;
    if (winner != null) {
      item.timer.cancel();
      if (winner.anchorExpired) {
        item.extendingHold = null;
        winner.anchorTimer.cancel();
        await _commitItem(id);
      } else {
        // Adopt the anchorTimer already counting from the renewed deletedAt timestamp.
        item.timer = winner.anchorTimer;
        item.extendingHold = null;
      }
    } else if (expired) {
      await _commitItem(id);
    }
  }

  Future<void> _commitItem(String id) async {
    final item = _pending.remove(id);
    if (item != null) {
      await item.execute();
    }
  }

  bool undo(String id) {
    final item = _pending.remove(id);
    if (item != null) {
      item.cancel();
      return true;
    }
    return false;
  }

  void dispose() {
    for (final item in _pending.values) {
      item.cancel();
    }
    _pending.clear();
  }
}

class _PendingHold {
  final int seq;
  final Timer anchorTimer;
  bool anchorExpired = false;
  _PendingHold(this.seq, this.anchorTimer);
}

class _PendingCommit {
  Timer timer;
  final Future<void> Function() commit;
  final List<_PendingHold> activeHolds = [];
  _PendingHold? extendingHold;
  bool expiredWhileHeld = false;
  bool _executed = false;

  int get holdCount => activeHolds.length;

  _PendingCommit(this.timer, this.commit);

  void cancel() {
    timer.cancel();
    for (final h in activeHolds) {
      h.anchorTimer.cancel();
    }
    activeHolds.clear();
    extendingHold?.anchorTimer.cancel();
    extendingHold = null;
  }

  Future<void> execute() async {
    if (_executed) return;
    _executed = true;
    cancel();
    try {
      await commit();
    } catch (_) {}
  }
}

/// Cleans up orphaned media referenced in [data] (both cover `image` and `gallery`).
Future<void> removeOrphanedDocMedia(MediaRepository? media, Map<String, dynamic>? data) async {
  if (media == null || data == null) return;
  final orphaned = orphanedDocMediaIds(data, null);
  if (orphaned.isEmpty) return;
  await Future.wait([
    for (final mid in orphaned)
      media.delete(mid).catchError((Object _) {}),
  ]);
}

/// Purges soft-deleted documents whose grace window has expired.
///
/// Runs lazily on admin open or collection snapshot updates.
Future<void> purgeExpiredSoftDeletes(
  AdminBackend repo,
  CollectionDef def,
  Iterable<AdminDoc> docs, {
  DateTime Function()? clock,
  bool Function(String id)? isLocalPending,
  bool Function(AdminDoc doc)? shouldSkip,
  Set<String>? purging,
  bool removeMedia = true,
}) async {
  final now = (clock?.call() ?? DateTime.now()).toUtc();
  for (final d in List<AdminDoc>.from(docs)) {
    if (shouldSkip?.call(d) ?? (isLocalPending?.call(d.id) == true)) continue;
    if (!isExpiredSoftDelete(d.data, now)) continue;
    if (purging != null && !purging.add(d.id)) continue;
    try {
      await repo.delete(def.name, d.id);
      if (removeMedia) {
        await removeOrphanedDocMedia(repo.media, d.data);
      }
    } catch (e, st) {
      ErrorReporting.capture(e, st, section: 'admin.purge');
    } finally {
      purging?.remove(d.id);
    }
  }
}

/// Coordinates 10s batch soft-delete, serialized per-ID write guards, batched
/// "Undo all" SnackBar presentation, deferred non-undo SnackBars, and lazy purge
/// across admin list screens (`CollectionListScreen` and `MessagesScreen`).
class SoftDeleteUndo {
  final PendingDelete _pending;
  final bool Function() isMounted;
  final void Function() onChanged;
  final ValueChanged<bool>? onBarChanged;
  final bool removeMedia;

  final Map<String, ({AdminBackend repo, String collection, String title})> _entries = {};
  final Map<String, DateTime> _pendingDeletedAt = {};
  final Map<String, DateTime> _undoneCutoffs = {};
  final Map<String, Future<bool>> _inFlightWrites = {};
  final Map<String, int> _gen = {};
  final Set<String> _restoringIds = {};
  final Set<String> _purging = {};
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  final ValueNotifier<({int count, String title})?> _barState = ValueNotifier(null);
  Timer? _barTimer;
  final List<SnackBar> _deferredSnacks = [];

  SoftDeleteUndo({
    required this.isMounted,
    required this.onChanged,
    this.onBarChanged,
    this.removeMedia = true,
    Duration window = const Duration(seconds: 10),
  }) : _pending = PendingDelete(window: window);

  bool get hasPending => _pending.hasPending;
  bool get hasActiveBar => _controller != null;
  bool isPending(String id) => _pending.isPending(id);
  bool isRestoring(String id) => _restoringIds.contains(id);

  bool isVisible(AdminDoc d) =>
      (!isSoftDeleted(d.data) || _restoringIds.contains(d.id)) && !_pending.isPending(d.id);

  bool isProtectedFromPurge(String id, [Map<String, dynamic>? data]) {
    if (_pending.isPending(id) || _restoringIds.contains(id) || _inFlightWrites.containsKey(id)) {
      return true;
    }
    final cutoff = _undoneCutoffs[id];
    final ts = data?['deletedAt'];
    if (cutoff != null && ts is DateTime && !ts.toUtc().isAfter(cutoff)) {
      return true;
    }
    return false;
  }

  void clearTransitionState() {
    _restoringIds.clear();
    _deferredSnacks.clear();
  }

  void checkLazyPurge(
    AdminBackend repo,
    CollectionDef def,
    List<AdminDoc> docs,
  ) {
    final now = DateTime.now().toUtc();
    if (docs.any((d) => isExpiredSoftDelete(d.data, now) && !isProtectedFromPurge(d.id, d.data))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isMounted()) {
          purgeExpiredSoftDeletes(
            repo,
            def,
            docs,
            shouldSkip: (d) => isProtectedFromPurge(d.id, d.data),
            purging: _purging,
            removeMedia: removeMedia,
          );
        }
      });
    }
  }

  void showSnack(ScaffoldMessengerState? messenger, SnackBar bar, {bool deferWhileUndo = false}) {
    if (!isMounted() || messenger == null || !messenger.mounted) return;
    if (deferWhileUndo && _controller != null) {
      _deferredSnacks.add(bar);
      return;
    }
    messenger.showSnackBar(bar);
  }

  void flushDeferredSnacks(ScaffoldMessengerState? messenger) {
    if (!isMounted() || messenger == null || !messenger.mounted) return;
    if (_controller != null || _deferredSnacks.isEmpty) return;
    for (final bar in _deferredSnacks) {
      messenger.showSnackBar(bar);
    }
    _deferredSnacks.clear();
  }

  Future<bool> _enqueueWrite(String id, Future<bool> Function(Future<bool>? prev) fn) {
    final prev = _inFlightWrites[id];
    final next = fn(prev);
    _inFlightWrites[id] = next;
    unawaited(next.whenComplete(() {
      if (identical(_inFlightWrites[id], next)) {
        _inFlightWrites.remove(id);
      }
    }));
    return next;
  }

  Future<void> delete({
    required AdminBackend repo,
    required String collection,
    required AdminDoc doc,
    required String title,
    required ScaffoldMessengerState? messenger,
    required String failedMsg,
    required String undoLabel,
    required String undoAllLabel,
  }) async {
    final id = doc.id;
    if (_pending.isPending(id)) return;
    final docData = doc.data;
    final deleteNow = DateTime.now().toUtc();
    final gen = (_gen[id] ?? 0) + 1;
    _gen[id] = gen;
    _restoringIds.remove(id);
    _undoneCutoffs.remove(id);
    _pendingDeletedAt[id] = deleteNow;

    final priorPending = [
      for (final entry in _entries.entries.toList())
        if (entry.key != id && _pending.isPending(entry.key)) (id: entry.key, info: entry.value),
    ];

    // Register before awaiting Firestore so rapid consecutive deletes and immediate
    // "Undo all" taps always operate on the full batch atomically.
    _entries[id] = (repo: repo, collection: collection, title: title);
    _pending.schedule(id, () async {
      _entries.remove(id);
      _pendingDeletedAt.remove(id);
      try {
        await repo.delete(collection, id);
        if (removeMedia) {
          await removeOrphanedDocMedia(repo.media, docData);
        }
      } catch (e) {
        try {
          await repo.update(collection, id, {'deletedAt': null});
        } catch (_) {}
        if (!isMounted()) return;
        onChanged();
        _syncAfterExpiry(
          messenger,
          failedMsg: failedMsg,
          undoLabel: undoLabel,
          undoAllLabel: undoAllLabel,
        );
        showSnack(
          messenger,
          SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
          deferWhileUndo: true,
        );
        return;
      }
      if (!isMounted()) return;
      _syncAfterExpiry(
        messenger,
        failedMsg: failedMsg,
        undoLabel: undoLabel,
        undoAllLabel: undoAllLabel,
      );
    });
    onChanged();

    // Acquire holds BEFORE scheduling _barTimer so renewal anchors stay aligned at t = 10s.
    final initialToken = _pending.holdAll([id])[id];
    final priorTokens = priorPending.isEmpty
        ? const <String, Object>{}
        : _pending.holdAll([for (final p in priorPending) p.id]);

    _presentBar(
      messenger,
      title: title,
      fallbackRepo: repo,
      fallbackCollection: collection,
      failedMsg: failedMsg,
      undoLabel: undoLabel,
      undoAllLabel: undoAllLabel,
      resetTimer: true,
    );

    unawaited(_enqueueWrite(id, (priorSelfWrite) async {
      if (priorSelfWrite != null) {
        try {
          await priorSelfWrite;
        } catch (_) {}
      }
      var written = false;
      try {
        await repo.update(collection, id, {'deletedAt': deleteNow});
        written = true;
      } catch (e) {
        if (isMounted() && _gen[id] == gen) {
          _pending.undo(id);
          _entries.remove(id);
          _pendingDeletedAt.remove(id);
          onChanged();
          _syncAfterExpiry(
            messenger,
            failedMsg: failedMsg,
            undoLabel: undoLabel,
            undoAllLabel: undoAllLabel,
          );
          showSnack(
            messenger,
            SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
            deferWhileUndo: true,
          );
        }
        return false;
      }
      if (!isMounted()) return written;
      if (_gen[id] == gen) {
        await _pending.releaseHold(id, extend: true, token: initialToken);
        if (isMounted()) {
          _syncAfterExpiry(
            messenger,
            failedMsg: failedMsg,
            undoLabel: undoLabel,
            undoAllLabel: undoAllLabel,
          );
        }
      }
      return written;
    }));

    // Renew deletedAt for prior pending items, serialized per item so slower earlier
    // renewals never overwrite newer deletedAt timestamps.
    for (final p in priorPending) {
      final token = priorTokens[p.id];
      final priorGen = _gen[p.id];
      _pendingDeletedAt[p.id] = deleteNow;
      unawaited(_enqueueWrite(p.id, (prevChain) async {
        var priorWritten = true;
        if (prevChain != null) {
          try {
            priorWritten = await prevChain;
          } catch (_) {
            priorWritten = false;
          }
        }
        if (!isMounted() || _gen[p.id] != priorGen || !_pending.isPending(p.id)) {
          return priorWritten;
        }
        var renewed = false;
        try {
          await p.info.repo.update(p.info.collection, p.id, {'deletedAt': deleteNow});
          renewed = true;
        } catch (_) {}
        if (!isMounted()) return priorWritten || renewed;
        if (_gen[p.id] == priorGen) {
          await _pending.releaseHold(p.id, extend: renewed, token: token);
          if (isMounted()) {
            _syncAfterExpiry(
              messenger,
              failedMsg: failedMsg,
              undoLabel: undoLabel,
              undoAllLabel: undoAllLabel,
            );
          }
        }
        return priorWritten || renewed;
      }));
    }
  }

  void _clearActiveBarState() {
    _barTimer?.cancel();
    _barTimer = null;
    _controller = null;
    _barState.value = null;
  }

  void _syncAfterExpiry(
    ScaffoldMessengerState? messenger, {
    required String failedMsg,
    required String undoLabel,
    required String undoAllLabel,
  }) {
    if (!isMounted()) return;
    if (!_pending.hasPending) {
      final hadActiveBar = _controller != null;
      _clearActiveBarState();
      if (hadActiveBar) {
        onBarChanged?.call(false);
        if (messenger != null && messenger.mounted) {
          messenger.removeCurrentSnackBar();
        }
        onChanged();
      }
      flushDeferredSnacks(messenger);
      return;
    }
    final pendingCount = _pending.pendingIds.length;
    if (_controller == null || _barState.value?.count == pendingCount) return;
    final last = _entries.values.isNotEmpty ? _entries.values.last : null;
    if (last == null) return;
    _presentBar(
      messenger,
      title: last.title,
      fallbackRepo: last.repo,
      fallbackCollection: last.collection,
      failedMsg: failedMsg,
      undoLabel: undoLabel,
      undoAllLabel: undoAllLabel,
      resetTimer: false,
    );
  }

  void _scheduleBarTimer(
    ScaffoldMessengerState messenger, {
    required String failedMsg,
    required String undoLabel,
    required String undoAllLabel,
  }) {
    _barTimer?.cancel();
    _barTimer = Timer(_pending.window, () {
      if (!isMounted()) return;
      if (_pending.hasPending && _entries.values.isNotEmpty) {
        final last = _entries.values.last;
        _presentBar(
          messenger,
          title: last.title,
          fallbackRepo: last.repo,
          fallbackCollection: last.collection,
          failedMsg: failedMsg,
          undoLabel: undoLabel,
          undoAllLabel: undoAllLabel,
          resetTimer: true,
        );
        return;
      }
      final hadActiveBar = _controller != null;
      _clearActiveBarState();
      if (hadActiveBar) {
        onBarChanged?.call(false);
        if (messenger.mounted) messenger.removeCurrentSnackBar();
        onChanged();
      }
      flushDeferredSnacks(messenger);
    });
  }

  Future<void> _undoAll(
    ScaffoldMessengerState messenger, {
    required AdminBackend fallbackRepo,
    required String fallbackCollection,
    required String failedMsg,
  }) async {
    final hadActiveBar = _controller != null;
    _clearActiveBarState();
    if (hadActiveBar) onBarChanged?.call(false);
    if (messenger.mounted) messenger.removeCurrentSnackBar();

    final ids = _pending.pendingIds.toList();
    final undone = <({String id, AdminBackend repo, String collection, Future<bool>? inFlight, int undoGen})>[];
    for (final pid in ids) {
      if (_pending.undo(pid)) {
        final undoGen = (_gen[pid] ?? 0) + 1;
        _gen[pid] = undoGen;
        final entry = _entries.remove(pid);
        final deletedAt = _pendingDeletedAt.remove(pid);
        if (deletedAt != null) _undoneCutoffs[pid] = deletedAt;
        _restoringIds.add(pid);
        undone.add((
          id: pid,
          repo: entry?.repo ?? fallbackRepo,
          collection: entry?.collection ?? fallbackCollection,
          inFlight: _inFlightWrites[pid],
          undoGen: undoGen,
        ));
      }
    }
    if (isMounted() && (hadActiveBar || undone.isNotEmpty)) onChanged();
    // Yield past SnackBarAction._handlePressed()'s trailing hideCurrentSnackBar call
    // so flushed errors are not immediately dismissed as if they were the Undo bar.
    await Future<void>.microtask(() {});
    flushDeferredSnacks(messenger);
    if (undone.isEmpty) return;

    final restoreTasks = <Future<bool>>[];
    for (final item in undone) {
      restoreTasks.add(_enqueueWrite(item.id, (_) async {
        var hadSoftDeleteWrite = true;
        if (item.inFlight != null) {
          try {
            hadSoftDeleteWrite = await item.inFlight!;
          } catch (_) {
            hadSoftDeleteWrite = false;
          }
        }
        if (!hadSoftDeleteWrite) {
          if (_gen[item.id] == item.undoGen) _restoringIds.remove(item.id);
          if (isMounted()) onChanged();
          return false;
        }
        try {
          await item.repo.update(item.collection, item.id, {'deletedAt': null});
          return false;
        } catch (e) {
          if (isMounted()) {
            showSnack(
              messenger,
              SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
              deferWhileUndo: true,
            );
          }
          return true;
        } finally {
          if (_gen[item.id] == item.undoGen) _restoringIds.remove(item.id);
          if (isMounted()) onChanged();
        }
      }));
    }
    await Future.wait(restoreTasks);
  }

  void _presentBar(
    ScaffoldMessengerState? messenger, {
    required String title,
    required AdminBackend fallbackRepo,
    required String fallbackCollection,
    required String failedMsg,
    required String undoLabel,
    required String undoAllLabel,
    required bool resetTimer,
  }) {
    if (!isMounted() || messenger == null || !messenger.mounted) return;
    final pendingCount = _pending.pendingIds.length;
    if (pendingCount == 0) return;
    final wantMulti = pendingCount > 1;
    final prevMulti = (_barState.value?.count ?? 0) > 1;
    _barState.value = (count: pendingCount, title: title);
    onBarChanged?.call(true);

    if (_controller != null && prevMulti == wantMulti) {
      if (resetTimer) {
        _scheduleBarTimer(
          messenger,
          failedMsg: failedMsg,
          undoLabel: undoLabel,
          undoAllLabel: undoAllLabel,
        );
      }
      return;
    }

    if (resetTimer) {
      _barTimer?.cancel();
      _barTimer = null;
    }
    _controller = null;
    messenger.removeCurrentSnackBar();
    final undoController = messenger.showSnackBar(
      SnackBar(
        duration: _pending.window,
        persist: true,
        content: ValueListenableBuilder<({int count, String title})?>(
          valueListenable: _barState,
          builder: (ctx, state, _) {
            final count = state?.count ?? pendingCount;
            final lastTitle = state?.title ?? title;
            final text = count > 1
                ? ctx.tr('deletedItemMultiUndo', {'n': '$count', 'last': lastTitle})
                : ctx.tr('deletedItemUndo', {'n': lastTitle});
            return Text(text);
          },
        ),
        action: SnackBarAction(
          label: wantMulti ? undoAllLabel : undoLabel,
          onPressed: () => _undoAll(
            messenger,
            fallbackRepo: fallbackRepo,
            fallbackCollection: fallbackCollection,
            failedMsg: failedMsg,
          ),
        ),
      ),
    );
    _controller = undoController;
    onChanged();
    undoController.closed.then((_) {
      if (identical(_controller, undoController)) {
        _clearActiveBarState();
        onBarChanged?.call(false);
        onChanged();
        flushDeferredSnacks(messenger);
      }
    });
    if (resetTimer) {
      _scheduleBarTimer(
        messenger,
        failedMsg: failedMsg,
        undoLabel: undoLabel,
        undoAllLabel: undoAllLabel,
      );
    }
  }

  void dispose() {
    _barTimer?.cancel();
    _barTimer = null;
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      // Defer close() out of State.dispose()'s locked finalizeTree phase, and keep
      // _barState alive until the ~250 ms exit transition finishes so late or sibling
      // Scaffold rebuilds never observe a disposed ValueNotifier.
      Future<void>.microtask(() {
        try {
          ctrl.close();
        } catch (_) {}
      });
      unawaited(ctrl.closed.whenComplete(_barState.dispose));
    } else {
      _barState.dispose();
    }
    _deferredSnacks.clear();
    _pending.dispose();
    _entries.clear();
    _pendingDeletedAt.clear();
    _undoneCutoffs.clear();
    _inFlightWrites.clear();
    _gen.clear();
    _restoringIds.clear();
  }
}
