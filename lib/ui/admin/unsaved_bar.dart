import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// Fixed bottom bar notifying the admin of unsaved changes with save & cancel actions.
///
/// Reflows gracefully at 320 px and 200% text scaling via [Wrap].
class UnsavedBar extends StatelessWidget {
  final bool dirty;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool saving;
  final Key? saveKey;
  final Key? cancelKey;
  final String? message;
  final String? saveLabel;
  final String? cancelLabel;

  const UnsavedBar({
    super.key,
    required this.dirty,
    required this.onSave,
    required this.onCancel,
    this.saving = false,
    this.saveKey,
    this.cancelKey,
    this.message,
    this.saveLabel,
    this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!dirty) return const SizedBox.shrink();

    return Material(
      key: const ValueKey('unsaved-bar'),
      elevation: 8,
      color: context.pal.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.pal.hairline)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, color: context.pal.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message ?? context.tr('unsavedBarText'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.pal.ink,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    key: cancelKey ?? const ValueKey('unsaved-bar-cancel'),
                    onPressed: saving ? null : onCancel,
                    child: Text(cancelLabel ?? context.tr('cancel')),
                  ),
                  FilledButton(
                    key: saveKey ?? const ValueKey('unsaved-bar-save'),
                    onPressed: saving ? null : onSave,
                    child: saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.pal.onPrimary,
                            ),
                          )
                        : Text(saveLabel ?? context.tr('save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
