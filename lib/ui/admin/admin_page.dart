import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/contact_categories.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/coptic_cross.dart';
import 'admin_access.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';
import 'advanced_owner_screen.dart';
import 'assistant_admin.dart';
import 'contact_admin.dart';
import 'collection_list.dart';
import 'features_editor.dart';
import 'notifications_admin.dart';
import 'pending_delete.dart';
import 'season_preset_admin.dart';
import 'session_policy.dart';
import 'unsaved_guard.dart';

const _rememberMePrefKey = 'admin_remember_me';

/// Hidden /admin area: email/password sign-in, role check (admins/{uid}),
/// then the dashboard.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  bool _rememberMe = false;
  AdminRepository? _repo;
  Stream<User?>? _authStream;
  String? _accessUid;
  Stream<AdminAccess>? _accessStream;
  Future<AdminAccess> Function()? _loadAccess;
  VoidCallback? _onSignOut;

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  void _syncRepo(AdminRepository? repo) {
    if (identical(repo, _repo)) return;
    _repo = repo;
    _authStream = repo?.authChanges();
    _accessUid = null;
    _accessStream = null;
    _loadAccess = null;
    _onSignOut = repo == null ? null : () => _handleSignOut(repo);
  }

  void _syncUser(AdminRepository repo, String uid) {
    if (_accessUid == uid && _accessStream != null && _loadAccess != null) return;
    _accessUid = uid;
    _loadAccess = () => repo.adminAccess(uid);
    _accessStream = repo.accessChanges(uid);
  }

  void _clearUser() {
    _accessUid = null;
    _accessStream = null;
    _loadAccess = null;
  }

  Future<void> _loadRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_rememberMePrefKey) ?? false;
      if (mounted && saved != _rememberMe) {
        setState(() => _rememberMe = saved);
      }
    } catch (_) {}
  }

  Future<void> _setRememberMe(bool value) async {
    if (mounted) setState(() => _rememberMe = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMePrefKey, value);
    } catch (_) {}
  }

  Future<void> _handleSignOut(AdminRepository repo) async {
    await _setRememberMe(false);
    await repo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final repo = ref.watch(adminRepositoryProvider);
    _syncRepo(repo);
    if (repo == null) return _AdminFrame(child: Center(child: Text(context.tr('adminUnavailable'))));
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _AdminFrame(child: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) {
          _clearUser();
          return _AdminFrame(
            child: AdminLoginForm(
              onSignIn: repo.signInWithPersistence,
              onResetPassword: repo.sendPasswordReset,
              initialRememberMe: _rememberMe,
              onRememberMeSignedIn: _setRememberMe,
            ),
          );
        }
        _syncUser(repo, user.uid);
        return AdminCheckGate(
          key: ValueKey(user.uid),
          repo: repo,
          uid: user.uid,
          email: user.email ?? '',
          loadAccess: _loadAccess!,
          accessChanges: _accessStream!,
          rememberMe: _rememberMe,
          onSignOut: _onSignOut!,
        );
      },
    );
  }
}

/// Plain admin chrome for the sign-in / permission states.
class _AdminFrame extends ConsumerWidget {
  final Widget child;
  const _AdminFrame({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const ChurchSeal(size: 30),
          const SizedBox(width: 8),
          Flexible(child: Text(context.tr('admin'), overflow: TextOverflow.ellipsis)),
        ]),
        leading: IconButton(
          tooltip: context.tr('backHome'),
          icon: const Icon(Icons.home_rounded),
          onPressed: () => context.go('/'),
        ),
        actions: [const LanguageToggle()],
      ),
      body: child,
    );
  }
}

class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: context.tr('language'),
    onPressed: () => ref.read(localeProvider.notifier).toggle(),
    icon: Text(
      context.isAr ? 'EN' : 'ع',
      style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.onPrimaryAccent),
    ),
  );
}

/// Checks admins/{uid}; a failed lookup shows a retry action instead of the
/// "not admin" screen, and paused/expired accounts see a clear status message.
class AdminCheckGate extends StatefulWidget {
  final AdminBackend repo;
  final String uid;
  final String email;
  final Future<AdminAccess> Function() loadAccess;
  final Stream<AdminAccess> accessChanges;
  final bool rememberMe;
  final VoidCallback onSignOut;
  const AdminCheckGate({
    super.key,
    required this.repo,
    required this.uid,
    required this.email,
    required this.loadAccess,
    required this.accessChanges,
    required this.rememberMe,
    required this.onSignOut,
  });

