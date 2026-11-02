import 'package:flutter/foundation.dart' show visibleForTesting;

import 'document_lang_stub.dart' if (dart.library.js_interop) 'document_lang_web.dart' as impl;

/// Keeps `<html lang>` in sync with the app locale on web so screen readers
/// use the right language; no-op on other platforms.
void setDocumentLanguage(String languageCode) => impl.setDocumentLanguage(languageCode);

/// Production origin every canonical URL points at (ADR-019).
const String kCanonicalOrigin = 'https://maximos-domadios-church.web.app';

/// Canonical URL of an app [path]: `''`/`'/'` → `'$kCanonicalOrigin/'`,
/// `/subpage` → `'$kCanonicalOrigin/subpage'` (trailing `/`, query and
/// fragment stripped).
String canonicalUrlForPath(String path) {
  var p = path;
  final cut = p.indexOf(RegExp('[?#]'));
  if (cut >= 0) p = p.substring(0, cut);
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (p.isEmpty || p == '/') return '$kCanonicalOrigin/';
  return p.startsWith('/') ? '$kCanonicalOrigin$p' : '$kCanonicalOrigin/$p';
}

/// What the document `<head>` should say about the current route: a
/// `<link rel="canonical">` URL (null = no link) and whether
/// `<meta name="robots" content="noindex">` is present. Never both: Google
/// warns against pairing `noindex` with a canonical pointing elsewhere.
class DocumentHeadSpec {
  final String? canonicalUrl;
  final bool noIndex;
  const DocumentHeadSpec({required this.canonicalUrl, required this.noIndex});

  @override
  String toString() => 'DocumentHeadSpec(canonicalUrl: $canonicalUrl, noIndex: $noIndex)';
}

/// Head spec for [path]: indexable routes get their canonical URL and no
/// `noindex`; non-indexable ones (`/admin`, 404, a switched-off section) get
/// `noindex` and no canonical link.
DocumentHeadSpec routeHeadSpec({required String path, required bool indexable}) => indexable
    ? DocumentHeadSpec(canonicalUrl: canonicalUrlForPath(path), noIndex: false)
    : const DocumentHeadSpec(canonicalUrl: null, noIndex: true);

/// Records each [DocumentHeadSpec] applied (widget tests run off the web,
/// where the platform implementation is a no-op).
@visibleForTesting
void Function(DocumentHeadSpec spec)? debugOnRouteMeta;

/// Syncs `<link rel="canonical">` and `<meta name="robots" content="noindex">`
/// with the current route on web; no-op on other platforms.
void setDocumentRouteMeta({required String path, required bool indexable}) {
  final spec = routeHeadSpec(path: path, indexable: indexable);
  debugOnRouteMeta?.call(spec);
  impl.applyDocumentHead(spec);
}
