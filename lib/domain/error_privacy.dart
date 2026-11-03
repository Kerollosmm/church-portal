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
    'blocked',
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
