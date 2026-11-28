import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'admin_strings.dart';
import 'save_diff.dart';

/// Shows a standard confirmation dialog that clearly names the target action or item.
///
/// If [destructive] is true, the confirm button uses the theme's alert palette.
Future<bool> confirmNamedAction(
  BuildContext context, {
  String? title,
  required String summary,
  required String actionLabel,
  bool destructive = false,
  Widget? details,
}) async {
  registerAdminStrings();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: title != null ? Text(title) : null,
      content: details == null
          ? Text(summary)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(summary),
                    const SizedBox(height: 12),
                    details,
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          key: const ValueKey('confirm-cancel'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-ok'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: destructive ? ctx.pal.alert : null,
            foregroundColor: destructive ? ctx.pal.onPrimary : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shows a confirmation dialog summarizing changed fields before saving
/// high-impact singleton settings documents (`features`, `today`, `church`).
Future<bool> confirmSaveDiff(BuildContext context, SaveDiffSummary diff) {
  registerAdminStrings();
  final changedLabel = context.tr('confirmSaveChanged');
  return confirmNamedAction(
    context,
    title: context.tr('confirmSaveTitle'),
    summary: context.tr('confirmSaveSummary'),
    actionLabel: context.tr('saveChanges'),
    details: Column(
      key: const ValueKey('save-diff-list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in diff.rows)
          Semantics(
            container: true,
            label: row.changedOnly
                ? '${row.label}: $changedLabel'
                : '${row.label}: ${row.oldValue} -> ${row.newValue}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: context.pal.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.pal.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.pal.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.changedOnly ? changedLabel : '${row.oldValue} → ${row.newValue}',
                      style: TextStyle(fontSize: 12.5, color: context.pal.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (diff.overflowCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr('confirmSaveMore', {'n': '${diff.overflowCount}'}),
              key: const ValueKey('save-diff-more'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.pal.primary),
            ),
          ),
      ],
    ),
  );
}
