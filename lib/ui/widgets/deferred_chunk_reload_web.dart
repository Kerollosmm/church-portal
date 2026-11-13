import 'package:web/web.dart' as web;

import 'deferred_chunk_policy.dart';

/// One full navigation so the browser revalidates `main.dart.js` and its
/// part files together. The flag blocks a reload loop; the retry card shows
/// if the next load fails too.
bool reloadStaleDeferredChunk(Object error) {
  try {
    final storage = web.window.sessionStorage;
    if (!shouldReloadDeferredChunk(error, storage.getItem(deferredReloadFlag))) return false;
    storage.setItem(deferredReloadFlag, '1');
    web.window.location.reload();
    return true;
  } catch (_) {
    return false;
  }
}
