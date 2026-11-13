import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../domain/push.dart';

Future<void> initPushStore() async {}

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

Future<String> refreshPermission() async => getPermission();

Future<bool> openSystemSettings() async => false;

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
    try {
      web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          icon: icon ?? '/icons/Icon-192.png',
        ),
      );
      return true;
    } catch (_) {
      return await showSwTestNotification(title: title, body: body, link: link);
    }
  } catch (_) {
    return false;
  }
}

JSObject _jsObjFromMap(Map<String, dynamic> map) {
  final jsonStr = jsonEncode(map);
  final jsonGlobal = globalContext['JSON'] as JSObject;
  return jsonGlobal.callMethod('parse'.toJS, jsonStr.toJS) as JSObject;
}

Future<JSObject?> _ensureChurchPush() async {
  try {
    final existing = globalContext['churchPush'] as JSObject?;
    if (existing != null) return existing;

    final doc = web.document;
    final existingScript = doc.querySelector('script[src="/push_client.js"]');
    if (existingScript == null) {
      final script = doc.createElement('script') as web.HTMLScriptElement;
      script.src = '/push_client.js';
      script.type = 'module';
      doc.head?.appendChild(script);
    }

    for (var i = 0; i < 50; i++) {
      final cp = globalContext['churchPush'] as JSObject?;
      if (cp != null) return cp;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  } catch (_) {}
  return globalContext['churchPush'] as JSObject?;
}

Future<String?> enableAndGetToken({
  required String vapidKey,
  required Map<String, dynamic> firebaseConfig,
}) async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return null;
    final args = _jsObjFromMap({
      'vapidKey': vapidKey,
      'firebaseConfig': firebaseConfig,
    });
    final promise = churchPush.callMethod('enable'.toJS, args) as JSPromise?;
    if (promise == null) return null;
    final jsResult = await promise.toDart;
    if (jsResult == null) return null;
    return jsResult.dartify() as String?;
  } catch (_) {
    return null;
  }
}

Future<String?> getWebToken({
  required String vapidKey,
  required Map<String, dynamic> firebaseConfig,
}) async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return null;
    final args = _jsObjFromMap({
      'vapidKey': vapidKey,
      'firebaseConfig': firebaseConfig,
    });
    final promise = churchPush.callMethod('getToken'.toJS, args) as JSPromise?;
    if (promise == null) return null;
    final jsResult = await promise.toDart;
    if (jsResult == null) return null;
    return jsResult.dartify() as String?;
  } catch (_) {
    return null;
  }
}

Future<bool> deleteWebToken({
  required Map<String, dynamic> firebaseConfig,
}) async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return false;
    final args = _jsObjFromMap({
      'firebaseConfig': firebaseConfig,
    });
    final promise = churchPush.callMethod('deleteToken'.toJS, args) as JSPromise?;
    if (promise == null) return false;
    final jsResult = await promise.toDart;
    return jsResult?.dartify() == true;
  } catch (_) {
    return false;
  }
}

Future<bool> showSwTestNotification({
  String? title,
  String? body,
  String? link,
}) async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return false;
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (body != null) map['body'] = body;
    if (link != null) map['link'] = link;
    final args = _jsObjFromMap(map);
    final promise = churchPush.callMethod('test'.toJS, args) as JSPromise?;
    if (promise == null) return false;
    final jsResult = await promise.toDart;
    return jsResult?.dartify() == true;
  } catch (_) {
    return false;
  }
}

Future<List<WebInboxItem>> readInbox() async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return const [];
    final promise = churchPush.callMethod('inbox'.toJS) as JSPromise?;
    if (promise == null) return const [];
    final jsResult = await promise.toDart;
    final dartVal = jsResult?.dartify();
    if (dartVal is List) {
      return dartVal
          .whereType<Map>()
          .map((m) => WebInboxItem.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false);
    }
    return const [];
  } catch (_) {
    return const [];
  }
}

Future<bool> clearInbox() async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return false;
    final promise = churchPush.callMethod('clearInbox'.toJS) as JSPromise?;
    if (promise == null) return false;
    final jsResult = await promise.toDart;
    return jsResult?.dartify() == true;
  } catch (_) {
    return false;
  }
}

Future<bool> syncQuietHours({
  required bool enabled,
  required String start,
  required String end,
  bool remindersRespectQuietHours = true,
}) async {
  try {
    final churchPush = await _ensureChurchPush();
    if (churchPush == null) return false;
    final args = _jsObjFromMap({
      'enabled': enabled,
      'start': start,
      'end': end,
      'remindersRespectQuietHours': remindersRespectQuietHours,
    });
    final promise = churchPush.callMethod('setQuiet'.toJS, args) as JSPromise?;
    if (promise == null) return false;
    final jsResult = await promise.toDart;
    return jsResult?.dartify() == true;
  } catch (_) {
    return false;
  }
}

final _deepLinksController = StreamController<String>.broadcast();
final _inboxEventsController = StreamController<WebInboxItem>.broadcast();
bool _listening = false;

void _ensureMessageListener() {
  if (_listening) return;
  _listening = true;

  void handleEvent(web.MessageEvent e) {
    try {
      final data = e.data.dartify();
      if (data is Map) {
        final type = data['type'] as String?;
        if (type == 'open') {
          final link = data['link'] as String?;
          if (link != null && link.isNotEmpty) {
            _deepLinksController.add(link);
          }
        } else if (type == 'received') {
          _inboxEventsController.add(
            WebInboxItem.fromJson(Map<String, dynamic>.from(data)),
          );
        }
      }
    } catch (_) {}
  }

  web.window.addEventListener('message', handleEvent.toJS);
  try {
    web.window.navigator.serviceWorker.addEventListener('message', handleEvent.toJS);
  } catch (_) {}
}

Stream<String> getDeepLinks() {
  _ensureMessageListener();
  return _deepLinksController.stream;
}

Stream<WebInboxItem> getInboxEvents() {
  _ensureMessageListener();
  return _inboxEventsController.stream;
}

String? readStorage(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeStorage(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}
