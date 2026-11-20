import 'package:material_ui/material_ui.dart';

import '../../domain/app_update.dart';

/// No-op web stub for Android in-app APK updater UI (ADR-077).
/// Keeps `UpdateBanner`, `UpdateSheet`, and `update*` copy out of `main.dart.js`.
class UpdateBanner extends StatelessWidget {
  final UpdateDecision? decision;
  final bool autoStartDownload;
  const UpdateBanner({super.key, this.decision, this.autoStartDownload = true});

  static Future<void> showUpdateSheet(
    BuildContext context,
    UpdateDecision decision, {
    bool autoStartDownload = true,
  }) async {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class UpdateSheet extends StatelessWidget {
  final UpdateDecision decision;
  final bool autoStart;
  const UpdateSheet({super.key, required this.decision, this.autoStart = true});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
