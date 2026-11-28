import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/attention.dart';
import '../../domain/cairo_time.dart';
import '../../domain/contact_categories.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart' show normalizeDigits, normalizeEgyptianPhone, usableWhatsappLink;
import '../widgets/cards.dart' show whatsappGreen;
import 'admin_access.dart';
import 'admin_schema.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';
import 'confirm_named.dart';
import 'doc_editor.dart';
import 'pending_delete.dart';
import 'screen_header.dart';
import 'state_switch.dart';

/// Counts open (new), non-soft-deleted messages in a snapshot.
int countUnreadMessages(Iterable<AdminDoc> docs) =>
    docs.where((d) => !isSoftDeleted(d.data) && messageIsOpen(d.data)).length;

/// Shared bounded live feed for `contact_messages` so the nav badge,
/// [OverviewScreen], and [MessagesScreen] share one Firestore listener.
class MessagesFeed extends ChangeNotifier {
  static const int pageSize = 50;

  final AdminBackend repo;
  int _limit;
  StreamSubscription<List<AdminDoc>>? _sub;
  List<AdminDoc>? _docs;
  Object? _error;
  bool _loadingMore = false;
  bool _disposed = false;

  MessagesFeed(this.repo, {int initialLimit = pageSize}) : _limit = initialLimit {
    _subscribe();
  }

  int get limit => _limit;
  List<AdminDoc>? get docs => _docs;
  Object? get error => _error;
  bool get hasData => _docs != null;
  bool get hasError => _error != null;
  bool get loadingMore => _loadingMore;
  bool get canLoadMore => _docs != null && _docs!.length >= _limit;
  int get unreadCount => countUnreadMessages(_docs ?? const <AdminDoc>[]);

  void _subscribe() {
    _sub?.cancel();
    _sub = repo.watchLatest('contact_messages', limit: _limit).listen(
      (data) {
        if (_disposed) return;
        _docs = data;
        _error = null;
        _loadingMore = false;
        notifyListeners();
      },
      onError: (Object err) {
        if (_disposed) return;
        if (_loadingMore) {
          _limit = (_limit - pageSize).clamp(pageSize, _limit);
        }
        _error = err;
        _loadingMore = false;
        notifyListeners();
      },
    );
  }

  void loadMore() {
    if (_disposed || _loadingMore || !canLoadMore) return;
    _limit += pageSize;
    _loadingMore = true;
    _error = null;
    notifyListeners();
    _subscribe();
  }

