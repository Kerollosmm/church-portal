import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `app-content-ready` on window (web/index.html hides its loading screen),
/// with a flag for a listener that attaches later.
void dispatchContentReady() {
  try {
    globalContext['__appContentReady'] = true.toJS;
    web.window.dispatchEvent(web.Event('app-content-ready'));
  } catch (_) {}
}

/// Runs [f] once the loading screen has had time to fade and the main thread
/// is idle (`requestIdleCallback`, capped at 2 s; Safari has none: 600 ms).
void afterIdle(void Function() f) {
  var done = false;
  void run() {
    if (done) return;
    done = true;
    f();
  }

  // The loading screen fades out over 0.5 s: start after it.
  Timer(const Duration(milliseconds: 600), () {
    try {
      if (globalContext.has('requestIdleCallback')) {
        web.window.requestIdleCallback(((web.IdleDeadline _) => run()).toJS, web.IdleRequestOptions(timeout: 2000));
        Timer(const Duration(milliseconds: 2500), run); // belt and braces
        return;
      }
    } catch (_) {}
    run();
  });
}

void cap(Duration after, void Function() f) => Timer(after, f);
