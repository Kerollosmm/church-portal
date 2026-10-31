import 'document_lang_stub.dart' if (dart.library.js_interop) 'document_lang_web.dart' as impl;

/// Keeps `<html lang>` in sync with the app locale on web so screen readers
/// use the right language; no-op on other platforms.
void setDocumentLanguage(String languageCode) => impl.setDocumentLanguage(languageCode);
