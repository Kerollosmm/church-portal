// Error tracking with Sentry (ADR-034): crash / error reports from the web
// and Android apps, privacy first (PDPL) and switchable in /admin.
//
// - Off without a DSN (debug runs and tests; see resolveSentryDsn).
// - Off while the admin switch `settings/features.errorReporting` is off:
//   [ErrorReportingGate] answers every event and the SDK is closed.
// - No visitor identity, form text or URL query strings ([scrubEvent]).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';
import '../domain/error_privacy.dart';
import 'sentry_js_gate.dart';

/// Whether reports may be sent, from the admin switch. Default on until
/// `settings/features` says otherwise; events raised before the switch is
/// known wait for it (at most [patience]) so an admin who switched reporting
/// off never has the first seconds of a visit reported.
class ErrorReportingGate {
  ErrorReportingGate({this.patience = const Duration(seconds: 10)});

  final Duration patience;
  bool _enabled = true;
  bool _known = false;
  Completer<void> _ready = Completer<void>();
  final List<void Function(bool enabled)> _listeners = [];

  bool get enabled => _enabled;
  bool get known => _known;

  /// The admin switch's current value (called on every change).
  void update(bool enabled) {
    final changed = enabled != _enabled;
    _enabled = enabled;
    _known = true;
    if (!_ready.isCompleted) _ready.complete();
    if (changed) {
      for (final l in List.of(_listeners)) {
        l(enabled);
      }
    }
  }

  void addListener(void Function(bool enabled) l) => _listeners.add(l);

  /// Waits for the switch (or [patience]) and says whether to send.
  Future<bool> allowed() async {
    if (!_known) {
      try {
        await _ready.future.timeout(patience);
      } on TimeoutException {
        // Still unknown (offline, no Firebase): the default (on) applies.
      }
    }
    return _enabled;
  }

  @visibleForTesting
  void reset() {
    _enabled = true;
    _known = false;
    _ready = Completer<void>();
    _listeners.clear();
  }
}

/// Removes personal data from [event] (in place) and returns it.
SentryEvent scrubEvent(SentryEvent event) {
  event.user = null;
  event.serverName = null;
  final req = event.request;
  if (req != null) {
    final ua = req.headers.entries.where((e) => e.key.toLowerCase() == 'user-agent');
    event.request = SentryRequest(
      url: req.url == null ? null : stripQuery(req.url!),
      method: req.method,
      headers: {for (final e in ua) e.key: e.value},
    );
  }
  // ignore: deprecated_member_use
  event.extra = null;
  final tags = event.tags;
  if (tags != null) {
    event.tags = {
      for (final e in tags.entries)
        if (allowedTags.contains(e.key)) e.key: e.key == 'route' ? stripQuery(e.value) : e.value,
    };
  }
  final msg = event.message;
  if (msg != null) {
    event.message = SentryMessage(msg.formatted.isEmpty ? msg.formatted : scrubText(msg.formatted),
        template: msg.template == null ? null : scrubText(msg.template!));
  }
  for (final ex in event.exceptions ?? const <SentryException>[]) {
    final v = ex.value;
    if (v != null) ex.value = scrubText(v);
  }
  if (event.transaction != null) event.transaction = stripQuery(event.transaction!);
  if (event.culprit != null) event.culprit = scrubText(event.culprit!);
  final crumbs = event.breadcrumbs;
  if (crumbs != null) {
    event.breadcrumbs = [
      for (final b in crumbs) ?scrubBreadcrumb(b),
    ];
  }
  // Custom contexts could carry form state: keep only the SDK's own ones.
  for (final k in event.contexts.keys.toList()) {
    if (!sdkContextKeys.contains(k)) event.contexts.remove(k);
  }
  return event;
}

/// Breadcrumbs keep their category and a scrubbed message; URLs lose their
/// query string; free-text / form keys are dropped. User-interaction crumbs
/// (taps) are dropped entirely.
Breadcrumb? scrubBreadcrumb(Breadcrumb? b) {
  if (b == null) return null;
  final cat = b.category ?? '';
  if (cat.startsWith('ui.')) return null;
  if (b.message != null) b.message = scrubText(b.message!);
  final data = b.data;
  if (data != null) {
    b.data = {
      for (final e in data.entries)
        if (!isSensitiveKey(e.key))
          e.key: switch (e.value) {
            final String s when e.key == 'url' || e.key == 'from' || e.key == 'to' => stripQuery(s),
            final String s => scrubText(s),
            final num n => n,
            final bool v => v,
            _ => null,
          },
    }..removeWhere((_, v) => v == null);
  }
  return b;
}

