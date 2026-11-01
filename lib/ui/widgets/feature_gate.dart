import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Shows [child] only while the section(s) behind [path] are switched on in
/// `settings/features`; otherwise a friendly "not available" page.
class FeatureGate extends ConsumerWidget {
  final String path;
  final Widget child;
  const FeatureGate({super.key, required this.path, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(featuresProvider.select((f) => f.routeEnabled(path)));
    return enabled ? child : const SectionUnavailable();
  }
}

class SectionUnavailable extends StatelessWidget {
  const SectionUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(children: [
      const SizedBox(height: 40),
      const Icon(Icons.visibility_off_rounded, size: 64, color: AppColors.muted),
      const SizedBox(height: 12),
      Text(context.tr('sectionUnavailable'),
          key: const Key('sectionUnavailable'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(context.tr('sectionUnavailableHint'),
          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      Center(child: FilledButton(onPressed: () => context.go('/'), child: Text(context.tr('backHome')))),
    ]);
  }
}