  @override
  State<AdminCheckGate> createState() => _AdminCheckGateState();
}

class _AdminCheckGateState extends State<AdminCheckGate> {
  static const _maxTimerDelay = Duration(days: 24);
  late Future<AdminAccess> _future = widget.loadAccess();
  Timer? _expiryTimer;
  DateTime? _scheduledExpiry;
  DateTime? _expiredForTarget;
  AdminAccess? _lastLiveAccess;
  int _expiryGen = 0;

  @override
  void didUpdateWidget(covariant AdminCheckGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.loadAccess != widget.loadAccess ||
        oldWidget.accessChanges != widget.accessChanges ||
        oldWidget.repo != widget.repo) {
      _future = widget.loadAccess();
      _scheduledExpiry = null;
      _expiredForTarget = null;
      _lastLiveAccess = null;
      _expiryGen++;
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
  }

  @override
  void dispose() {
    _expiryGen++;
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _ensureExpiryTimer(AdminAccess access) {
    final target = access.isAllowed ? access.expiresAt?.toUtc() : null;
    if (target == _scheduledExpiry) return;
    _scheduledExpiry = target;
    if (_expiredForTarget != target) _expiredForTarget = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final gen = ++_expiryGen;
    if (target == null) return;
    final remaining = target.difference(DateTime.now().toUtc());
    _scheduleExpiryStep(target, gen, remaining);
  }

  void _scheduleExpiryStep(DateTime targetUtc, int gen, Duration remaining) {
    if (!mounted || gen != _expiryGen || _scheduledExpiry != targetUtc) return;
    if (remaining <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _expiryGen && _scheduledExpiry == targetUtc) {
          setState(() => _expiredForTarget = targetUtc);
        }
      });
      return;
    }
    // Cap each Timer step at 24 days so 32-bit JS setTimeout never overflows (~24.8 days).
    final isChunk = remaining > _maxTimerDelay;
    final step = isChunk ? _maxTimerDelay : remaining;
    _expiryTimer = Timer(step, () {
      if (!mounted || gen != _expiryGen || _scheduledExpiry != targetUtc) return;
      if (!isChunk) {
        setState(() => _expiredForTarget = targetUtc);
        return;
      }
      final wallRemaining = targetUtc.difference(DateTime.now().toUtc());
      final trackedRemaining = remaining - _maxTimerDelay;
      final nextRemaining = wallRemaining < trackedRemaining ? wallRemaining : trackedRemaining;
      _scheduleExpiryStep(targetUtc, gen, nextRemaining);
    });
  }

  Widget _errorScreen(BuildContext context) => _AdminFrame(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: context.pal.alert),
              const SizedBox(height: 8),
              Text(context.tr('adminCheckFailed'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => setState(() {
                      _lastLiveAccess = null;
                      _future = widget.loadAccess();
                    }),
                    child: Text(context.tr('retry')),
                  ),
                  OutlinedButton(onPressed: widget.onSignOut, child: Text(context.tr('signOut'))),
                ],
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return FutureBuilder<AdminAccess>(
      future: _future,
      builder: (context, adm) {
        if (adm.connectionState != ConnectionState.done) {
          return const _AdminFrame(child: Center(child: CircularProgressIndicator()));
        }
        if (adm.hasError) {
          return _errorScreen(context);
        }
        // Live access after the authoritative server check: a demoted, stopped,
        // expired, or removed admin loses access at once.
        return StreamBuilder<AdminAccess>(
          stream: widget.accessChanges,
          initialData: adm.data,
          builder: (context, live) {
            if (!live.hasError &&
                (live.connectionState == ConnectionState.active || live.connectionState == ConnectionState.done) &&
                live.hasData) {
              _lastLiveAccess = live.data;
            }
            if (live.hasError) {
              final retained = _lastLiveAccess;
              if (retained == null) return _errorScreen(context);
              return _forAccess(context, retained);
            }
            final current = live.data ?? _lastLiveAccess ?? adm.data ?? const AdminAccess(status: AdminAccountStatus.none);
            return _forAccess(context, current);
          },
        );
      },
    );
  }

  Widget _forAccess(BuildContext context, AdminAccess rawAccess) {
    var access = rawAccess;
    final targetUtc = access.isAllowed ? access.expiresAt?.toUtc() : null;
    final firedForTarget = targetUtc != null && _expiredForTarget == targetUtc;
    if (access.isAllowed && targetUtc != null && (firedForTarget || !DateTime.now().toUtc().isBefore(targetUtc))) {
      access = AdminAccess(role: access.role, status: AdminAccountStatus.expired, expiresAt: access.expiresAt);
    }
    _ensureExpiryTimer(access);

    if (!access.isAllowed) {
      final (IconData icon, String message) = switch (access.status) {
        AdminAccountStatus.stopped => (Icons.pause_circle_outline, context.tr('adminStoppedAccount')),
        AdminAccountStatus.expired => (
            Icons.event_busy_outlined,
            access.expiresAt == null
                ? context.tr('adminExpiredAccount')
                : '${context.tr('adminExpiredAccount')} (${fmtDate(CairoTime.fromInstant(access.expiresAt!))})'
          ),
        _ => (Icons.lock_outline, context.tr('notAdmin')),
      };
      return _AdminFrame(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: context.pal.alert),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                Text(widget.email, style: TextStyle(color: context.pal.muted)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: widget.onSignOut, child: Text(context.tr('signOut'))),
              ],
            ),
          ),
        ),
      );
    }
    return AdminDashboard(
      repo: widget.repo,
      uid: widget.uid,
      email: widget.email.isEmpty ? widget.uid : widget.email,
      role: access.role!,
      rememberMe: widget.rememberMe,
      onSignOut: widget.onSignOut,
    );
  }
}

