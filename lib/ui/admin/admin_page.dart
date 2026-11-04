import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../data/error_reporting.dart';
import '../../state/providers.dart';
import '../widgets/coptic_cross.dart';
import 'admin_schema.dart';
import 'admin_screens.dart';
import 'assistant_admin.dart';
import 'contact_admin.dart';
import 'collection_list.dart';
import 'features_editor.dart';
import 'season_preset_admin.dart';

/// Hidden /admin area: email/password sign-in, role check (admins/{uid}),
/// then the dashboard.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(adminRepositoryProvider);
    if (repo == null) return _AdminFrame(child: Center(child: Text(context.tr('adminUnavailable'))));
    return StreamBuilder<User?>(
      stream: repo.authChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _AdminFrame(child: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return _AdminFrame(child: _LoginForm(repo: repo));
        return _AdminCheck(key: ValueKey(user.uid), repo: repo, user: user);
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
/// "not admin" screen.
class _AdminCheck extends StatefulWidget {
  final AdminRepository repo;
  final User user;
  const _AdminCheck({super.key, required this.repo, required this.user});

  @override
  State<_AdminCheck> createState() => _AdminCheckState();
}

class _AdminCheckState extends State<_AdminCheck> {
  late Future<String?> _future = widget.repo.adminRole(widget.user.uid);
  late final Stream<String?> _roleStream = widget.repo.roleChanges(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final user = widget.user;
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, adm) {
        if (adm.connectionState != ConnectionState.done) {
          return const _AdminFrame(child: Center(child: CircularProgressIndicator()));
        }
        if (adm.hasError) {
          return _AdminFrame(
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
                        onPressed: () => setState(() => _future = repo.adminRole(user.uid)),
                        child: Text(context.tr('retry')),
                      ),
                      OutlinedButton(onPressed: repo.signOut, child: Text(context.tr('signOut'))),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        // Live role after the authoritative server check: a demoted or
        // removed admin loses the owner screens (or the dashboard) at once.
        return StreamBuilder<String?>(
          stream: _roleStream,
          initialData: adm.data,
          builder: (context, live) => _forRole(context, live.hasError ? adm.data : live.data),
        );
      },
    );
  }

  Widget _forRole(BuildContext context, String? role) {
    final repo = widget.repo;
    final user = widget.user;
    if (role == null) {
      return _AdminFrame(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: context.pal.alert),
              const SizedBox(height: 8),
              Text(context.tr('notAdmin')),
              Text(user.email ?? '', style: TextStyle(color: context.pal.muted)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: repo.signOut, child: Text(context.tr('signOut'))),
            ],
          ),
        ),
      );
    }
    return AdminDashboard(
      repo: repo,
      uid: user.uid,
      email: user.email ?? user.uid,
      role: role,
      onSignOut: repo.signOut,
    );
  }
}

