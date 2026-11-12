// Admin control plane for notifications (ADR-059): sender status, scheduled
// church announcements, what visitors may subscribe to (types, times, texts),
// the «ذكّرني» options and the sent log. Rewritten for clarity in the PR #55
// UX review: plain Arabic first (English second), friendly names instead of
// stored keys, Cairo times, confirmations and inline validation.
library;

import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/push_env.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart' show builtInLinkTargets, customPagePath, categoryPath, isValidSlug;
import '../../domain/features.dart' show FeatureSettings;
import '../../domain/item_detail.dart' show DetailKind, detailPathFor;
import '../../domain/push.dart';
import '../../domain/reminders.dart' show EventKey, leadLabel;
import '../../domain/rules.dart' show toArabicDigits;
import '../../domain/time_format.dart';
import '../../domain/today.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';
import 'admin_validators.dart';

const Map<String, List<String>> _notificationsAdminStrings = {
  'nm_statusSubtitle': [
    'شغّل أو أوقف كل الإشعارات، وتأكد أن خدمة الإرسال تعمل.',
    'Turn all notifications on or off and check the sending service.',
  ],
  'nm_masterOnHint': [
    'مفعّلة: يرى الزوار خيارات الإشعارات وتُرسل الإعلانات المجدولة.',
    'On: visitors see notification options and scheduled announcements are sent.',
  ],
  'nm_masterOffHint': [
    'متوقفة: لن يُرسل أي إشعار ولن تظهر خيارات الإشعارات للزوار.',
    'Off: nothing is sent and visitors do not see notification options.',
  ],
  'nm_pushOffBanner': [
    'الإشعارات متوقفة الآن. يمكنك تجهيز الإعلانات والنصوص، لكن لن يُرسل شيء حتى تشغّلها وتضغط «حفظ الإعدادات».',
    'Notifications are off. You can prepare announcements and texts, but nothing is sent until you turn them on and press “Save settings”.',
  ],
  'nm_senderOkHint': [
    'تفحص الخدمة كل ١٥ دقيقة؛ الإعلان المجدول يصل عادةً خلال ١٥–٣٠ دقيقة من موعده.',
    'It checks every 15 minutes; a scheduled announcement usually arrives 15–30 minutes after its time.',
  ],
  'nm_senderLateHint': [
    'لم تعمل منذ أكثر من ساعة. لا شيء مفقود — سترسل ما فاتها عند أول تشغيل. إن استمر التأخير أبلغ المسؤول التقني.',
    'It has not run for over an hour. Nothing is lost — it catches up on its next run. Tell the technical admin if this continues.',
  ],
  'nm_senderStoppedHint': [
    'لم تعمل منذ أكثر من ٣ ساعات، فلن تُرسل الإعلانات. أبلغ المسؤول التقني (راجع دليل التشغيل: مُرسِل الإشعارات).',
    'It has not run for over 3 hours, so announcements are not going out. Tell the technical admin (operations guide: push sender).',
  ],
  'nm_senderNeverHint': [
    'لم تُسجَّل أي دورة إرسال حتى الآن. يجهّزها المسؤول التقني مرة واحدة (دليل التشغيل)؛ حتى ذلك الحين تُحفظ الإعلانات ولا تُرسل.',
    'No sending run has been recorded yet. The technical admin sets it up once (operations guide); until then announcements are saved but not sent.',
  ],
  'nm_scheduledSubtitle': [
    'اكتب إعلانًا (نهضة، قداس، اجتماع…) واختر موعد إرساله؛ يصل كإشعار لكل من فعّل «تنويهات وأخبار».',
    'Write an announcement (revival, liturgy, meeting…) and choose when it goes out; it reaches everyone who turned on “Announcements”.',
  ],
  'nm_vapidHint': [
    'من Firebase Console ← Project settings ← Cloud Messaging ← Web Push certificates. اتركه فارغًا إن لم يتوفر بعد (لن تعمل إشعارات المتصفح و iPhone بدونه).',
    'From Firebase Console → Project settings → Cloud Messaging → Web Push certificates. Leave empty if not available yet (browser & iPhone push need it).',
  ],
  'nm_errVapid': [
    'المفتاح غير صحيح: يجب أن يكون ٨٠–١٠٠ حرف إنجليزي/رقم أو - و _ فقط (انسخه كاملًا).',
    'Invalid key: 80–100 letters, digits, - or _ (copy it whole).',
  ],
  'nm_errPast': [
    'هذا الموعد مرّ بالفعل. اختر موعدًا قادمًا أو «في أقرب وقت».',
    'That time has passed. Pick a future time or “As soon as possible”.',
  ],
  'nm_errFull': [
    'القائمة ممتلئة (٢٠). احذف إعلانًا قديمًا أولًا.',
    'The list is full (20). Delete an old one first.',
  ],
  'nm_webHealthCapBanner': [
    'تنبيه: وصلت تذكيرات اليوم إلى الحد الأقصى (١٠٠٠ تذكير) — قد لا تصل بعض التذكيرات الإضافية اليوم.',
    'Warning: Daily reminder limit reached (1,000 reminders) — additional reminders may not be sent today.',
  ],
  'nm_webPlannerDelayNotice': [
    'ملاحظة: تعديلات منتصف اليوم على القداسات والصلوات تستغرق نحو ساعتين إلى ٦ ساعات لتنعكس في تذكيرات المتصفح (يعمل المجدول ٤ مرات يوميًا: ٢:٠٣ و ٨:٠٣ و ١٤:٠٣ و ٢٠:٠٣ بتوقيت القاهرة).',
    'Note: Mid-day edits to liturgies take ~2–6 hours to reflect in browser reminders (the planner runs 4 times daily at 02:03, 08:03, 14:03, 20:03 Cairo time).',
  ],
  'nm_errRowGone': [
    'حُذف هذا الإعلان من جهاز آخر. أغلق المحرر وأعد المحاولة.',
    'This announcement was deleted elsewhere. Close the editor and try again.',
  ],
  'nm_errAlreadySending': [
    'بدأ إرسال هذا الإعلان بالفعل فلا يمكن تعديله. استخدم «أعد الإرسال» إن لزم.',
    'Sending already started, so it cannot be edited. Use “Send again” if needed.',
  ],
};

/// Admin screen combining the notifications manager and the app-install settings.
class AppAndNotificationsScreen extends StatefulWidget {
  final AdminBackend repo;
  final String role;
  const AppAndNotificationsScreen({super.key, required this.repo, this.role = 'editor'});

  @override
  State<AppAndNotificationsScreen> createState() => _AppAndNotificationsScreenState();
}

class _AppAndNotificationsScreenState extends State<AppAndNotificationsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    registerStrings(_notificationsAdminStrings);
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
              Tab(icon: const Icon(Icons.notifications_active_outlined), text: context.tr('nm_tabNotifications')),
              Tab(icon: const Icon(Icons.install_mobile_outlined), text: context.tr('nm_tabInstall')),
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

/// Types that have a send time the admin sets (the user may still pick their
/// own time on the phone for verse / Katameros).
const _timedTypes = {NotifyType.verse_daily, NotifyType.katameros_daily, NotifyType.feasts, NotifyType.seasons};

/// Types whose text templates are used somewhere. Announcements are written
/// one by one in «إعلانات مجدولة», so their template is not offered.
bool _hasTemplate(NotifyType t) => t != NotifyType.announcements;

IconData _typeIcon(NotifyType t) => switch (t) {
      NotifyType.announcements => Icons.campaign_outlined,
      NotifyType.verse_daily => Icons.menu_book_outlined,
      NotifyType.katameros_daily => Icons.auto_stories_outlined,
      NotifyType.seasons => Icons.event_outlined,
      NotifyType.feasts => Icons.celebration_outlined,
      NotifyType.reminders => Icons.alarm_outlined,
    };

/// One link the scheduled-push picker offers.
class _LinkChoice {
  final String path, labelAr, labelEn, group, eventKey;
  const _LinkChoice(this.path, this.labelAr, this.labelEn, this.group, {this.eventKey = ''});
}

/// Notification manager tab.
class NotificationsAdminSection extends StatefulWidget {
  final AdminBackend repo;
  final String role;

