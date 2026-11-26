import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import 'admin_strings.dart';

/// Live Web Push cron health rows (`meta/push_topics` queue drain and
/// `meta/push_plan` reminder planner) plus the daily rate-cap warning banner.
///
/// Subscribes via [AdminBackend.watchDoc] instead of `.first` so stale
/// IndexedDB cache snapshots are replaced immediately when server snapshots
/// arrive, and refreshes age thresholds once per minute while mounted.
class WebPushHealthRows extends StatefulWidget {
  final AdminBackend repo;

  /// Optional UTC clock override for deterministic tests.
  final DateTime Function()? now;

  const WebPushHealthRows({
    super.key,
    required this.repo,
    this.now,
  });

  @override
  State<WebPushHealthRows> createState() => _WebPushHealthRowsState();
}

class _WebPushHealthRowsState extends State<WebPushHealthRows> {
  Map<String, dynamic>? _topicsMeta;
  Map<String, dynamic>? _planMeta;
  StreamSubscription<AdminDoc?>? _topicsSub;
  StreamSubscription<AdminDoc?>? _planSub;
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant WebPushHealthRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo) {
      _cancelSubs();
      _topicsMeta = null;
      _planMeta = null;
      _subscribe();
    }
  }

  void _subscribe() {
    _topicsSub = widget.repo.watchDoc('meta/push_topics').listen(
      (doc) {
        if (mounted) setState(() => _topicsMeta = doc?.data);
      },
      onError: (_) {},
    );
    _planSub = widget.repo.watchDoc('meta/push_plan').listen(
      (doc) {
        if (mounted) setState(() => _planMeta = doc?.data);
      },
      onError: (_) {},
    );
  }

  void _cancelSubs() {
    _topicsSub?.cancel();
    _topicsSub = null;
    _planSub?.cancel();
    _planSub = null;
  }

  @override
  void dispose() {
    _cancelSubs();
    _ageTimer?.cancel();
    _ageTimer = null;
    super.dispose();
  }

  static DateTime? _asDateTime(dynamic v) {
    if (v is DateTime) return v.toUtc();
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    return null;
  }

  Widget _statusRow(BuildContext context, {required Key key, required Color color, required String text}) => Row(
        key: key,
        children: [
          Icon(
            color == context.pal.success ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final nowUtc = (widget.now?.call() ?? DateTime.now()).toUtc();
    final rawQueue = _topicsMeta?['cronQueue'];
    final cronQueue = rawQueue is Map ? rawQueue : null;
    final drainAt = _asDateTime(cronQueue?['lastDrainAt'] ?? cronQueue?['lastIdleAt'] ?? _topicsMeta?['lastDrainAt']);
    final rawDrainError = cronQueue?['lastIidError'] ?? _topicsMeta?['lastIidError'];
    final drainError = rawDrainError is String ? rawDrainError : null;
    final drainAge = drainAt == null ? null : nowUtc.difference(drainAt);
    final (Color drainColor, String drainText) = switch (drainAge) {
      null => (context.pal.muted, context.tr('nm_webHealthDrainNever')),
      final a when a > const Duration(minutes: 45) || (drainError != null && drainError.isNotEmpty) =>
        (context.pal.goldText, context.tr('nm_webHealthDrainLate')),
      _ => (context.pal.success, context.tr('nm_webHealthDrainOk')),
    };

    final planAt = _asDateTime(_planMeta?['lastPlanAt']);
    final capReached = (cronQueue?['capReached'] ?? _planMeta?['capReached']) == true;
    final planAge = planAt == null ? null : nowUtc.difference(planAt);
    final (Color planColor, String planText) = switch (planAge) {
      null => (context.pal.muted, context.tr('nm_webHealthPlanNever')),
      final a when a > const Duration(hours: 7) => (context.pal.goldText, context.tr('nm_webHealthPlanLate')),
      _ => (context.pal.success, context.tr('nm_webHealthPlanOk')),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusRow(context, key: const ValueKey('web-health-drain'), color: drainColor, text: drainText),
        const SizedBox(height: 6),
        _statusRow(context, key: const ValueKey('web-health-plan'), color: planColor, text: planText),
        if (capReached) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('web-health-cap-banner'),
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
    );
  }
}
