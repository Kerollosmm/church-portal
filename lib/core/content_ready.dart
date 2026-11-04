import 'dart:async';

import 'content_ready_stub.dart' if (dart.library.js_interop) 'content_ready_web.dart' as impl;

/// The HTML loading screen and the page-idle moment (ADR-038).
///
/// `web/index.html` keeps its loading screen (the static hero copy) over the
/// app until [signal] says the first real settings / home data has been
/// painted, or until its own time limit; then it fades out. [whenIdle]
/// completes once that has happened and the browser is idle, so heavy
/// decoration (the hero `<video>` and CSS motion layer) starts after the
/// page is complete instead of competing with it.
class ContentReady {
  ContentReady._();

  static bool _signalled = false;
  static final Completer<void> _idle = Completer<void>();

  /// Whether [signal] has run.
  static bool get signalled => _signalled;

  /// Completes after [signal] once the browser is idle (immediately after
  /// [signal] off the web).
  static Future<void> get whenIdle {
    if (!_capArmed) {
      _capArmed = true;
      // Never wait forever: if the data never settles, decorate anyway
      // (the loading screen has its own limit too).
      impl.cap(maxWait, signal);
    }
    return _idle.future;
  }

  static bool _capArmed = false;

  /// Upper bound for [whenIdle] from its first use (web).
  static const maxWait = Duration(seconds: 12);

  /// Tells the loading screen that real content is on screen (idempotent).
  static void signal() {
    if (_signalled) return;
    _signalled = true;
    impl.dispatchContentReady();
    impl.afterIdle(() {
      if (!_idle.isCompleted) _idle.complete();
    });
  }
}
