import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool getIsSupported() {
  try {
    final hasNotification = globalContext.has('Notification');
    final nav = globalContext['navigator'] as JSObject?;
    final hasSw = nav != null && nav.has('serviceWorker');
    final hasPush = globalContext.has('PushManager');
    return hasNotification && hasSw && hasPush;
  } catch (_) {
    return false;
  }
}

String getPermission() {
  try {
    if (!globalContext.has('Notification')) return 'denied';
    return web.Notification.permission;
  } catch (_) {
    return 'denied';
  }
}

Future<String> requestPermission() async {
  try {
    if (!globalContext.has('Notification')) return 'denied';
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart;
  } catch (_) {
    return 'denied';
  }
}

Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) async {
  try {
    if (!globalContext.has('Notification')) return false;
    if (web.Notification.permission != 'granted') {
      final perm = await web.Notification.requestPermission().toDart;
      if (perm.toDart != 'granted') return false;
    }
    web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        icon: icon ?? '/icons/Icon-192.png',
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}