  void retry() {
    if (_disposed) return;
    _docs = null;
    _error = null;
    _loadingMore = false;
    notifyListeners();
    _subscribe();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

/// Exposes a shared [MessagesFeed] down the admin dashboard widget tree.
class MessagesFeedScope extends InheritedNotifier<MessagesFeed> {
  const MessagesFeedScope({super.key, required MessagesFeed feed, required super.child}) : super(notifier: feed);

  static MessagesFeed? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessagesFeedScope>()?.notifier;
}

/// Dashboard home: "Needs your attention" summary, 6 quick task buttons, latest edits.
class OverviewScreen extends StatefulWidget {
  final AdminBackend repo;
  final String role;
  final void Function(String screenId) onOpen;
  final DateTime Function()? now;
  const OverviewScreen({
    super.key,
    required this.repo,
    required this.role,
    required this.onOpen,
    this.now,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  static final Set<String> _watchedCollections = {
    for (final c in adminCollections) c.name,
  };
  static const _maxRefreshInterval = Duration(minutes: 1);
  static const _minRefreshDelay = Duration(milliseconds: 50);
  static const _streamTimeout = Duration(seconds: 10);

  /// Latest docs per collection (null = still loading / failed).
  final Map<String, List<AdminDoc>?> _docs = {};
  final Set<String> _failed = {};
  final Set<String> _timedOut = {};
  final Map<String, Timer> _streamTimers = {};
  AdminDoc? _features;
  bool _featuresLoaded = false;
  final List<StreamSubscription<Object?>> _subs = [];
  StreamSubscription<List<AdminDoc>>? _localMessagesSub;
  MessagesFeed? _sharedFeed;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _subscribeCollections();
    _rescheduleRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = MessagesFeedScope.maybeOf(context);
    if (!identical(shared, _sharedFeed)) {
      _sharedFeed?.removeListener(_onSharedFeedChanged);
      _sharedFeed = shared;
      if (shared != null) {
        _localMessagesSub?.cancel();
        _localMessagesSub = null;
        shared.addListener(_onSharedFeedChanged);
        _syncSharedFeedWatch(shared);
      } else {
        _subscribeLocalMessages();
      }
    } else if (shared != null) {
      _syncSharedFeedWatch(shared);
    } else if (_localMessagesSub == null) {
      _subscribeLocalMessages();
    }
  }

  void _syncSharedFeedWatch(MessagesFeed shared) {
    if (shared.hasData || shared.hasError) {
      _clearStreamWatch('contact_messages');
    } else if (!_timedOut.contains('contact_messages') && !_streamTimers.containsKey('contact_messages')) {
      _startStreamTimer('contact_messages');
    }
  }

  void _onSharedFeedChanged() {
    if (!mounted) return;
    final shared = _sharedFeed;
    if (shared == null) return;
    if (shared.hasData || shared.hasError) {
      _clearStreamWatch('contact_messages');
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different backend (e.g. after re-sign-in): re-bind every stream.
    if (widget.repo != oldWidget.repo) {
      _cancel();
      _docs.clear();
      _failed.clear();
      _timedOut.clear();
      _features = null;
      _featuresLoaded = false;
      _subscribeCollections();
      if (_sharedFeed == null) {
        _subscribeLocalMessages();
      }
    }
    _rescheduleRefresh();
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _localMessagesSub?.cancel();
    _localMessagesSub = null;
    for (final t in _streamTimers.values) {
      t.cancel();
    }
    _streamTimers.clear();
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _startStreamTimer(String key) {
    _streamTimers.remove(key)?.cancel();
    _streamTimers[key] = Timer(_streamTimeout, () {
      _streamTimers.remove(key);
      if (!mounted) return;
      setState(() => _timedOut.add(key));
    });
  }

  void _clearStreamWatch(String key) {
    _streamTimers.remove(key)?.cancel();
    _timedOut.remove(key);
  }

  void _subscribeCollections() {
    for (final n in _watchedCollections) {
      _startStreamTimer(n);
      _subs.add(widget.repo.watch(n).listen(
            (d) => setState(() {
              _docs[n] = d;
              _failed.remove(n);
              _clearStreamWatch(n);
              if (n == 'alerts') _rescheduleRefresh();
            }),
            onError: (_) => setState(() {
              _failed.add(n);
              _clearStreamWatch(n);
            }),
          ));
    }
    const featuresKey = 'settings/features';
    _startStreamTimer(featuresKey);
    _subs.add(widget.repo.watchDoc(featuresKey).listen(
          (d) => setState(() {
            _features = d;
            _featuresLoaded = true;
            _failed.remove(featuresKey);
            _clearStreamWatch(featuresKey);
          }),
          onError: (_) => setState(() {
            _failed.add(featuresKey);
            _clearStreamWatch(featuresKey);
          }),
        ));
  }

  void _subscribeLocalMessages() {
    _localMessagesSub?.cancel();
    const key = 'contact_messages';
    _startStreamTimer(key);
    _localMessagesSub = widget.repo.watchLatest(key, limit: MessagesFeed.pageSize).listen(
          (d) => setState(() {
            _docs[key] = d;
            _failed.remove(key);
            _clearStreamWatch(key);
          }),
          onError: (_) => setState(() {
            _failed.add(key);
            _clearStreamWatch(key);
          }),
        );
  }

  void _retry() {
    _cancel();
    setState(() {
      _docs.clear();
      _failed.clear();
      _timedOut.clear();
      _features = null;
      _featuresLoaded = false;
    });
    _subscribeCollections();
    if (_sharedFeed != null) {
      _sharedFeed!.retry();
      _startStreamTimer('contact_messages');
    } else {
      _subscribeLocalMessages();
    }
    _rescheduleRefresh();
  }

  List<Alert> _currentAlerts() => [
        for (final d in _docs['alerts'] ?? const <AdminDoc>[])
          if (!isSoftDeleted(d.data)) Alert.fromMap(d.id, d.data),
      ];

  void _rescheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!mounted) return;
    final nowUtc = (widget.now?.call() ?? DateTime.now()).toUtc();
    var delay = _maxRefreshInterval;
    for (final a in _currentAlerts()) {
      final ends = a.endsAt?.toUtc();
      if (!a.visible || !a.active || ends == null) continue;
      final enterWindow = ends.subtract(const Duration(hours: 48));
      if (enterWindow.isAfter(nowUtc)) {
        final d = enterWindow.difference(nowUtc);
        if (d < delay) delay = d;
      }
      final expireAt = ends.add(const Duration(milliseconds: 1));
      if (expireAt.isAfter(nowUtc)) {
        final d = expireAt.difference(nowUtc);
        if (d < delay) delay = d;
      }
    }
    if (delay < _minRefreshDelay) delay = _minRefreshDelay;
    _refreshTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _rescheduleRefresh();
    });
  }

  @override
  void dispose() {
    _sharedFeed?.removeListener(_onSharedFeedChanged);
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final onOpen = widget.onOpen;
    final sharedFeed = _sharedFeed;
    final messages = sharedFeed != null ? sharedFeed.docs : _docs['contact_messages'];
    final newMessages = countUnreadMessages(messages ?? const <AdminDoc>[]);
    final f = FeatureSettings.fromMap(_features?.data);
    final alertsList = _currentAlerts();
    var unconfirmed = 0;
    String? unconfirmedTarget;
    final unconfirmedByCollection = <String, ({int count, String label})>{};
    var missingEnglish = 0;
    String? missingEnglishTarget;
    for (final c in adminCollections) {
      final list = _docs[c.name];
      if (list == null) continue;
      final pairs = f.englishEnabled ? englishFieldPairs(c.fields) : const <(String, String)>[];
      for (final d in list) {
        if (!c.matches(d.data) || isSoftDeleted(d.data)) continue;
        if (d.data['sample'] == true) {
          unconfirmed++;
          unconfirmedTarget ??= c.id;
          final existing = unconfirmedByCollection[c.id];
          unconfirmedByCollection[c.id] = (
            count: (existing?.count ?? 0) + 1,
            label: context.pick(c.labelAr, c.labelEn),
          );
        }
        if (f.englishEnabled && docMissingEnglish(d.data, pairs)) {
          missingEnglish++;
          missingEnglishTarget ??= c.id;
        }
      }
    }
    String? unconfirmedSubtitle;
    if (unconfirmedByCollection.length > 1) {
      final sorted = unconfirmedByCollection.values.toList()..sort((a, b) => b.count.compareTo(a.count));
      final top = sorted.first;
      unconfirmedSubtitle = context.tr('att_unconfirmedBreakdown', {'c': '${top.count}', 'sec': top.label});
    }
    final currentNow = widget.now?.call() ?? DateTime.now();
    final attention = attentionItems(
      newMessages: newMessages,
      alerts: alertsList,
      unconfirmed: unconfirmed,
      streamOn: f.today.liveEnabled,
      streamUrl: f.today.liveUrl,
      englishOn: f.englishEnabled,
      missingEnglish: missingEnglish,
      now: currentNow,
      unconfirmedTarget: unconfirmedTarget ?? 'liturgies',
      missingEnglishTarget: missingEnglishTarget ?? 'liturgies',
    );
    final messagesFailed = sharedFeed != null ? sharedFeed.hasError : _failed.contains('contact_messages');
    final messagesTimedOut = _timedOut.contains('contact_messages') &&
        !(sharedFeed?.hasData ?? false) &&
        !(sharedFeed?.hasError ?? false);
    final hasError = _failed.isNotEmpty || _timedOut.isNotEmpty || messagesFailed || messagesTimedOut;
    final featuresFailed =
        _failed.contains('settings/features') || _timedOut.contains('settings/features');
    final messagesReady = sharedFeed != null ? sharedFeed.hasData : _docs.containsKey('contact_messages');
    final ready = !hasError && _featuresLoaded && _watchedCollections.every(_docs.containsKey) && messagesReady;

    final edited = <(String, AdminDoc)>[
      for (final e in _docs.entries)
        if (e.key != 'contact_messages')
          for (final d in e.value ?? const <AdminDoc>[])
            if (d.updatedAt != null && !isSoftDeleted(d.data)) (e.key, d),
    ]..sort((a, b) => b.$2.updatedAt!.compareTo(a.$2.updatedAt!));

    return Scaffold(
      backgroundColor: context.pal.background,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AdminScreenHeader(
          title: context.tr('overviewTitle'),
          help: context.tr('help_overview'),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('attentionTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (attention.isNotEmpty) ...[
          Card(
            key: const ValueKey('attention-section'),
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < attention.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _attentionTile(
                    context,
                    attention[i],
                    onOpen,
                    subtitle: attention[i].kind == AttentionKind.unconfirmedData ? unconfirmedSubtitle : null,
                  ),
                ],
              ],
            ),
          ),
          if (hasError) const SizedBox(height: 8),
        ],
        if (hasError)
          Card(
            key: const ValueKey('attention-error'),
            margin: EdgeInsets.zero,
            color: context.pal.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final retryBtn = TextButton.icon(
                    key: const ValueKey('attention-retry'),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.tr('retry')),
                  );
                  final msgRow = Row(
                    children: [
                      Icon(Icons.error_outline, color: context.pal.alert),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('attentionLoadError'),
                          style: TextStyle(color: context.pal.alert, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 340) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        msgRow,
                        const SizedBox(height: 4),
                        Align(alignment: AlignmentDirectional.centerEnd, child: retryBtn),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: msgRow),
                      const SizedBox(width: 8),
                      retryBtn,
                    ],
                  );
                },
              ),
            ),
          )
        else if (attention.isEmpty && ready)
          Card(
            key: const ValueKey('attention-all-clear'),
            margin: EdgeInsets.zero,
            color: context.pal.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: context.pal.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('attentionAllClear'),
                      style: TextStyle(color: context.pal.success, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (attention.isEmpty)
          const Card(
            key: ValueKey('attention-loading'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: LinearProgressIndicator(),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          context.tr('quickTasksTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('quick-tasks'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _taskButton(
              context,
              key: const ValueKey('task-schedules'),
              icon: Icons.access_time_outlined,
              label: context.tr('task_schedules'),
              onTap: () => onOpen('liturgies'),
            ),
            _taskButton(
              context,
              key: const ValueKey('task-announcement'),
              icon: Icons.campaign_outlined,
              label: context.tr('task_announcement'),
              onTap: () => onOpen('app'),
            ),
            _taskButton(
              context,
              key: const ValueKey('task-inbox'),
              icon: Icons.mark_email_unread_outlined,
              label: context.tr('task_inbox'),
              onTap: () => onOpen('messages'),
            ),
            _taskButton(
              context,
              key: const ValueKey('task-service'),
              icon: Icons.volunteer_activism_outlined,
              label: context.tr('task_service'),
              onTap: () => onOpen('facilities'),
            ),
            _taskButton(
              context,
              key: const ValueKey('task-priest'),
              icon: Icons.person_add_alt_1_outlined,
              label: context.tr('task_priest'),
              onTap: () => onOpen('priests'),
            ),
            _taskButton(
              context,
              key: const ValueKey('task-donations'),
              icon: Icons.article_outlined,
              label: context.tr('task_donations'),
              onTap: () => onOpen('pages'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          key: const ValueKey('sections-summary'),
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.toggle_on_outlined, color: context.pal.primary),
                title: Text(context.tr('sectionsSummary'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  featuresFailed
                      ? '—'
                      : (_featuresLoaded
                          ? '${context.tr('sectionsOn')}: ${Sections.all.length - f.disabledCount}/${Sections.all.length}'
                          : '…'),
                ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(context.tr('openSite')),
                  onPressed: () => openUrl(Uri.base.resolve('/').toString()),
                ),
                onTap: () => onOpen('features'),
              ),
              if (featuresFailed) ...[
                const Divider(height: 1),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: TextButton.icon(
                      key: const ValueKey('sections-retry'),
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.tr('retry')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(context.tr('recentEdits'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (edited.isEmpty)
          Text(context.tr('noRecentEdits'), style: TextStyle(color: context.pal.muted))
        else
          Card(
            child: Column(children: [
              for (final e in edited.take(8))
                ListTile(
                  dense: true,
                  leading: Icon(adminIcon(_iconFor(e.$1)), color: context.pal.primary),
                  title: Text(_titleOf(e.$2), overflow: TextOverflow.ellipsis),
                  subtitle: Text(context.tr('updatedBy', {'t': fmtDateTime(e.$2.updatedAt!), 'u': e.$2.updatedBy})),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _attentionTile(BuildContext context, AttentionItem item, void Function(String) onOpen, {String? subtitle}) {
    final (IconData icon, Color color, String label) = switch (item.kind) {
      AttentionKind.newMessages => (
          Icons.mail_outline,
          context.pal.alert,
          context.tr('att_newMessages', {'n': '${item.count}'}),
        ),
      AttentionKind.expiringAlerts => (
          Icons.campaign_outlined,
          context.pal.goldText,
          context.tr('att_expiringAlerts', {'n': '${item.count}'}),
        ),
      AttentionKind.unconfirmedData => (
          Icons.fact_check_outlined,
          context.pal.goldText,
          context.tr('att_unconfirmedData', {'n': '${item.count}'}),
        ),
      AttentionKind.streamWithoutLink => (
          Icons.live_tv_outlined,
          context.pal.alert,
          context.tr('att_streamWithoutLink'),
        ),
      AttentionKind.missingEnglish => (
          Icons.translate_outlined,
          context.pal.primary,
          context.tr('att_missingEnglish', {'n': '${item.count}'}),
        ),
    };
    return ListTile(
      key: ValueKey('attention-${item.kind.name}'),
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: context.pal.muted, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(item.targetScreenId),
    );
  }

  Widget _taskButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      FilledButton.tonalIcon(
        key: key,
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  static String _iconFor(String col) {
    for (final c in adminCollections) {
      if (c.name == col) return c.icon;
    }
    return 'list';
  }

  static String _titleOf(AdminDoc d) {
    for (final k in ['titleAr', 'nameAr', 'name', 'titleEn', 'nameEn']) {
      final v = d.data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return d.id;
  }
}

IconData adminIcon(String name) => switch (name) {
      'alerts' => Icons.campaign_outlined,
      'seasons' => Icons.event_note_outlined,
      'liturgies' => Icons.access_time_outlined,
      'meetings' => Icons.school_outlined,
      'services' => Icons.volunteer_activism_outlined,
      'activities' => Icons.groups_outlined,
      'priests' => Icons.person_outline,
      'departed' => Icons.local_florist_outlined,
      'saints' => Icons.auto_awesome_outlined,
      'milestones' => Icons.history_edu_outlined,
      'categories' => Icons.category_outlined,
      'entries' => Icons.view_list_outlined,
      'pages' => Icons.article_outlined,
      'contactCats' => Icons.forum_outlined,
      _ => Icons.list_alt,
    };

/// A settings document as a form: settings/church by default, also
/// settings/assistant (ADR-029). A newer stored version replaces the form only
/// when it has no unsaved edits; otherwise a banner offers a reload.
class ChurchInfoScreen extends StatefulWidget {
  final AdminBackend repo;
  final DocDef doc;

  /// Optional widget above the form (e.g. the assistant's status card).
  final Widget? header;

  /// Whether to render the screen title and one-line help header (P2-19).
  final bool showHeader;

  const ChurchInfoScreen({
    super.key,
    required this.repo,
    this.doc = churchInfoDoc,
    this.header,
    this.showHeader = true,
  });

  @override
  State<ChurchInfoScreen> createState() => _ChurchInfoScreenState();
}

class _ChurchInfoScreenState extends State<ChurchInfoScreen> {
  late Stream<AdminDoc?> _stream = widget.repo.watchDoc(widget.doc.path);
  StreamSubscription<AdminDoc?>? _featuresSub;
  bool _englishEnabled = true;

  @override
  void initState() {
    super.initState();
    _bindFeatures();
  }

  void _bindFeatures() {
    _featuresSub?.cancel();
    _featuresSub = null;
    _englishEnabled = true;
    if (widget.doc.path == 'settings/features') return;
    _featuresSub = widget.repo.watchDoc('settings/features').listen(
      (d) {
        if (!mounted) return;
        final next = FeatureSettings.fromMap(d?.data).englishEnabled;
        if (next != _englishEnabled) setState(() => _englishEnabled = next);
      },
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(covariant ChurchInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different backend or document definition: re-bind the stream and
    // rebuild the form from it. Two definitions may share a path with
    // different fields (settings/features: today vs season settings), and
    // DocEditor builds its per-field state only once.
    if (widget.repo != oldWidget.repo ||
        widget.doc.path != oldWidget.doc.path ||
        !identical(widget.doc, oldWidget.doc)) {
      _stream = widget.repo.watchDoc(widget.doc.path);
      _shown = null;
      _loaded = false;
      _editorKey = GlobalKey<DocEditorState>();
      _bindFeatures();
    }
  }

  @override
  void dispose() {
    _featuresSub?.cancel();
    super.dispose();
  }

  GlobalKey<DocEditorState> _editorKey = GlobalKey<DocEditorState>();
  AdminDoc? _shown;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return StreamBuilder<AdminDoc?>(
      // A new stream (another backend) gets a fresh StreamBuilder: a reused one
      // keeps the old backend's last snapshot while waiting, and that stale
      // document would then be marked as loaded.
      key: ObjectKey(_stream),
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final latest = snap.data;
        final changed = !_loaded || latest?.updatedAt != _shown?.updatedAt || (latest == null) != (_shown == null);
        final editor = _editorKey.currentState;
        final saving = editor?.saving ?? false;
        final dirty = editor?.dirty ?? false;
        final echo =
            _loaded && editor != null && isEchoOfEditor(_shown?.data ?? const {}, latest?.data, editor.collect());
        if (changed && (!dirty && !saving || echo)) {
          // The snapshot of our own save (only metadata or the values the form
          // already holds changed) keeps the form and its scroll position.
          if (_loaded && !echo) _editorKey = GlobalKey<DocEditorState>();
          _shown = latest;
          _loaded = true;
        }
        final stale = changed && (dirty || saving) && !echo;
        final doc = _shown;
        final englishEnabled = widget.doc.path == 'settings/features'
            ? FeatureSettings.fromMap(doc?.data).englishEnabled
            : _englishEnabled;
        final title = widget.showHeader ? context.pick(widget.doc.labelAr, widget.doc.labelEn) : '';
        final help = widget.showHeader ? context.pick(widget.doc.helpAr, widget.doc.helpEn) : '';
        return Column(children: [
          if (widget.showHeader && widget.header != null)
            AdminScreenHeader(
              title: title,
              help: help,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            ),
          ?widget.header,
          if (stale)
            MaterialBanner(
              content: Text(context.tr('updatedElsewhere')),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    _shown = latest;
                    _editorKey = GlobalKey<DocEditorState>();
                  }),
                  child: Text(context.tr('reload')),
                ),
              ],
            ),
          if (doc?.updatedAt != null)
            Container(
              width: double.infinity,
              color: context.pal.surfaceAlt,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(context.tr('updatedBy', {'t': fmtDateTime(doc!.updatedAt!), 'u': doc.updatedBy}),
                  style: TextStyle(fontSize: 12, color: context.pal.muted)),
            ),
          Expanded(
            child: DocEditor(
              key: _editorKey,
              title: widget.showHeader && widget.header == null ? title : '',
              help: widget.showHeader && widget.header == null ? help : '',
              fields: widget.doc.fields,
              data: doc?.data ?? const {},
              popOnSave: false,
              englishEnabled: englishEnabled,
              onSave: (data) => widget.repo.saveDoc(widget.doc.path, data),
            ),
          ),
        ]);
      },
    );
  }
}

/// Client-side search predicate for [MessagesScreen]: matches name,
/// normalized phone digits, message text, notes, email, dates (`preferredDate`
/// and Cairo `createdAt`), and category/subtype labels.
bool messageMatchesQuery(
  AdminDoc d,
  ContactSettings cfg,
  String query, {
  String anonymousLabel = '',
  String otherLabel = '',
}) {
  final q = normalizeDigits(query).trim().toLowerCase();
  if (q.isEmpty) return true;
  final m = d.data;
  final anonymous = m['anonymous'] == true;
  final phone = (m['phone'] ?? '').toString();
  final normPhone = normalizeDigits(phone).replaceAll(RegExp(r'[\s\-().]'), '');
  final egPhone = normalizeEgyptianPhone(phone) ?? '';
  final catKey = m['category'] is String ? m['category'] as String : null;
  final cat = cfg.bySlot(catKey ?? 'c1');
  final sub = cat?.subtype('${m['bookingType'] ?? ''}');
  final created = m['createdAt'];

  final parts = <String>[
    if (anonymous) ...[anonymousLabel, 'anonymous', 'مجهول'] else '${m['name'] ?? ''}',
    phone,
    normPhone,
    egPhone,
    '${m['email'] ?? ''}',
    '${m['message'] ?? ''}',
    '${m['adminNotes'] ?? ''}',
    '${m['preferredDate'] ?? ''}',
    '${m['kind'] ?? ''}',
    if (created is DateTime) ...[fmtDateTime(created), fmtDate(created)],
    if (catKey != null)
      if (cat != null) ...[cat.labelAr, cat.labelEn] else otherLabel,
    if (sub != null) ...[sub.labelAr, sub.labelEn] else '${m['bookingType'] ?? ''}',
  ];
  final haystack = normalizeDigits(parts.join(' ')).toLowerCase();
  if (haystack.contains(q)) return true;
  final qDigits = q.replaceAll(RegExp(r'[\s\-().]'), '');
  if (qDigits.isNotEmpty &&
      RegExp(r'^[+\d]+$').hasMatch(qDigits) &&
      (normPhone.toLowerCase().contains(qDigits) || egPhone.contains(qDigits))) {
    return true;
  }
  return false;
}

/// contact_messages inbox: read, mark handled, delete.
/// Contact inbox (ADR-028): one box per contact category (plus "Other" for
/// messages of a deleted type and the separate anonymous box), open / done
/// filters, booking status (new → contacted → confirmed / declined) and
/// internal notes.
class MessagesScreen extends StatefulWidget {
  final AdminBackend repo;
  const MessagesScreen({super.key, required this.repo});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _search = TextEditingController();
  String _filter = 'new';
  String _box = 'all';
  late final _undo = SoftDeleteUndo(
    isMounted: () => mounted,
    onChanged: () {
      if (mounted) setState(() {});
    },
    removeMedia: false,
  );
  static const _messagesDef = CollectionDef('contact_messages', '', '', [], []);
  MessagesFeed? _sharedFeed;
  MessagesFeed? _ownedFeed;
  late Stream<AdminDoc?> _config = widget.repo.watchDoc('settings/contact');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = MessagesFeedScope.maybeOf(context);
    if (!identical(shared, _sharedFeed)) {
      _sharedFeed = shared;
      if (shared != null) {
        _ownedFeed?.dispose();
        _ownedFeed = null;
      } else {
        _ownedFeed ??= MessagesFeed(widget.repo);
      }
    } else if (shared == null && _ownedFeed == null) {
      _ownedFeed = MessagesFeed(widget.repo);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _ownedFeed?.dispose();
    _ownedFeed = null;
    _undo.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different backend: re-bind the streams.
    if (widget.repo != oldWidget.repo) {
      _undo.clearTransitionState();
      _config = widget.repo.watchDoc('settings/contact');
      if (_sharedFeed == null) {
        _ownedFeed?.dispose();
        _ownedFeed = MessagesFeed(widget.repo);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final feed = _sharedFeed ?? _ownedFeed!;
    return Scaffold(
      backgroundColor: context.pal.background,
      body: StreamBuilder<AdminDoc?>(
        key: ObjectKey(_config),
        stream: _config,
        builder: (context, cfgSnap) {
          // Missing doc, still loading or unreadable: the code defaults.
          final cfg = ContactSettings.fromMap(cfgSnap.data?.data);
          return ListenableBuilder(
            key: ObjectKey(feed),
            listenable: feed,
            builder: (context, _) {
              if (!feed.hasData && feed.hasError) {
                return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${feed.error}')));
              }
              if (!feed.hasData) return const Center(child: CircularProgressIndicator());
              return _body(context, cfg, feed.docs!, feed);
            },
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, ContactSettings cfg, List<AdminDoc> docs, MessagesFeed feed) {
    _undo.checkLazyPurge(widget.repo, _messagesDef, docs);
    final visible = docs.where(_undo.isVisible).toList();
    final all = [...visible]..sort((a, b) {
        final ta = a.data['createdAt'], tb = b.data['createdAt'];
        if (ta is DateTime && tb is DateTime) return tb.compareTo(ta);
        return ta is DateTime ? -1 : (tb is DateTime ? 1 : 0);
      });
    final slots = {for (final c in cfg.categories) c.slot};
    String boxOf(AdminDoc d) {
      final b = inboxBoxOf(d.data);
      return b == 'anonymous' || slots.contains(b) ? b : 'other';
    }

    int open(String box) => all.where((d) => (box == 'all' || boxOf(d) == box) && messageIsOpen(d.data)).length;
    final boxes = <(String, String)>[
      ('all', context.tr('msg_all')),
      for (final c in cfg.categories) (c.slot, context.pick(c.labelAr, c.labelEn)),
      ('anonymous', context.tr('inboxAnonymous')),
      if (all.any((d) => boxOf(d) == 'other')) ('other', context.tr('otherCategory')),
    ];
    final box = boxes.any((b) => b.$1 == _box) ? _box : 'all';
    final anonymousLabel = context.tr('anonymousSender');
    final otherLabel = context.tr('otherCategory');
    final query = _search.text;
    final list = all.where((d) {
      if (box != 'all' && boxOf(d) != box) return false;
      final isOpen = messageIsOpen(d.data);
      if (!(_filter == 'all' || (_filter == 'new' ? isOpen : !isOpen))) return false;
      return messageMatchesQuery(
        d,
        cfg,
        query,
        anonymousLabel: anonymousLabel,
        otherLabel: otherLabel,
      );
    }).toList();
    Widget chip(String id, String label, bool selected, VoidCallback onTap, {Key? key}) => ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: TextStyle(color: selected ? context.pal.onBar : context.pal.primary),
          onSelected: (_) => onTap(),
        );
    Widget loadMoreSection() => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (feed.hasError) ...[
                Text(
                  formatAdminError(feed.error!, isAr: context.isAr),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.pal.alert),
                ),
                const SizedBox(height: 8),
              ],
              Center(
                child: OutlinedButton.icon(
                  key: const Key('messages-load-more'),
                  onPressed: feed.loadingMore ? null : feed.loadMore,
                  icon: feed.loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(context.tr('loadMore')),
                ),
              ),
            ],
          ),
        );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminScreenHeader(
                title: context.tr('messagesTitle'),
                help: context.tr('help_messages'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  key: const Key('messages-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.tr('searchHint'),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('messages-search-clear'),
                            tooltip: context.tr('clearSearch'),
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final b in boxes)
                    chip(b.$1, open(b.$1) > 0 ? '${b.$2} (${open(b.$1)})' : b.$2, box == b.$1, () => setState(() => _box = b.$1),
                        key: ValueKey('box-${b.$1}')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 6, children: [
                  for (final f in ['new', 'handled', 'all'])
                    chip(f, context.tr('msg_$f'), _filter == f, () => setState(() => _filter = f), key: ValueKey('filter-$f')),
                ]),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('noMessages')),
                    if (feed.canLoadMore) ...[
                      const SizedBox(height: 12),
                      loadMoreSection(),
                    ],
                  ],
                ),
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, feed.canLoadMore ? 8 : 40),
            sliver: SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _message(context, cfg, list[i]),
            ),
          ),
          if (feed.canLoadMore) SliverToBoxAdapter(child: loadMoreSection()),
        ],
      ],
    );
  }

  Widget _message(BuildContext context, ContactSettings cfg, AdminDoc d) {
    final m = d.data;
    final anonymous = m['anonymous'] == true;
    final status = (m['status'] ?? MessageStatus.newMsg).toString();
    final open = messageIsOpen(m);
    final created = m['createdAt'];
    final phone = (m['phone'] ?? '').toString();
    final waUrl = usableWhatsappLink(phone);
    final email = (m['email'] ?? '').toString();
    final notes = (m['adminNotes'] ?? '').toString();
    final cat = cfg.bySlot(m['category'] is String ? m['category'] as String : 'c1');
    final booking = m['kind'] == ContactKinds.booking || (m['kind'] == null && (cat?.isBooking ?? false) && m['preferredDate'] != null);
    final sub = cat?.subtype('${m['bookingType'] ?? ''}');
    final subLabel = sub == null ? '${m['bookingType'] ?? ''}' : context.pick(sub.labelAr, sub.labelEn);
    final date = '${m['preferredDate'] ?? ''}';
    final catLabel = m['category'] == null
        ? null
        : (cat == null ? context.tr('otherCategory') : context.pick(cat.labelAr, cat.labelEn));
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 8),
      color: open ? context.pal.surface : context.pal.surfaceAlt.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                anonymous
                    ? Icons.privacy_tip_outlined
                    : (open ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
                color: open ? context.pal.primary : context.pal.muted),
            const SizedBox(width: 8),
            // Name and date wrap onto two lines on phones / large text.
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 2,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(anonymous ? context.tr('anonymousSender') : '${m['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (created is DateTime)
                    Text(fmtDateTime(created), style: TextStyle(color: context.pal.muted, fontSize: 12)),
                ],
              ),
            ),
          ]),
          if (catLabel != null || booking) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (catLabel != null) _InfoChip(catLabel),
              if (booking && subLabel.isNotEmpty) _InfoChip(subLabel),
              if (booking && date.isNotEmpty) _InfoChip('📅 $date'),
            ]),
          ],
          const SizedBox(height: 6),
          SelectableText('${m['message'] ?? ''}', style: const TextStyle(height: 1.6)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (phone.isNotEmpty)
              ActionChip(
                key: ValueKey('msgCall-${d.id}'),
                avatar: const Icon(Icons.call, size: 16),
                label: Text(phone, textDirection: TextDirection.ltr),
                onPressed: () => callPhone(phone),
              ),
            if (waUrl != null)
              ActionChip(
                key: ValueKey('msgWhatsApp-${d.id}'),
                avatar: const Icon(Icons.chat_rounded, size: 16, color: whatsappGreen),
                label: Text(context.tr('whatsapp')),
                onPressed: () => openUrl(waUrl),
              ),
            if (email.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.email_outlined, size: 16),
                label: Text(email, textDirection: TextDirection.ltr),
                onPressed: () => openUrl('mailto:$email'),
              ),
            if (m['lang'] != null) Text('(${m['lang']})', style: TextStyle(color: context.pal.muted)),
          ]),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(8)),
              child: Text('${context.tr('adminNotes')}: $notes', style: const TextStyle(height: 1.5)),
            ),
          ],
          const Divider(height: 18),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (booking)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${context.tr('bookingStatus')}: '),
                DropdownButton<String>(
                  key: ValueKey('bookingStatus-${d.id}'),
                  value: MessageStatus.booking.contains(status) ? status : MessageStatus.newMsg,
                  items: [
                    for (final s in MessageStatus.booking)
                      DropdownMenuItem(value: s, child: Text(context.tr('status_$s'))),
                  ],
                  onChanged: (v) => v == null ? null : _update(context, d, {'status': v}),
                ),
              ])
            else if (open)
              TextButton.icon(
                key: ValueKey('msgToggleStatus-${d.id}'),
                onPressed: () => _update(context, d, {'status': MessageStatus.handled}),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(context.tr('markHandled')),
              )
            else
              const SizedBox.shrink(),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: ValueKey('notes-${d.id}'),
                tooltip: context.tr('editNotes'),
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: () => _editNotes(context, d, notes),
              ),
              IconButton(
                tooltip: context.tr('copy'),
                icon: const Icon(Icons.copy_outlined),
                onPressed: () => Clipboard.setData(ClipboardData(
                    text: anonymous ? '${m['message']}' : '${m['name']}\n$phone $email\n${m['message']}')),
              ),
              IconButton(
                tooltip: context.tr('delete'),
                icon: Icon(Icons.delete_outline, color: context.pal.alert),
                onPressed: () => _delete(context, d),
              ),
              if (!booking && !open)
                IconButton(
                  key: ValueKey('msgMore-${d.id}'),
                  tooltip: context.tr('moreActions'),
                  icon: const Icon(Icons.more_vert),
                  onPressed: () async {
                    final action = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: Text(ctx.tr('moreActions')),
                        children: [
                          SimpleDialogOption(
                            key: ValueKey('msgMarkNew-${d.id}'),
                            onPressed: () => Navigator.pop(ctx, 'markNew'),
                            child: Row(
                              children: [
                                const Icon(Icons.refresh, size: 18),
                                const SizedBox(width: 8),
                                Flexible(child: Text(ctx.tr('markNew'))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    if (action == 'markNew' && context.mounted) {
                      await _update(context, d, {'status': MessageStatus.newMsg});
                    }
                  },
                ),
            ]),
          ]),
        ]),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context, AdminDoc d, String current) async {
    final text = await showDialog<String>(context: context, builder: (_) => _NotesDialog(initial: current));
    if (text == null || text == current || !context.mounted) return;
    await _update(context, d, {'adminNotes': text});
  }

  Future<void> _update(BuildContext context, AdminDoc d, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('saveFailed', {'e': '{e}'});
    final isAr = context.isAr;
    try {
      await widget.repo.update('contact_messages', d.id, data);
    } catch (e) {
      _undo.showSnack(
        messenger,
        SnackBar(content: Text(failed.replaceAll('{e}', formatAdminError(e, isAr: isAr)))),
        deferWhileUndo: true,
      );
    }
  }

  Future<void> _delete(BuildContext context, AdminDoc d) async {
    final m = d.data;
    final anonymous = m['anonymous'] == true || (m['name'] as String?)?.trim().isEmpty != false;
    final sender = anonymous ? context.tr('anonymousSender') : '${m['name'] ?? ''}'.trim();
    final ok = await confirmNamedAction(
      context,
      summary: '«$sender»\n\n${context.tr('confirmDeleteMessage')}',
      actionLabel: context.tr('delete'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _undo.delete(
      repo: widget.repo,
      collection: 'contact_messages',
      doc: d,
      title: sender,
      messenger: ScaffoldMessenger.of(context),
      failedMsg: context.tr('deleteFailed', {'e': '{e}'}),
      undoLabel: context.tr('undo'),
      undoAllLabel: context.tr('undoAll'),
    );
  }
}

/// Internal notes editor (owns its controller, so it outlives the closing
/// animation).
class _NotesDialog extends StatefulWidget {
  final String initial;
  const _NotesDialog({required this.initial});

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('adminNotes')),
        content: TextField(
          key: const Key('adminNotesField'),
          controller: _ctl,
          minLines: 3,
          maxLines: 8,
          maxLength: adminNotesMax,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, _ctl.text.trim()), child: Text(context.tr('save'))),
        ],
      );
}

