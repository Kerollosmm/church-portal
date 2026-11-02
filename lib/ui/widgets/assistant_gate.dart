import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../domain/features.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Decides whether `/ask` may download the deferred assistant chunk: waits
/// for `settings/church` (until it arrives `assistantVisibleProvider` reads
/// false, which is not final), then shows "not available" without fetching
/// the AI SDK when the assistant is off (no App Check, kill switch, section
/// off), and builds [builder] (the [DeferredLoader]) only when it is on.
class AssistantGate extends ConsumerWidget {
  final WidgetBuilder builder;
  const AssistantGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (settings.isLoading) return const Center(child: CircularProgressIndicator());
    final visible = ref.watch(assistantVisibleProvider);
    setDocumentRouteMeta(path: '/ask', indexable: visible);
    if (!visible) {
      return PageBody(
        header: CustomizablePageHeader(
            pageKey: CustomizablePages.ask, title: context.tr('askTitle'), icon: Icons.auto_awesome_rounded),
        children: [const PageIntro(pageKey: CustomizablePages.ask), EmptyState(message: context.tr('askUnavailable'), icon: Icons.smart_toy_outlined)],
      );
    }
    return builder(context);
  }
}
