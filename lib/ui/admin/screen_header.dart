import 'package:material_ui/material_ui.dart';

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
