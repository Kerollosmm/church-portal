// Tiny, safe Markdown subset for the assistant's replies (ADR-030).
//
// Supports **bold** / __bold__, *italic* / _italic_, `-`/`*`/`+`/`•` bullets,
// `1.` / `1)` numbered lists, `#` headings (rendered bold) and [text](url)
// links. Everything else is plain text: raw HTML tags are stripped, images
// (`![alt](url)`) keep only their alt text, code spans lose their backticks,
// and any `*` left unpaired is dropped so a literal asterisk never shows.
//
// Pure Dart (no Flutter) so it is unit-testable; `SafeMarkdown` renders it.

enum MdBlockKind { paragraph, bullet, numbered, heading }

class MdInline {
  final String text;
  final bool bold;
  final bool italic;

  /// The link target, only when it passed [safeLinkTarget]; null otherwise.
  final String? link;
  const MdInline(this.text, {this.bold = false, this.italic = false, this.link});

  @override
  String toString() => 'MdInline($text, b:$bold, i:$italic, link:$link)';
}

class MdBlock {
  final MdBlockKind kind;

  /// The list marker for numbered items ("1."); empty otherwise.
  final String marker;
  final int indent;
  final List<MdInline> spans;
  const MdBlock(this.kind, this.spans, {this.marker = '', this.indent = 0});

  String get plainText => spans.map((s) => s.text).join();
}

/// Returns [raw] if it is a link the assistant may open — `http(s)://…`,
/// `tel:…` or an internal route (`/path`, not `//host`) — else null.
String? safeLinkTarget(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
  if (t.startsWith('/')) {
    if (t.startsWith('//') || t.contains('\\')) return null;
    return t;
  }
  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) return null;
  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      return uri.host.isEmpty ? null : t;
    case 'tel':
      return RegExp(r'^tel:\+?[0-9\-\s().]{3,}$', caseSensitive: false).hasMatch(t) ? t : null;
    default:
      return null;
  }
}

final _bulletRe = RegExp(r'^(\s*)[-*+•·]\s+(.*)$');
final _numberRe = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final _headingRe = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$');
final _hrRe = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _htmlTagRe = RegExp(r'</?[A-Za-z][A-Za-z0-9-]*(\s[^<>]*)?/?>');
final _imageRe = RegExp(r'!\[([^\]]*)\]\([^)]*\)');

/// Parses [source] into blocks. Blank lines separate paragraphs; consecutive
/// non-list lines join into one paragraph with line breaks kept.
List<MdBlock> parseSimpleMarkdown(String source) {
  final text = source.replaceAll('\r\n', '\n').replaceAllMapped(_imageRe, (m) => m.group(1)!).replaceAll(_htmlTagRe, '');
  final blocks = <MdBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    blocks.add(MdBlock(MdBlockKind.paragraph, parseInline(para.join('\n'))));
    para.clear();
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.replaceAll('\t', '    ');
    if (line.trim().isEmpty || _hrRe.hasMatch(line) || line.trim().startsWith('```')) {
      flush();
      continue;
    }
    final h = _headingRe.firstMatch(line);
    if (h != null) {
      flush();
      blocks.add(MdBlock(MdBlockKind.heading,
          parseInline(h.group(1)!).map((s) => MdInline(s.text, bold: true, italic: s.italic, link: s.link)).toList()));
      continue;
    }
    final b = _bulletRe.firstMatch(line);
    if (b != null) {
      flush();
      blocks.add(MdBlock(MdBlockKind.bullet, parseInline(b.group(2)!), indent: b.group(1)!.length >= 2 ? 1 : 0));
      continue;
    }
    final n = _numberRe.firstMatch(line);
    if (n != null) {
      flush();
      blocks.add(MdBlock(MdBlockKind.numbered, parseInline(n.group(3)!),
          marker: '${n.group(2)}.', indent: n.group(1)!.length >= 2 ? 1 : 0));
      continue;
    }
    final quote = line.trimLeft().startsWith('>') ? line.trimLeft().replaceFirst(RegExp(r'^>+\s?'), '') : line;
    para.add(quote.trimRight());
  }
  flush();
  return blocks;
}

