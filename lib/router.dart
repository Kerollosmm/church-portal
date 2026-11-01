import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';
import 'core/l10n.dart';
import 'state/providers.dart';
// Deferred (plan PR 3, 3.3): separate web chunks, fetched only on /admin and
// /ask, so the public bundle excludes the admin dashboard and the AI SDK.
import 'ui/admin/admin_page.dart' deferred as admin_page;
import 'ui/pages/about_page.dart';
import 'ui/pages/activities_page.dart';
import 'ui/pages/assistant_page.dart' deferred as assistant_page;
import 'ui/pages/clinics_page.dart';
import 'ui/pages/contact_page.dart';
import 'ui/pages/education_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/mass_schedule_page.dart';
import 'ui/pages/public_services_page.dart';
import 'ui/widgets/app_shell.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/deferred_loader.dart';
import 'ui/widgets/feature_gate.dart';

/// Every public page is wrapped in a [FeatureGate]: a section switched off in
/// `settings/features` shows "not available" instead of its content.
NoTransitionPage<void> _page(GoRouterState s, Widget child) =>
    NoTransitionPage(key: s.pageKey, child: FeatureGate(path: s.uri.path, child: child));

/// Rewrites `?lang=` to match the selected language (`lang=en` for English,
/// no parameter for Arabic, the default). Null when the URL already matches.
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

/// What the router does about `?lang=` for one navigation.
class LangSync {
  /// Location to redirect to (null = keep the URL).
  final String? redirect;

  /// Language the URL asks for (null = keep the selected language).
  final bool? english;
  const LangSync({this.redirect, this.english});
}

/// Bidirectional `?lang=` sync (BUG-07):
/// - [userToggled] (EN/ع button): the URL follows the language.
/// - an explicit `lang=en` / `lang=ar` (deep link, shared or in-app link,
///   Back/Forward): the language follows the URL.
/// - no `lang` while English: from the browser history / platform
///   ([fromPlatform]) it means Arabic; from in-app navigation
///   (`context.go('/clinics')`) English is kept and `lang=en` added.
/// Arabic stays the canonical, parameter-free URL.
LangSync resolveLangSync(Uri uri,
    {required bool english, bool userToggled = false, bool fromPlatform = false}) {
  if (userToggled) return LangSync(redirect: _syncLangQuery(uri, english));
  final q = uri.queryParameters['lang'];
  if (q == 'en') return LangSync(english: english ? null : true);
  if (q == 'ar') {
    // Arabic is the default: drop the explicit parameter (canonical URL).
    final qp = Map<String, String>.from(uri.queryParameters)..remove('lang');
    final canonical = Uri(path: uri.path.isEmpty ? '/' : uri.path, queryParameters: qp.isEmpty ? null : qp).toString();
    return LangSync(english: english ? false : null, redirect: canonical);
  }
  if (english && fromPlatform) return const LangSync(english: false);
  return LangSync(redirect: _syncLangQuery(uri, english));
}

/// Notes route changes reported by the platform (browser Back/Forward,
/// address bar, Android deep links) so the redirect can tell them apart from
/// in-app `context.go` navigation. Registered before go_router's own
/// observer, so it sees each report first; it never consumes it.
class _PlatformRouteObserver with WidgetsBindingObserver {
  bool _pending = false;

  bool consume() {
    final v = _pending;
    _pending = false;
    return v;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    _pending = true;
    return Future<bool>.value(false);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects (URL lang sync) when the language is toggled, without
  // rebuilding the router itself.
  final localeChanges = ValueNotifier<int>(0);
  ref.listen(localeProvider, (_, _) => localeChanges.value++);
  ref.onDispose(localeChanges.dispose);
  final platformNav = _PlatformRouteObserver();
  WidgetsBinding.instance.addObserver(platformNav);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(platformNav));
  // Last URL the redirect accepted as-is. The same URL again means a refresh
  // (the language changed, the location did not): the URL follows the
  // language, like a toggle.
  Uri? lastSyncedUri;
  return GoRouter(
    initialLocation: '/',
    refreshListenable: localeChanges,
    redirect: (context, state) {
      final notifier = ref.read(localeProvider.notifier);
      final english = ref.read(localeProvider).languageCode == 'en';
      final toggled = notifier.consumeUserChange();
      final r = resolveLangSync(
        state.uri,
        english: english,
        userToggled: toggled || state.uri == lastSyncedUri,
        fromPlatform: platformNav.consume(),
      );
      if (r.english != null) {
        final target = r.english! ? const Locale('en') : const Locale('ar');
        // Not during the router's build: change the language right after.
        scheduleMicrotask(() => notifier.syncFromUrl(target));
      }
      if (r.redirect == null) lastSyncedUri = state.uri;
      return r.redirect;
    },
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
          GoRoute(
            path: '/ask',
            pageBuilder: (c, s) => _page(
                s,
                DeferredLoader(
                  loadLibrary: assistant_page.loadLibrary,
                  builder: (_) => assistant_page.AssistantPage(),
                )),
          ),
        ],
      ),
      GoRoute(
        path: AppConfig.adminPath,
        builder: (c, s) => DeferredLoader(
          loadLibrary: admin_page.loadLibrary,
          builder: (_) => admin_page.AdminPage(),
          fullScreen: true,
        ),
      ),
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
