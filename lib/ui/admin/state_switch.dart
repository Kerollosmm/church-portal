import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

/// A switch with an explicit, bilingual written state badge («ظاهر / مخفي»,
/// «مفعّل / مقفول», etc.) so administrators never rely on switch thumb position
/// or color alone to discern state (ADR-050, Phase 3 Packet P1-09).
///
/// Responsive: at narrow widths (e.g. 320 px) and 200% text scale, the badge
/// and switch wrap cleanly beneath the title/subtitle without [RenderFlex]
/// overflow.
class AdminStateSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String onLabel;
  final String offLabel;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final Key? switchKey;
  final bool isThreeLine;
  final String? semanticLabel;

  const AdminStateSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onLabel,
    required this.offLabel,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.switchKey,
    this.isThreeLine = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final stateWord = value ? onLabel : offLabel;
    final isInteractive = onChanged != null;

    final badge = Semantics(
      label: semanticLabel ?? stateWord,
      child: Container(
        key: const ValueKey('state-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: value
              ? context.pal.primary.withValues(alpha: 0.12)
              : context.pal.muted.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? context.pal.primary.withValues(alpha: 0.35)
                : context.pal.hairline,
          ),
        ),
        child: Text(
          stateWord,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: value ? context.pal.primary : context.pal.muted,
          ),
        ),
      ),
    );

    final switchWidget = Switch(
      key: switchKey,
      value: value,
      onChanged: onChanged,
    );

    final controlGroup = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        badge,
        switchWidget,
      ],
    );

    if (title == null && subtitle == null && secondary == null) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: contentPadding ?? EdgeInsets.zero,
          child: controlGroup,
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isInteractive ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final isCompact = constraints.maxWidth < 420 || textScale > 1.2;

              final titleColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.titleMedium ??
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.pal.ink),
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.pal.muted) ??
                          TextStyle(fontSize: 12.5, color: context.pal.muted, height: 1.35),
                      child: subtitle!,
                    ),
                  ],
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (secondary != null) ...[
                          secondary!,
                          const SizedBox(width: 12),
                        ],
                        Expanded(child: titleColumn),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        badge,
                        switchWidget,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: isThreeLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  if (secondary != null) ...[
                    secondary!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: titleColumn),
                  const SizedBox(width: 12),
                  badge,
                  const SizedBox(width: 8),
                  switchWidget,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

