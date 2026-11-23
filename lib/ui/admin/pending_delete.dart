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

  /// Suspends timer expiry for [ids] with per-hold identity tokens so overlapping
  /// batch deletions or stale renewals from undone items cannot touch a replacement entry.
  Map<String, Object> holdAll(Iterable<String> ids) {
    final tokens = <String, Object>{};
    for (final id in ids) {
      final item = _pending[id];
      if (item == null) continue;
      if (item.activeHolds.isEmpty) {
        item.expiredWhileHeld = false;
        item.extendOnRelease = false;
      }
      final token = Object();
      item.activeHolds.add(token);
      tokens[id] = token;
    }
    return tokens;
  }

  /// Releases one hold on [id] matching [token]: ignores stale tokens from undone/replaced
  /// entries, and only when the last overlapping hold releases does it extend or commit.
  Future<void> releaseHold(String id, {required bool extend, Object? token}) async {
    final item = _pending[id];
    if (item == null) return;
    if (token != null) {
      if (!item.activeHolds.remove(token)) return;
    } else if (item.activeHolds.isNotEmpty) {
      item.activeHolds.remove(item.activeHolds.last);
    } else {
      return;
    }
    if (extend) item.extendOnRelease = true;
    if (item.activeHolds.isNotEmpty) return;
    final shouldExtend = item.extendOnRelease;
    final expired = item.expiredWhileHeld;
    item.extendOnRelease = false;
    item.expiredWhileHeld = false;
    if (shouldExtend) {
      _resetTimer(id, item);
    } else if (expired) {
      await _commitItem(id);
    }
  }

  /// Resets the grace-window timer on every currently pending deletion (or [ids])
  /// so a combined batch undo SnackBar stays truthful for the full [window].
  void extendAll([Iterable<String>? ids]) {
    final targets = ids?.toSet();
    for (final entry in _pending.entries.toList()) {
      if (targets != null && !targets.contains(entry.key)) continue;
      _resetTimer(entry.key, entry.value);
    }
  }

  void _resetTimer(String id, _PendingCommit item) {
    item.activeHolds.clear();
    item.extendOnRelease = false;
    item.expiredWhileHeld = false;
    item.timer.cancel();
    item.timer = Timer(window, () => _onTimerFired(id, item));
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

  Future<void> flush() async {
    final items = List<_PendingCommit>.from(_pending.values);
    _pending.clear();
    for (final item in items) {
      await item.execute();
    }
  }

  void dispose() {
    for (final item in _pending.values) {
      item.cancel();
    }
    _pending.clear();
  }
}

class _PendingCommit {
  Timer timer;
  final Future<void> Function() commit;
  final List<Object> activeHolds = [];
  bool extendOnRelease = false;
  bool expiredWhileHeld = false;
  bool _executed = false;

  int get holdCount => activeHolds.length;

  _PendingCommit(this.timer, this.commit);

  void cancel() {
    timer.cancel();
  }

  Future<void> execute() async {
    if (_executed) return;
    _executed = true;
    timer.cancel();
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
