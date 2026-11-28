import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// Screen title + one-line help header shown at the top of every admin screen (P2-19).
class AdminScreenHeader extends StatelessWidget {
  final String title;
  final String help;
  final EdgeInsetsGeometry padding;

  const AdminScreenHeader({
    super.key,
    required this.title,
    this.help = '',
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (title.isEmpty && help.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              key: const Key('screen-title'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.pal.primary,
              ),
            ),
          if (help.isNotEmpty) ...[
            if (title.isNotEmpty) const SizedBox(height: 4),
            Text(
              help,
              key: const Key('screen-help'),
              style: TextStyle(color: context.pal.muted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

/// Toolbar action to enter bulk selection mode with a 48 px hit target.
class BulkSelectButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const BulkSelectButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final label = context.tr('selectItems');
    return IconButton(
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(Icons.checklist_rounded),
      onPressed: onPressed,
    );
  }
}

/// Accessible 48×48 checkbox for bulk-selectable rows.
class BulkRowCheckbox extends StatelessWidget {
  final bool value;
  final String semanticLabel;
  final ValueChanged<bool?>? onChanged;
  const BulkRowCheckbox({
    super.key,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Checkbox(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            semanticLabel: semanticLabel,
            onChanged: onChanged,
          ),
        ),
      );
}

/// Pinned action bar shown while bulk selection mode is active.
class BulkSelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final bool busy;
  final FocusNode? selectAllFocusNode;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onCancel;
  final List<Widget> actions;

  const BulkSelectionBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.busy,
    this.selectAllFocusNode,
    required this.onToggleSelectAll,
    required this.onCancel,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = totalCount > 0 && selectedCount == totalCount;
    final bool? selectAllValue = allSelected ? true : (selectedCount > 0 ? null : false);
    return Material(
      key: const Key('bulk-selection-bar'),
      color: context.pal.surfaceAlt,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Checkbox(
                              key: const Key('bulk-select-all'),
                              focusNode: selectAllFocusNode,
                              value: selectAllValue,
                              tristate: true,
                              materialTapTargetSize: MaterialTapTargetSize.padded,
                              semanticLabel: context.tr(allSelected ? 'deselectAll' : 'selectAll'),
                              onChanged: busy || totalCount == 0
                                  ? null
                                  : (_) => onToggleSelectAll(),
                            ),
                          ),
                        ),
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: busy || totalCount == 0 ? null : onToggleSelectAll,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                              child: Text(
                                context.tr('selectedCount', {'n': '$selectedCount'}),
                                key: const Key('bulk-selected-count'),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...actions,
                  TextButton.icon(
                    key: const Key('bulk-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: busy ? null : onCancel,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(context.tr('cancel')),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
