import 'package:web/web.dart' as web;

import 'document_lang.dart' show DocumentHeadSpec;

void setDocumentLanguage(String languageCode) {
  final root = web.document.documentElement;
  if (root != null && root.getAttribute('lang') != languageCode) root.setAttribute('lang', languageCode);
}

/// Creates, updates or removes `<link rel="canonical">` and
/// `<meta name="robots" content="noindex">` in `<head>` to match [spec].
void applyDocumentHead(DocumentHeadSpec spec) {
  final head = web.document.head;
  if (head == null) return;
  final canonical = head.querySelector('link[rel="canonical"]');
  final url = spec.canonicalUrl;
  if (url != null) {
    final link = canonical ?? (web.document.createElement('link')..setAttribute('rel', 'canonical'));
    if (link.getAttribute('href') != url) link.setAttribute('href', url);
    if (canonical == null) head.appendChild(link);
  } else {
    canonical?.remove();
  }
  final robots = head.querySelector('meta[name="robots"]');
  if (spec.noIndex) {
    if (robots == null) {
      head.appendChild(web.document.createElement('meta')
        ..setAttribute('name', 'robots')
        ..setAttribute('content', 'noindex'));
    } else if (robots.getAttribute('content') != 'noindex') {
      robots.setAttribute('content', 'noindex');
    }
  } else {
    robots?.remove();
  }
}