/// Inline parser: emphasis, links, code spans. Unpaired markers are dropped
/// (`*`) or kept literally (`_` inside words, e.g. snake_case).
List<MdInline> parseInline(String s) {
  final out = <MdInline>[];
  _inline(s, false, false, out);
  // Merge adjacent runs with the same style.
  final merged = <MdInline>[];
  for (final r in out) {
    if (r.text.isEmpty) continue;
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && last.bold == r.bold && last.italic == r.italic && last.link == null && r.link == null) {
      merged[merged.length - 1] = MdInline(last.text + r.text, bold: r.bold, italic: r.italic);
    } else {
      merged.add(r);
    }
  }
  return merged;
}

bool _isWordChar(String c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);

void _inline(String s, bool bold, bool italic, List<MdInline> out) {
  final buf = StringBuffer();
  void emit() {
    if (buf.isNotEmpty) out.add(MdInline(buf.toString(), bold: bold, italic: italic));
    buf.clear();
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];
    // Escapes: \* \_ \[ …
    if (c == '\\' && i + 1 < s.length && r'\*_[]()`#'.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }
    // Code span: drop the backticks, keep the text verbatim.
    if (c == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i) {
        buf.write(s.substring(i + 1, end));
        i = end + 1;
      } else {
        i++;
      }
      continue;
    }
    // Link: [label](target)
    if (c == '[') {
      final close = s.indexOf(']', i + 1);
      if (close > i && close + 1 < s.length && s[close + 1] == '(') {
        var end = -1, depth = 0;
        for (var j = close + 2; j < s.length; j++) {
          if (s[j] == '(') depth++;
          if (s[j] == ')') {
            if (depth == 0) {
              end = j;
              break;
            }
            depth--;
          }
        }
        if (end > close) {
          emit();
          final label = s.substring(i + 1, close);
          final target = safeLinkTarget(s.substring(close + 2, end));
          final inner = <MdInline>[];
          _inline(label, bold, italic, inner);
          for (final r in inner) {
            out.add(MdInline(r.text, bold: r.bold, italic: r.italic, link: target));
          }
          i = end + 1;
          continue;
        }
      }
    }
    // Strong: ** or __
    if ((c == '*' || c == '_') && i + 1 < s.length && s[i + 1] == c) {
      final marker = '$c$c';
      final end = s.indexOf(marker, i + 2);
      final leftOk = c == '*' || i == 0 || !_isWordChar(s[i - 1]);
      if (end > i + 2 && leftOk) {
        emit();
        _inline(s.substring(i + 2, end), true, italic, out);
        i = end + 2;
        continue;
      }
      if (c == '*') {
        i += 2; // unpaired ** — drop it
        continue;
      }
    }
    // Emphasis: * or _
    if (c == '*' || c == '_') {
      final next = i + 1 < s.length ? s[i + 1] : '';
      final leftOk = c == '*' || i == 0 || !_isWordChar(s[i - 1]);
      if (leftOk && next.isNotEmpty && next.trim().isNotEmpty) {
        var end = i + 1;
        while (true) {
          end = s.indexOf(c, end);
          if (end < 0) break;
          final rightOk = c == '*' || end + 1 >= s.length || !_isWordChar(s[end + 1]);
          if (s[end - 1].trim().isNotEmpty && rightOk && !(end + 1 < s.length && s[end + 1] == c)) break;
          end++;
        }
        if (end > i + 1) {
          emit();
          _inline(s.substring(i + 1, end), bold, true, out);
          i = end + 1;
          continue;
        }
      }
      if (c == '*') {
        i++; // unpaired * — never show a literal asterisk
        continue;
      }
    }
    buf.write(c);
    i++;
  }
  emit();
}

/// True when the first strong directional character of [s] is Arabic/Hebrew.
bool startsRtl(String s) {
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]').hasMatch(ch)) return true;
    if (RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(ch)) return false;
  }
  return false;
}