  /// Device notification test (injectable for tests).
  final PushEnv pushEnv;
  const NotificationsAdminSection({super.key, required this.repo, this.role = 'editor', this.pushEnv = const PlatformPushEnv()});

  @override
  State<NotificationsAdminSection> createState() => _NotificationsAdminSectionState();
}

class _NotificationsAdminSectionState extends State<NotificationsAdminSection> with AutomaticKeepAliveClientMixin {
  // Keep unsaved edits when the admin switches to the «تثبيت التطبيق» tab.
  @override
  bool get wantKeepAlive => true;

  late final Stream<AdminDoc?> _featuresStream = widget.repo.watchDoc('settings/features');
  late final Stream<AdminDoc?> _notificationsStream = widget.repo.watchDoc('settings/notifications');

  // ---- settings/features form (saved with the bottom bar) ----
  bool _saving = false;
  bool _dirty = false;
  bool _populating = false;
  AdminDoc? _lastFeatures;
  Map<String, dynamic> _featuresData = const {};
  bool _showErrors = false;
  String? _leadsNote;

  bool _pushEnabled = false;
  final TextEditingController _vapidCtrl = TextEditingController();
  final Set<NotifyType> _offeredTypes = Set.of(NotifyType.values);
  final Set<int> _reminderLeads = {0, 15, 60, 1440};
  int _reminderDefaultLead = 60;
  final Set<String> _reminderSources = {'lit', 'mtg', 'day'};
  final Map<NotifyType, Map<String, TextEditingController>> _typeCtrls = {};

  Map<String, dynamic>? _topicsMeta;
  Map<String, dynamic>? _planMeta;

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

