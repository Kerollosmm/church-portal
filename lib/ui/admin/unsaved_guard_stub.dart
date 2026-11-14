import 'package:flutter/foundation.dart';

final List<VoidCallback> _stubFlushCallbacks = [];

void registerDirtyToken() {}

void unregisterDirtyToken() {}

VoidCallback addBeforeUnloadFlush(VoidCallback callback) {
  _stubFlushCallbacks.add(callback);
  return () => _stubFlushCallbacks.remove(callback);
}

void debugTriggerBeforeUnload() {
  for (final cb in List<VoidCallback>.of(_stubFlushCallbacks)) {
    try {
      cb();
    } catch (_) {}
  }
}
