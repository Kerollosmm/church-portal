// The Sentry JS SDK (loaded by sentry_flutter on web) reports window errors
// on its own, past the Dart `beforeSend`: give it the same admin switch and
// privacy rules (ADR-034). No-op off the web.
export 'sentry_js_gate_stub.dart' if (dart.library.js_interop) 'sentry_js_gate_web.dart';
