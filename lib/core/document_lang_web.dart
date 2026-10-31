import 'package:web/web.dart' as web;

void setDocumentLanguage(String languageCode) {
  final root = web.document.documentElement;
  if (root != null && root.getAttribute('lang') != languageCode) root.setAttribute('lang', languageCode);
}
