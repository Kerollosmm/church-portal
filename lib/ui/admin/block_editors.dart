import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/custom_content.dart'
    show ListStyles, detailsBodyMax, detailsSummaryMax, listBlockMaxItems, listItemMax;
import '../../domain/rules.dart' show toArabicDigits;

/// Mutable editor state for a single bilingual item inside a list block.
class ListItemDraft {
  final TextEditingController arCtrl;
  final TextEditingController enCtrl;

  /// Loaded English text preserved untouched while `englishEnabled == false`.
  final String initialEn;
  final GlobalKey arKey = GlobalKey();
  final GlobalKey enKey = GlobalKey();
  final FocusNode arFocus = FocusNode();
  final FocusNode enFocus = FocusNode();

  ListItemDraft._({
    required this.arCtrl,
    required this.enCtrl,
    required this.initialEn,
  });

  factory ListItemDraft.from({String ar = '', String en = ''}) => ListItemDraft._(
        arCtrl: TextEditingController(text: ar),
        enCtrl: TextEditingController(text: en),
        initialEn: en,
      );

  void dispose() {
    arCtrl.dispose();
    enCtrl.dispose();
    arFocus.dispose();
    enFocus.dispose();
  }
}

/// Admin editor for a [BlockTypes.list] block (style toggle + dynamic items).
class ListBlockEditor extends StatelessWidget {
  final int blockIndex;
  final String style;
  final List<ListItemDraft> items;
  final bool englishEnabled;
  final ValueChanged<String> onStyleChanged;
  final VoidCallback onChanged;
  final VoidCallback onAddItem;
  final ValueChanged<int> onRemoveItem;
  final void Function(int from, int to) onMoveItem;
  final String? Function(int itemIndex, bool isEn)? itemErrorText;
  final String? blockErrorText;

  const ListBlockEditor({
    super.key,
    required this.blockIndex,
    required this.style,
    required this.items,
    required this.englishEnabled,
    required this.onStyleChanged,
    required this.onChanged,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onMoveItem,
    this.itemErrorText,
    this.blockErrorText,
  });

