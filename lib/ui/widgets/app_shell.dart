import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../state/providers.dart';
import 'coptic_cross.dart';

class NavItem {
  final String key;
  final String path;
  final IconData icon;
  const NavItem(this.key, this.path, this.icon);
}

const navItems = [
  NavItem('home', '/', Icons.home_rounded),
  NavItem('massSchedule', '/mass-schedule', Icons.access_time_filled_rounded),
  NavItem('clinics', '/clinics', Icons.local_hospital_rounded),
  NavItem('education', '/church-education', Icons.school_rounded),
  NavItem('activities', '/church-activities', Icons.groups_rounded),
  NavItem('publicServices', '/public-services', Icons.volunteer_activism_rounded),
  NavItem('about', '/about', Icons.church_rounded),
  NavItem('contact', '/contact', Icons.call_rounded),
];
const askNavItem = NavItem('ask', '/ask', Icons.auto_awesome_rounded);

/// Common chrome for all public pages: app bar (logo, services menu,
/// highlighted Mass times + Clinics buttons, language toggle) and drawer.
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Large system text makes the full link bar overflow: compare the width
    // in "unscaled text" units so big text switches to the compact bar.
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width / textScale.clamp(1.0, 3.0) >= 1024;
    // Ultra-narrow phones (< 360 px) or very large text: the highlighted
    // Mass/Clinics buttons move to the drawer (they are already listed
    // there) so the church title never overflows or clips.
    final collapseHighlights = !wide && (width < 360 || textScale >= 1.5);
    // Subpages on phones get a 1-tap Back-to-Home arrow: every in-app link is
    // a sibling route (context.go), so there is nothing to pop, and installed
    // PWAs have no browser back button.
    final showBack = !wide && location != '/';
    final showAsk = ref.watch(assistantVisibleProvider);
    final features = ref.watch(featuresProvider);
    final showMass = !collapseHighlights && features.routeEnabled('/mass-schedule');
    final showClinics = !collapseHighlights && features.routeEnabled('/clinics');
    final settings = ref.watch(settingsProvider).value;
    // Full church name (admin-editable in settings); bundled l10n name until settings load.
    final fullName = settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: wide ? 16 : 0,
        leadingWidth: showBack ? 48 : null,
        leading: showBack
            ? IconButton(
                key: const Key('backHome'),
                tooltip: context.tr('backHome'),
                // Mirrored automatically in RTL (matchTextDirection).
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/'),
              )
            : null,
        title: InkWell(
          onTap: () => context.go('/'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ChurchSeal(size: wide ? 46 : 38),
            const SizedBox(width: 10),
            // The full name is long: on wide screens show it under the short
            // name; on phones show only the short name (max two lines).
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(context.tr('appShort'),
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: wide ? 17 : 14, height: 1.25)),
                if (wide)
                  Text(fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.goldLight, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
        actions: [
          if (wide) ...[
            _navText(context, 'home', '/'),
            if (features.routeEnabled('/about')) _navText(context, 'about', '/about'),
            if (features.routeEnabled('/church-education')) _navText(context, 'education', '/church-education'),
            _ServicesMenu(showAsk: showAsk),
            const SizedBox(width: 8),
          ],
          if (showMass) ...[
            _HighlightButton(
              label: context.tr('massSchedule'),
              icon: Icons.access_time_filled_rounded,
              onTap: () => context.go('/mass-schedule'),
              compact: !wide,
              gold: true,
            ),
            const SizedBox(width: 6),
          ],
          if (showClinics)
            _HighlightButton(
              label: context.tr('clinics'),
              icon: Icons.local_hospital_rounded,
              onTap: () => context.go('/clinics'),
              compact: !wide,
            ),
          IconButton(
            tooltip: context.tr('language'),
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            icon: Text(context.isAr ? 'EN' : 'ع',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.goldLight, fontSize: 16)),
          ),
          if (!wide)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: context.tr('menu'),
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      endDrawer: wide ? null : _AppDrawer(location: location, showAsk: showAsk),
      body: child,
    );
  }

  Widget _navText(BuildContext context, String key, String path) {
    final selected = location == path;
    return TextButton(
      onPressed: () => context.go(path),
      style: TextButton.styleFrom(foregroundColor: selected ? AppColors.goldLight : Colors.white),
      child: Text(context.tr(key), style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
    );
  }
}

/// Nav items whose section is switched on (the assistant also needs
/// [showAsk]: App Check + `assistantEnabled`).
List<NavItem> visibleNavItems(FeatureSettings f, {required bool showAsk}) =>
    [for (final i in navItems) if (f.routeEnabled(i.path)) i, if (showAsk) askNavItem];

class _ServicesMenu extends ConsumerWidget {
  final bool showAsk;
  const _ServicesMenu({required this.showAsk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(featuresProvider);
    final items = [
      for (final i in [navItems[4], navItems[5], navItems[7]]) // activities, public services, contact
        if (f.routeEnabled(i.path)) i,
      if (showAsk) askNavItem,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: context.tr('services'),
      onSelected: (p) => context.go(p),
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem(
            value: i.path,
            child: Row(children: [
              Icon(i.icon, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(context.tr(i.key)),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Text(context.tr('services'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const Icon(Icons.arrow_drop_down, color: Colors.white),
        ]),
      ),
    );
  }
}

class _HighlightButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final bool gold;
  const _HighlightButton(
      {required this.label, required this.icon, required this.onTap, this.compact = false, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final bg = gold ? AppColors.gold : Colors.white;
    final fg = gold ? AppColors.ink : Theme.of(context).colorScheme.primary;
    if (compact) {
      // 48x48 dp minimum touch target (WCAG 2.5.8 / Material guideline).
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        style: IconButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        icon: Icon(icon, size: 20),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  final String location;
  final bool showAsk;
  const _AppDrawer({required this.location, required this.showAsk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = visibleNavItems(ref.watch(featuresProvider), showAsk: showAsk);
    final settings = ref.watch(settingsProvider).value;
    return Drawer(
      backgroundColor: AppColors.cream,
      child: SafeArea(
        child: ListView(children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.primary,
            child: Row(children: [
              const ChurchSeal(size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Text(settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.4)),
              ),
            ]),
          ),
          for (final i in items)
            ListTile(
              leading: Icon(i.icon, color: Theme.of(context).colorScheme.primary),
              title: Text(context.tr(i.key), style: const TextStyle(fontWeight: FontWeight.w600)),
              selected: location == i.path,
              selectedTileColor: AppColors.gold.withValues(alpha: 0.15),
              onTap: () {
                Navigator.of(context).pop();
                context.go(i.path);
              },
            ),
        ]),
      ),
    );
  }
}
