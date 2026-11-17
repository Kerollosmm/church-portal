import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// Shows a standard confirmation dialog that clearly names the target action or item.
///
/// If [destructive] is true, the confirm button uses the theme's alert palette.
Future<bool> confirmNamedAction(
  BuildContext context, {
  String? title,
  required String summary,
  required String actionLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: title != null ? Text(title) : null,
      content: Text(summary),
      actions: [
        TextButton(
          key: const ValueKey('confirm-cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-ok'),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: ctx.pal.alert,
                  foregroundColor: ctx.pal.onPrimary,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