  @override
  Widget build(BuildContext context) {
    final ar = context.isAr;
    final countText = ar
        ? '${toArabicDigits('${items.length}')} من ${toArabicDigits('$listBlockMaxItems')}'
        : '${items.length} / $listBlockMaxItems';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('listStyleLabel'),
          style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.ink),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: Key('listStyle-$blockIndex-bullet'),
              label: Text(context.tr('opt_listStyle_bullet')),
              selected: style != ListStyles.numbered,
              onSelected: (_) => onStyleChanged(ListStyles.bullet),
            ),
            ChoiceChip(
              key: Key('listStyle-$blockIndex-numbered'),
              label: Text(context.tr('opt_listStyle_numbered')),
              selected: style == ListStyles.numbered,
              onSelected: (_) => onStyleChanged(ListStyles.numbered),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  context.tr('listItemsLabel'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.ink),
                ),
                Text(
                  countText,
                  style: TextStyle(fontSize: 12, color: context.pal.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            OutlinedButton.icon(
              key: Key('addListItem-$blockIndex'),
              onPressed: items.length >= listBlockMaxItems ? null : onAddItem,
              icon: const Icon(Icons.add),
              label: Text(context.tr('addListItem')),
            ),
          ],
        ),
        if (blockErrorText != null && blockErrorText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              blockErrorText!,
              style: TextStyle(color: context.pal.alert, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        for (var i = 0; i < items.length; i++)
          Card(
            key: ObjectKey(items[i]),
            color: context.pal.surface,
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: items[i].arKey,
                    child: TextField(
                      key: Key('listItemAr-$blockIndex-$i'),
                      controller: items[i].arCtrl,
                      focusNode: items[i].arFocus,
                      maxLength: listItemMax,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: '${context.tr('listItemArLabel')} ${ar ? toArabicDigits('${i + 1}') : '${i + 1}'}',
                        errorText: itemErrorText?.call(i, false),
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  if (englishEnabled) ...[
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: items[i].enKey,
                      child: TextField(
                        key: Key('listItemEn-$blockIndex-$i'),
                        controller: items[i].enCtrl,
                        focusNode: items[i].enFocus,
                        maxLength: listItemMax,
                        maxLines: null,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: '${context.tr('listItemEnLabel')} ${i + 1}',
                          errorText: itemErrorText?.call(i, true),
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 2,
                        children: [
                          IconButton(
                            key: Key('listItemUp-$blockIndex-$i'),
                            tooltip: context.tr('moveUp'),
                            icon: const Icon(Icons.arrow_upward, size: 20),
                            onPressed: i == 0 ? null : () => onMoveItem(i, i - 1),
                          ),
                          IconButton(
                            key: Key('listItemDown-$blockIndex-$i'),
                            tooltip: context.tr('moveDown'),
                            icon: const Icon(Icons.arrow_downward, size: 20),
                            onPressed: i == items.length - 1 ? null : () => onMoveItem(i, i + 1),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        key: Key('listItemRemove-$blockIndex-$i'),
                        onPressed: () => onRemoveItem(i),
                        icon: Icon(Icons.delete_outline, color: context.pal.alert, size: 20),
                        label: Text(context.tr('remove'), style: TextStyle(color: context.pal.alert)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Mutable editor state for a bilingual collapsible details block.
class DetailsDraft {
  final TextEditingController summaryArCtrl;
  final TextEditingController summaryEnCtrl;
  final TextEditingController bodyArCtrl;
  final TextEditingController bodyEnCtrl;

  /// Loaded English texts preserved untouched while `englishEnabled == false`.
  final String initialSummaryEn;
  final String initialBodyEn;

  final GlobalKey summaryArKey = GlobalKey();
  final GlobalKey summaryEnKey = GlobalKey();
  final GlobalKey bodyArKey = GlobalKey();
  final GlobalKey bodyEnKey = GlobalKey();

  final FocusNode summaryArFocus = FocusNode();
  final FocusNode summaryEnFocus = FocusNode();
  final FocusNode bodyArFocus = FocusNode();
  final FocusNode bodyEnFocus = FocusNode();

  DetailsDraft._({
    required this.summaryArCtrl,
    required this.summaryEnCtrl,
    required this.bodyArCtrl,
    required this.bodyEnCtrl,
    required this.initialSummaryEn,
    required this.initialBodyEn,
  });

  factory DetailsDraft.from({
    String summaryAr = '',
    String summaryEn = '',
    String bodyAr = '',
    String bodyEn = '',
  }) =>
      DetailsDraft._(
        summaryArCtrl: TextEditingController(text: summaryAr),
        summaryEnCtrl: TextEditingController(text: summaryEn),
        bodyArCtrl: TextEditingController(text: bodyAr),
        bodyEnCtrl: TextEditingController(text: bodyEn),
        initialSummaryEn: summaryEn,
        initialBodyEn: bodyEn,
      );

  bool ownsFocusNode(FocusNode node) =>
      identical(summaryArFocus, node) ||
      identical(summaryEnFocus, node) ||
      identical(bodyArFocus, node) ||
      identical(bodyEnFocus, node);

  bool ownsFieldKey(GlobalKey key) =>
      identical(summaryArKey, key) ||
      identical(summaryEnKey, key) ||
      identical(bodyArKey, key) ||
      identical(bodyEnKey, key);

  void dispose() {
    summaryArCtrl.dispose();
    summaryEnCtrl.dispose();
    bodyArCtrl.dispose();
    bodyEnCtrl.dispose();
    summaryArFocus.dispose();
    summaryEnFocus.dispose();
    bodyArFocus.dispose();
    bodyEnFocus.dispose();
  }
}

/// Admin editor for a [BlockTypes.details] block (bilingual summary + body).
class DetailsBlockEditor extends StatelessWidget {
  final int blockIndex;
  final DetailsDraft draft;
  final bool englishEnabled;
  final VoidCallback onChanged;
  final String? Function(String field, bool isEn)? fieldErrorText;

  const DetailsBlockEditor({
    super.key,
    required this.blockIndex,
    required this.draft,
    required this.englishEnabled,
    required this.onChanged,
    this.fieldErrorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('detailsHint'),
          style: TextStyle(fontSize: 12.5, color: context.pal.muted),
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: draft.summaryArKey,
          child: TextField(
            key: Key('detailsSummaryAr-$blockIndex'),
            controller: draft.summaryArCtrl,
            focusNode: draft.summaryArFocus,
            maxLength: detailsSummaryMax,
            minLines: 1,
            maxLines: 2,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: context.tr('detailsSummaryArLabel'),
              errorText: fieldErrorText?.call('summary', false),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        if (englishEnabled) ...[
          const SizedBox(height: 8),
          KeyedSubtree(
            key: draft.summaryEnKey,
            child: TextField(
              key: Key('detailsSummaryEn-$blockIndex'),
              controller: draft.summaryEnCtrl,
              focusNode: draft.summaryEnFocus,
              maxLength: detailsSummaryMax,
              minLines: 1,
              maxLines: 2,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('detailsSummaryEnLabel'),
                errorText: fieldErrorText?.call('summary', true),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
        const SizedBox(height: 8),
        KeyedSubtree(
          key: draft.bodyArKey,
          child: TextField(
            key: Key('detailsBodyAr-$blockIndex'),
            controller: draft.bodyArCtrl,
            focusNode: draft.bodyArFocus,
            maxLength: detailsBodyMax,
            minLines: 3,
            maxLines: null,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: context.tr('detailsBodyArLabel'),
              errorText: fieldErrorText?.call('body', false),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        if (englishEnabled) ...[
          const SizedBox(height: 8),
          KeyedSubtree(
            key: draft.bodyEnKey,
            child: TextField(
              key: Key('detailsBodyEn-$blockIndex'),
              controller: draft.bodyEnCtrl,
              focusNode: draft.bodyEnFocus,
              maxLength: detailsBodyMax,
              minLines: 3,
              maxLines: null,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('detailsBodyEnLabel'),
                errorText: fieldErrorText?.call('body', true),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ],
    );
  }
}
