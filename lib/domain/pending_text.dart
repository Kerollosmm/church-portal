/// Seed placeholders that say a fact still waits for the church
/// («— في انتظار تأكيد الكنيسة.», "pending church confirmation",
/// «(لم يُؤكَّد أنه تابع للكنيسة)»): public pages and the assistant prompt
/// treat them as empty (ADR-050, issue 16). ADR-046 already removed every
/// visible sample mark; this removes the same message written inside the
/// text itself. Only the display is cleaned: the admin edits the stored
/// text as it is.
library;

/// Phrases that mark a placeholder (Arabic with or without tashkeel, and
/// English).
final RegExp _marker = RegExp(
  r'(?:في\s+|ب)انتظار\s+(?:ال)?تأكيد|لم\s+ي[ُ]?ؤ[َ]?ك[َّ]*د|غير\s+مؤكد|'
  r'pending\s+(?:church\s+)?confirmation|awaiting\s+(?:church\s+)?confirmation|not\s+(?:yet\s+)?confirmed',
  caseSensitive: false,
);

/// A bracketed aside that holds a marker: «(لم يُؤكَّد أنه تابع للكنيسة)».
final RegExp _aside = RegExp(r'\s*[(\[（][^()\[\]（）]*[)\]）]');

/// Does [s] contain a pending-confirmation placeholder?
bool hasPendingPlaceholder(String s) => _marker.hasMatch(s);

/// [s] without its pending-confirmation placeholders: a bracketed aside
/// holding one is dropped, then every sentence holding one. Text with none
/// is returned unchanged; a text that was only a placeholder becomes ''.
String stripPendingPlaceholders(String s) {
  if (!_marker.hasMatch(s)) return s;
  var out = s.replaceAllMapped(_aside, (m) => _marker.hasMatch(m[0]!) ? '' : m[0]!);
  if (!_marker.hasMatch(out)) return _tidy(out);
  // Sentences end at . ! ? ؟ or a line break; keep each end mark.
  final parts = RegExp(r'[^.!?؟\n]+[.!?؟]*\s*|\n').allMatches(out).map((m) => m[0]!);
  out = parts.where((p) => !_marker.hasMatch(p)).join();
  return _tidy(out);
}

String _tidy(String s) => s
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'\s+([.!?؟،,])'), (m) => m[1]!)
    .trim();
