import 'dart:async';
import '../../data/admin_repository.dart';
import '../../data/error_reporting.dart';
import '../../data/media_repository.dart';
import '../../domain/media.dart';
import '../../domain/models.dart';
import 'admin_schema.dart';

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
  Set<String>? purging,
}) async {
  final now = (clock?.call() ?? DateTime.now()).toUtc();
  for (final d in List<AdminDoc>.from(docs)) {
    if (isLocalPending?.call(d.id) == true) continue;
    if (!isExpiredSoftDelete(d.data, now)) continue;
    if (purging != null && !purging.add(d.id)) continue;
    try {
      await repo.delete(def.name, d.id);
      await removeOrphanedDocMedia(repo.media, d.data);
    } catch (e, st) {
      ErrorReporting.capture(e, st, section: 'admin.purge');
    } finally {
      purging?.remove(d.id);
    }
  }
}
