import 'dart:async';
import 'package:flutter/foundation.dart';
import 'unsaved_guard.dart';

/// Buffers destructive deletions for a reversible grace window (default 10 s).
///
/// While deletions are pending, registers with the browser beforeunload hook so
/// closing the tab flushes pending operations to the backend instead of losing them.
class PendingDelete {
  final Duration window;

  PendingDelete({this.window = const Duration(seconds: 10)});

  final Map<String, _PendingCommit> _pending = {};
  VoidCallback? _unregisterBeforeUnload;

  bool get hasPending => _pending.isNotEmpty;
  Set<String> get pendingIds => _pending.keys.toSet();

  void schedule(String id, Future<void> Function() commit) {
    _pending[id]?.cancel();
    late final _PendingCommit item;
    final timer = Timer(window, () async {
      await _commitItem(id);
    });
    item = _PendingCommit(timer, commit);
    _pending[id] = item;
    _syncBeforeUnload();
  }

  Future<void> _commitItem(String id) async {
    final item = _pending.remove(id);
    _syncBeforeUnload();
    if (item != null) {
      await item.execute();
    }
  }

  bool undo(String id) {
    final item = _pending.remove(id);
    if (item != null) {
      item.cancel();
      _syncBeforeUnload();
      return true;
    }
    return false;
  }

  Future<void> flush() async {
    final items = List<_PendingCommit>.from(_pending.values);
    _pending.clear();
    _syncBeforeUnload();
    for (final item in items) {
      await item.execute();
    }
  }

  void dispose() {
    _unregisterBeforeUnload?.call();
    _unregisterBeforeUnload = null;
    flush();
  }

  void _syncBeforeUnload() {
    if (hasPending && _unregisterBeforeUnload == null) {
      _unregisterBeforeUnload = addBeforeUnloadFlush(() {
        flush();
      });
    } else if (!hasPending && _unregisterBeforeUnload != null) {
      _unregisterBeforeUnload?.call();
      _unregisterBeforeUnload = null;
    }
  }
}

class _PendingCommit {
  final Timer timer;
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
