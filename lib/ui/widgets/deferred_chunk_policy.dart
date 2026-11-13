import 'dart:async';

/// sessionStorage key: one automatic reload per tab after a stale deferred part.
const deferredReloadFlag = 'church_portal_deferred_reloaded';

/// The stale-part failure reloads once. Dart uses [DeferredLoadException] for
/// a network drop too (`Loading … failed: …`); that one keeps the retry card
/// so an offline visit does not spend the single reload.
bool shouldReloadDeferredChunk(Object error, String? flag) =>
    flag != '1' && error is DeferredLoadException && error.toString().contains('not loaded');
