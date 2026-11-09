// Administrative control plane for notifications, FCM scheduling, and app settings (ADR-059).
library;

import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/push_env.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/models.dart' show parseHm;
import '../../domain/push.dart';
import '../../domain/reminders.dart' show leadLabel;
import '../../domain/time_format.dart';
import '../../domain/today.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';
import 'admin_validators.dart';

/// Admin screen combining Notifications manager and App Install settings.
class AppAndNotificationsScreen extends StatefulWidget {
  final AdminBackend repo;
  final String role;
  const AppAndNotificationsScreen({super.key, required this.repo, this.role = 'editor'});

  @override
  State<AppAndNotificationsScreen> createState() => _AppAndNotificationsScreenState();
}

class _AppAndNotificationsScreenState extends State<AppAndNotificationsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: context.pal.background,
          child: TabBar(
            controller: _tabController,
            labelColor: context.pal.primary,
            unselectedLabelColor: context.pal.muted,
            indicatorColor: context.pal.primary,
            tabs: [
              Tab(
                icon: const Icon(Icons.notifications_active_outlined),
                text: context.tr('adminNotificationsTitle'),
              ),
              Tab(
                icon: const Icon(Icons.install_mobile_outlined),
                text: context.tr('appSettingsTitle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              NotificationsAdminSection(repo: widget.repo, role: widget.role),
              ChurchInfoScreen(key: const ValueKey('app-install-doc'), repo: widget.repo, doc: appSettingsDoc),
            ],
          ),
        ),
      ],
    );
  }
}

/// Notification Manager screen tab: types, templates, reminders config, scheduled FCM pushes, and sent log.
class NotificationsAdminSection extends StatefulWidget {
  final AdminBackend repo;
  final String role;
  const NotificationsAdminSection({super.key, required this.repo, this.role = 'editor'});

  @override
  State<NotificationsAdminSection> createState() => _NotificationsAdminSectionState();
}

class _NotificationsAdminSectionState extends State<NotificationsAdminSection> {
  late final Stream<AdminDoc?> _featuresStream = widget.repo.watchDoc('settings/features');
  late final Stream<AdminDoc?> _notificationsStream = widget.repo.watchDoc('settings/notifications');

  // Form states
  bool _saving = false;
  bool _dirty = false;

  bool _pushEnabled = false;
  final TextEditingController _vapidCtrl = TextEditingController();
  final Set<NotifyType> _offeredTypes = Set.from(NotifyType.values);
  final Set<int> _reminderLeads = {0, 15, 60, 1440};
  int _reminderDefaultLead = 60;
  final Set<String> _reminderSources = {'lit', 'mtg', 'day'};

  // Per-type editable controllers: type -> {time, daysBefore, titleAr, titleEn, bodyAr, bodyEn}
  final Map<NotifyType, Map<String, TextEditingController>> _typeCtrls = {};

  // Scheduled Notification draft
  bool _isCreatingPush = false;
  String? _draftId;
  DateTime? _draftAtUtc;
  bool _draftEarliest = false;
  String _draftTargets = 'all';
  final TextEditingController _draftTitleAr = TextEditingController();
  final TextEditingController _draftTitleEn = TextEditingController();
  final TextEditingController _draftBodyAr = TextEditingController();
  final TextEditingController _draftBodyEn = TextEditingController();
  final TextEditingController _draftLink = TextEditingController(text: '/');
  final TextEditingController _draftEventKey = TextEditingController();

  final PushEnv _pushEnv = const PlatformPushEnv();

  @override
  void initState() {
    super.initState();
    _initTypeControllers();
  }

