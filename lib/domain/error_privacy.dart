// Privacy helpers for error reports (Sentry, ADR-034). Pure Dart: no
// Flutter / Firebase / Sentry imports, so the rules are unit-tested.
//
// A public church site under Egypt's PDPL: error reports carry no visitor
// identity (no user id, e-mail, IP, phone), no form text (contact messages,
// assistant questions) and no URL query strings.

/// The URL without its query string and fragment (`?lang=en`, tokens, …).
/// Not a URL (or empty) → returned with anything after `?` / `#` cut.
String stripQuery(String url) {
  var cut = url.length;
  final q = url.indexOf('?');
  final h = url.indexOf('#');
  if (q >= 0 && q < cut) cut = q;
  if (h >= 0 && h < cut) cut = h;
  return url.substring(0, cut);
}

final RegExp _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
// 7+ digits, optionally separated by spaces / dashes / dots, with an optional
// leading +: phone numbers (Egyptian mobiles are 11 digits) and other ids.
// Arabic-Indic digits too (٠-٩, ۰-۹).
final RegExp _longNumber = RegExp(r'\+?[0-9٠-٩۰-۹](?:[ \-.]?[0-9٠-٩۰-۹]){6,}');
final RegExp _urlWithQuery = RegExp(r'(https?://[^\s?#"]+)[?#][^\s"]*');

/// Removes personal data that can hide in free text (an exception message,
/// a log line): e-mail addresses, phone numbers / long digit runs, URL query
/// strings. Short numbers (times, counts, HTTP codes) are kept.
String scrubText(String text) => text
    .replaceAllMapped(_urlWithQuery, (m) => m.group(1)!)
    .replaceAll(_email, '[email]')
    .replaceAll(_longNumber, '[number]');

/// [text] with every occurrence of each non-trivial [secret] (a visitor's
/// question, a contact message) replaced by `[redacted]`, then [scrubText].
String redact(String text, Iterable<String> secrets) {
  var out = text;
  for (final s in secrets) {
    final t = s.trim();
    if (t.length >= 3) out = out.replaceAll(t, '[redacted]');
  }
  return scrubText(out);
}

/// Assistant failures the visitor already sees as a friendly message and
/// that say nothing about a bug: quota / rate limits, billing, safety blocks.
/// Not reported (they would only be noise).
bool isUserFacingAssistantError(Object e) {
  final t = e.toString().toLowerCase();
  const expected = [
    '429',
    'quota',
    'resource_exhausted',
    'resource exhausted',
    'rate limit',
    'too many requests',
    'billing',
    'safety',
    // Model safety / prompt blocks only (not "blocked by the client" network errors).
    'blockreason',
    'block_reason',
    'blocked due to',
    'prompt was blocked',
    'response was blocked',
    'candidate was blocked',
  ];
  return expected.any(t.contains);
}

/// Keys of form / free-text data that are never sent, wherever they appear
/// (extra, contexts, breadcrumb data). Compared lower-case.
const Set<String> sensitiveKeys = {
  'message', 'text', 'body', 'question', 'prompt', 'answer', 'name', 'phone', 'email', 'mail',
  'password', 'token', 'cookie', 'cookies', 'authorization', 'payload', 'input', 'query', 'value',
  'user', 'uid', 'ip', 'ip_address',
};

bool isSensitiveKey(String key) {
  final k = key.toLowerCase();
  return sensitiveKeys.contains(k) || k.contains('password') || k.contains('token') || k.contains('email');
}

/// The tags an error report may carry (anything else is dropped).
const Set<String> allowedTags = {'route', 'section', 'source', 'test'};

/// Sentry release name: `church-portal@<version>+<short sha>`; the SHA is
/// cut to 7 characters. Null without a SHA (the SDK then derives one from
/// the package info).
String? buildSentryRelease(String version, String sha) {
  final v = version.trim();
  final s = sha.trim();
  if (s.isEmpty) return null;
  final short = s.length > 7 ? s.substring(0, 7) : s;
  return 'church-portal@${v.isEmpty ? '0.0.0' : v}+$short';
}

/// Which Sentry DSN a build uses (ADR-034):
/// - `--dart-define=SENTRY_DSN=…` wins; an empty value switches reporting off;
/// - otherwise release builds use the project's public [fallback] DSN (a
///   GitHub repository variable could not be created from the agent's tools,
///   and a DSN is public by design);
/// - debug / profile builds and tests without the define: off (null).
String? resolveSentryDsn({required bool hasDefine, required String define, required bool release, required String fallback}) {
  if (hasDefine) return define.trim().isEmpty ? null : define.trim();
  return release && fallback.trim().isNotEmpty ? fallback.trim() : null;
}