class _LoginForm extends StatefulWidget {
  final AdminRepository repo;
  const _LoginForm({required this.repo});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.signIn(_email.text, _password.text);
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
      ok = await widget.repo.sendPasswordReset(email);
    } catch (_) {
      ok = false;
    }
    messenger.showSnackBar(SnackBar(content: Text(ok ? sent : failed)));
  }

  @override
  Widget build(BuildContext context) {
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
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: TextStyle(color: context.pal.alert)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
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

/// One admin destination (sidebar / drawer entry).
class AdminDest {
  final String id;
  final IconData icon;
  final String labelAr, labelEn;
  const AdminDest(this.id, this.icon, this.labelAr, this.labelEn);
}

/// Destinations shown to [role] (owners also get "Admins").
List<AdminDest> adminDestinations(String role) => [
  const AdminDest('overview', Icons.dashboard_outlined, 'نظرة عامة', 'Overview'),
  const AdminDest('features', Icons.toggle_on_outlined, 'الأقسام والصفحة الرئيسية', 'Sections & home page'),
  const AdminDest('today', Icons.today_outlined, 'اليوم والبث المباشر', 'Today & live stream'),
  const AdminDest('seasonSettings', Icons.celebration_outlined, 'إعدادات المواسم', 'Season settings'),
  const AdminDest('seasonPreset', Icons.checklist_rounded, 'تجهيز الموسم', 'Season preparation'),
  const AdminDest('church', Icons.church_outlined, 'بيانات الكنيسة', 'Church info'),
  const AdminDest('assistant', Icons.smart_toy_outlined, 'المساعد الذكي', 'AI assistant'),
  for (final c in adminCollections) AdminDest(c.id, adminIcon(c.icon), c.labelAr, c.labelEn),
  const AdminDest('messages', Icons.mail_outline, 'رسائل الزوار', 'Contact messages'),
  const AdminDest('contactCats', Icons.forum_outlined, 'أنواع رسائل التواصل', 'Contact form types'),
  if (role == AdminRoles.owner) const AdminDest('admins', Icons.admin_panel_settings_outlined, 'المشرفون', 'Admins'),
];

/// Responsive dashboard: sidebar on desktop, drawer on mobile.
class AdminDashboard extends StatefulWidget {
  final AdminBackend repo;
  final String uid, email, role;
  final VoidCallback onSignOut;
  final String initial;
  const AdminDashboard({
    super.key,
    required this.repo,
    required this.uid,
    required this.email,
    required this.role,
    required this.onSignOut,
    this.initial = 'overview',
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late String _current = widget.initial;

  void _open(String id) => setState(() => _current = id);

  Widget _screen() {
    final repo = widget.repo;
    switch (_current) {
      case 'overview':
        return OverviewScreen(repo: repo, role: widget.role, onOpen: _open);
      case 'features':
        return Consumer(
          builder: (context, ref, _) => FeaturesScreen(
            repo: repo,
            // Owner only (ADR-034): one harmless test event to check Sentry.
            onSendTestError: widget.role == AdminRoles.owner ? ErrorReporting.sendTestEvent : null,
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
        return ChurchInfoScreen(key: const ValueKey('seasonSettings'), repo: repo, doc: seasonSettingsDoc);
      case 'seasonPreset':
        return SeasonPresetScreen(repo: repo);
      case 'church':
        return ChurchInfoScreen(key: const ValueKey('church'), repo: repo);
      case 'assistant':
        return AssistantAdminScreen(repo: repo);
      case 'messages':
        return MessagesScreen(repo: repo);
      case 'contactCats':
        return ContactCategoriesScreen(repo: repo);
      case 'admins':
        return widget.role == AdminRoles.owner
            ? AdminsScreen(repo: repo, selfUid: widget.uid)
            : Center(child: Text(context.tr('ownerOnly')));
    }
    final def = collectionById(_current);
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
            for (final d in dests)
              ListTile(
                key: ValueKey('nav-${d.id}'),
                dense: true,
                leading: Icon(d.icon),
                title: Text(context.pick(d.labelAr, d.labelEn), style: const TextStyle(fontWeight: FontWeight.w600)),
                selected: _current == d.id,
                // Same colours for every entry: burgundy icons, ink labels;
                // the selected one gets a gold highlight and a burgundy
                // label (icon and text alike).
                iconColor: context.pal.primary,
                textColor: context.pal.ink,
                selectedColor: context.pal.primary,
                selectedTileColor: context.pal.ornament.withValues(alpha: 0.22),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                onTap: () {
                  if (inDrawer) Navigator.of(context).pop();
                  _open(d.id);
                },
              ),
            const Divider(),
            ListTile(
              dense: true,
              leading: Icon(Icons.logout, color: context.pal.alert),
              title: Text(context.tr('signOut')),
              onTap: widget.onSignOut,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final dest = adminDestinations(widget.role)
        .firstWhere((d) => d.id == _current, orElse: () => adminDestinations(widget.role).first);
    return Scaffold(
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
          IconButton(tooltip: context.tr('openSite'), icon: const Icon(Icons.public), onPressed: () => context.go('/')),
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
    );
  }
}