/// Global entry point: the app reports through here, never through Sentry
/// directly, so tests and builds without a DSN need nothing.
class ErrorReporting {
  ErrorReporting._();

  static final ErrorReportingGate gate = ErrorReportingGate();

  /// Sentry was initialised (a DSN was configured and the SDK started).
  static bool get active => _active;
  static bool _active = false;

  /// The current page path (no query), set by the router.
  static String? _route;
  static String? get route => _route;
  static set route(String? path) {
    final p = path == null ? null : stripQuery(path);
    if (p == _route) return;
    _route = p;
    if (_active) {
      Sentry.configureScope((s) => s.setTag('route', p ?? ''));
    }
  }

  /// Test hook: receives every [capture] call (also without Sentry).
  @visibleForTesting
  static void Function(Object error, StackTrace? stack, Map<String, String> tags)? debugSink;

  /// Reports a caught [error]. [section] names the feature (`content:<stream>`,
  /// `assistant`, `contact`, `admin`); the current route is added.
  static void capture(Object error, StackTrace? stack, {required String section, String? source}) {
    final tags = {'section': section, 'route': ?_route, 'source': ?source};
    debugSink?.call(error, stack, tags);
    if (!_active || !gate.enabled) return;
    unawaited(Sentry.captureException(error, stackTrace: stack, withScope: (scope) {
      for (final e in tags.entries) {
        scope.setTag(e.key, e.value);
      }
    }).then((_) {}, onError: (Object _) {}));
  }

  /// The `beforeSend` of every event: waits for the admin switch, drops the
  /// event when reporting is off, scrubs it otherwise.
  static Future<SentryEvent?> beforeSend(SentryEvent event, Hint hint) async {
    if (!await gate.allowed()) return null;
    return scrubEvent(event);
  }

  /// Applies the project's settings to [o] (also used by tests).
  static void configure(SentryFlutterOptions o, {required String dsn, required String environment, String? release}) {
    o.dsn = dsn;
    o.environment = environment;
    if (release != null) o.release = release;
    // Privacy (PDPL, ADR-034).
    o.sendDefaultPii = false;
    o.attachScreenshot = false;
    o.attachViewHierarchy = false;
    o.reportViewHierarchyIdentifiers = false;
    o.enableUserInteractionBreadcrumbs = false;
    o.enableUserInteractionTracing = false;
    o.replay.sessionSampleRate = 0;
    o.replay.onErrorSampleRate = 0;
    // No release-health sessions: nothing leaves the device unless an error
    // happens (and the admin switch allows it).
    o.enableAutoSessionTracking = false;
    // Errors only: no performance tracing, no profiling.
    o.tracesSampleRate = null;
    o.enableAutoPerformanceTracing = false;
    o.maxBreadcrumbs = 40;
    // No "discarded events" reports either: with the switch off, nothing at all.
    o.sendClientReports = false;
    o.beforeSend = beforeSend;
    o.beforeBreadcrumb = (b, _) => scrubBreadcrumb(b);
  }

  /// Starts Sentry around [runApp] when a DSN is configured; otherwise just
  /// runs the app (reporting off). Never throws because of Sentry.
  static Future<void> run(FutureOr<void> Function() appRunner, {String? dsn, String? environment, String? release}) async {
    final useDsn = dsn ?? AppConfig.sentryDsn;
    if (useDsn == null || useDsn.isEmpty) {
      _active = false;
      await appRunner();
      return;
    }
    try {
      await SentryFlutter.init(
        (o) => configure(o,
            dsn: useDsn, environment: environment ?? AppConfig.sentryEnvironment, release: release ?? AppConfig.sentryRelease),
        appRunner: () async {
          _active = true;
          // The Sentry JS SDK (web) reports window errors itself; give it the
          // same switch and scrubbing.
          installSentryJsGate(gate.allowed);
          await appRunner();
        },
      );
    } catch (e) {
      debugPrint('Sentry init failed, running without error reporting: $e');
      if (!_active) await appRunner();
    }
    // Switched off in /admin: close the SDK (stops the JS / native handlers
    // too). Switching it back on takes effect at the next visit / app start.
    gate.addListener((enabled) {
      if (!enabled && _active) {
        _active = false;
        unawaited(Sentry.close());
      }
    });
  }

  /// Sends one harmless test event (admin "Send test error", owner only).
  /// Returns false when reporting is not active.
  static Future<bool> sendTestEvent() async {
    if (!_active || !gate.enabled) return false;
    await Sentry.captureException(
      StateError('Test error from /admin (ignore)'),
      stackTrace: StackTrace.current,
      withScope: (s) {
        s.setTag('section', 'admin');
        s.setTag('test', 'true');
      },
    );
    return true;
  }
}
