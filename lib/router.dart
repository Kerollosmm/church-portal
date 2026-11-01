import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';
import 'core/l10n.dart';
import 'state/providers.dart';
import 'ui/admin/admin_page.dart';
import 'ui/pages/about_page.dart';
import 'ui/pages/activities_page.dart';
import 'ui/pages/assistant_page.dart';
import 'ui/pages/clinics_page.dart';
import 'ui/pages/contact_page.dart';
import 'ui/pages/education_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/mass_schedule_page.dart';
import 'ui/pages/public_services_page.dart';
import 'ui/widgets/app_shell.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/feature_gate.dart';

/// Every public page is wrapped in a [FeatureGate]: a section switched off in
/// `settings/features` shows "not available" instead of its content.
NoTransitionPage<void> _page(GoRouterState s, Widget child) =>
    NoTransitionPage(key: s.pageKey, child: FeatureGate(path: s.uri.path, child: child));

/// Keeps `?lang=en` in the URL in sync with the selected language, so links
/// copied from the address bar, reloads and in-app navigation keep English.
String? _syncLangQuery(Uri uri, bool english) {
  final hasEn = uri.queryParameters['lang'] == 'en';
  if (english == hasEn) return null;
  final qp = Map<String, String>.from(uri.queryParameters);
  if (english) {
    qp['lang'] = 'en';
  } else {
    qp.remove('lang');
  }
  return Uri(path: uri.path.isEmpty ? '/' : uri.path, queryParameters: qp.isEmpty ? null : qp).toString();
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects (URL lang sync) when the language is toggled, without
  // rebuilding the router itself.
  final localeChanges = ValueNotifier<int>(0);
  ref.listen(localeProvider, (_, _) => localeChanges.value++);
  ref.onDispose(localeChanges.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: localeChanges,
    redirect: (context, state) =>
        _syncLangQuery(state.uri, ref.read(localeProvider).languageCode == 'en'),
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => _page(s, const HomePage())),
          GoRoute(path: '/about', pageBuilder: (c, s) => _page(s, const AboutPage())),
          GoRoute(path: '/mass-schedule', pageBuilder: (c, s) => _page(s, const MassSchedulePage())),
          GoRoute(path: '/church-education', pageBuilder: (c, s) => _page(s, const EducationPage())),
          GoRoute(path: '/church-activities', pageBuilder: (c, s) => _page(s, const ActivitiesPage())),
          GoRoute(
            path: '/clinics',
            pageBuilder: (c, s) => _page(s, ClinicsPage(initialSpecialty: s.uri.queryParameters['specialty'])),
          ),
          GoRoute(path: '/public-services', pageBuilder: (c, s) => _page(s, const PublicServicesPage())),
          GoRoute(path: '/contact', pageBuilder: (c, s) => _page(s, const ContactPage())),
          GoRoute(path: '/ask', pageBuilder: (c, s) => _page(s, const AssistantPage())),
        ],
      ),
      GoRoute(path: AppConfig.adminPath, builder: (c, s) => const AdminPage()),
    ],
    errorBuilder: (context, state) => AppShell(
      location: state.uri.path,
      child: PageBody(children: [
        const SizedBox(height: 40),
        const Icon(Icons.explore_off_rounded, size: 64),
        const SizedBox(height: 12),
        Text(context.tr('notFound'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Center(child: FilledButton(onPressed: () => context.go('/'), child: Text(context.tr('backHome')))),
      ]),
    ),
  );
});
