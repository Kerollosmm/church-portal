import 'dart:async';

/// Wraps a live stream with a bounded watchdog timer for slow/stalled listeners.
///
/// If [live] does not emit before [timeout]:
/// - Calls [readCache]. On a non-null result, emits the cached value, optionally
///   triggers [refreshServer] so sensitive control docs do not stay on stale
///   cache alone, and keeps [live] subscribed so late live updates replace it
///   automatically.
/// - On a cache miss (`readCache` returns `null` or throws): if [fallback] is
///   non-null, notifies `onFallback?.call(true)` and emits [fallback]; else if
///   [onMissError] is provided, emits its error while keeping [live] subscribed.
///
/// Whenever [live] emits data, cancels the watchdog timer, notifies
/// `onFallback?.call(false)` if currently on fallback, and forwards the value.
Stream<T> watchWithFallback<T>({
  required Stream<T> live,
  required Duration timeout,
  required Future<T?> Function() readCache,
  Future<T?> Function()? refreshServer,
  T? fallback,
  Object Function()? onMissError,
  void Function(bool onFallback)? onFallback,
}) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  Timer? timer;
  var hasLiveData = false;
  var onFallbackNow = false;
  var cancelled = false;
  var closed = false;

  void clearFallbackMark() {
    if (!onFallbackNow) return;
    onFallbackNow = false;
    onFallback?.call(false);
  }

  Future<void> triggerServerRefresh() async {
    if (refreshServer == null) return;
    try {
      final fresh = await refreshServer();
      if (fresh != null && !cancelled && !closed && !hasLiveData) {
        clearFallbackMark();
        out.add(fresh);
      }
    } catch (_) {
      // Best-effort refresh: keep cached emission and live listener active.
    }
  }

  Future<void> onTimeout() async {
    if (cancelled || closed || hasLiveData) return;
    T? cached;
    try {
      cached = await readCache();
    } catch (_) {
      cached = null;
    }
    if (cancelled || closed || hasLiveData) return;
    if (cached != null) {
      out.add(cached);
      if (refreshServer != null) {
        unawaited(triggerServerRefresh());
      }
      return;
    }
    if (fallback != null) {
      onFallbackNow = true;
      onFallback?.call(true);
      out.add(fallback);
      return;
    }
    if (onMissError != null) {
      out.addError(onMissError(), StackTrace.current);
    }
  }

  out = StreamController<T>(
    onListen: () {
      timer = Timer(timeout, onTimeout);
      sub = live.listen(
        (v) {
          timer?.cancel();
          hasLiveData = true;
          clearFallbackMark();
          if (!closed) out.add(v);
        },
        onError: (Object e, StackTrace st) {
          timer?.cancel();
          if (!closed) out.addError(e, st);
        },
        onDone: () {
          timer?.cancel();
          closed = true;
          if (!out.isClosed) out.close();
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      if (!closed) clearFallbackMark();
      await sub?.cancel();
    },
  );
  return out.stream;
}
