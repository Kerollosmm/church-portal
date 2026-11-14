import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

int _dirtyCount = 0;
final List<VoidCallback> _flushCallbacks = [];
bool _listenerAttached = false;
JSFunction? _jsListener;

void _ensureListener() {
  if (_listenerAttached) return;
  _listenerAttached = true;
  _jsListener = ((web.Event event) {
    for (final cb in List<VoidCallback>.of(_flushCallbacks)) {
      try {
        cb();
      } catch (_) {}
    }
    if (_dirtyCount > 0) {
      try {
        event.preventDefault();
        (event as web.BeforeUnloadEvent).returnValue = '';
      } catch (_) {}
    }
  }).toJS;
  web.window.addEventListener('beforeunload', _jsListener);
}

void registerDirtyToken() {
  _dirtyCount++;
  _ensureListener();
}

void unregisterDirtyToken() {
  if (_dirtyCount > 0) _dirtyCount--;
}

VoidCallback addBeforeUnloadFlush(VoidCallback callback) {
  _flushCallbacks.add(callback);
  _ensureListener();
  return () => _flushCallbacks.remove(callback);
}

void debugTriggerBeforeUnload() {
  for (final cb in List<VoidCallback>.of(_flushCallbacks)) {
    try {
      cb();
    } catch (_) {}
  }
}