  void _initTypeControllers() {
    for (final type in NotifyType.values) {
      final def = NotifyTypeSpec.builtInDefaults[type]!;
      _typeCtrls[type] = {
        'time': TextEditingController(text: def.time),
        'daysBefore': TextEditingController(text: def.daysBefore > 0 ? def.daysBefore.toString() : ''),
        'titleAr': TextEditingController(text: def.titleAr),
        'titleEn': TextEditingController(text: def.titleEn),
        'bodyAr': TextEditingController(text: def.bodyAr),
        'bodyEn': TextEditingController(text: def.bodyEn),
      };
      for (final c in _typeCtrls[type]!.values) {
        c.addListener(_markDirty);
      }
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _vapidCtrl.dispose();
    for (final map in _typeCtrls.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    _draftTitleAr.dispose();
    _draftTitleEn.dispose();
    _draftBodyAr.dispose();
    _draftBodyEn.dispose();
    _draftLink.dispose();
    _draftEventKey.dispose();
    super.dispose();
  }

  void _populateFeatures(Map<String, dynamic>? data) {
    if (data == null) return;
    _pushEnabled = data['push'] == true;
    _vapidCtrl.text = data['pushVapidKey']?.toString() ?? '';

    final rawTypes = data['pushTypes'];
    if (rawTypes is List) {
      _offeredTypes.clear();
      for (final t in rawTypes) {
        final parsed = NotifyType.tryParse(t?.toString());
        if (parsed != null) _offeredTypes.add(parsed);
      }
    }

    final rawLeads = data['reminderLeads'];
    if (rawLeads is List) {
      _reminderLeads.clear();
      for (final l in rawLeads) {
        if (l is num && allowedReminderLeads.contains(l.toInt())) {
          _reminderLeads.add(l.toInt());
        }
      }
    }

    if (data['reminderDefaultLead'] is num) {
      _reminderDefaultLead = (data['reminderDefaultLead'] as num).toInt();
    }

    final rawSources = data['reminderSources'];
    if (rawSources is String) {
      _reminderSources.clear();
      _reminderSources.addAll(rawSources.split(',').map((s) => s.trim()).where(PushSettings.allReminderSources.contains));
    }

    final rawNotifyTypes = data['notifyTypes'];
    if (rawNotifyTypes is List) {
      for (final row in rawNotifyTypes) {
        if (row is! String) continue;
        final parts = row.split('\u001f');
        if (parts.isEmpty) continue;
        final type = NotifyType.tryParse(parts[0]);
        if (type == null) continue;
        final map = _typeCtrls[type];
        if (map == null) continue;

        if (parts.length > 1 && parts[1].isNotEmpty) map['time']!.text = parts[1];
        if (parts.length > 2 && parts[2].isNotEmpty) map['daysBefore']!.text = parts[2];
        if (parts.length > 3 && parts[3].isNotEmpty) map['titleAr']!.text = parts[3];
        if (parts.length > 4 && parts[4].isNotEmpty) map['titleEn']!.text = parts[4];
        if (parts.length > 5 && parts[5].isNotEmpty) map['bodyAr']!.text = parts[5];
        if (parts.length > 6 && parts[6].isNotEmpty) map['bodyEn']!.text = parts[6];
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final notifyTypesList = <String>[];
      for (final type in NotifyType.values) {
        final c = _typeCtrls[type]!;
        final def = NotifyTypeSpec.builtInDefaults[type]!;
        final time = c['time']!.text.trim();
        final days = c['daysBefore']!.text.trim();
        final titleAr = c['titleAr']!.text.trim();
        final titleEn = c['titleEn']!.text.trim();
        final bodyAr = c['bodyAr']!.text.trim();
        final bodyEn = c['bodyEn']!.text.trim();

        final isModified = time != def.time ||
            days != (def.daysBefore > 0 ? def.daysBefore.toString() : '') ||
            titleAr != def.titleAr ||
            titleEn != def.titleEn ||
            bodyAr != def.bodyAr ||
            bodyEn != def.bodyEn;

        if (isModified) {
          notifyTypesList.add([
            type.name,
            time,
            days,
            titleAr,
            titleEn,
            bodyAr,
            bodyEn,
          ].join('\u001f'));
        }
      }

      final payload = {
        'push': _pushEnabled,
        'pushVapidKey': _vapidCtrl.text.trim(),
        'pushTypes': _offeredTypes.map((t) => t.name).toList(),
        'reminderLeads': _reminderLeads.toList()..sort(),
        'reminderDefaultLead': _reminderDefaultLead,
        'reminderSources': _reminderSources.toList().join(','),
        'notifyTypes': notifyTypesList,
      };

      await widget.repo.saveDoc('settings/features', payload);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('saved'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: context.pal.alert));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveScheduledPush(NotifySchedule scheduleDoc) async {
    final titleAr = _draftTitleAr.text.trim();
    if (titleAr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('err_title_required'))));
      return;
    }

    DateTime atUtc;
    if (_draftEarliest || _draftAtUtc == null) {
      atUtc = DateTime.now().toUtc();
    } else {
      atUtc = _draftAtUtc!;
    }

    final row = ScheduledNotification(
      id: _draftId ?? DayEvent.generateRandomId(),
      atUtc: atUtc,
      targets: _draftTargets,
      titleAr: titleAr,
      titleEn: _draftTitleEn.text.trim(),
      bodyAr: _draftBodyAr.text.trim(),
      bodyEn: _draftBodyEn.text.trim(),
      link: safeNotificationLink(_draftLink.text),
      eventKey: _draftEventKey.text.trim(),
    );

    final err = validateScheduledNotification(row);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(err))));
      return;
    }

    setState(() => _saving = true);
    try {
      final updatedList = List<ScheduledNotification>.from(scheduleDoc.schedule);
      if (_draftId != null) {
        final idx = updatedList.indexWhere((r) => r.id == _draftId);
        if (idx >= 0) {
          updatedList[idx] = row;
        } else {
          updatedList.add(row);
        }
      } else {
        if (updatedList.length >= 20) {
          throw Exception('Max 20 scheduled notifications allowed');
        }
        updatedList.add(row);
      }

      final payload = {
        'schedule': updatedList.map((r) => r.toRow()).toList(),
      };
      await widget.repo.saveDoc('settings/notifications', payload);

      if (mounted) {
        setState(() {
          _isCreatingPush = false;
          _draftId = null;
          _draftTitleAr.clear();
          _draftTitleEn.clear();
          _draftBodyAr.clear();
          _draftBodyEn.clear();
          _draftLink.text = '/';
          _draftEventKey.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('saved'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: context.pal.alert));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteScheduledPush(NotifySchedule scheduleDoc, String id) async {
    if (!scheduleDoc.canDeleteRow(id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('err_cannot_delete_sending'))));
      return;
    }

    setState(() => _saving = true);
    try {
      final updatedList = scheduleDoc.schedule.where((r) => r.id != id).toList();
      final payload = {
        'schedule': updatedList.map((r) => r.toRow()).toList(),
      };
      await widget.repo.saveDoc('settings/notifications', payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('deleted'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: context.pal.alert));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSentLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('clearSentLog')),
        content: Text(context.tr('clearLogConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('confirm'))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.repo.saveDoc('settings/notifications', {'sentLog': []});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('cleared'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: context.pal.alert));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testNotificationOnDevice() async {
    final title = _draftTitleAr.text.trim().isNotEmpty ? _draftTitleAr.text.trim() : 'إشعار تجريبي من كنيسة القديسين';
    final body = _draftBodyAr.text.trim().isNotEmpty ? _draftBodyAr.text.trim() : 'هذا اختبار فوري للإشعارات على جهازك';
    final ok = await _pushEnv.showLocalNotification(title, body, icon: '/icons/Icon-192.png');
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('deviceTestSuccess'))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_pushEnv.isSupported ? context.tr('deviceTestPermDenied') : context.tr('deviceTestUnsupported')),
        backgroundColor: context.pal.alert,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      stream: _featuresStream,
      builder: (context, featSnap) {
        if (featSnap.hasData && featSnap.data != null && !_dirty) {
          _populateFeatures(featSnap.data!.data);
        }

        return StreamBuilder<AdminDoc?>(
          stream: _notificationsStream,
          builder: (context, notifSnap) {
            final notifyDoc = NotifySchedule.fromDoc(notifSnap.data?.data);

            return Scaffold(
              backgroundColor: context.pal.background,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    children: [
                      _buildHeaderCard(context, notifyDoc.health),
                      const SizedBox(height: 16),
                      _buildNotificationTypesSection(context),
                      const SizedBox(height: 16),
                      _buildRemindMeSection(context),
                      const SizedBox(height: 16),
                      _buildScheduledPushesSection(context, notifyDoc),
                      const SizedBox(height: 16),
                      _buildSentLogSection(context, notifyDoc),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: _dirty
                  ? Container(
                      color: context.pal.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.tr('unsavedChanges'), style: TextStyle(color: context.pal.alert, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _saving ? null : _saveSettings,
                              style: ElevatedButton.styleFrom(backgroundColor: context.pal.primary),
                              child: _saving
                                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onPrimary))
                                  : Text(context.tr('save'), style: TextStyle(color: context.pal.onPrimary)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildHeaderCard(BuildContext context, SenderHealth health) {
    Color healthColor;
    String healthText;
    IconData healthIcon;

    final lastRun = health.lastRunAt;
    final now = DateTime.now().toUtc();
    final diff = lastRun != null ? now.difference(lastRun) : null;

    if (lastRun == null || diff == null || diff > const Duration(hours: 3) || health.status == 'error') {
      healthColor = context.pal.alert;
      healthText = context.tr('senderHealthError');
      healthIcon = Icons.error_outline;
    } else if (diff > const Duration(hours: 1)) {
      healthColor = context.pal.goldText;
      healthText = context.tr('senderHealthDegraded');
      healthIcon = Icons.warning_amber_outlined;
    } else {
      healthColor = context.pal.success;
      healthText = context.tr('senderHealthOk');
      healthIcon = Icons.check_circle_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(healthIcon, color: healthColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(healthText, style: TextStyle(color: healthColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (lastRun != null)
                        Text(
                          context.tr('lastSenderRun', {'time': '${lastRun.toLocal().hour.toString().padLeft(2, '0')}:${lastRun.toLocal().minute.toString().padLeft(2, '0')}'}),
                          style: TextStyle(color: context.pal.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('enablePush'), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(context.tr('adminNotificationsHint')),
              value: _pushEnabled,
              onChanged: (v) => setState(() {
                _pushEnabled = v;
                _markDirty();
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vapidCtrl,
              decoration: InputDecoration(
                labelText: 'VAPID Public Key (Web Push)',
                helperText: 'Required for web browser and iOS PWA push notifications (80-100 chars)',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 16),
            Text(context.tr('offeredTypes'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NotifyType.values.map((t) {
                final selected = _offeredTypes.contains(t);
                return FilterChip(
                  label: Text(t.labelAr),
                  selected: selected,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _offeredTypes.add(t);
                    } else {
                      _offeredTypes.remove(t);
                    }
                    _markDirty();
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTypesSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('notifyTypesSection'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...NotifyType.values.map((t) => _buildTypeCard(context, t)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(BuildContext context, NotifyType type) {
    final ctrls = _typeCtrls[type]!;
    final def = NotifyTypeSpec.builtInDefaults[type]!;
    final channelBadge = switch (type) {
      NotifyType.announcements => context.tr('channelBadgeRemote'),
      NotifyType.seasons => context.tr('channelBadgeRemote'),
      NotifyType.reminders => context.tr('channelBadgeHybrid'),
      _ => context.tr('channelBadgeLocal'),
    };

    return ExpansionTile(
      key: ValueKey('type_${type.name}'),
      leading: Icon(Icons.tune_outlined, color: context.pal.primary),
      title: Row(
        children: [
          Expanded(child: Text(type.labelAr, style: const TextStyle(fontWeight: FontWeight.bold))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.pal.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(channelBadge, style: TextStyle(fontSize: 11, color: context.pal.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      subtitle: Text(type.descriptionAr, style: TextStyle(fontSize: 12, color: context.pal.muted)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (type == NotifyType.verse_daily || type == NotifyType.katameros_daily || type == NotifyType.feasts || type == NotifyType.seasons)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrls['time'],
                        decoration: InputDecoration(
                          labelText: 'وقت الإرسال الافتراضي (HH:mm)',
                          hintText: def.time,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (type == NotifyType.seasons) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: ctrls['daysBefore'],
                          decoration: InputDecoration(
                            labelText: 'قبل الموعد بـ (أيام)',
                            hintText: def.daysBefore.toString(),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 12),
              _buildTemplateField(
                context,
                label: 'عنوان الإشعار (عربي)',
                controller: ctrls['titleAr']!,
                typeId: type.name,
                placeholders: def.allowedPlaceholders,
              ),
              const SizedBox(height: 8),
              _buildTemplateField(
                context,
                label: 'نص الإشعار (عربي)',
                controller: ctrls['bodyAr']!,
                typeId: type.name,
                placeholders: def.allowedPlaceholders,
                multiline: true,
              ),
              const SizedBox(height: 12),
              _buildTemplateField(
                context,
                label: 'Title Template (English)',
                controller: ctrls['titleEn']!,
                typeId: type.name,
                placeholders: def.allowedPlaceholders,
              ),
              const SizedBox(height: 8),
              _buildTemplateField(
                context,
                label: 'Body Template (English)',
                controller: ctrls['bodyEn']!,
                typeId: type.name,
                placeholders: def.allowedPlaceholders,
                multiline: true,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: Text(context.tr('resetToDefault')),
                  onPressed: () {
                    ctrls['time']!.text = def.time;
                    ctrls['daysBefore']!.text = def.daysBefore > 0 ? def.daysBefore.toString() : '';
                    ctrls['titleAr']!.text = def.titleAr;
                    ctrls['titleEn']!.text = def.titleEn;
                    ctrls['bodyAr']!.text = def.bodyAr;
                    ctrls['bodyEn']!.text = def.bodyEn;
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String typeId,
    required List<String> placeholders,
    bool multiline = false,
  }) {
    final unknown = unknownPlaceholders(typeId, controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLines: multiline ? 3 : 1,
          decoration: InputDecoration(
            labelText: label,
            errorText: unknown.isNotEmpty ? context.tr('err_unknown_placeholder') : null,
            border: const OutlineInputBorder(),
            counterText: '${controller.text.length} / ${multiline ? 300 : 120}',
          ),
        ),
        if (placeholders.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: placeholders.map((ph) {
              return ActionChip(
                label: Text(ph, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                onPressed: () {
                  final text = controller.text;
                  final sel = controller.selection;
                  if (sel.isValid && sel.start >= 0) {
                    final next = text.replaceRange(sel.start, sel.end, ph);
                    controller.value = TextEditingValue(
                      text: next,
                      selection: TextSelection.collapsed(offset: sel.start + ph.length),
                    );
                  } else {
                    controller.text = '$text$ph';
                  }
                  _markDirty();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildRemindMeSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('notifyRemindersCard'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(context.tr('reminderSourcesLabel'), style: const TextStyle(fontWeight: FontWeight.w600)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('srcLiturgies')),
              value: _reminderSources.contains('lit'),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _reminderSources.add('lit');
                } else {
                  _reminderSources.remove('lit');
                }
                _markDirty();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('srcMeetings')),
              value: _reminderSources.contains('mtg'),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _reminderSources.add('mtg');
                } else {
                  _reminderSources.remove('mtg');
                }
                _markDirty();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('srcDayEvents')),
              value: _reminderSources.contains('day'),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _reminderSources.add('day');
                } else {
                  _reminderSources.remove('day');
                }
                _markDirty();
              }),
            ),
            const Divider(height: 24),
            Text('مدد التذكير المتاحة للمستخدم («ذكّرني قبل...»):', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allowedReminderLeads.map((m) {
                final label = leadLabel(m, 'ar');
                final sel = _reminderLeads.contains(m);
                return FilterChip(
                  label: Text(label),
                  selected: sel,
                  onSelected: (on) => setState(() {
                    if (on) {
                      if (_reminderLeads.length < 4) _reminderLeads.add(m);
                    } else {
                      if (_reminderLeads.length > 1) {
                        _reminderLeads.remove(m);
                        if (!_reminderLeads.contains(_reminderDefaultLead)) {
                          _reminderDefaultLead = _reminderLeads.first;
                        }
                      }
                    }
                    _markDirty();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _reminderLeads.contains(_reminderDefaultLead) ? _reminderDefaultLead : _reminderLeads.first,
              decoration: const InputDecoration(labelText: 'المدة الافتراضية للتذكير', border: OutlineInputBorder()),
              items: _reminderLeads.map((m) => DropdownMenuItem(value: m, child: Text(leadLabel(m, 'ar')))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _reminderDefaultLead = v);
                  _markDirty();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledPushesSection(BuildContext context, NotifySchedule scheduleDoc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text('${context.tr('scheduledPushesSection')} (${scheduleDoc.schedule.length}/20)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('addScheduledPush')),
                  onPressed: scheduleDoc.schedule.length >= 20 || _isCreatingPush
                      ? null
                      : () => setState(() {
                            _isCreatingPush = true;
                            _draftId = null;
                            _draftAtUtc = DateTime.now().toUtc().add(const Duration(hours: 1));
                            _draftEarliest = false;
                            _draftTargets = 'all';
                            _draftTitleAr.clear();
                            _draftTitleEn.clear();
                            _draftBodyAr.clear();
                            _draftBodyEn.clear();
                            _draftLink.text = '/';
                            _draftEventKey.clear();
                          }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isCreatingPush) _buildPushDraftEditor(context, scheduleDoc),
            if (scheduleDoc.schedule.isEmpty && !_isCreatingPush)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(context.tr('emptySchedule'), style: TextStyle(color: context.pal.muted))),
              ),
            ...scheduleDoc.schedule.map((row) => _buildScheduleRowCard(context, scheduleDoc, row)),
          ],
        ),
      ),
    );
  }

  Widget _buildPushDraftEditor(BuildContext context, NotifySchedule scheduleDoc) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        color: context.pal.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.pal.primary.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_draftId == null ? context.tr('addScheduledPush') : 'تعديل الإشعار المجدول', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _isCreatingPush = false),
                  ),
                ],
              ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('sendAtEarliest')),
            value: _draftEarliest,
            onChanged: (on) => setState(() => _draftEarliest = on == true),
          ),
          if (!_draftEarliest) ...[
            Text('${context.tr('sendAtLabel')}:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_draftAtUtc == null ? 'اختر التاريخ' : dayKey(CairoTime.calendarDate(_draftAtUtc!))),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _draftAtUtc ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) {
                      setState(() {
                        final curTime = _draftAtUtc != null ? parseHm('${_draftAtUtc!.hour}:${_draftAtUtc!.minute}') ?? 720 : 720;
                        _draftAtUtc = CairoTime.at(picked.year, picked.month, picked.day, curTime).toUtc();
                      });
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(_draftAtUtc == null ? 'اختر الوقت' : formatTimeArabic('${_draftAtUtc!.toLocal().hour.toString().padLeft(2, '0')}:${_draftAtUtc!.toLocal().minute.toString().padLeft(2, '0')}')),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: _draftAtUtc?.toLocal().hour ?? 12, minute: _draftAtUtc?.toLocal().minute ?? 0),
                    );
                    if (picked != null) {
                      setState(() {
                        final cur = _draftAtUtc ?? DateTime.now();
                        _draftAtUtc = CairoTime.at(cur.year, cur.month, cur.day, picked.hour * 60 + picked.minute).toUtc();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              const Text('المنصة:', style: TextStyle(fontWeight: FontWeight.w600)),
              ChoiceChip(
                label: Text(context.tr('pushTargetAll')),
                selected: _draftTargets == 'all',
                onSelected: (on) { if (on) setState(() => _draftTargets = 'all'); },
              ),
              ChoiceChip(
                label: Text(context.tr('pushTargetApp')),
                selected: _draftTargets == 'app',
                onSelected: (on) { if (on) setState(() => _draftTargets = 'app'); },
              ),
              ChoiceChip(
                label: Text(context.tr('pushTargetWeb')),
                selected: _draftTargets == 'web',
                onSelected: (on) { if (on) setState(() => _draftTargets = 'web'); },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _draftTitleAr,
            decoration: const InputDecoration(labelText: 'العنوان (عربي) *', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _draftBodyAr,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'نص الرسالة (عربي)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _draftTitleEn,
            decoration: const InputDecoration(labelText: 'Title (English)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _draftBodyEn,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Message Body (English)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _draftLink,
            decoration: InputDecoration(
              labelText: context.tr('deepLinkTarget'),
              hintText: '/mass-schedule',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _draftEventKey,
            decoration: InputDecoration(
              labelText: context.tr('linkToEvent'),
              hintText: 'lit-xxx, meeting-xxx, day-xxx',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Live Preview Card
          Text(context.tr('previewCardTitle'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildLiveNotificationPreview(context),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.devices_outlined),
                label: Text(context.tr('testOnDevice')),
                onPressed: _testNotificationOnDevice,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(context.tr('save')),
                onPressed: () => _saveScheduledPush(scheduleDoc),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
}

  Widget _buildLiveNotificationPreview(BuildContext context) {
    final title = _draftTitleAr.text.trim().isNotEmpty ? _draftTitleAr.text.trim() : 'عنوان الإشعار';
    final body = _draftBodyAr.text.trim().isNotEmpty ? _draftBodyAr.text.trim() : 'نص الإشعار يظهر هنا بوضوح للمستخدم عند استلام التنبيه.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.pal.background,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: context.pal.shadow(0.08), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.pal.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.church, color: context.pal.onPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('كنيسة القديسين مكسيموس ودوماديوس', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: context.pal.primary)),
                    Text('الآن', style: TextStyle(fontSize: 11, color: context.pal.muted)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 13, color: context.pal.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRowCard(BuildContext context, NotifySchedule scheduleDoc, ScheduledNotification row) {
    final rowStatus = scheduleDoc.status[row.id];
    final isExpired = scheduleDoc.isExpiredAt(row.id, DateTime.now().toUtc());

    String statusLabel;
    Color statusColor;

    if (rowStatus?.state == 'ok') {
      statusLabel = context.tr('statusSent');
      statusColor = context.pal.success;
    } else if (rowStatus?.state == 'sending') {
      statusLabel = context.tr('statusSending');
      statusColor = context.pal.goldText;
    } else if (rowStatus?.state == 'partial') {
      statusLabel = context.tr('statusPartial');
      statusColor = context.pal.barDeep;
    } else if (rowStatus?.state == 'error') {
      statusLabel = context.tr('statusError');
      statusColor = context.pal.alert;
    } else if (rowStatus?.state == 'unconfirmed') {
      statusLabel = context.tr('statusUnconfirmed');
      statusColor = context.pal.alert;
    } else if (isExpired) {
      statusLabel = context.tr('statusExpired');
      statusColor = context.pal.muted;
    } else if (!row.atUtc.isAfter(DateTime.now().toUtc())) {
      statusLabel = context.tr('statusQueued');
      statusColor = context.pal.primary;
    } else {
      statusLabel = context.tr('statusScheduled');
      statusColor = context.pal.primary;
    }

    final canDelete = scheduleDoc.canDeleteRow(row.id);
    final canClone = rowStatus?.state == 'partial' ||
        rowStatus?.state == 'error' ||
        rowStatus?.state == 'unconfirmed' ||
        isExpired;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    row.titleAr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            if (row.bodyAr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(row.bodyAr, style: TextStyle(color: context.pal.muted, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: context.pal.muted),
                const SizedBox(width: 4),
                Text(
                  '${dayKey(CairoTime.calendarDate(row.atUtc))} ${row.atUtc.toLocal().hour.toString().padLeft(2, '0')}:${row.atUtc.toLocal().minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: context.pal.muted),
                ),
                const SizedBox(width: 12),
                Icon(Icons.link, size: 14, color: context.pal.muted),
                const SizedBox(width: 4),
                Text(row.link, style: TextStyle(fontSize: 12, color: context.pal.muted)),
                const Spacer(),
                Text(row.targets.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.pal.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (canClone)
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(context.tr('cloneForRetry')),
                    onPressed: () {
                      final cloned = scheduleDoc.cloneDraftForRetry(row, DayEvent.generateRandomId(), DateTime.now().toUtc().add(const Duration(hours: 1)));
                      setState(() {
                        _isCreatingPush = true;
                        _draftId = cloned.id;
                        _draftAtUtc = cloned.atUtc;
                        _draftTargets = cloned.targets;
                        _draftTitleAr.text = cloned.titleAr;
                        _draftTitleEn.text = cloned.titleEn;
                        _draftBodyAr.text = cloned.bodyAr;
                        _draftBodyEn.text = cloned.bodyEn;
                        _draftLink.text = cloned.link;
                        _draftEventKey.text = cloned.eventKey;
                      });
                    },
                  ),
                if (canDelete)
                  TextButton.icon(
                    icon: Icon(Icons.delete_outline, size: 16, color: context.pal.alert),
                    label: Text(context.tr('deleteRow'), style: TextStyle(color: context.pal.alert)),
                    onPressed: () => _deleteScheduledPush(scheduleDoc, row.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentLogSection(BuildContext context, NotifySchedule scheduleDoc) {
    final log = scheduleDoc.sentLog.take(30).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.tr('sentLogSection'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.role == 'owner')
                  TextButton.icon(
                    icon: Icon(Icons.clear_all, size: 16, color: context.pal.alert),
                    label: Text(context.tr('clearSentLog'), style: TextStyle(color: context.pal.alert)),
                    onPressed: log.isEmpty ? null : _clearSentLog,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(context.tr('emptySentLog'), style: TextStyle(color: context.pal.muted))),
              ),
            ...log.map((entry) {
              final resultColor = entry.webState == 'error' || entry.appState == 'error'
                  ? context.pal.alert
                  : (entry.webState == 'partial' || entry.appState == 'partial' ? context.pal.goldText : context.pal.success);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.surfaceAlt.withValues(alpha: 0.5)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.titleAr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            '${dayKey(CairoTime.calendarDate(entry.sentAt))} ${entry.sentAt.toLocal().hour.toString().padLeft(2, '0')}:${entry.sentAt.toLocal().minute.toString().padLeft(2, '0')} (${entry.targets})',
                            style: TextStyle(fontSize: 11, color: context.pal.muted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: resultColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        entry.webState.isNotEmpty ? 'W:${entry.webState}' : (entry.appState.isNotEmpty ? 'A:${entry.appState}' : 'OK'),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: resultColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
