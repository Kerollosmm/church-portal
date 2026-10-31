import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';
import 'core/l10n.dart';
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

NoTransitionPage<void> _page(GoRouterState s, Widget child) => NoTransitionPage(key: s.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
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
