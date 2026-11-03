import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../domain/error_privacy.dart';

/// Sets `beforeSend` on the Sentry JS client: drops JS-side events while the
/// admin switch is off, and removes the user, cookies, headers other than the
/// User-Agent, and the URL query string. Events captured in Dart travel as
/// envelopes and are filtered by the Dart `beforeSend` instead.
void installSentryJsGate(bool Function() allowed) {
  try {
    final sentry = globalContext['Sentry'];
    if (sentry == null || !sentry.isA<JSObject>()) return;
    final client = (sentry as JSObject).callMethod<JSAny?>('getClient'.toJS);
    if (client == null || !client.isA<JSObject>()) return;
    final options = (client as JSObject).callMethod<JSAny?>('getOptions'.toJS);
    if (options == null || !options.isA<JSObject>()) return;
    JSObject? beforeSend(JSObject event, JSAny? hint) {
      if (!allowed()) return null;
      try {
        event.delete('user'.toJS);
        event.delete('extra'.toJS);
        final req = event['request'];
        if (req != null && req.isA<JSObject>()) {
          final r = req as JSObject;
          final url = r['url'];
          if (url != null && url.isA<JSString>()) r['url'] = stripQuery((url as JSString).toDart).toJS;
          r.delete('query_string'.toJS);
          r.delete('cookies'.toJS);
          r.delete('data'.toJS);
          final headers = r['headers'];
          if (headers != null && headers.isA<JSObject>()) {
            final ua = (headers as JSObject)['User-Agent'];
            final kept = JSObject();
            if (ua != null) kept['User-Agent'] = ua;
            r['headers'] = kept;
          }
        }
      } catch (_) {
        return null; // could not scrub: do not send
      }
      return event;
    }

    (options as JSObject)['beforeSend'] = beforeSend.toJS;
  } catch (e) {
    debugPrint('Sentry JS gate not installed: $e');
  }
}
