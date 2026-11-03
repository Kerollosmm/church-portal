import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../state/providers.dart';
import 'coptic_cross.dart';
import 'ornaments.dart';

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

/// Where the phone Back arrow goes from [location]: an item detail page
/// (`/clinics/<id>`, `/about/priests/<id>`…) returns to the page listing it
/// (milestones: Home, where "Our story" lives); every other route goes Home.
String parentRouteOf(String location) => parseDetailPath(location)?.$1.parentPath ?? '/';

/// l10n key naming the page [parentRoute] (for "Back to …").
String _parentLabelKey(String parentRoute) => switch (parentRoute) {
      '/church-education' => 'education',
      '/church-activities' => 'activities',
      '/clinics' => 'clinics',
      '/public-services' => 'publicServices',
      '/about' => 'about',
      _ => 'home',
    };

/// "Back to …" for a detail page's parent ("Back to home" for Home).
String backToLabel(BuildContext context, String parentRoute) =>
    parentRoute == '/' ? context.tr('backHome') : context.tr('backTo', {'s': context.tr(_parentLabelKey(parentRoute))});

/// Paths grouped under «خدمات الكنيسة / Church services» (desktop menu and
/// drawer group); the rest sit under «الكنيسة / The church».
const serviceNavPaths = ['/mass-schedule', '/church-education', '/church-activities', '/public-services', '/clinics'];

/// Common chrome for all public pages ("Iconostasis"): a vellum app bar with
/// the seal and church name, the grouped menu (Home · About · Church
/// services ▾ · Ask · Contact) and one primary "Mass times" action on wide
/// screens, the interlace band underneath, and the grouped end drawer on phones.
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
    // Subpages on phones get a 1-tap Back-to-Home arrow: every in-app link is
    // a sibling route (context.go), so there is nothing to pop, and installed
    // PWAs have no browser back button.
    final showBack = !wide && location != '/';
    // Item detail pages go back to the section that lists them, not Home.
    final parent = parentRouteOf(location);
    final toParent = parent != '/' || parseDetailPath(location) != null;
    // Ultra-narrow phones (< 360 px), very large text, or a subpage below
    // 400 px (the Back arrow takes another 48 dp): the highlighted Mass/Clinics
    // buttons move to the drawer (they are already listed there) so the church
    // title keeps a readable width.
    final collapseHighlights = !wide && (width < 360 || textScale >= 1.5 || (showBack && width < 400));
    final showAsk = ref.watch(assistantVisibleProvider);
    final features = ref.watch(featuresProvider);
    // Until settings/features arrives the defaults are "everything on": wait
    // before showing highlight buttons for sections an admin may have off.
    final ready = ref.watch(featuresReadyProvider);
    final showMass = ready && !collapseHighlights && features.routeEnabled('/mass-schedule');
    final showClinics = ready && !wide && !collapseHighlights && features.routeEnabled('/clinics');
    final settings = ref.watch(settingsProvider).value;
    // Full church name (admin-editable in settings); bundled l10n name until settings load.
    final fullName = settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wide ? 76 : 64,
        titleSpacing: wide ? 24 : (showBack ? 0 : 12),
        leadingWidth: showBack ? 48 : null,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(12), child: InterlaceBand()),
        leading: showBack
            ? IconButton(
                key: Key(toParent ? 'backParent' : 'backHome'),
                tooltip: toParent ? backToLabel(context, parent) : context.tr('backHome'),
                // Mirrored automatically in RTL (matchTextDirection).
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go(parent),
              )
            : null,
        title: InkWell(
          onTap: () => context.go('/'),
          child: LayoutBuilder(builder: (context, c) {
            // Wide bars with many menu entries (or very large text) leave the
            // title little room: fall back to the seal alone, never overflow.
            final seal = wide ? 48.0 : 38.0;
            if (c.maxWidth < seal + 70) {
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: ChurchSeal(size: c.maxWidth < seal ? c.maxWidth : seal),
              );
            }
            return Row(mainAxisSize: MainAxisSize.min, children: [
              ChurchSeal(size: seal),
              const SizedBox(width: 10),
              // The full name is long: on wide screens show it under the short
              // name; on phones show only the short name (max two lines).
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('appShort'),
                      maxLines: wide ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(context, size: wide ? 18 : 15, color: AppColors.ink, height: 1.3)),
                  if (wide)
                    Text(fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w400)),
                ]),
              ),
            ]);
          }),
        ),
        actions: [
          if (wide) ...[
            // Capped and scrollable: very large text or long labels never
            // overflow the bar (the title then falls back to the seal).
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _navText(context, 'home', '/'),
                  if (features.routeEnabled('/about')) _navText(context, 'about', '/about'),
                  _ServicesMenu(location: location),
                  if (showAsk) _navText(context, 'ask', '/ask'),
                  if (features.routeEnabled('/contact')) _navText(context, 'contact', '/contact'),
                ]),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: context.tr('language'),
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            style: IconButton.styleFrom(side: const BorderSide(color: AppColors.hairline)),
            icon: Text(context.isAr ? 'EN' : 'ع',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldText, fontSize: 15)),
          ),
          const SizedBox(width: 6),
          if (showMass) ...[
            _HighlightButton(
              label: context.tr('massSchedule'),
              icon: Icons.access_time_filled_rounded,
              onTap: () => context.go('/mass-schedule'),
              compact: !wide,
              filled: true,
            ),
            const SizedBox(width: 6),
          ],
          if (showClinics) ...[
            _HighlightButton(
              label: context.tr('clinics'),
              icon: Icons.local_hospital_rounded,
              onTap: () => context.go('/clinics'),
              compact: true,
            ),
            const SizedBox(width: 2),
          ],
          if (!wide)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: context.tr('menu'),
                icon: Icon(Icons.menu_rounded, color: primary),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          SizedBox(width: wide ? 24 : 4),
        ],
      ),
      endDrawer: wide ? null : _AppDrawer(location: location, showAsk: showAsk),
      body: child,
    );
  }

  Widget _navText(BuildContext context, String key, String path) {
    final selected = location == path;
    final primary = Theme.of(context).colorScheme.primary;
    return _NavLabel(
      label: context.tr(key),
      selected: selected,
      color: selected ? primary : AppColors.ink,
      onTap: () => context.go(path),
    );
  }
}

