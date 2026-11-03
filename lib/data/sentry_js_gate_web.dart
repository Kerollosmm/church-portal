import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../domain/error_privacy.dart';

@JS('JSON.stringify')
external JSString? _stringify(JSAny? value);

@JS('JSON.parse')
external JSAny? _parse(JSString text);

/// Sets `beforeSend` on the Sentry JS client (window errors the JS SDK
/// catches itself; Dart events travel as envelopes and pass the Dart
/// `beforeSend`). It returns a Promise: the event waits for the admin switch
/// like the Dart side ([allowed]), is dropped while reporting is off, and is
/// otherwise rebuilt from its JSON with [scrubEventJson]. If anything fails,
/// the event is dropped (fail closed).
void installSentryJsGate(Future<bool> Function() allowed) {
  try {
    final sentry = globalContext['Sentry'];
    if (sentry == null || !sentry.isA<JSObject>()) return;
    final client = (sentry as JSObject).callMethod<JSAny?>('getClient'.toJS);
    if (client == null || !client.isA<JSObject>()) return;
    final options = (client as JSObject).callMethod<JSAny?>('getOptions'.toJS);
    if (options == null || !options.isA<JSObject>()) return;

    Future<JSAny?> gate(JSAny? event) async {
      try {
        if (!await allowed()) return null;
        final text = _stringify(event)?.toDart;
        if (text == null) return null;
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) return null;
        return _parse(jsonEncode(scrubEventJson(decoded)).toJS);
      } catch (_) {
        return null;
      }
    }

    JSPromise<JSAny?> beforeSend(JSAny? event, JSAny? hint) => gate(event).toJS;

    (options as JSObject)['beforeSend'] = beforeSend.toJS;
  } catch (e) {
    debugPrint('Sentry JS gate not installed: $e');
  }
}
