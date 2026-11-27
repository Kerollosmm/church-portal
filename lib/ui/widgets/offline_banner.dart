import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';

/// Compact connectivity-hint banner shown when the device has no network.
///
/// Uses [connectivityProvider] (a hint only — lie-fi still reports online;
/// Firestore timeouts remain the authoritative guard).
class OfflineBanner extends ConsumerWidget {
  final String? message;

  const OfflineBanner({super.key, this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider).value ?? true;
    if (online) return const SizedBox.shrink();

    final text = message ?? context.tr('offlineBanner');
    final pal = context.pal;

    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      child: Container(
        key: const Key('offlineBanner'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: pal.notice,
          border: Border(
            bottom: BorderSide(color: pal.noticeEdge, width: 1.0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: pal.noticeInk),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pal.noticeInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
