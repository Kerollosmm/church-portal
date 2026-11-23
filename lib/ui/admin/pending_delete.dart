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
    final timer = Timer(window, () async {
      await _commitItem(id);
    });
    item = _PendingCommit(timer, commit);
    _pending[id] = item;
  }

  /// Resets the grace-window timer on every currently pending deletion so a
  /// combined batch undo SnackBar stays truthful for the full [window].
  void extendAll() {
    for (final entry in _pending.entries.toList()) {
      final item = entry.value;
      item.timer.cancel();
      item.timer = Timer(window, () async {
        await _commitItem(entry.key);
      });
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
  bool _executed = false;

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
