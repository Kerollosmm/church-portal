import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../data/error_reporting.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';
import 'screen_header.dart';
import 'state_switch.dart';
import 'unsaved_guard.dart';

/// Owner-only «متقدم» screen (P2-21): Sentry error reporting switch & test,
/// App Check status, VAPID push key + Web Push queue drain health, and
/// Android APK / install banner settings.
class AdvancedOwnerScreen extends StatefulWidget {
  final AdminBackend repo;
  final bool appCheckActive;
  final Future<bool> Function() onSendTestError;

  const AdvancedOwnerScreen({
    super.key,
    required this.repo,
    this.appCheckActive = false,
    this.onSendTestError = ErrorReporting.sendTestEvent,
  });

  @override
  State<AdvancedOwnerScreen> createState() => _AdvancedOwnerScreenState();
}

class _AdvancedOwnerScreenState extends State<AdvancedOwnerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Stream<AdminDoc?> _featuresStream = widget.repo.watchDoc('settings/features');

  final TextEditingController _vapidCtrl = TextEditingController();
  String _storedVapid = '';
  bool _vapidInitialized = false;
  bool _vapidDirty = false;
  bool _savingSentry = false;
  bool _savingVapid = false;
  String? _vapidError;

  Map<String, dynamic>? _topicsMeta;
  Map<String, dynamic>? _planMeta;

  @override
  void initState() {
    super.initState();
    _loadWebHealth();
  }

  @override
  void didUpdateWidget(covariant AdvancedOwnerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo) {
      _featuresStream = widget.repo.watchDoc('settings/features');
      _storedVapid = '';
      _vapidInitialized = false;
      _vapidDirty = false;
      _vapidError = null;
      _topicsMeta = null;
      _planMeta = null;
      _loadWebHealth();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _vapidCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWebHealth() async {
    try {
      final tDoc = await widget.repo.watchDoc('meta/push_topics').first.timeout(const Duration(seconds: 4));
      final pDoc = await widget.repo.watchDoc('meta/push_plan').first.timeout(const Duration(seconds: 4));
      if (mounted) {
        setState(() {
          _topicsMeta = tDoc?.data;
          _planMeta = pDoc?.data;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleErrorReporting(bool value) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final savedText = context.tr('saved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    setState(() => _savingSentry = true);
    try {
      await widget.repo.saveDoc('settings/features', {'errorReporting': value});
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(savedText)));
    } catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    } finally {
      if (mounted) setState(() => _savingSentry = false);
    }
  }

  Future<void> _sendTestError() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sentText = context.tr('testErrorSent');
    final offText = context.tr('testErrorInactive');
    bool ok;
    try {
      ok = await widget.onSendTestError();
    } catch (_) {
      ok = false;
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? sentText : offText)));
  }

  Future<void> _saveVapid() async {
    final key = _vapidCtrl.text.trim();
    if (!isValidVapidKey(key)) {
      setState(() => _vapidError = context.tr('nm_errVapid'));
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final savedText = context.tr('adv_vapidSaved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    setState(() {
      _savingVapid = true;
      _vapidError = null;
    });
    try {
      await widget.repo.saveDoc('settings/features', {'pushVapidKey': key});
      if (mounted) {
        final stillMatches = _vapidCtrl.text.trim() == key;
        setState(() {
          _storedVapid = key;
          if (stillMatches) {
            if (_vapidCtrl.text != key) _vapidCtrl.text = key;
            _vapidDirty = false;
          } else {
            _vapidDirty = true;
          }
        });
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(savedText)));
      }
    } catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    } finally {
      if (mounted) setState(() => _savingVapid = false);
    }
  }

  DateTime? _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    return null;
  }

  Widget _card(BuildContext context, IconData icon, String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, color: context.pal.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.primary),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  void _resetVapid() {
    setState(() {
      _vapidCtrl.text = _storedVapid;
      _vapidDirty = false;
      _vapidError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return UnsavedGuard(
      dirty: _vapidDirty,
      handlePop: false,
      onBrowserBackDiscard: _resetVapid,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: AdminScreenHeader(
              title: context.tr('advancedGroup'),
              help: context.tr('help_advanced'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            ),
          ),
          SliverToBoxAdapter(
            child: Material(
              color: context.pal.background,
              child: TabBar(
                controller: _tabs,
                labelColor: context.pal.primary,
                unselectedLabelColor: context.pal.muted,
                indicatorColor: context.pal.primary,
                tabs: [
                  Tab(
                    key: const ValueKey('adv-tab-system'),
                    icon: const Icon(Icons.tune_outlined),
                    text: context.tr('adv_tabSystem'),
                  ),
                  Tab(
                    key: const ValueKey('adv-tab-apk'),
                    icon: const Icon(Icons.install_mobile_outlined),
                    text: context.tr('adv_tabApk'),
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildSystemTab(context),
            ChurchInfoScreen(
              key: const ValueKey('app-install-doc'),
              repo: widget.repo,
              doc: appInstallDoc,
              showHeader: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemTab(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      key: ObjectKey(_featuresStream),
      stream: _featuresStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data?.data ?? const <String, dynamic>{};
        final errorReporting = data['errorReporting'] != false;
        final storedVapid = data['pushVapidKey'] is String ? (data['pushVapidKey'] as String).trim() : '';
        _storedVapid = storedVapid;
        if (!_vapidInitialized || !_vapidDirty) {
          if (_vapidCtrl.text != storedVapid) _vapidCtrl.text = storedVapid;
          _vapidInitialized = true;
        }

        final cronQueue = _topicsMeta?['cronQueue'] as Map?;
        final drainAt = _asDateTime(cronQueue?['lastDrainAt'] ?? cronQueue?['lastIdleAt'] ?? _topicsMeta?['lastDrainAt']);
        final drainError = (cronQueue?['lastIidError'] ?? _topicsMeta?['lastIidError']) as String?;
        final drainAge = drainAt == null ? null : DateTime.now().toUtc().difference(drainAt);
        final (Color drainColor, String drainText) = switch (drainAge) {
          null => (context.pal.muted, context.tr('nm_webHealthDrainNever')),
          final a when a > const Duration(minutes: 45) || (drainError != null && drainError.isNotEmpty) =>
            (context.pal.goldText, context.tr('nm_webHealthDrainLate')),
          _ => (context.pal.success, context.tr('nm_webHealthDrainOk')),
        };

        final planAt = _asDateTime(_planMeta?['lastPlanAt']);
        final capReached = (cronQueue?['capReached'] ?? _planMeta?['capReached']) == true;
        final planAge = planAt == null ? null : DateTime.now().toUtc().difference(planAt);
        final (Color planColor, String planText) = switch (planAge) {
          null => (context.pal.muted, context.tr('nm_webHealthPlanNever')),
          final a when a > const Duration(hours: 7) => (context.pal.goldText, context.tr('nm_webHealthPlanLate')),
          _ => (context.pal.success, context.tr('nm_webHealthPlanOk')),
        };

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(context, Icons.bug_report_outlined, context.tr('errorReportingTitle'), [
                  AdminStateSwitch(
                    key: const ValueKey('features-errorReporting'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('errorReporting')),
                    subtitle: Text(context.tr('errorReportingHint')),
                    value: errorReporting,
                    onLabel: context.tr('switch_enabled'),
                    offLabel: context.tr('switch_disabled'),
                    onChanged: _savingSentry ? null : _toggleErrorReporting,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const ValueKey('features-sendTestError'),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(context.tr('sendTestError')),
                      onPressed: _sendTestError,
                    ),
                  ),
                ]),
                Card(
                  key: const ValueKey('adv-app-check'),
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Icon(
                            widget.appCheckActive ? Icons.verified_user_outlined : Icons.shield_outlined,
                            color: widget.appCheckActive ? context.pal.success : context.pal.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('adv_appCheckTitle'),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.primary),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(widget.appCheckActive ? 'adv_appCheckActive' : 'adv_appCheckInactive'),
                          style: TextStyle(
                            color: widget.appCheckActive ? context.pal.success : context.pal.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  key: const ValueKey('adv-vapid-queues'),
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Icon(Icons.key_outlined, color: context.pal.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('adv_vapidTitle'),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.primary),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        TextField(
                          key: const ValueKey('vapid'),
                          controller: _vapidCtrl,
                          enabled: !_savingVapid,
                          textDirection: TextDirection.ltr,
                          onChanged: (v) => setState(() {
                            _vapidDirty = v.trim() != _storedVapid;
                            _vapidError = null;
                          }),
                          decoration: InputDecoration(
                            labelText: context.tr('nm_vapidLabel'),
                            helperText: context.tr('nm_vapidHint'),
                            helperMaxLines: 4,
                            errorText: _vapidError,
                            errorMaxLines: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.icon(
                            key: const ValueKey('adv-save-vapid'),
                            onPressed: _savingVapid ? null : _saveVapid,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(context.tr('adv_saveVapid')),
                          ),
                        ),
                        const Divider(height: 24),
                        Text(
                          context.tr('adv_queuesTitle'),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.pal.primaryDeep),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(
                            drainColor == context.pal.success ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                            color: drainColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(drainText, style: TextStyle(color: drainColor, fontSize: 13))),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(
                            planColor == context.pal.success ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                            color: planColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(planText, style: TextStyle(color: planColor, fontSize: 13))),
                        ]),
                        if (capReached) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.pal.alert.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.pal.alert.withValues(alpha: 0.35)),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.warning_amber_rounded, color: context.pal.alert, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr('nm_webHealthCapBanner'),
                                  style: TextStyle(color: context.pal.ink, height: 1.45),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