/// `--dart-define=SENTRY_ENVIRONMENT` (CI: `production` on main, `preview`
/// on PR previews) or, without it, `production` for release builds and
/// `debug` otherwise.
String resolveSentryEnvironment({required String define, required bool release}) {
  final d = define.trim();
  if (d.isNotEmpty) return d;
  return release ? 'production' : 'debug';
}

/// A contact-form submit failure as it may be reported: the error's type and
/// its scrubbed message — never the form's fields.
class ContactSubmitFailure implements Exception {
  final String type;
  final String message;
  const ContactSubmitFailure(this.type, this.message);

  @override
  String toString() => 'ContactSubmitFailure($type): $message';
}

/// Context keys the SDKs set themselves; custom ones (form state) are dropped.
const Set<String> sdkContextKeys = {
  'device', 'os', 'app', 'browser', 'runtime', 'gpu', 'culture', 'flutter_context', 'trace', 'response',
};

/// One breadcrumb as JSON (Sentry JS shape) scrubbed like the Dart ones; null = drop.
Map<String, dynamic>? scrubBreadcrumbJson(Map<String, dynamic> b) {
  final cat = '${b['category'] ?? ''}';
  if (cat.startsWith('ui.')) return null;
  final out = Map<String, dynamic>.of(b);
  if (out['message'] is String) out['message'] = scrubText(out['message'] as String);
  final data = out['data'];
  if (data is Map) {
    out['data'] = <String, dynamic>{
      for (final e in data.entries)
        if (!isSensitiveKey('${e.key}')) '${e.key}': ?_scrubValue('${e.key}', e.value),
    };
  } else {
    out.remove('data');
  }
  return out;
}

Object? _scrubValue(String key, Object? v) => switch (v) {
      final String s when key == 'url' || key == 'from' || key == 'to' => stripQuery(s),
      final String s => scrubText(s),
      final num n => n,
      final bool b => b,
      _ => null,
    };

/// A whole Sentry event as JSON (the shape the Sentry **JS** SDK hands to its
/// `beforeSend`), scrubbed with the same rules as `scrubEvent` (ADR-034): no
/// user / server name / extra / custom contexts, request without cookies, body
/// or headers but the User-Agent, no query strings, scrubbed messages,
/// exception values and breadcrumbs, only the allowed tags.
Map<String, dynamic> scrubEventJson(Map<String, dynamic> event) {
  final e = Map<String, dynamic>.of(event)
    ..remove('user')
    ..remove('extra')
    ..remove('server_name');
  final req = e['request'];
  if (req is Map) {
    String? ua;
    final headers = req['headers'];
    if (headers is Map) {
      for (final h in headers.entries) {
        if ('${h.key}'.toLowerCase() == 'user-agent' && h.value is String) ua = h.value as String;
      }
    }
    e['request'] = <String, dynamic>{
      if (req['url'] is String) 'url': stripQuery(req['url'] as String),
      if (req['method'] is String) 'method': req['method'],
      if (ua != null) 'headers': {'User-Agent': ua},
    };
  }
  final msg = e['message'];
  if (msg is String) {
    e['message'] = scrubText(msg);
  } else if (msg is Map) {
    e['message'] = <String, dynamic>{
      for (final k in ['formatted', 'message'])
        if (msg[k] is String) k: scrubText(msg[k] as String),
    };
  }
  final ex = e['exception'];
  if (ex is Map && ex['values'] is List) {
    e['exception'] = <String, dynamic>{
      ...ex.map((k, v) => MapEntry('$k', v)),
      'values': [
        for (final v in ex['values'] as List)
          if (v is Map)
            <String, dynamic>{
              ...v.map((k, x) => MapEntry('$k', x)),
              if (v['value'] is String) 'value': scrubText(v['value'] as String),
            },
      ],
    };
  }
  List<Map<String, dynamic>> crumbs(List l) => [
        for (final b in l)
          if (b is Map) ?scrubBreadcrumbJson(b.map((k, v) => MapEntry('$k', v))),
      ];
  final bc = e['breadcrumbs'];
  if (bc is List) {
    e['breadcrumbs'] = crumbs(bc);
  } else if (bc is Map && bc['values'] is List) {
    e['breadcrumbs'] = {'values': crumbs(bc['values'] as List)};
  }
  final tags = e['tags'];
  if (tags is Map) {
    e['tags'] = <String, dynamic>{
      for (final t in tags.entries)
        if (allowedTags.contains('${t.key}')) '${t.key}': t.key == 'route' && t.value is String ? stripQuery(t.value as String) : t.value,
    };
  }
  if (e['transaction'] is String) e['transaction'] = stripQuery(e['transaction'] as String);
  if (e['culprit'] is String) e['culprit'] = scrubText(e['culprit'] as String);
  final ctx = e['contexts'];
  if (ctx is Map) {
    e['contexts'] = <String, dynamic>{
      for (final c in ctx.entries)
        if (sdkContextKeys.contains('${c.key}')) '${c.key}': c.value,
    };
  }
  return e;
}
