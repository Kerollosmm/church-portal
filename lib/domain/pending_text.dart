/// Seed placeholders that say a fact still waits for the church
/// («— في انتظار تأكيد الكنيسة.», "pending church confirmation",
/// «تفاصيل غير مُؤكَّدة»): public pages and the assistant prompt
/// treat them as empty (ADR-050, issue 16). ADR-046 already removed every
/// visible sample mark; this removes the same message written inside the
/// text itself. Only the display is cleaned: the admin edits the stored
/// text as it is.
library;

/// Phrases that mark a placeholder (Arabic, matched on the text without
/// tashkeel so «غير مُؤكَّدة» counts too, and English).
final RegExp _marker = RegExp(
  r'(?:في\s+|ب)انتظار\s+(?:ال)?تأكيد|لم\s+يؤكد|غير\s+مؤكد|'
  r'pending\s+(?:church\s+)?confirmation|awaiting\s+(?:church\s+)?confirmation|not\s+(?:yet\s+)?confirmed',
  caseSensitive: false,
);

/// Arabic tashkeel and tatweel, ignored when looking for a marker (the
/// kept text keeps its own; CodeRabbit on PR #45).
final RegExp _tashkeel = RegExp('[\u064B-\u065F\u0670\u0640]');

/// A caveat about affiliation («لم يُؤكَّد أنه تابع للكنيسة», "not confirmed
/// as a church ministry") is a real fact for visitors, not a placeholder:
/// it stays (CodeRabbit on PR #45).
final RegExp _affiliation = RegExp(r'تابع|ministry|affiliat', caseSensitive: false);

bool _marked(String s) {
  final bare = s.replaceAll(_tashkeel, '');
  return _marker.hasMatch(bare) && !_affiliation.hasMatch(bare);
}

/// A bracketed aside that holds a marker: «(لم يُؤكَّد أنه تابع للكنيسة)».
final RegExp _aside = RegExp(r'\s*[(\[（][^()\[\]（）]*[)\]）]');

/// Does [s] contain a pending-confirmation placeholder?
bool hasPendingPlaceholder(String s) => _marked(s);

/// [s] without its pending-confirmation placeholders: a bracketed aside
/// holding one is dropped, then every sentence holding one. Text with none
/// is returned unchanged; a text that was only a placeholder becomes ''.
String stripPendingPlaceholders(String s) {
  if (!_marked(s)) return s;
  var out = s.replaceAllMapped(_aside, (m) => _marked(m[0]!) ? '' : m[0]!);
  if (!_marked(out)) return _tidy(out);
  out = _sentence.allMatches(out).map((m) => m[0]!).where((p) => !_marked(p)).join();
  return _tidy(out);
}

/// One sentence: it ends at . ! ? ؟ (kept) or a line break. A link is one
/// unit, so the dots inside `https://example.org/contact` do not split the
/// sentence that holds it (CodeRabbit on PR #45).
final RegExp _sentence = RegExp(
  r'(?:(?:https?://|www\.)\S+?(?=[.!?؟]*(?:\s|$))|[^.!?؟\n])+[.!?؟]*\s*|[.!?؟]+\s*|\n',
  caseSensitive: false,
);

String _tidy(String s) => s
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'\s+([.!?؟،,])'), (m) => m[1]!)
    .trim();