  DateTime? _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    return null;
  }

  // ---- scheduled announcement editor ----
  bool _editorOpen = false;
  bool _editingExisting = false;
  String _draftId = '';
  bool _draftSoon = false;
  DateTime _draftDay = DateTime(2026);
  int _draftMinutes = 19 * 60;
  String _draftTargets = 'all';
  String _draftLink = '/';
  String _draftLinkLabelAr = 'الرئيسية';
  String _draftLinkLabelEn = 'Home';
  String _draftEventKey = '';
  String? _draftError;
  bool _previewEnglish = false;
  final TextEditingController _draftTitleAr = TextEditingController();
  final TextEditingController _draftTitleEn = TextEditingController();
  final TextEditingController _draftBodyAr = TextEditingController();
  final TextEditingController _draftBodyEn = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final type in NotifyType.values) {
      final def = NotifyTypeSpec.builtInDefaults[type]!;
      _typeCtrls[type] = {
        'time': TextEditingController(text: def.time),
        'daysBefore': TextEditingController(text: '${def.daysBefore}'),
        'titleAr': TextEditingController(text: def.titleAr),
        'titleEn': TextEditingController(text: def.titleEn),
        'bodyAr': TextEditingController(text: def.bodyAr),
        'bodyEn': TextEditingController(text: def.bodyEn),
      };
      for (final c in _typeCtrls[type]!.values) {
        c.addListener(_markDirty);
      }
    }
    for (final c in [_draftTitleAr, _draftTitleEn, _draftBodyAr, _draftBodyEn]) {
      c.addListener(_onDraftChanged);
    }
    _loadWebHealth();
  }

  void _onDraftChanged() {
    if (mounted) setState(() => _draftError = null);
  }

  void _markDirty() {
    if (_populating || _dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _vapidCtrl.dispose();
    for (final map in _typeCtrls.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    for (final c in [_draftTitleAr, _draftTitleEn, _draftBodyAr, _draftBodyEn]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // settings/features: load + save
  // ---------------------------------------------------------------------------

  /// Copies the stored settings into the form. Runs only for a new snapshot
  /// and never while the admin has unsaved edits; controller listeners are
  /// muted so loading never marks the form dirty (the old screen called
  /// setState during build here).
  void _populateFeatures(AdminDoc? doc) {
    if (identical(doc, _lastFeatures) || _dirty) return;
    _lastFeatures = doc;
    final data = doc?.data ?? const <String, dynamic>{};
    _featuresData = data;
    final s = PushSettings.fromMap(data);
    _populating = true;
    try {
      _pushEnabled = s.enabled;
      _vapidCtrl.text = s.vapidKey;
      _offeredTypes
        ..clear()
        ..addAll(data['pushTypes'] is List ? s.offered : NotifyType.values);
      _reminderLeads
        ..clear()
        ..addAll(s.reminderLeads);
      _reminderDefaultLead = s.defaultLead;
      _reminderSources
        ..clear()
        ..addAll(s.reminderSources);
      final cfg = NotifyConfig.fromFeatures(FeatureSettings.fromMap(data));
      for (final type in NotifyType.values) {
        final spec = cfg.specFor(type);
        final c = _typeCtrls[type]!;
        c['time']!.text = spec.time;
        c['daysBefore']!.text = '${spec.daysBefore}';
        c['titleAr']!.text = spec.titleAr;
        c['titleEn']!.text = spec.titleEn;
        c['bodyAr']!.text = spec.bodyAr;
        c['bodyEn']!.text = spec.bodyEn;
      }
    } finally {
      _populating = false;
    }
  }

  /// First problem in the settings form (l10n key), or null.
  String? _settingsProblem() {
    if (!isValidVapidKey(_vapidCtrl.text.trim())) return 'nm_errVapid';
    for (final type in NotifyType.values) {
      final c = _typeCtrls[type]!;
      if (!isValidHm(c['time']!.text.trim())) return 'nm_errTime';
      for (final k in ['titleAr', 'titleEn', 'bodyAr', 'bodyEn']) {
        final t = c[k]!.text;
        if (unknownPlaceholders(type.name, t).isNotEmpty) return 'err_unknown_placeholder';
        if (t.contains('\u001f') || t.contains('\u001e')) return 'err_bad_char';
      }
    }
    return null;
  }

  Future<void> _saveSettings() async {
    final problem = _settingsProblem();
    if (problem != null) {
      setState(() => _showErrors = true);
      _snack(context.tr(problem), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final rows = <String>[];
      for (final type in NotifyType.values) {
        final c = _typeCtrls[type]!;
        final def = NotifyTypeSpec.builtInDefaults[type]!;
        String v(String k) => c[k]!.text.trim();
        final days = type == NotifyType.seasons ? v('daysBefore') : '';
        final modified = v('time') != def.time ||
            (type == NotifyType.seasons && days != '${def.daysBefore}') ||
            v('titleAr') != def.titleAr ||
            v('titleEn') != def.titleEn ||
            v('bodyAr') != def.bodyAr ||
            v('bodyEn') != def.bodyEn;
        if (modified) {
          rows.add([type.name, v('time'), days, v('titleAr'), v('titleEn'), v('bodyAr'), v('bodyEn')].join('\u001f'));
        }
      }
      final leads = _reminderLeads.toList()..sort();
      await widget.repo.saveDoc('settings/features', {
        'push': _pushEnabled,
        'pushVapidKey': _vapidCtrl.text.trim(),
        'pushTypes': [for (final t in NotifyType.values) if (_offeredTypes.contains(t)) t.name],
        'reminderLeads': leads,
        'reminderDefaultLead': leads.contains(_reminderDefaultLead) ? _reminderDefaultLead : leads.first,
        'reminderSources': [for (final s in const ['lit', 'mtg', 'day']) if (_reminderSources.contains(s)) s].join(','),
        'notifyTypes': rows,
      });
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _showErrors = false;
      });
      _snack(context.tr('nm_settingsSaved'));
    } catch (e) {
      if (mounted) _snack(context.tr('nm_saveFailed', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discardSettings() async {
    final ok = await _confirm(
      title: context.tr('nm_discardTitle'),
      body: context.tr('nm_discardBody'),
      action: context.tr('nm_discard'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _dirty = false;
      _showErrors = false;
      final doc = _lastFeatures;
      _lastFeatures = null;
      _populateFeatures(doc);
    });
  }

  // ---------------------------------------------------------------------------
  // settings/notifications: scheduled announcements
  // ---------------------------------------------------------------------------

  void _openEditor({ScheduledNotification? row, bool retry = false}) {
    final now = CairoTime.now();
    setState(() {
      _editorOpen = true;
      _editingExisting = row != null && !retry;
      _draftError = null;
      _previewEnglish = false;
      _draftId = _editingExisting ? row!.id : DayEvent.generateRandomId();
      if (row != null && !retry) {
        final c = CairoTime.fromInstant(row.atUtc);
        _draftSoon = false;
        _draftDay = DateTime(c.year, c.month, c.day);
        _draftMinutes = c.hour * 60 + c.minute;
      } else {
        // New: tomorrow 9 AM Cairo is a sane default; a retry goes out soon.
        final t = DateTime(now.year, now.month, now.day + 1);
        _draftSoon = retry;
        _draftDay = t;
        _draftMinutes = 9 * 60;
      }
      _draftTargets = row?.targets ?? 'all';
      _draftTitleAr.text = row?.titleAr ?? '';
      _draftTitleEn.text = row?.titleEn ?? '';
      _draftBodyAr.text = row?.bodyAr ?? '';
      _draftBodyEn.text = row?.bodyEn ?? '';
      _draftLink = row?.link ?? '/';
      _draftEventKey = row?.eventKey ?? '';
      _draftLinkLabelAr = _linkName(_draftLink);
      if (_draftEventKey.isNotEmpty) _draftLinkLabelAr = '$_draftLinkLabelAr${context.tr('nm_linkedEventSuffix')}';
      _draftLinkLabelEn = _draftLinkLabelAr;
      if (retry && row != null) {
        _draftTargets = _retryTargets(row);
      }
      _draftTitleAr.selection = TextSelection.collapsed(offset: _draftTitleAr.text.length);
    });
  }

  NotifySchedule _schedule = const NotifySchedule();

  String _retryTargets(ScheduledNotification row) =>
      _schedule.cloneDraftForRetry(row, row.id, row.atUtc).targets;

  LinkTargetLike? _knownLink(String path) {
    for (final t in builtInLinkTargets) {
      if (t.path == path) return LinkTargetLike(t.labelAr, t.labelEn);
    }
    return null;
  }

  /// Friendly name of a stored link for the row cards; unknown paths are
  /// shown left-to-right isolated so RTL text does not scramble them.
  String _linkName(String path) {
    final named = _knownLink(path);
    if (named != null) return context.pick(named.labelAr, named.labelEn);
    if (path.startsWith('/church-education/')) return context.tr('nm_meetingPage');
    if (path.startsWith('/page/') || path.startsWith('/section/')) return context.tr('nm_customPage', {'p': '\u2066$path\u2069'});
    return '\u2066$path\u2069';
  }

  DateTime get _draftAtUtc => _draftSoon
      ? DateTime.now().toUtc()
      : CairoTime.at(_draftDay.year, _draftDay.month, _draftDay.day, _draftMinutes).toUtc();

  Future<void> _saveDraft() async {
    final row = ScheduledNotification(
      id: _draftId,
      atUtc: _draftAtUtc,
      targets: _draftTargets,
      titleAr: _draftTitleAr.text.trim(),
      titleEn: _draftTitleEn.text.trim(),
      bodyAr: _draftBodyAr.text.trim(),
      bodyEn: _draftBodyEn.text.trim(),
      link: safeNotificationLink(_draftLink),
      eventKey: _draftEventKey,
    );
    final err = validateScheduledNotification(row);
    if (err != null) {
      setState(() => _draftError = err);
      return;
    }
    if (!_draftSoon && !row.atUtc.isAfter(DateTime.now().toUtc())) {
      setState(() => _draftError = 'nm_errPast');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.saveDocsFresh(['settings/notifications'], (current) {
        final fresh = NotifySchedule.fromDoc(current['settings/notifications']);
        final list = List<ScheduledNotification>.of(fresh.schedule);
        final idx = list.indexWhere((r) => r.id == row.id);
        if (_editingExisting) {
          if (idx < 0) throw _UserFacing('nm_errRowGone');
          if (!fresh.canEditRow(row.id)) throw _UserFacing('nm_errAlreadySending');
          list[idx] = row;
        } else {
          if (list.length >= 20) throw _UserFacing('nm_errFull');
          list.add(row);
        }
        return {
          'settings/notifications': {'schedule': [for (final r in list) r.toRow()]},
        };
      });
      if (!mounted) return;
      setState(() => _editorOpen = false);
      _snack(context.tr(_draftSoon ? 'nm_savedSoon' : 'nm_savedAt', {'when': _whenText(row.atUtc)}));
    } on _UserFacing catch (e) {
      if (mounted) setState(() => _draftError = e.key);
    } catch (e) {
      if (mounted) _snack(context.tr('nm_saveFailed', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRow(ScheduledNotification row) async {
    if (!_schedule.canDeleteRow(row.id)) {
      _snack(context.tr('err_cannot_delete_sending'), error: true);
      return;
    }
    final phase = _schedule.phaseOf(row, DateTime.now().toUtc());
    final ok = await _confirm(
      title: context.tr('nm_deleteTitle'),
      body: '«${row.titleAr}»\n\n${context.tr(phase == 'scheduled' || phase == 'queued' ? 'nm_deleteBodyPending' : 'nm_deleteBodyDone')}',
      action: context.tr('deleteRow'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.repo.saveDocsFresh(['settings/notifications'], (current) {
        final fresh = NotifySchedule.fromDoc(current['settings/notifications']);
        if (!fresh.canDeleteRow(row.id)) throw _UserFacing('err_cannot_delete_sending');
        return {
          'settings/notifications': {
            'schedule': [for (final r in fresh.schedule) if (r.id != row.id) r.toRow()],
          },
        };
      });
      if (!mounted) return;
      if (_editorOpen && _draftId == row.id) setState(() => _editorOpen = false);
      _snack(context.tr('nm_deleted'));
    } on _UserFacing catch (e) {
      if (mounted) _snack(context.tr(e.key), error: true);
    } catch (e) {
      if (mounted) _snack(context.tr('nm_saveFailed', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSentLog() async {
    final ok = await _confirm(
      title: context.tr('clearSentLog'),
      body: context.tr('clearLogConfirm'),
      action: context.tr('clearSentLog'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.repo.saveDoc('settings/notifications', {'sentLog': <String>[]});
      if (mounted) _snack(context.tr('nm_logCleared'));
    } catch (e) {
      if (mounted) _snack(context.tr('nm_saveFailed', {'e': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testOnDevice() async {
    final title = _draftTitleAr.text.trim().isNotEmpty ? _draftTitleAr.text.trim() : context.tr('nm_testTitle');
    final body = _draftBodyAr.text.trim().isNotEmpty ? _draftBodyAr.text.trim() : context.tr('nm_testBody');
    final ok = await widget.pushEnv.showLocalNotification(title, body, icon: '/icons/Icon-192.png');
    if (!mounted) return;
    if (ok) {
      _snack(context.tr('deviceTestSuccess'));
    } else {
      _snack(context.tr(widget.pushEnv.isSupported ? 'deviceTestPermDenied' : 'deviceTestUnsupported'), error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Link / event picker
  // ---------------------------------------------------------------------------

  Future<List<AdminDoc>> _read(String collection) async {
    try {
      return await widget.repo.watch(collection).first.timeout(const Duration(seconds: 10));
    } catch (_) {
      return const [];
    }
  }

  /// One-off reads when the picker opens (no listener stays open).
  Future<List<_LinkChoice>> _loadLinkChoices() async {
    final results = await Future.wait([
      _read('pages'),
      _read('categories'),
      _read('liturgies'),
      _read('meetings'),
      _read('seasons'),
    ]);
    String s(AdminDoc d, String k) => '${d.data[k] ?? ''}'.trim();
    final out = <_LinkChoice>[
      for (final t in builtInLinkTargets) _LinkChoice(t.path, t.labelAr, t.labelEn, 'pages'),
      for (final p in results[0])
        if (isValidSlug(s(p, 'slug'))) _LinkChoice(customPagePath(s(p, 'slug')), s(p, 'titleAr'), s(p, 'titleEn'), 'pages'),
      for (final c in results[1])
        if (isValidSlug(s(c, 'slug'))) _LinkChoice(categoryPath(s(c, 'slug')), s(c, 'nameAr'), s(c, 'nameEn'), 'pages'),
    ];
    void addEvent(String group, String path, String key, String ar, String en) {
      if (ar.isEmpty && en.isEmpty) return;
      // Only ids the rules accept become an event link; others still open the page.
      out.add(_LinkChoice(path, ar.isEmpty ? en : ar, en.isEmpty ? ar : en, group, eventKey: isValidPushEventKey(key) ? key : ''));
    }

    for (final d in results[2]) {
      addEvent('liturgies', '/mass-schedule', EventKey.liturgy(d.id), s(d, 'nameAr'), s(d, 'nameEn'));
    }
    for (final d in results[3]) {
      addEvent('meetings', detailPathFor(DetailKind.meeting, d.id), EventKey.meeting(d.id), s(d, 'nameAr'), s(d, 'nameEn'));
    }
    for (final d in results[4]) {
      addEvent('seasons', '/mass-schedule', EventKey.seasonService(d.id), s(d, 'nameAr'), s(d, 'nameEn'));
    }
    for (final e in DayEvent.listFrom(_featuresData['dayEvents'])) {
      addEvent('dayEvents', '/', EventKey.dayEvent(e.id), e.titleAr, e.titleEn);
    }
    return out;
  }

  Future<void> _pickLink() async {
    final picked = await showDialog<_LinkChoice>(
      context: context,
      builder: (ctx) => _LinkPickerDialog(load: _loadLinkChoices),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draftLink = picked.path;
      _draftEventKey = picked.eventKey;
      _draftLinkLabelAr = picked.labelAr;
      _draftLinkLabelEn = picked.labelEn;
      _draftError = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? context.pal.alert : null,
    ));
  }

  Future<bool> _confirm({required String title, required String body, required String action, bool destructive = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(key: const ValueKey('confirm-cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            key: const ValueKey('confirm-ok'),
            style: destructive ? FilledButton.styleFrom(backgroundColor: context.pal.alert, foregroundColor: context.pal.onPrimary) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  String _digits(String s) => context.isAr ? toArabicDigits(s) : s;

  String _hmText(int minutes) {
    final hm = '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    return context.isAr ? formatTimeArabic(hm) : formatTimeLatin(hm);
  }

  /// «الثلاثاء ١٠ نوفمبر، ٧:٠٠ م» in Cairo time.
  String _whenText(DateTime utc) {
    final c = CairoTime.fromInstant(utc);
    final day = '${weekdayName(c.weekday, arabic: context.isAr)} ${formatDayMonth(DateTime(c.year, c.month, c.day), arabic: context.isAr)}';
    return '$day${context.isAr ? '،' : ','} ${_hmText(c.hour * 60 + c.minute)}';
  }

  /// «منذ ١٢ دقيقة» / «12 min ago».
  String _ago(DateTime utc) {
    final d = DateTime.now().toUtc().difference(utc);
    if (d.inMinutes < 1) return context.tr('nm_justNow');
    String unit(int n, String one, String two, String few, String many) {
      if (!context.isAr) return '';
      if (n == 1) return one;
      if (n == 2) return two;
      return '${toArabicDigits('$n')} ${n <= 10 ? few : many}';
    }

    if (d.inMinutes < 60) {
      final n = d.inMinutes;
      return context.isAr ? 'منذ ${unit(n, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}' : '$n min ago';
    }
    if (d.inHours < 48) {
      final n = d.inHours;
      return context.isAr ? 'منذ ${unit(n, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}' : '$n h ago';
    }
    final n = d.inDays;
    return context.isAr ? 'منذ ${unit(n, 'يوم', 'يومين', 'أيام', 'يومًا')}' : '$n days ago';
  }

  Widget _chip({
    Key? key,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    IconData? icon,
    bool filter = false,
  }) {
    final style = TextStyle(color: selected ? context.pal.onBar : context.pal.primary, fontWeight: FontWeight.w600);
    final avatar = icon == null ? null : Icon(icon, size: 18, color: selected ? context.pal.onBar : context.pal.primary);
    return filter
        ? FilterChip(
            key: key,
            label: Text(label),
            avatar: selected ? null : avatar,
            selected: selected,
            checkmarkColor: context.pal.onBar,
            labelStyle: style,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: onSelected,
          )
        : ChoiceChip(
            key: key,
            label: Text(label),
            avatar: avatar,
            selected: selected,
            showCheckmark: false,
            labelStyle: style,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: onSelected,
          );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    registerStrings(_notificationsAdminStrings);
    return StreamBuilder<AdminDoc?>(
      stream: _featuresStream,
      builder: (context, featSnap) {
        if (featSnap.connectionState != ConnectionState.waiting) _populateFeatures(featSnap.data);
        return StreamBuilder<AdminDoc?>(
          stream: _notificationsStream,
          builder: (context, notifSnap) {
            _schedule = NotifySchedule.fromDoc(notifSnap.data?.data);
            return Scaffold(
              backgroundColor: context.pal.background,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    key: const ValueKey('notifications-admin-list'),
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 40),
                    children: [
                      _statusCard(context),
                      const SizedBox(height: 16),
                      _scheduledSection(context),
                      const SizedBox(height: 16),
                      _typesSection(context),
                      const SizedBox(height: 16),
                      _remindSection(context),
                      const SizedBox(height: 16),
                      _sentLogSection(context),
                      const SizedBox(height: 16),
                      _advancedSection(context),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: _dirty ? _saveBar(context) : null,
            );
          },
        );
      },
    );
  }

  Widget _saveBar(BuildContext context) => Material(
        color: context.pal.surface,
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_note, color: context.pal.goldText),
                  const SizedBox(width: 6),
                  Flexible(child: Text(context.tr('nm_unsaved'), style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
                Wrap(spacing: 8, children: [
                  TextButton(
                    key: const ValueKey('discard-settings'),
                    onPressed: _saving ? null : _discardSettings,
                    child: Text(context.tr('nm_discard')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('save-settings'),
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onPrimary))
                        : const Icon(Icons.save_outlined),
                    label: Text(context.tr('nm_saveSettings')),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );

  // ---- section scaffolding ----

  Widget _section(BuildContext context,
      {required Key key, required IconData icon, required String title, String? subtitle, Widget? trailing, required List<Widget> children}) {
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: context.pal.primary.withValues(alpha: 0.12),
                  child: Icon(icon, color: context.pal.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: context.pal.muted, fontSize: 13, height: 1.4)),
                    ],
                  ]),
                ),
              ],
            ),
            if (trailing != null) ...[const SizedBox(height: 12), trailing],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _banner(BuildContext context, {required IconData icon, required Color color, required String text, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: context.pal.ink, height: 1.45))),
        ]),
      );

  // ---- 1. status ----

  Widget _statusCard(BuildContext context) {
    final health = _schedule.health;
    final last = health.lastRunAt;
    final age = last == null ? null : DateTime.now().toUtc().difference(last);
    final (Color color, IconData icon, String title, String detail) = switch (age) {
      null => (context.pal.muted, Icons.hourglass_empty, context.tr('nm_senderNever'), context.tr('nm_senderNeverHint')),
      final a when a > const Duration(hours: 3) || health.status == 'error' =>
        (context.pal.alert, Icons.error_outline, context.tr('nm_senderStopped'), context.tr('nm_senderStoppedHint')),
      final a when a > const Duration(hours: 1) =>
        (context.pal.goldText, Icons.warning_amber_outlined, context.tr('nm_senderLate'), context.tr('nm_senderLateHint')),
      _ => (context.pal.success, Icons.check_circle_outline, context.tr('nm_senderOk'), context.tr('nm_senderOkHint')),
    };
    return _section(
      context,
      key: const ValueKey('nm-status'),
      icon: Icons.notifications_active_outlined,
      title: context.tr('nm_statusTitle'),
      subtitle: context.tr('nm_statusSubtitle'),
      children: [
        SwitchListTile(
          key: const ValueKey('push-master-switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('nm_masterSwitch'), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(context.tr(_pushEnabled ? 'nm_masterOnHint' : 'nm_masterOffHint')),
          value: _pushEnabled,
          onChanged: (v) => setState(() {
            _pushEnabled = v;
            _markDirty();
          }),
        ),
        if (!_pushEnabled) ...[
          const SizedBox(height: 4),
          _banner(context,
              key: const ValueKey('push-off-banner'), icon: Icons.notifications_off_outlined, color: context.pal.goldText, text: context.tr('nm_pushOffBanner')),
        ],
        const Divider(height: 28),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, key: const ValueKey('sender-health'), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
              if (last != null)
                Text(context.tr('nm_lastCheck', {'ago': _ago(last), 'when': _whenText(last)}),
                    style: TextStyle(color: context.pal.muted, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(detail, style: TextStyle(fontSize: 13, color: context.pal.ink, height: 1.4)),
              if (health.lastError != null && health.lastError!.isNotEmpty && age != null && age > const Duration(hours: 1))
                Text(context.tr('nm_lastError', {'e': health.lastError!}), style: TextStyle(fontSize: 12, color: context.pal.alert)),
            ]),
          ),
        ]),
        const Divider(height: 24),
        Text(context.tr('nm_webHealthTitle'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.pal.primaryDeep)),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final cronQueue = _topicsMeta?['cronQueue'] as Map?;
          final drainAt = _asDateTime(cronQueue?['lastDrainAt'] ?? _topicsMeta?['lastDrainAt']);
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
            final a when a > const Duration(hours: 7) =>
              (context.pal.goldText, context.tr('nm_webHealthPlanLate')),
            _ => (context.pal.success, context.tr('nm_webHealthPlanOk')),
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(drainColor == context.pal.success ? Icons.check_circle_outline : Icons.warning_amber_outlined, color: drainColor, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(drainText, style: TextStyle(color: drainColor, fontSize: 13))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(planColor == context.pal.success ? Icons.check_circle_outline : Icons.warning_amber_outlined, color: planColor, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(planText, style: TextStyle(color: planColor, fontSize: 13))),
              ]),
              if (capReached) ...[
                const SizedBox(height: 8),
                _banner(context, icon: Icons.warning_amber_rounded, color: context.pal.alert, text: context.tr('nm_webHealthCapBanner')),
              ],
            ],
          );
        }),
      ],
    );
  }

  // ---- 2. scheduled announcements ----

  Widget _scheduledSection(BuildContext context) {
    final now = DateTime.now().toUtc();
    final rows = List<ScheduledNotification>.of(_schedule.schedule);
    final pending = rows.where((r) => const {'scheduled', 'queued', 'sending'}.contains(_schedule.phaseOf(r, now))).toList()
      ..sort((a, b) => a.atUtc.compareTo(b.atUtc));
    final done = rows.where((r) => !pending.contains(r)).toList()..sort((a, b) => b.atUtc.compareTo(a.atUtc));
    final full = rows.length >= 20;
    return _section(
      context,
      key: const ValueKey('nm-scheduled'),
      icon: Icons.campaign_outlined,
      title: context.tr('nm_scheduledTitle'),
      subtitle: context.tr('nm_scheduledSubtitle'),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('addScheduledPush'),
            icon: const Icon(Icons.add),
            label: Text(context.tr('addScheduledPush')),
            onPressed: full || _editorOpen ? null : () => _openEditor(),
          ),
          Text(context.tr('nm_countOf20', {'n': _digits('${rows.length}')}), style: TextStyle(color: context.pal.muted, fontSize: 12.5)),
        ],
      ),
      children: [
        if (full) ...[
          _banner(context, icon: Icons.info_outline, color: context.pal.goldText, text: context.tr('nm_fullHint')),
          const SizedBox(height: 8),
        ],
        if (_editorOpen) _editor(context),
        if (rows.isEmpty && !_editorOpen)
          Padding(
            key: const ValueKey('schedule-empty'),
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Icon(Icons.outbox_outlined, size: 36, color: context.pal.muted),
              const SizedBox(height: 6),
              Text(context.tr('emptySchedule'), textAlign: TextAlign.center, style: TextStyle(color: context.pal.muted)),
            ]),
          ),
        if (pending.isNotEmpty) _subhead(context, context.tr('nm_upcoming')),
        for (final r in pending) _rowCard(context, r),
        if (done.isNotEmpty) _subhead(context, context.tr('nm_past')),
        for (final r in done) _rowCard(context, r),
      ],
    );
  }

  Widget _subhead(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: context.pal.muted, fontSize: 13)),
      );

  (String, Color, IconData) _phaseLook(String phase) => switch (phase) {
        'scheduled' => (context.tr('statusScheduled'), context.pal.primary, Icons.schedule),
        'queued' => (context.tr('statusQueued'), context.pal.primary, Icons.hourglass_top),
        'sending' => (context.tr('statusSending'), context.pal.goldText, Icons.send_outlined),
        'ok' => (context.tr('statusSent'), context.pal.success, Icons.check_circle_outline),
        'partial' => (context.tr('statusPartial'), context.pal.goldText, Icons.rule),
        'unconfirmed' => (context.tr('statusUnconfirmed'), context.pal.alert, Icons.help_outline),
        'expired' => (context.tr('statusExpired'), context.pal.muted, Icons.event_busy_outlined),
        _ => (context.tr('statusError'), context.pal.alert, Icons.error_outline),
      };

  (String, IconData) _targetLook(String t) => switch (t) {
        'app' => (context.tr('pushTargetApp'), Icons.android),
        'web' => (context.tr('pushTargetWeb'), Icons.language),
        _ => (context.tr('pushTargetAll'), Icons.devices),
      };

  Widget _meta(BuildContext context, IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.pal.muted),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: context.pal.muted), overflow: TextOverflow.ellipsis)),
      ]);

  Widget _rowCard(BuildContext context, ScheduledNotification row) {
    final now = DateTime.now().toUtc();
    final phase = _schedule.phaseOf(row, now);
    final (label, color, icon) = _phaseLook(phase);
    final (tLabel, tIcon) = _targetLook(row.targets);
    final linkText = _linkName(row.link);
    final canEdit = _schedule.canEditRow(row.id) && !_editorOpen;
    final canRetry = const {'partial', 'error', 'unconfirmed', 'expired'}.contains(phase) && !_editorOpen && _schedule.schedule.length < 20;
    final explain = context.tr('nm_phase_$phase');
    return Container(
      key: ValueKey('row-${row.id}'),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(start: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: context.pal.shadow(0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
            Text(_whenText(row.atUtc), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        Text(row.titleAr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        if (row.bodyAr.isNotEmpty) Text(row.bodyAr, style: TextStyle(color: context.pal.muted, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _meta(context, tIcon, tLabel),
          _meta(context, row.eventKey.isNotEmpty ? Icons.event_available_outlined : Icons.open_in_new, context.tr('nm_opens', {'page': linkText})),
          if (row.titleEn.isNotEmpty) _meta(context, Icons.translate, context.tr('nm_hasEnglish')),
        ]),
        if (explain != 'nm_phase_$phase') ...[
          const SizedBox(height: 6),
          Text(explain, style: TextStyle(fontSize: 12.5, color: color == context.pal.muted ? context.pal.muted : context.pal.ink)),
        ],
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(spacing: 4, children: [
            if (canEdit)
              TextButton.icon(
                key: ValueKey('edit-${row.id}'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.tr('nm_edit')),
                onPressed: () => _openEditor(row: row),
              ),
            if (canRetry)
              TextButton.icon(
                key: ValueKey('retry-${row.id}'),
                icon: const Icon(Icons.replay, size: 18),
                label: Text(context.tr('cloneForRetry')),
                onPressed: () => _openEditor(row: row, retry: true),
              ),
            if (_schedule.canDeleteRow(row.id))
              TextButton.icon(
                key: ValueKey('delete-${row.id}'),
                icon: Icon(Icons.delete_outline, size: 18, color: context.pal.alert),
                label: Text(context.tr('deleteRow'), style: TextStyle(color: context.pal.alert)),
                onPressed: _saving ? null : () => _deleteRow(row),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _step(BuildContext context, String n, String title, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: context.pal.primary,
            child: Text(n, style: TextStyle(color: context.pal.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (hint != null) Text(hint, style: TextStyle(fontSize: 12.5, color: context.pal.muted, height: 1.4)),
            ]),
          ),
        ]),
      );

  Widget _editor(BuildContext context) {
    final err = _draftError;
    String? fieldErr(Set<String> keys) => err != null && keys.contains(err) ? context.tr(err) : null;
    return Padding(
      key: const ValueKey('push-editor'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
      color: context.pal.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.pal.primary.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(context.tr(_editingExisting ? 'nm_editTitle' : 'nm_newTitle'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          IconButton(
            key: const ValueKey('editor-close'),
            tooltip: context.tr('cancel'),
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _editorOpen = false),
          ),
        ]),
        // Step 1: text
        _step(context, _digits('1'), context.tr('nm_stepText'), hint: context.tr('nm_stepTextHint')),
        TextField(
          key: const ValueKey('draft-titleAr'),
          controller: _draftTitleAr,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: context.tr('nm_titleArLabel'),
            hintText: context.tr('nm_titleArHint'),
            errorText: fieldErr({'err_title_required', 'err_title_length'}),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('draft-bodyAr'),
          controller: _draftBodyAr,
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.tr('nm_bodyArLabel'),
            hintText: context.tr('nm_bodyArHint'),
            errorText: fieldErr({'err_body_required', 'err_body_length'}),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('draft-english'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _draftTitleEn.text.isNotEmpty || _draftBodyEn.text.isNotEmpty,
            leading: const Icon(Icons.translate),
            title: Text(context.tr('nm_englishOptional')),
            subtitle: Text(context.tr('nm_englishOptionalHint'), style: TextStyle(fontSize: 12, color: context.pal.muted)),
            children: [
              TextField(
                key: const ValueKey('draft-titleEn'),
                controller: _draftTitleEn,
                maxLength: 120,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: context.tr('nm_titleEnLabel')),
              ),
              TextField(
                key: const ValueKey('draft-bodyEn'),
                controller: _draftBodyEn,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: context.tr('nm_bodyEnLabel')),
              ),
            ],
          ),
        ),
        // Step 2: when
        _step(context, _digits('2'), context.tr('nm_stepWhen'), hint: context.tr('nm_stepWhenHint')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(
            key: const ValueKey('when-soon'),
            label: context.tr('sendAtEarliest'),
            icon: Icons.bolt,
            selected: _draftSoon,
            onSelected: (_) => setState(() => _draftSoon = true),
          ),
          _chip(
            key: const ValueKey('when-at'),
            label: context.tr('nm_whenAt'),
            icon: Icons.event,
            selected: !_draftSoon,
            onSelected: (_) => setState(() => _draftSoon = false),
          ),
        ]),
        if (!_draftSoon) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('pick-date'),
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${weekdayName(_draftDay.weekday, arabic: context.isAr)} ${formatDate(_draftDay, arabic: context.isAr)}'),
              onPressed: () async {
                final today = CairoTime.now();
                final first = DateTime(today.year, today.month, today.day);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _draftDay.isBefore(first) ? first : _draftDay,
                  firstDate: first,
                  lastDate: first.add(const Duration(days: 120)),
                );
                if (picked != null) setState(() => _draftDay = DateTime(picked.year, picked.month, picked.day));
              },
            ),
            OutlinedButton.icon(
              key: const ValueKey('pick-time'),
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(_hmText(_draftMinutes)),
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: _draftMinutes ~/ 60, minute: _draftMinutes % 60),
                );
                if (picked != null) setState(() => _draftMinutes = picked.hour * 60 + picked.minute);
              },
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            context.tr('nm_whenSummary', {'when': _whenText(_draftAtUtc)}),
            key: const ValueKey('when-summary'),
            style: TextStyle(fontSize: 12.5, color: fieldErr({'nm_errPast'}) != null ? context.pal.alert : context.pal.muted),
          ),
          if (fieldErr({'nm_errPast'}) != null)
            Text(context.tr('nm_errPast'), style: TextStyle(color: context.pal.alert, fontSize: 12.5)),
        ],
        // Step 3: who
        _step(context, _digits('3'), context.tr('nm_stepWho'), hint: context.tr('nm_stepWhoHint')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in const ['all', 'app', 'web'])
            _chip(
              key: ValueKey('target-$t'),
              label: _targetLook(t).$1,
              icon: _targetLook(t).$2,
              selected: _draftTargets == t,
              onSelected: (_) => setState(() => _draftTargets = t),
            ),
        ]),
        // Step 4: link
        _step(context, _digits('4'), context.tr('nm_stepLink'), hint: context.tr('nm_stepLinkHint')),
        InkWell(
          key: const ValueKey('pick-link'),
          borderRadius: BorderRadius.circular(10),
          onTap: _pickLink,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: context.tr('deepLinkTarget'),
              errorText: fieldErr({'err_bad_link', 'err_invalid_event_key'}),
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Row(children: [
              Icon(_draftEventKey.isNotEmpty ? Icons.event_available_outlined : Icons.web_outlined, size: 18, color: context.pal.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(context.pick(_draftLinkLabelAr, _draftLinkLabelEn), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
        // Step 5: preview
        _step(context, _digits('5'), context.tr('previewCardTitle')),
        Wrap(spacing: 8, children: [
          _chip(label: 'عربي', selected: !_previewEnglish, onSelected: (_) => setState(() => _previewEnglish = false)),
          _chip(label: 'English', selected: _previewEnglish, onSelected: (_) => setState(() => _previewEnglish = true)),
        ]),
        const SizedBox(height: 8),
        _preview(context),
        if (err != null && fieldErr({'err_title_required', 'err_title_length', 'err_body_required', 'err_body_length', 'nm_errPast', 'err_bad_link', 'err_invalid_event_key'}) == null) ...[
          const SizedBox(height: 10),
          _banner(context, key: const ValueKey('draft-error'), icon: Icons.error_outline, color: context.pal.alert, text: context.tr(err)),
        ],
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('test-device'),
              icon: const Icon(Icons.phone_android_outlined),
              label: Text(context.tr('testOnDevice')),
              onPressed: _testOnDevice,
            ),
            Wrap(spacing: 8, children: [
              TextButton(onPressed: () => setState(() => _editorOpen = false), child: Text(context.tr('cancel'))),
              FilledButton.icon(
                key: const ValueKey('save-push'),
                icon: _saving
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onPrimary))
                    : const Icon(Icons.check),
                label: Text(context.tr(_editingExisting ? 'nm_saveChanges' : 'nm_schedule')),
                onPressed: _saving ? null : _saveDraft,
              ),
            ]),
          ],
        ),
      ]),
      ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final en = _previewEnglish;
    String pick(TextEditingController enC, TextEditingController arC) => en && enC.text.trim().isNotEmpty ? enC.text.trim() : arC.text.trim();
    final title = pick(_draftTitleEn, _draftTitleAr);
    final body = pick(_draftBodyEn, _draftBodyAr);
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Container(
        key: const ValueKey('push-preview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.pal.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: context.pal.shadow(0.10), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 18, backgroundColor: context.pal.primary, child: Icon(Icons.church, color: context.pal.onPrimary, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(en ? 'Sts Maximus & Domadius Church' : 'كنيسة القديسين مكسيموس ودوماديوس',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.pal.muted)),
                ),
                Text(en ? 'now' : 'الآن', style: TextStyle(fontSize: 11, color: context.pal.muted)),
              ]),
              const SizedBox(height: 3),
              Text(title.isEmpty ? context.tr('nm_previewTitle') : title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: title.isEmpty ? context.pal.muted : context.pal.ink)),
              Text(body.isEmpty ? context.tr('nm_previewBody') : body,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.pal.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---- 3. types ----

  Widget _typesSection(BuildContext context) {
    return _section(
      context,
      key: const ValueKey('nm-types'),
      icon: Icons.tune,
      title: context.tr('notifyTypesSection'),
      subtitle: context.tr('nm_typesSubtitle'),
      children: [
        if (_offeredTypes.isEmpty)
          _banner(context, icon: Icons.info_outline, color: context.pal.goldText, text: context.tr('nm_noTypesOffered')),
        for (final t in NotifyType.values) _typeTile(context, t),
      ],
    );
  }

  Widget _typeTile(BuildContext context, NotifyType type) {
    final ctrls = _typeCtrls[type]!;
    final def = NotifyTypeSpec.builtInDefaults[type]!;
    final offered = _offeredTypes.contains(type);
    final how = switch (type) {
      NotifyType.announcements || NotifyType.seasons => context.tr('channelBadgeRemote'),
      NotifyType.reminders => context.tr('channelBadgeHybrid'),
      _ => context.tr('channelBadgeLocal'),
    };
    final time = ctrls['time']!.text.trim();
    final summary = [
      if (_timedTypes.contains(type) && isValidHm(time) && time.isNotEmpty) context.tr('nm_atTime', {'t': context.isAr ? formatTimeArabic(time) : formatTimeLatin(time)}),
      if (type == NotifyType.seasons) _daysLabel(int.tryParse(ctrls['daysBefore']!.text.trim()) ?? def.daysBefore),
    ].join(' · ');
    return Padding(
      key: ValueKey('type_${type.name}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
      color: context.pal.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: offered ? context.pal.primary.withValues(alpha: 0.35) : context.pal.hairline),
      ),
      child: Column(children: [
        SwitchListTile(
          key: ValueKey('offer-${type.name}'),
          secondary: Icon(_typeIcon(type), color: offered ? context.pal.primary : context.pal.muted),
          title: Text(context.pick(type.labelAr, type.labelEn), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${context.pick(type.descriptionAr, type.descriptionEn)}\n$how${summary.isEmpty ? '' : ' · $summary'}',
            style: TextStyle(fontSize: 12.5, color: context.pal.muted, height: 1.4),
          ),
          isThreeLine: true,
          value: offered,
          onChanged: (on) => setState(() {
            on ? _offeredTypes.add(type) : _offeredTypes.remove(type);
            _markDirty();
          }),
        ),
        if (type == NotifyType.announcements)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
            child: Text(context.tr('nm_announcementsNote'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
          ),
        if (_hasTemplate(type))
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('customize-${type.name}'),
              tilePadding: const EdgeInsetsDirectional.only(start: 16, end: 12),
              childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              title: Text(context.tr(_timedTypes.contains(type) ? 'nm_customizeTimeText' : 'nm_customizeText'),
                  style: TextStyle(fontSize: 13.5, color: context.pal.primary, fontWeight: FontWeight.w600)),
              children: [_typeEditor(context, type)],
            ),
          ),
      ]),
      ),
    );
  }

  String _daysLabel(int d) => d == 0 ? context.tr('nm_daysSame') : context.tr('nm_daysBefore', {'n': context.isAr ? context.dayCount(d) : '$d'});

  Widget _typeEditor(BuildContext context, NotifyType type) {
    final ctrls = _typeCtrls[type]!;
    final def = NotifyTypeSpec.builtInDefaults[type]!;
    final time = ctrls['time']!.text.trim();
    final timeBad = !isValidHm(time);
    final days = int.tryParse(ctrls['daysBefore']!.text.trim()) ?? def.daysBefore;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_timedTypes.contains(type)) ...[
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: ValueKey('time-${type.name}'),
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(time.isEmpty || timeBad
                ? context.tr('nm_pickTime')
                : context.tr('nm_sendTimeBtn', {'t': context.isAr ? formatTimeArabic(time) : formatTimeLatin(time)})),
            onPressed: () async {
              final parts = isValidHm(time) && time.isNotEmpty ? time.split(':') : def.time.split(':');
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
              );
              if (picked != null) {
                ctrls['time']!.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                setState(() {});
              }
            },
          ),
          if (type == NotifyType.seasons)
            DropdownButton<int>(
              key: const ValueKey('daysBefore-seasons'),
              value: days.clamp(0, 7),
              items: [for (var d = 0; d <= 7; d++) DropdownMenuItem(value: d, child: Text(_daysLabel(d)))],
              onChanged: (v) {
                if (v == null) return;
                ctrls['daysBefore']!.text = '$v';
                setState(() {});
              },
            ),
        ]),
        if (timeBad && _showErrors) Text(context.tr('nm_errTime'), style: TextStyle(color: context.pal.alert, fontSize: 12.5)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            context.tr(type == NotifyType.seasons
                ? 'nm_seasonsTimeHint'
                : (type == NotifyType.feasts ? 'nm_feastTimeHint' : 'nm_userTimeHint')),
            style: TextStyle(fontSize: 12.5, color: context.pal.muted, height: 1.4),
          ),
        ),
      ],
      _templateField(context, type, ctrls['titleAr']!, context.tr('nm_tplTitleAr'), 120),
      _templateField(context, type, ctrls['bodyAr']!, context.tr('nm_tplBodyAr'), 300, multiline: true),
      _templateField(context, type, ctrls['titleEn']!, context.tr('nm_tplTitleEn'), 120, ltr: true),
      _templateField(context, type, ctrls['bodyEn']!, context.tr('nm_tplBodyEn'), 300, multiline: true, ltr: true),
      _templateSample(context, type),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          key: ValueKey('reset-${type.name}'),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(context.tr('resetToDefault')),
          onPressed: () async {
            final ok = await _confirm(
              title: context.tr('resetToDefault'),
              body: context.tr('nm_resetBody', {'type': context.pick(type.labelAr, type.labelEn)}),
              action: context.tr('resetToDefault'),
            );
            if (!ok) return;
            ctrls['time']!.text = def.time;
            ctrls['daysBefore']!.text = '${def.daysBefore}';
            ctrls['titleAr']!.text = def.titleAr;
            ctrls['titleEn']!.text = def.titleEn;
            ctrls['bodyAr']!.text = def.bodyAr;
            ctrls['bodyEn']!.text = def.bodyEn;
            setState(() {});
          },
        ),
      ),
    ]);
  }

  Widget _templateField(BuildContext context, NotifyType type, TextEditingController c, String label, int max,
      {bool multiline = false, bool ltr = false}) {
    final placeholders = NotifyTypeSpec.builtInDefaults[type]!.allowedPlaceholders;
    final unknown = unknownPlaceholders(type.name, c.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: c,
          maxLength: max,
          minLines: multiline ? 2 : 1,
          maxLines: multiline ? 4 : 1,
          textDirection: ltr ? TextDirection.ltr : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            helperText: context.tr('nm_tplEmptyHint'),
            errorText: unknown.isEmpty ? null : context.tr('nm_errUnknownPh', {'ph': unknown.join('، ')}),
            errorMaxLines: 3,
          ),
        ),
        if (placeholders.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(context.tr('nm_insert'), style: TextStyle(fontSize: 12, color: context.pal.muted)),
            for (final ph in placeholders)
              ActionChip(
                key: ValueKey('ph-${type.name}-$ph'),
                avatar: Icon(Icons.add, size: 14, color: context.pal.primary),
                label: Text(context.pick(placeholderLabel(ph).$1, placeholderLabel(ph).$2), style: const TextStyle(fontSize: 12)),
                tooltip: ph,
                onPressed: () {
                  final text = c.text;
                  final sel = c.selection;
                  if (sel.isValid && sel.start >= 0) {
                    c.value = TextEditingValue(
                      text: text.replaceRange(sel.start, sel.end, ph),
                      selection: TextSelection.collapsed(offset: sel.start + ph.length),
                    );
                  } else {
                    c.text = '$text$ph';
                  }
                  setState(() {});
                },
              ),
          ]),
      ]),
    );
  }

  Widget _templateSample(BuildContext context, NotifyType type) {
    final c = _typeCtrls[type]!;
    final ar = context.isAr;
    final vars = ar ? placeholderSamplesAr : placeholderSamplesEn;
    final title = renderTemplate(c[ar ? 'titleAr' : 'titleEn']!.text, vars);
    final body = renderTemplate(c[ar ? 'bodyAr' : 'bodyEn']!.text, vars);
    return Container(
      key: ValueKey('sample-${type.name}'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: context.pal.surfaceAlt.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('nm_sampleLabel'), style: TextStyle(fontSize: 11.5, color: context.pal.muted)),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(body, style: TextStyle(color: context.pal.muted, fontSize: 13)),
      ]),
    );
  }

  // ---- 4. «ذكّرني» ----

  Widget _remindSection(BuildContext context) {
    final remindersOn = _offeredTypes.contains(NotifyType.reminders);
    final sources = [
      ('lit', Icons.church_outlined, 'srcLiturgies', 'nm_srcLiturgiesHint'),
      ('mtg', Icons.groups_outlined, 'srcMeetings', 'nm_srcMeetingsHint'),
      ('day', Icons.today_outlined, 'srcDayEvents', 'nm_srcDayHint'),
    ];
    final leads = _reminderLeads.toList()..sort();
    return _section(
      context,
      key: const ValueKey('nm-remind'),
      icon: Icons.alarm_outlined,
      title: context.tr('notifyRemindersCard'),
      subtitle: context.tr('nm_remindSubtitle'),
      children: [
        if (!remindersOn) ...[
          _banner(context, icon: Icons.info_outline, color: context.pal.goldText, text: context.tr('nm_remindersOff')),
          const SizedBox(height: 8),
        ],
        _banner(context, icon: Icons.info_outline, color: context.pal.muted, text: context.tr('nm_webPlannerDelayNotice')),
        const SizedBox(height: 12),
        Text(context.tr('reminderSourcesLabel'), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final s in sources)
          SwitchListTile(
            key: ValueKey('src-${s.$1}'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(s.$2, color: context.pal.primary),
            title: Text(context.tr(s.$3)),
            subtitle: Text(context.tr(s.$4), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
            value: _reminderSources.contains(s.$1),
            onChanged: (on) => setState(() {
              on ? _reminderSources.add(s.$1) : _reminderSources.remove(s.$1);
              _markDirty();
            }),
          ),
        const Divider(height: 24),
        Text(context.tr('nm_leadsLabel'), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(context.tr('nm_leadsHint'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in allowedReminderLeads)
            _chip(
              key: ValueKey('lead-$m'),
              filter: true,
              label: leadLabel(m, context.isAr ? 'ar' : 'en'),
              selected: _reminderLeads.contains(m),
              onSelected: (on) {
                // Inline note, not a snack bar: a snack bar would cover the
                // save bar at the bottom of the screen.
                if (on && _reminderLeads.length >= 4) {
                  setState(() => _leadsNote = 'nm_leadsMax');
                  return;
                }
                if (!on && _reminderLeads.length <= 1) {
                  setState(() => _leadsNote = 'nm_leadsMin');
                  return;
                }
                setState(() {
                  _leadsNote = null;
                  on ? _reminderLeads.add(m) : _reminderLeads.remove(m);
                  if (!_reminderLeads.contains(_reminderDefaultLead)) _reminderDefaultLead = (_reminderLeads.toList()..sort()).first;
                  _markDirty();
                });
              },
            ),
        ]),
        if (_leadsNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.tr(_leadsNote!), key: const ValueKey('leads-note'), style: TextStyle(color: context.pal.alert, fontSize: 12.5)),
          ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          key: ValueKey('default-lead-${leads.join(',')}'),
          initialValue: leads.contains(_reminderDefaultLead) ? _reminderDefaultLead : leads.first,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('nm_defaultLead'), helperText: context.tr('nm_defaultLeadHint'), helperMaxLines: 2),
          items: [for (final m in leads) DropdownMenuItem(value: m, child: Text(leadLabel(m, context.isAr ? 'ar' : 'en')))],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _reminderDefaultLead = v);
            _markDirty();
          },
        ),
      ],
    );
  }

  // ---- 5. sent log ----

  Widget _sentLogSection(BuildContext context) {
    final log = _schedule.sentLog.take(30).toList();
    return _section(
      context,
      key: const ValueKey('nm-log'),
      icon: Icons.history,
      title: context.tr('sentLogSection'),
      subtitle: context.tr('nm_logSubtitle'),
      trailing: widget.role == 'owner' && log.isNotEmpty
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('clear-log'),
                icon: Icon(Icons.delete_sweep_outlined, size: 18, color: context.pal.alert),
                label: Text(context.tr('clearSentLog'), style: TextStyle(color: context.pal.alert)),
                onPressed: _saving ? null : _clearSentLog,
              ),
            )
          : null,
      children: [
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(context.tr('emptySentLog'), textAlign: TextAlign.center, style: TextStyle(color: context.pal.muted)),
          ),
        for (final e in log) _logRow(context, e),
      ],
    );
  }

  Widget _logRow(BuildContext context, SentEntry e) {
    final state = e.result.isNotEmpty ? e.result : (e.webState == 'error' || e.appState == 'error' ? 'error' : 'ok');
    final (label, color, icon) = _phaseLook(switch (state) { 'ok' || 'partial' || 'unconfirmed' || 'expired' => state, _ => 'error' });
    final season = e.id.startsWith('season:');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(season ? Icons.event_outlined : Icons.campaign_outlined, size: 20, color: context.pal.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.titleAr.isEmpty ? '—' : e.titleAr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(
              '${_whenText(e.sentAt)} · ${context.tr(season ? 'nm_logSeason' : 'nm_logAnnouncement')}',
              style: TextStyle(fontSize: 12, color: context.pal.muted),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ]),
    );
  }

  // ---- 6. advanced ----

  Widget _advancedSection(BuildContext context) {
    final bad = !isValidVapidKey(_vapidCtrl.text.trim());
    return Card(
      key: const ValueKey('nm-advanced'),
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: bad && _showErrors,
          leading: Icon(Icons.settings_outlined, color: context.pal.muted),
          title: Text(context.tr('nm_advanced'), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(context.tr('nm_advancedHint'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              key: const ValueKey('vapid'),
              controller: _vapidCtrl,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(_markDirty),
              decoration: InputDecoration(
                labelText: context.tr('nm_vapidLabel'),
                helperText: context.tr('nm_vapidHint'),
                helperMaxLines: 4,
                errorText: bad ? context.tr('nm_errVapid') : null,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A friendly name for a stored link.
class LinkTargetLike {
  final String labelAr, labelEn;
  const LinkTargetLike(this.labelAr, this.labelEn);
}

class _UserFacing implements Exception {
  final String key;
  _UserFacing(this.key);
}

/// «اختر ما يفتح عند الضغط»: site pages, then events grouped by kind, then a
/// custom in-app path.
class _LinkPickerDialog extends StatefulWidget {
  final Future<List<_LinkChoice>> Function() load;
  const _LinkPickerDialog({required this.load});

  @override
  State<_LinkPickerDialog> createState() => _LinkPickerDialogState();
}

class _LinkPickerDialogState extends State<_LinkPickerDialog> {
  late final Future<List<_LinkChoice>> _future = widget.load();
  final _custom = TextEditingController();
  String? _customErr;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  static const _groups = [
    ('pages', Icons.web_outlined, 'nm_grpPages'),
    ('liturgies', Icons.church_outlined, 'nm_grpLiturgies'),
    ('meetings', Icons.groups_outlined, 'nm_grpMeetings'),
    ('dayEvents', Icons.today_outlined, 'nm_grpDayEvents'),
    ('seasons', Icons.event_outlined, 'nm_grpSeasons'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('nm_pickLinkTitle')),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<List<_LinkChoice>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            final all = snap.data!;
            return ListView(shrinkWrap: true, children: [
              for (final g in _groups)
                if (all.any((c) => c.group == g.$1)) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
                    child: Text(context.tr(g.$3), style: TextStyle(fontWeight: FontWeight.bold, color: context.pal.primary)),
                  ),
                  for (final c in all.where((c) => c.group == g.$1))
                    ListTile(
                      key: ValueKey('link-${c.group}-${c.path}-${c.eventKey}'),
                      dense: true,
                      leading: Icon(g.$2, size: 20),
                      title: Text(context.pick(c.labelAr, c.labelEn)),
                      subtitle: c.group == 'pages' ? null : Text(context.tr(c.eventKey.isEmpty ? 'nm_opensPageOnly' : 'nm_opensEvent')),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('custom-link'),
                  controller: _custom,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.tr('nm_customLink'),
                    hintText: '/page/donations',
                    errorText: _customErr,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        final v = _custom.text.trim();
                        if (!validNotificationLink(v) || safeNotificationLink(v) != v) {
                          setState(() => _customErr = context.tr('err_bad_link'));
                          return;
                        }
                        Navigator.pop(context, _LinkChoice(v, v, v, 'custom'));
                      },
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel')))],
    );
  }
}
