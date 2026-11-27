import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get isOnline {
  try {
    return web.window.navigator.onLine;
  } catch (_) {
    return true;
  }
}

Future<void> initConnectivityEnv() async {}

Future<bool> checkOnline() async => isOnline;

Stream<bool> getOnOnlineChanged() {
  late final StreamController<bool> controller;
  JSFunction? onOnlineJs;
  JSFunction? onOfflineJs;

  controller = StreamController<bool>.broadcast(
    onListen: () {
      try {
        onOnlineJs = ((web.Event _) {
          if (!controller.isClosed) controller.add(isOnline);
        }).toJS;
        onOfflineJs = ((web.Event _) {
          if (!controller.isClosed) controller.add(isOnline);
        }).toJS;
        web.window.addEventListener('online', onOnlineJs!);
        web.window.addEventListener('offline', onOfflineJs!);
      } catch (_) {}
    },
    onCancel: () {
      try {
        if (onOnlineJs != null) {
          web.window.removeEventListener('online', onOnlineJs!);
        }
        if (onOfflineJs != null) {
          web.window.removeEventListener('offline', onOfflineJs!);
        }
      } catch (_) {}
      onOnlineJs = null;
      onOfflineJs = null;
    },
  );

  return controller.stream;
}
