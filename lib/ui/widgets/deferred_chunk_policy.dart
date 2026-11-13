import 'dart:async';

/// sessionStorage key: one automatic reload per tab after a stale deferred part.
const deferredReloadFlag = 'church_portal_deferred_reloaded';

/// A [DeferredLoadException] reloads once. Any later failure, and every other
/// error, stays on the retry card.
bool shouldReloadDeferredChunk(Object error, String? flag) =>
    error is DeferredLoadException && flag != '1';
