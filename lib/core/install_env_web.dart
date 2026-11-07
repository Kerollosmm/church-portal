import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

String getUserAgent() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}

String getPlatform() {
  try {
    return web.window.navigator.platform;
  } catch (_) {
    return '';
  }
}

int getMaxTouchPoints() {
  try {
    return web.window.navigator.maxTouchPoints;
  } catch (_) {
    return 0;
  }
}

bool getIsStandalone() {
  try {
    final standaloneMedia = web.window.matchMedia('(display-mode: standalone)').matches;
    final minimalUiMedia = web.window.matchMedia('(display-mode: minimal-ui)').matches;

    var navStandalone = false;
    final nav = globalContext['navigator'] as JSObject?;
    if (nav != null && nav.has('standalone')) {
      final val = nav['standalone'];
      if (val != null && val.isA<JSBoolean>()) {
        navStandalone = (val as JSBoolean).toDart;
      }
    }
    return standaloneMedia || minimalUiMedia || navStandalone;
  } catch (_) {
    return false;
  }
}

bool getHasDeferredPrompt() {
  try {
    return globalContext['__installPrompt'] != null;
  } catch (_) {
    return false;
  }
}

bool getInstalledEventReceived() {
  try {
    return web.window.sessionStorage.getItem('church_portal_installed') == '1';
  } catch (_) {
    return false;
  }
}

void clearInstalledSessionFlag() {
  try {
    web.window.sessionStorage.removeItem('church_portal_installed');
  } catch (_) {}
}

Future<bool> promptInstall() async {
  try {
    final prompt = globalContext['__installPrompt'] as JSObject?;
    if (prompt == null) return false;
    globalContext['__installPrompt'] = null;
    if (prompt.has('prompt')) {
      prompt.callMethod('prompt'.toJS);
    }
    return true;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic>? readJson(String key) {
  try {
    final raw = web.window.localStorage.getItem(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Throws when the browser refuses the write (private mode, quota, storage
/// disabled), so callers such as [ReminderStore] can report it.
void writeJson(String key, Map<String, dynamic> data) {
  try {
    web.window.localStorage.setItem(key, jsonEncode(data));
  } catch (e) {
    throw StateError('localStorage write refused: $e');
  }
}

void removeStorageKey(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}

/// Window listeners registered after index.html's own capture handlers, so
/// `__installPrompt` / the session flag are already set when [onChange] runs.
void Function() listenInstallChanges(void Function() onChange) {
  try {
    final handler = ((web.Event _) => onChange()).toJS;
    web.window.addEventListener('beforeinstallprompt', handler);
    web.window.addEventListener('appinstalled', handler);
    return () {
      web.window.removeEventListener('beforeinstallprompt', handler);
      web.window.removeEventListener('appinstalled', handler);
    };
  } catch (_) {
    return () {};
  }
}
