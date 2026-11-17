import 'package:flutter/foundation.dart';

typedef DiscardHandler = Future<bool> Function();

final List<VoidCallback> _stubFlushCallbacks = [];
final List<DiscardHandler> _handlers = [];
int _dirtyCount = 0;
bool _handlingPop = false;

void registerDirtyToken() {
  _dirtyCount++;
}

void unregisterDirtyToken() {
  if (_dirtyCount > 0) _dirtyCount--;
}

void registerDiscardHandler(DiscardHandler handler) {
  _handlers.add(handler);
}

void unregisterDiscardHandler(DiscardHandler handler) {
  _handlers.remove(handler);
}

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

Future<bool> debugSimulatePopState() async {
  if (_dirtyCount <= 0 || _handlers.isEmpty || _handlingPop) return false;
  _handlingPop = true;
  try {
    final top = _handlers.last;
    final discard = await top();
    return discard;
  } finally {
    _handlingPop = false;
  }
}