/// Desktop nav entry: ink label, primary + gold underline when current.
class _NavLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  final bool caret;
  const _NavLabel({required this.label, required this.selected, required this.color, this.onTap, this.caret = false});

  @override
  Widget build(BuildContext context) {
    final text = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14.5)),
      if (caret) const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.goldText),
    ]);
    final decorated = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2)),
      ),
      child: text,
    );
    if (onTap == null) return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: decorated);
    return TextButton(onPressed: onTap, style: TextButton.styleFrom(foregroundColor: color), child: decorated);
  }
}

/// Nav items whose section is switched on (the assistant also needs
/// [showAsk]: App Check + `assistantEnabled`).
List<NavItem> visibleNavItems(FeatureSettings f, {required bool showAsk}) =>
    [for (final i in navItems) if (f.routeEnabled(i.path)) i, if (showAsk) askNavItem];

class _ServicesMenu extends ConsumerWidget {
  final String location;
  const _ServicesMenu({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(featuresProvider);
    final ready = ref.watch(featuresReadyProvider);
    final items = [
      for (final i in navItems)
        if (serviceNavPaths.contains(i.path) && f.routeEnabled(i.path) && (ready || i.path != '/clinics')) i,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final selected = items.any((i) => location == i.path || location.startsWith('${i.path}/'));
    final primary = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<String>(
      tooltip: context.tr('churchServices'),
      onSelected: (p) => context.go(p),
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem(
            value: i.path,
            height: 48,
            child: Row(children: [
              Icon(i.icon, color: primary, size: 20),
              const SizedBox(width: 12),
              Flexible(child: Text(context.tr(i.key), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _NavLabel(
          label: context.tr('churchServices'),
          selected: selected,
          color: selected ? primary : AppColors.ink,
          caret: true,
        ),
      ),
    );
  }
}

class _HighlightButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final bool filled;
  const _HighlightButton(
      {required this.label, required this.icon, required this.onTap, this.compact = false, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (compact) {
      // 48x48 dp minimum touch target (WCAG 2.5.8 / Material guideline).
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        style: IconButton.styleFrom(
          backgroundColor: filled ? primary : Colors.transparent,
          foregroundColor: filled ? Colors.white : primary,
          side: filled ? null : const BorderSide(color: AppColors.hairline),
        ),
        icon: Icon(icon, size: 20),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
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
    final primary = Theme.of(context).colorScheme.primary;
    final church = [for (final i in items) if (!serviceNavPaths.contains(i.path) && i.path != '/ask') i];
    final services = [for (final i in items) if (serviceNavPaths.contains(i.path) || i.path == '/ask') i];

    Widget group(String title, List<NavItem> list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 4),
            child: Semantics(
              header: true,
              child: Text(title,
                  style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
          for (final i in list)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                minTileHeight: 48,
                leading: Icon(i.icon, color: primary, size: 22),
                title: Text(context.tr(i.key), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                selected: location == i.path,
                selectedColor: AppColors.ink,
                selectedTileColor: AppColors.parchment,
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(i.path);
                },
              ),
            ),
        ]);

    return Drawer(
      child: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
            color: AppColors.vellum,
            child: Row(children: [
              const ChurchSeal(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Text(settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(context, size: 15, color: AppColors.ink, height: 1.5)),
              ),
              IconButton(
                tooltip: context.tr('close'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const InterlaceBand(),
          if (church.isNotEmpty) group(context.tr('navChurch'), church),
          if (services.isNotEmpty) group(context.tr('churchServices'), services),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}
