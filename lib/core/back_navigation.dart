import 'package:flutter/foundation.dart' show visibleForTesting;

import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart'
    as impl;

/// How the in-app Back arrow leaves a page.
enum BackAction {
  /// Pop the browser's own history entry (web, we came from the target page).
  historyBack,

  /// Replace the current history entry with the target (web, arrived by a
  /// deep link / another page), so browser Back never returns to this page.
  replace,

  /// Plain `context.go` (native apps have no browser history).
  go,
}

String _normalizedPath(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  return path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
}

/// Picks how Back reaches [target]. On the web, when the page the visitor
/// came from ([previous]) already is [target], the browser history entry is
/// popped (a new `go` would stack a duplicate, so browser Back would return
/// to the page they just left); otherwise the current entry is replaced.
BackAction decideBackAction({
  required bool isWeb,
  required String? previous,
  required String target,
}) {
  if (!isWeb) return BackAction.go;
  final cameFromTarget = previous != null && _normalizedPath(previous) == _normalizedPath(target);
  return cameFromTarget ? BackAction.historyBack : BackAction.replace;
}

/// Test hook replacing the real browser `history.back()`.
@visibleForTesting
void Function()? debugBrowserHistoryBack;

/// Pops one browser history entry (no-op off the web).
void browserHistoryBack() {
  final hook = debugBrowserHistoryBack;
  if (hook != null) return hook();
  impl.browserHistoryBack();
}