class _InfoChip extends StatelessWidget {
  final String text;
  const _InfoChip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.pal.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.pal.primary.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: context.pal.primary, fontWeight: FontWeight.w700)),
      );
}

/// Owner-only: list, add, change role, remove admins.
class AdminsScreen extends StatefulWidget {
  final AdminBackend repo;
  final String selfUid;
  const AdminsScreen({super.key, required this.repo, required this.selfUid});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  late Stream<List<AdminDoc>> _stream = widget.repo.watch('admins');

  @override
  void didUpdateWidget(covariant AdminsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different backend: re-bind the stream.
    if (widget.repo != oldWidget.repo) _stream = widget.repo.watch('admins');
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return Scaffold(
      backgroundColor: context.pal.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-admin',
        onPressed: () => _addDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.tr('addAdmin')),
      ),
      body: StreamBuilder<List<AdminDoc>>(
        // A new stream (another backend) gets a fresh StreamBuilder: a reused
        // one keeps the old backend's list while the new one loads.
        key: ObjectKey(_stream),
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final admins = [...snap.data!]..sort((a, b) => '${a.data['email']}'.compareTo('${b.data['email']}'));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            AdminScreenHeader(
              title: context.tr('adminsTitle'),
              help: context.tr('help_admins'),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            ),
            Card(
              color: context.pal.surfaceAlt,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(context.tr('adminsHelp'), style: const TextStyle(height: 1.6)),
              ),
            ),
            const SizedBox(height: 8),
            for (final a in admins) _tile(context, a),
          ]);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, AdminDoc a) {
    final self = a.id == widget.selfUid;
    final role = a.data['role'] == AdminRoles.owner ? AdminRoles.owner : AdminRoles.editor;
    final active = a.active;
    final expiresAt = a.expiresAt;
    final nowUtc = DateTime.now().toUtc();
    final expired = expiresAt != null && !nowUtc.isBefore(expiresAt.toUtc());
    final inactive = !active || expired;
    final expiryStr = expiresAt == null ? '' : fmtDate(CairoTime.fromInstant(expiresAt));
    return Card(
      key: ValueKey('admin-card-${a.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          role == AdminRoles.owner ? Icons.workspace_premium_outlined : Icons.edit_note,
          color: inactive ? context.pal.muted : context.pal.primary,
        ),
        title: Text(
          '${a.data['email'] ?? ''}${self ? ' (${context.tr('you')})' : ''}',
          textDirection: TextDirection.ltr,
          style: inactive ? TextStyle(color: context.pal.muted) : null,
        ),
        // The role menu, status switch, expiry picker and remove button wrap cleanly (phones / large text).
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText('UID: ${a.id}', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            // Long role labels ellipsize instead of overflowing at 320 px / 200%.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: DropdownButton<String>(
                isExpanded: true,
                value: role,
                onChanged: self
                    ? null
                    : (v) => v == null ? null : _changeRole(context, a, role, v),
                items: [
                  for (final r in AdminRoles.all)
                    DropdownMenuItem(value: r, child: Text(context.tr('role_$r'), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            if (self)
              Container(
                key: ValueKey('admin-self-active-${a.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.pal.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.pal.primary.withValues(alpha: 0.3)),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: context.pal.primary),
                    Text(
                      context.tr('selfActiveTag'),
                      style: TextStyle(
                        color: context.pal.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              AdminStateSwitch(
                key: ValueKey('admin-active-${a.id}'),
                value: active,
                onLabel: context.tr('activeStatus'),
                offLabel: context.tr('stoppedStatus'),
                onChanged: (next) => _toggleActive(context, a, next),
              ),
            if (role != AdminRoles.owner || expiresAt != null)
              ActionChip(
                key: ValueKey('admin-expiry-${a.id}'),
                avatar: Icon(Icons.event_outlined, size: 18, color: expired ? context.pal.alert : context.pal.primary),
                label: Text(
                  expiresAt == null
                      ? context.tr('adminNoExpiry')
                      : context.tr(expired ? 'adminExpiredOn' : 'adminExpiresOn', {'d': expiryStr}),
                  overflow: TextOverflow.ellipsis,
                  style: expired ? TextStyle(color: context.pal.alert, fontWeight: FontWeight.w700) : null,
                ),
                onPressed: (self || role == AdminRoles.owner) ? null : () => _pickExpiry(context, a),
              ),
            if (expiresAt != null && !self)
              IconButton(
                key: ValueKey('admin-clear-expiry-${a.id}'),
                tooltip: context.tr('clearEndDate'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _guard(
                  context,
                  () => widget.repo.setAdminStatus(a.id, clearExpiresAt: true),
                ),
              ),
            IconButton(
              tooltip: context.tr('removeAdmin'),
              icon: Icon(Icons.person_remove_outlined, color: self ? context.pal.muted : context.pal.alert),
              onPressed: self
                  ? null
                  : () async {
                      final email = a.data['email'] ?? a.id;
                      final ok = await confirmNamedAction(
                        context,
                        summary: '$email\n\n${context.tr('confirmRemoveAdmin')}',
                        actionLabel: context.tr('removeAdmin'),
                        destructive: true,
                      );
                      if (ok && context.mounted) {
                        await _guard(context, () => widget.repo.removeAdmin(a.id));
                      }
                    },
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, AdminDoc a, String currentRole, String nextRole) async {
    if (nextRole == currentRole) return;
    final rawEmail = '${a.data['email'] ?? ''}'.trim();
    final who = rawEmail.isNotEmpty ? rawEmail : a.id;
    final roleLabel = context.tr('role_$nextRole');
    final ok = await confirmNamedAction(
      context,
      summary: '$who\n\n${context.tr('confirmChangeAdminRole', {'role': roleLabel})}',
      actionLabel: context.tr('changeRoleAction'),
      destructive: currentRole == AdminRoles.owner && nextRole != AdminRoles.owner,
    );
    if (ok && context.mounted) {
      await _guard(context, () => widget.repo.setAdminRole(a, nextRole));
    }
  }

  Future<void> _toggleActive(BuildContext context, AdminDoc a, bool next) async {
    final email = '${a.data['email'] ?? a.id}';
    final ok = await confirmNamedAction(
      context,
      summary: '$email\n\n${context.tr(next ? 'confirmResumeAdmin' : 'confirmPauseAdmin')}',
      actionLabel: context.tr(next ? 'resumeAdmin' : 'pauseAdmin'),
      destructive: !next,
    );
    if (ok && context.mounted) {
      await _guard(context, () => widget.repo.setAdminStatus(a.id, active: next));
    }
  }

  Future<void> _pickExpiry(BuildContext context, AdminDoc a) async {
    final existing = a.expiresAt;
    final initial = existing != null ? CairoTime.fromInstant(existing) : CairoTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    final endOfDayUtc = CairoTime.at(picked.year, picked.month, picked.day, 23 * 60 + 59)
        .toUtc()
        .add(const Duration(seconds: 59));
    await _guard(context, () => widget.repo.setAdminStatus(a.id, expiresAt: endOfDayUtc));
  }

  Future<void> _guard(BuildContext context, Future<void> Function() op) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = context.tr('saved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    final isAr = context.isAr;
    try {
      await op();
      messenger.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', formatAdminError(e, isAr: isAr)))));
    }
  }

  Future<void> _addDialog(BuildContext context) async {
    final uid = TextEditingController();
    final email = TextEditingController();
    var role = AdminRoles.editor;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.tr('addAdmin')),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: uid,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'UID *', helperText: context.tr('uidHelp')),
                  validator: (v) => isValidAdminUid(v ?? '') ? null : context.tr('invalid'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: email,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: '${context.tr('emailLabel')} *'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                      ? null
                      : context.tr('errEmail'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: context.tr('role')),
                  items: [
                    for (final r in AdminRoles.all) DropdownMenuItem(value: r, child: Text(context.tr('role_$r'))),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? AdminRoles.editor),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: Text(context.tr('add')),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      await _guard(context, () => widget.repo.setAdmin(uid.text.trim(), email: email.text.trim(), role: role));
    }
    uid.dispose();
    email.dispose();
  }
}

/// Firebase Auth UIDs are 1–128 chars without '/'.
bool isValidAdminUid(String v) {
  final s = v.trim();
  return s.isNotEmpty && s.length <= 128 && RegExp(r'^[A-Za-z0-9_\-:.]+$').hasMatch(s);
}
