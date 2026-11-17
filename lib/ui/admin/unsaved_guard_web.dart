import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef DiscardHandler = Future<bool> Function();

int _dirtyCount = 0;
final List<VoidCallback> _flushCallbacks = [];
final List<DiscardHandler> _discardHandlers = [];
bool _beforeUnloadAttached = false;
bool _popstateAttached = false;
JSFunction? _beforeUnloadJsListener;
JSFunction? _popstateJsListener;

bool _ignoringInternalPop = false;
bool _handlingPop = false;

bool _isSentinelOnTop() {
  try {
    final state = web.window.history.state;
    if (state == null) return false;
    if (state.isA<JSObject>()) {
      final obj = state as JSObject;
      final val = obj['_unsavedGuard'];
      return val != null && val.isA<JSBoolean>() && (val as JSBoolean).toDart;
    }
  } catch (_) {}
  return false;
}

void _pushSentinel() {
  try {
    final stateObj = JSObject();
    stateObj['_unsavedGuard'] = true.toJS;
    web.window.history.pushState(stateObj, '', web.window.location.href);
  } catch (_) {}
}

void _ensureListeners() {
  if (!_beforeUnloadAttached) {
    _beforeUnloadAttached = true;
    _beforeUnloadJsListener = ((web.Event event) {
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
    web.window.addEventListener('beforeunload', _beforeUnloadJsListener);
  }

  if (!_popstateAttached) {
    _popstateAttached = true;
    _popstateJsListener = ((web.Event event) {
      if (_ignoringInternalPop) {
        _ignoringInternalPop = false;
        event.stopImmediatePropagation();
        return;
      }
      if (_dirtyCount <= 0 || _discardHandlers.isEmpty) return;

      event.stopImmediatePropagation();
      if (_handlingPop) return;

      _triggerPopGuard();
    }).toJS;
    web.window.addEventListener('popstate', _popstateJsListener, true.toJS);
  }
}

Future<bool> _triggerPopGuard() async {
  if (_discardHandlers.isEmpty || _handlingPop) return false;
  _handlingPop = true;
  try {
    final handler = _discardHandlers.last;
    final discard = await handler();
    if (!discard) {
      _pushSentinel();
    }
    return discard;
  } finally {
    _handlingPop = false;
  }
}

void registerDirtyToken() {
  final wasZero = _dirtyCount == 0;
  _dirtyCount++;
  _ensureListeners();
  if (wasZero) {
    _pushSentinel();
  }
}

void unregisterDirtyToken() {
  if (_dirtyCount > 0) {
    _dirtyCount--;
    if (_dirtyCount == 0) {
      if (_isSentinelOnTop()) {
        _ignoringInternalPop = true;
        web.window.history.back();
      }
    }
  }
}

void registerDiscardHandler(DiscardHandler handler) {
  _discardHandlers.add(handler);
}

void unregisterDiscardHandler(DiscardHandler handler) {
  _discardHandlers.remove(handler);
}

VoidCallback addBeforeUnloadFlush(VoidCallback callback) {
  _flushCallbacks.add(callback);
  _ensureListeners();
  return () => _flushCallbacks.remove(callback);
}

void debugTriggerBeforeUnload() {
  for (final cb in List<VoidCallback>.of(_flushCallbacks)) {
    try {
      cb();
    } catch (_) {}
  }
}

Future<bool> debugSimulatePopState() async {
  if (_dirtyCount <= 0 || _discardHandlers.isEmpty || _handlingPop) return false;
  return _triggerPopGuard();
}