class AdminLoginForm extends StatefulWidget {
  final Future<void> Function(String email, String password, {bool rememberMe}) onSignIn;
  final Future<bool> Function(String email) onResetPassword;
  final bool initialRememberMe;
  final ValueChanged<bool>? onRememberMeSignedIn;
  const AdminLoginForm({
    super.key,
    required this.onSignIn,
    required this.onResetPassword,
    this.initialRememberMe = false,
    this.onRememberMeSignedIn,
  });

  @override
  State<AdminLoginForm> createState() => _AdminLoginFormState();
}

class _AdminLoginFormState extends State<AdminLoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _rememberMe = widget.initialRememberMe;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return; // Enter pressed while a sign-in is pending
    final failed = context.tr('signInFailed');
    final remember = _rememberMe;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignIn(_email.text, _password.text, rememberMe: remember);
      widget.onRememberMeSignedIn?.call(remember);
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final need = context.tr('enterEmailFirst');
    final sent = context.tr('resetSent');
    final failed = context.tr('resetFailed');
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = need);
      return;
    }
    var ok = false;
    try {
      ok = await widget.onResetPassword(email);
    } catch (_) {
      ok = false;
    }
    messenger.showSnackBar(SnackBar(content: Text(ok ? sent : failed)));
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('signIn'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.pal.primary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('login-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('login-password'),
                    controller: _password,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const ValueKey('login-remember-me'),
                    value: _rememberMe,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(context.tr('rememberMe')),
                    onChanged: _busy ? null : (v) => setState(() => _rememberMe = v ?? false),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: TextStyle(color: context.pal.alert)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('login-submit'),
                    onPressed: _busy ? null : _signIn,
                    child: _busy
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onBar),
                          )
                        : Text(context.tr('signIn')),
                  ),
                  const SizedBox(height: 6),
                  TextButton(onPressed: _busy ? null : _resetPassword, child: Text(context.tr('forgotPassword'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar / drawer navigation group (P2-18).
enum AdminGroup {
  home,
  schedule,
  announcements,
  church,
  services,
  pages,
  messages,
  ownerSettings,
}

/// One admin destination (sidebar / drawer entry).
class AdminDest {
  final String id;
  final IconData icon;
  final String labelAr, labelEn;
  final AdminGroup group;
  const AdminDest(
    this.id,
    this.icon,
    this.labelAr,
    this.labelEn, {
    this.group = AdminGroup.home,
  });
}

/// Destinations shown to [role] across 7 editor groups + owner settings (P2-18).
List<AdminDest> adminDestinations(String role) => [
      const AdminDest('overview', Icons.dashboard_outlined, 'الرئيسية', 'Overview', group: AdminGroup.home),
      // Schedule
      AdminDest('liturgies', adminIcon('liturgies'), 'القداسات والصلوات', 'Liturgies', group: AdminGroup.schedule),
      AdminDest('meetings', adminIcon('meetings'), 'الاجتماعات', 'Meetings', group: AdminGroup.schedule),
      const AdminDest('today', Icons.today_outlined, 'اليوم والبث', 'Today & live stream', group: AdminGroup.schedule),
      AdminDest('seasons', adminIcon('seasons'), 'المواسم', 'Seasons', group: AdminGroup.schedule),
      // Announcements
      AdminDest('alerts', adminIcon('alerts'), 'التنويهات', 'Notices', group: AdminGroup.announcements),
      const AdminDest('app', Icons.notifications_active_outlined, 'الإعلانات والإشعارات', 'Announcements & notifications',
          group: AdminGroup.announcements),
      // Church
      AdminDest('priests', adminIcon('priests'), 'الآباء الكهنة', 'Priests', group: AdminGroup.church),
      AdminDest('saints', adminIcon('saints'), 'شفعاء الكنيسة', 'Patron saints', group: AdminGroup.church),
      AdminDest('milestones', adminIcon('milestones'), 'محطات تاريخية', 'Milestones', group: AdminGroup.church),
      const AdminDest('church', Icons.church_outlined, 'بيانات الكنيسة', 'Church info', group: AdminGroup.church),
      // Services & activities
      AdminDest('facilities', adminIcon('services'), 'الخدمات العامة', 'Public services', group: AdminGroup.services),
      AdminDest('activities', adminIcon('activities'), 'الأنشطة والكورالات', 'Activities', group: AdminGroup.services),
      AdminDest('clinics', adminIcon('clinics'), 'العيادات', 'Clinics', group: AdminGroup.services),
      // Pages
      const AdminDest('features', Icons.toggle_on_outlined, 'الأقسام والرئيسية', 'Sections & home',
          group: AdminGroup.pages),
      AdminDest('pages', adminIcon('pages'), 'الصفحات المخصصة', 'Custom pages', group: AdminGroup.pages),
      AdminDest('categories', adminIcon('categories'), 'الأقسام المخصصة', 'Custom sections', group: AdminGroup.pages),
      // Messages
      const AdminDest('messages', Icons.mail_outline, 'رسائل الزوار', 'Contact messages', group: AdminGroup.messages),
      // Owner settings
      if (role == AdminRoles.owner) ...[
        const AdminDest('admins', Icons.admin_panel_settings_outlined, 'المشرفون', 'Admins',
            group: AdminGroup.ownerSettings),
        const AdminDest('contactCats', Icons.forum_outlined, 'أنواع رسائل التواصل', 'Contact form types',
            group: AdminGroup.ownerSettings),
        const AdminDest('assistant', Icons.smart_toy_outlined, 'المساعد الذكي', 'AI assistant',
            group: AdminGroup.ownerSettings),
        const AdminDest('seasonSettings', Icons.celebration_outlined, 'إعدادات المواسم', 'Season settings',
            group: AdminGroup.ownerSettings),
        const AdminDest('advanced', Icons.tune_outlined, 'متقدم', 'Advanced', group: AdminGroup.ownerSettings),
      ],
    ];

/// Responsive dashboard: sidebar on desktop, drawer on mobile.
class AdminDashboard extends StatefulWidget {
  final AdminBackend repo;
  final String uid, email, role;
  final VoidCallback onSignOut;
  final String initial;
  final bool rememberMe;
  final SessionPolicy sessionPolicy;
  const AdminDashboard({
    super.key,
    required this.repo,
    required this.uid,
    required this.email,
    required this.role,
    required this.onSignOut,
    this.initial = 'overview',
    this.rememberMe = false,
    this.sessionPolicy = const SessionPolicy(),
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

String _normalizeAdminDest(String id) => switch (id) {
      'entries' => 'categories',
      'departedPriests' => 'priests',
      _ => id,
    };

class _AdminDashboardState extends State<AdminDashboard> {
  final UnsavedGuardRegistry _unsaved = UnsavedGuardRegistry();
  final List<StreamSubscription> _purgeSubs = [];
  late String _current = _normalizeAdminDest(widget.initial);
  late Stream<List<AdminDoc>> _messagesStream = widget.repo.watch('contact_messages');

  @override
  void initState() {
    super.initState();
    _purgeExpiredSoftDeletes();
  }

  @override
  void didUpdateWidget(covariant AdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo) {
      _messagesStream = widget.repo.watch('contact_messages');
    }
  }

  void _purgeExpiredSoftDeletes() {
    for (final def in adminCollections) {
      final sub = widget.repo.watch(def.name).take(1).listen(
        (docs) {
          if (mounted) {
            purgeExpiredSoftDeletes(widget.repo, def, docs);
          }
        },
        onError: (Object _) {},
      );
      _purgeSubs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final sub in _purgeSubs) {
      sub.cancel();
    }
    _purgeSubs.clear();
    _unsaved.dispose();
    super.dispose();
  }

  Future<void> _open(String id) async {
    final target = _normalizeAdminDest(id);
    if (target == _current) return;
    if (_unsaved.isDirty) {
      final discard = await confirmDiscardChanges(context);
      if (!discard || !mounted) return;
    }
    if (mounted) setState(() => _current = target);
  }

  Future<void> _handleNavTap(String id, bool inDrawer) async {
    if (id == _current) {
      if (inDrawer) Navigator.of(context).pop();
      return;
    }
    if (_unsaved.isDirty) {
      final discard = await confirmDiscardChanges(context);
      if (!discard || !mounted) return;
    }
    if (inDrawer && mounted) Navigator.of(context).pop();
    if (mounted) setState(() => _current = id);
  }

  Future<void> _handleSignOut(bool inDrawer) async {
    if (_unsaved.isDirty) {
      final discard = await confirmDiscardChanges(context);
      if (!discard || !mounted) return;
    }
    if (inDrawer && mounted) Navigator.of(context).pop();
    widget.onSignOut();
  }

  bool get _isOwner => widget.role == AdminRoles.owner;

  Widget _ownerOnly() => Center(child: Text(context.tr('ownerOnly')));

  Widget _screen() {
    final repo = widget.repo;
    switch (_current) {
      case 'overview':
        return OverviewScreen(repo: repo, role: widget.role, onOpen: _open);
      case 'features':
        return Consumer(
          builder: (context, ref, _) => FeaturesScreen(
            repo: repo,
            activeSeasonKeys: [
              for (final k in ref.watch(activeSeasonKeysProvider).split(','))
                if (k.isNotEmpty) k,
            ],
          ),
        );
      // Keyed per section: 'today' and 'seasonSettings' edit the same
      // document (settings/features) with different fields, so a reused
      // screen would keep the other section's form state.
      case 'today':
        return ChurchInfoScreen(key: const ValueKey('today'), repo: repo, doc: todaySettingsDoc);
      case 'seasonSettings':
        return _isOwner
            ? ChurchInfoScreen(key: const ValueKey('seasonSettings'), repo: repo, doc: seasonSettingsDoc)
            : _ownerOnly();
      case 'seasons':
        return SeasonsHubScreen(key: const ValueKey('seasons'), repo: repo, initialTab: 0);
      case 'seasonPreset':
        return SeasonsHubScreen(key: const ValueKey('seasons-preset'), repo: repo, initialTab: 1);
      case 'app':
        return AppAndNotificationsScreen(key: const ValueKey('app'), repo: repo, role: widget.role);
      case 'church':
        return ChurchInfoScreen(key: const ValueKey('church'), repo: repo);
      case 'assistant':
        return _isOwner ? AssistantAdminScreen(repo: repo) : _ownerOnly();
      case 'messages':
        return MessagesScreen(repo: repo);
      case 'contactCats':
        return _isOwner ? ContactCategoriesScreen(repo: repo) : _ownerOnly();
      case 'admins':
        return _isOwner ? AdminsScreen(repo: repo, selfUid: widget.uid) : _ownerOnly();
      case 'advanced':
        return _isOwner
            ? Consumer(
                builder: (context, ref, _) => AdvancedOwnerScreen(
                  key: const ValueKey('advanced'),
                  repo: repo,
                  appCheckActive: ref.watch(firebaseStatusProvider).appCheckActive,
                ),
              )
            : _ownerOnly();
    }
    final def = collectionById(_normalizeAdminDest(_current));
    if (def == null) return OverviewScreen(repo: repo, role: widget.role, onOpen: _open);
    return CollectionListScreen(key: ValueKey(def.id), repo: repo, def: def);
  }

  Widget _nav(BuildContext context, {required bool inDrawer}) {
    final dests = adminDestinations(widget.role);
    // A Material (not a coloured Container) so the selected tile's highlight
    // is painted where it can be seen (PR #23: it was hidden under the
    // Container colour, leaving only the text tinted).
    return Material(
      color: context.pal.surfaceAlt,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: context.pal.success, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          context.tr('role_${widget.role}'),
                          style: TextStyle(color: context.pal.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (final g in AdminGroup.values)
              if (dests.any((d) => d.group == g)) ...[
                Padding(
                  key: ValueKey('nav-group-${g.name}'),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    context.tr('grp_${g.name}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.pal.muted,
                    ),
                  ),
                ),
                for (final d in dests.where((d) => d.group == g))
                  ListTile(
                    key: ValueKey('nav-${d.id}'),
                    dense: true,
                    leading: Icon(d.icon),
                    title: Text(context.pick(d.labelAr, d.labelEn), style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: d.id == 'messages' ? _messagesBadge(context) : null,
                    selected: _current == d.id || (d.id == 'seasons' && _current == 'seasonPreset'),
                    // Same colours for every entry: burgundy icons, ink labels;
                    // the selected one gets a gold highlight and a burgundy
                    // label (icon and text alike).
                    iconColor: context.pal.primary,
                    textColor: context.pal.ink,
                    selectedColor: context.pal.primary,
                    selectedTileColor: context.pal.ornament.withValues(alpha: 0.22),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    onTap: () => _handleNavTap(d.id, inDrawer),
                  ),
              ],
            const Divider(),
            ListTile(
              dense: true,
              leading: Icon(Icons.logout, color: context.pal.alert),
              title: Text(context.tr('signOut')),
              onTap: () => _handleSignOut(inDrawer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messagesBadge(BuildContext context) => StreamBuilder<List<AdminDoc>>(
        key: ObjectKey(_messagesStream),
        stream: _messagesStream,
        builder: (context, snap) {
          final unread = (snap.data ?? const <AdminDoc>[])
              .where((d) => !isSoftDeleted(d.data) && messageIsOpen(d.data))
              .length;
          if (unread <= 0) return const SizedBox.shrink();
          return Container(
            key: const ValueKey('nav-messages-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: context.pal.alert,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$unread',
              style: TextStyle(
                color: context.pal.onBar,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      );

  Future<void> _handleOpenSite() async {
    if (_unsaved.isDirty) {
      final discard = await confirmDiscardChanges(context);
      if (!discard || !mounted) return;
    }
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final resolvedId = _current == 'seasonPreset' ? 'seasons' : _current;
    final dest = adminDestinations(widget.role)
        .firstWhere((d) => d.id == resolvedId, orElse: () => adminDestinations(widget.role).first);
    return UnsavedGuardScope(
      registry: _unsaved,
      child: AdminSessionGuard(
        enabled: !widget.rememberMe,
        policy: widget.sessionPolicy,
        unsaved: _unsaved,
        onSignOut: widget.onSignOut,
        child: ListenableBuilder(
          listenable: _unsaved,
          builder: (context, child) => PopScope(
            canPop: !_unsaved.isDirty,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final discard = await confirmDiscardChanges(context);
              if (discard && context.mounted) {
                final nav = Navigator.of(context);
                if (nav.canPop()) nav.pop(result);
              }
            },
            child: child!,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const ChurchSeal(size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${context.tr('admin')} — ${context.pick(dest.labelAr, dest.labelEn)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: context.tr('openSite'),
                  icon: const Icon(Icons.public),
                  onPressed: _handleOpenSite,
                ),
                const LanguageToggle(),
              ],
            ),
            drawer: wide ? null : Drawer(child: _nav(context, inDrawer: true)),
            body: wide
                ? Row(
                    children: [
                      SizedBox(width: 270, child: _nav(context, inDrawer: false)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _screen()),
                    ],
                  )
                : _screen(),
          ),
        ),
      ),
    );
  }
}
