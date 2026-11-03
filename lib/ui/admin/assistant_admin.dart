import 'package:material_ui/material_ui.dart';

import '../../config/app_config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/features.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';

/// /admin → AI assistant (ADR-029): the on / off switches (the existing
/// "Ask the church" section switch and Church info's "Enable the AI
/// assistant") on top of the settings/assistant form.
class AssistantAdminScreen extends StatelessWidget {
  final AdminBackend repo;
  const AssistantAdminScreen({super.key, required this.repo});

  @override
  Widget build(BuildContext context) =>
      ChurchInfoScreen(repo: repo, doc: assistantSettingsDoc, header: AssistantSwitches(repo: repo));
}

/// The two switches the public assistant needs (both on), written as
/// single-field merges so nothing else in those documents changes.
class AssistantSwitches extends StatefulWidget {
  final AdminBackend repo;
  const AssistantSwitches({super.key, required this.repo});

  @override
  State<AssistantSwitches> createState() => _AssistantSwitchesState();
}

class _AssistantSwitchesState extends State<AssistantSwitches> {
  late Stream<AdminDoc?> _church = widget.repo.watchDoc('settings/church');
  late Stream<AdminDoc?> _features = widget.repo.watchDoc('settings/features');
  bool _saving = false;

  @override
  void didUpdateWidget(covariant AssistantSwitches oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo) {
      _church = widget.repo.watchDoc('settings/church');
      _features = widget.repo.watchDoc('settings/features');
    }
  }

  Future<void> _save(String path, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    String failed(Object e) => context.tr('saveFailed', {'e': '$e'});
    setState(() => _saving = true);
    try {
      await widget.repo.saveDoc(path, data);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failed(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update(String collection, String id, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    String failed(Object e) => context.tr('saveFailed', {'e': '$e'});
    setState(() => _saving = true);
    try {
      await widget.repo.update(collection, id, data);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failed(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      key: ObjectKey(_church),
      stream: _church,
      builder: (context, church) => StreamBuilder<AdminDoc?>(
        key: ObjectKey(_features),
        stream: _features,
        builder: (context, features) {
          final enabled = church.data?.data['assistantEnabled'] == true;
          final rawSections = features.data?.data['sections'];
          // A missing key = on (FeatureSettings.enabled).
          final sectionOn = rawSections is! Map || rawSections[Sections.assistant] != false;
          final ready = church.hasData && features.hasData && !_saving;
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  key: const Key('assistantSectionSwitch'),
                  title: Text(context.tr('assistantSectionSwitch')),
                  subtitle: Text(context.tr('assistantSectionSwitchHint')),
                  value: sectionOn,
                  // Only `sections.assistant` is written (a field-path update),
                  // so another admin's concurrent change to a different section
                  // is never reverted by a stale map.
                  onChanged: ready
                      ? (v) => features.data == null
                          ? _save('settings/features', {
                              'sections': {Sections.assistant: v},
                            })
                          : _update('settings', 'features', {'sections.${Sections.assistant}': v})
                      : null,
                ),
                SwitchListTile(
                  key: const Key('assistantEnabledSwitch'),
                  title: Text(context.tr('assistantEnabledSwitch')),
                  subtitle: Text(context.tr('assistantEnabledSwitchHint')),
                  value: enabled,
                  onChanged: church.data == null || !ready
                      ? null
                      : (v) => _save('settings/church', {'assistantEnabled': v}),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    context.tr('assistantStatusNote', {'m': AppConfig.geminiModel}),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
