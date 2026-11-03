import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/launch.dart';
import '../../domain/simple_markdown.dart';

/// Renders the assistant's reply as the safe Markdown subset of
/// `parseSimpleMarkdown` (ADR-030): bold, italics, bullet / numbered lists and
/// links. Never renders HTML or images. Links open only when
/// `safeLinkTarget` accepted them (http(s), tel:, internal routes); any other
/// link stays plain, untappable text. Text direction follows the reply's
/// first strong character, so an Arabic reply is RTL even in the English UI.
/// Links keep the body colour (underlined), so contrast equals the text's.
class SafeMarkdown extends StatefulWidget {
  final String data;
  final TextStyle style;
  const SafeMarkdown(this.data, {super.key, required this.style});

  @override
  State<SafeMarkdown> createState() => _SafeMarkdownState();
}

class _SafeMarkdownState extends State<SafeMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _open(String target) {
    if (target.startsWith('/')) {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go(target);
        return;
      }
    }
    openUrl(target);
  }

  InlineSpan _span(MdInline r) {
    var style = TextStyle(
      fontWeight: r.bold ? FontWeight.w700 : null,
      fontStyle: r.italic ? FontStyle.italic : null,
    );
    GestureRecognizer? rec;
    final link = r.link;
    if (link != null) {
      style = style.copyWith(decoration: TextDecoration.underline, decorationColor: widget.style.color);
      final t = TapGestureRecognizer()..onTap = () => _open(link);
      _recognizers.add(t);
      rec = t;
    }
    return TextSpan(text: r.text, style: style, recognizer: rec, mouseCursor: rec == null ? null : SystemMouseCursors.click);
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final blocks = parseSimpleMarkdown(widget.data);
    final dir = startsRtl(widget.data) ? TextDirection.rtl : TextDirection.ltr;
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final text = Text.rich(TextSpan(children: b.spans.map(_span).toList()), style: widget.style);
      final gap = i == 0 ? 0.0 : (b.kind == MdBlockKind.paragraph || b.kind == MdBlockKind.heading ? 6.0 : 2.0);
      if (b.kind == MdBlockKind.bullet || b.kind == MdBlockKind.numbered) {
        children.add(Padding(
          padding: EdgeInsetsDirectional.only(top: gap, start: 4.0 + b.indent * 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: b.kind == MdBlockKind.bullet ? 16 : 24,
              child: Text(b.kind == MdBlockKind.bullet ? '•' : b.marker, style: widget.style),
            ),
            Expanded(child: text),
          ]),
        ));
      } else {
        children.add(Padding(padding: EdgeInsets.only(top: gap), child: text));
      }
    }
    return Directionality(
      textDirection: dir,
      child: SelectionArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
