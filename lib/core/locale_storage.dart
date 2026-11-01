import 'locale_storage_stub.dart' if (dart.library.js_interop) 'locale_storage_web.dart' as impl;

/// `localStorage` key holding the visitor's chosen language (`ar` / `en`).
const languageStorageKey = 'church_portal_lang';

/// Remembers the visitor's language choice across visits. Web keeps it in
/// `window.localStorage` (via the existing `package:web`, no new
/// dependency); other platforms are a no-op, so the app starts in Arabic.
abstract class LanguageStore {
  const LanguageStore();

  /// The saved language code (`ar` / `en`), or null when none / unreadable.
  String? read();

  /// Saves [code]. Failures (storage disabled, quota, privacy mode) are ignored.
  void write(String code);
}

/// The platform store: `localStorage` on web, nothing elsewhere.
class PlatformLanguageStore extends LanguageStore {
  const PlatformLanguageStore();

  @override
  String? read() {
    final v = impl.readLanguage(languageStorageKey);
    return v == 'ar' || v == 'en' ? v : null;
  }

  @override
  void write(String code) => impl.writeLanguage(languageStorageKey, code);
}
