import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../state/providers.dart';
import '../pages/category_page.dart' show categoryIcon;
import 'coptic_cross.dart';
import 'golden.dart';
import 'today_widgets.dart';

class NavItem {
  final String key;
  final String path;
  final IconData icon;

  /// Admin-defined entries (categories / custom pages, ADR-027) carry their
  /// own labels; built-in ones use the l10n [key].
  final String? labelAr, labelEn;
  const NavItem(this.key, this.path, this.icon, {this.labelAr, this.labelEn});

  String label(BuildContext context) => labelAr == null ? context.tr(key) : context.pick(labelAr!, labelEn ?? '');
}

/// Menu entries of admin-defined categories ("Church services" group) and
/// of custom pages switched into the menu ("The church" group).
({List<NavItem> categories, List<NavItem> pages}) customNavItems(WidgetRef ref) {
  final f = ref.watch(featuresProvider);
  // Each list follows its section switch (Sections.customSections / customPages).
  final cats = f.enabled(Sections.customSections) ? ref.watch(categoriesProvider).value ?? const [] : const [];
  final pages = f.enabled(Sections.customPages) ? ref.watch(customPagesProvider).value ?? const [] : const [];
  return (
    categories: [
      for (final c in cats)
        if (c.showInNav) NavItem('cat-${c.slug}', c.path, categoryIcon(c.icon), labelAr: c.nameAr, labelEn: c.nameEn),
    ],
    pages: [
      for (final p in pages)
        if (p.showInNav)
          NavItem('page-${p.slug}', p.path, Icons.article_rounded, labelAr: p.titleAr, labelEn: p.titleEn),
    ],
  );
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

/// Common chrome for all public pages ("Golden hour"): a translucent cream
/// app bar with the church name, the maroon seal tab hanging from its start
/// corner (as on the posters), the grouped menu (Home · About · Church
/// services ▾ · Ask · Contact) and one primary "Mass times" pill on wide
/// screens, the grouped end drawer on phones, and the fixed warm backdrop.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _drawerOpen = false;

  String get location => widget.location;

  @override
  Widget build(BuildContext context) {
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
    // 400 px (the Back arrow takes another 48 dp): the highlighted Mass
    // button moves to the drawer (it is already listed there) so the church
    // title keeps a readable width.
    final collapseHighlights = !wide && (width < 360 || textScale >= 1.5 || (showBack && width < 400));
    final showAsk = ref.watch(assistantVisibleProvider);
    final features = ref.watch(featuresProvider);
    // Until settings/features arrives the defaults are "everything on": wait
    // before showing highlight buttons for sections an admin may have off.
    final ready = ref.watch(featuresReadyProvider);
    final showMass = ready && !collapseHighlights && features.routeEnabled('/mass-schedule');
    // Top utility bar (Coptic date strip + live badge).
    final todaySettings = ref.watch(todaySettingsProvider);
    final copticMode = todaySettings.copticStrip;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final liveActive = todaySettings.liveOn(now);
    final showTopBar = ready && (TopUtilityBar.shownOn(copticMode, location) || liveActive);
    // No Clinics shortcut in the bar (owner request, 4 Nov 2026): clinics stay
    // reachable from the drawer / Services menu and Home when their section is on.
    final settings = ref.watch(settingsProvider).value;
    // Full church name (admin-editable in settings); bundled l10n name until settings load.
    final fullName = settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn);
    final primary = Theme.of(context).colorScheme.primary;
    // The hanging seal tab (start corner, after the Back arrow on phones).
    final tabW = wide ? 88.0 : 64.0;
    final tabH = wide ? 108.0 : 80.0;
    final tabStart = (showBack ? 48.0 : 0.0) + (wide ? 24.0 : 6.0);
    final tabSpace = tabW + (wide ? 12.0 : 8.0) - (wide ? 0 : (showBack ? 0 : 6));

    final mainAppBar = AppBar(
      primary: !showTopBar,
      toolbarHeight: wide ? 76 : 64,
      titleSpacing: wide ? 24 : (showBack ? 0 : 6),
      leadingWidth: showBack ? 48 : null,
      shape: const Border(bottom: BorderSide(color: Color(0x59C9963F))),
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
          // The seal hangs in the tab at the start corner: the title keeps
          // its room. Wide bars with many entries (or very large text)
          // leave little width: the name then disappears, never overflows.
          if (c.maxWidth < tabSpace + 70) return SizedBox(width: c.maxWidth.clamp(0, tabSpace));
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: tabSpace),
            // The full name is long: on wide screens show it under the short
            // name; on phones show only the short name (max two lines).
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(context.tr('appShort'),
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(context, size: wide ? 23 : 17, color: primary, height: 1.25)),
                if (wide)
                  Text(fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: context.pal.muted, fontWeight: FontWeight.w400)),
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
                for (final p in customNavItems(ref).pages) _navItemText(context, p),
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
          style: IconButton.styleFrom(
              backgroundColor: context.pal.surface, side: BorderSide(color: context.pal.hairline, width: 1.5)),
          icon: Text(context.isAr ? 'EN' : 'ع',
              style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.goldText, fontSize: 15)),
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
    );

    final scaffold = Scaffold(
      onEndDrawerChanged: (open) => setState(() => _drawerOpen = open),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight((showTopBar ? 32.0 : 0.0) + (wide ? 76.0 : 64.0)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTopBar)
              Container(
                color: const Color(0xFF3B0A0A),
                child: SafeArea(
                  bottom: false,
                  left: false,
                  right: false,
                  child: TopUtilityBar(location: location),
                ),
              ),
            mainAppBar,
          ],
        ),
      ),
      endDrawer: wide ? null : _AppDrawer(location: location, showAsk: showAsk),
      body: Stack(children: [
        const Positioned.fill(child: WarmBackdrop()),
        // Today layer (ADR-040): while the church is streaming,
        // the live banner sits above every page.
        Column(children: [
          const LiveStreamBanner(),
          Expanded(child: widget.child),
        ]),
      ]),
    );
    return Stack(children: [
      scaffold,
      if (!_drawerOpen)
        PositionedDirectional(
          start: tabStart,
          top: MediaQuery.paddingOf(context).top + (showTopBar ? 32.0 : 0.0),
          child: Semantics(
            link: true,
            label: '${context.tr('logoLabel')} — ${context.tr('home')}',
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('sealTabHome'),
              onTap: () => context.go('/'),
              child: MouseRegion(cursor: SystemMouseCursors.click, child: SealTab(width: tabW, height: tabH)),
            ),
          ),
        ),
    ]);
  }

  Widget _navItemText(BuildContext context, NavItem item) {
    final selected = widget.location == item.path;
    final primary = Theme.of(context).colorScheme.primary;
    return _NavLabel(
      label: item.label(context),
      selected: selected,
      color: selected ? primary : context.pal.ink,
      onTap: () => context.go(item.path),
    );
  }

  Widget _navText(BuildContext context, String key, String path) {
    final location = widget.location;
    final selected = location == path;
    final primary = Theme.of(context).colorScheme.primary;
    return _NavLabel(
      label: context.tr(key),
      selected: selected,
      color: selected ? primary : context.pal.ink,
      onTap: () => context.go(path),
    );
  }
}

/// Desktop nav entry: ink label; the current page sits on a soft primary pill.
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
      if (caret) Icon(Icons.expand_more_rounded, size: 18, color: context.pal.goldText),
    ]);
    final decorated = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(999),
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
      ...customNavItems(ref).categories,
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
              Flexible(child: Text(i.label(context), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _NavLabel(
          label: context.tr('churchServices'),
          selected: selected,
          color: selected ? primary : context.pal.ink,
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
          foregroundColor: filled ? context.pal.onPrimary : primary,
          side: filled ? null : BorderSide(color: context.pal.hairline),
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
    final custom = customNavItems(ref);
    final church = [
      for (final i in items) if (!serviceNavPaths.contains(i.path) && i.path != '/ask') i,
      ...custom.pages,
    ];
    final services = [
      for (final i in items) if (serviceNavPaths.contains(i.path) || i.path == '/ask') i,
      ...custom.categories,
    ];

    Widget group(String title, List<NavItem> list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 14, 20, 4),
            child: Semantics(
              header: true,
              child: Text(title,
                  style: TextStyle(color: context.pal.goldText, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
          for (final i in list)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              child: ListTile(
                minTileHeight: 48,
                leading: Icon(i.icon, color: location == i.path ? context.pal.onPrimaryAccent : primary, size: 22),
                title: Text(i.label(context), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                selected: location == i.path,
                selectedColor: context.pal.onPrimary,
                selectedTileColor: primary,
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(i.path);
                },
              ),
            ),
        ]);

    return Drawer(
      child: Stack(children: [
        const Positioned.fill(child: WarmBackdrop()),
        SafeArea(
          child: ListView(padding: EdgeInsets.zero, children: [
            // Maroon header with the seal (the posters' tab, laid flat).
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 8, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [primary, primaryDarkOf(context)],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.pal.onPrimaryAccent,
                    boxShadow: const [BoxShadow(color: Color(0x73200000), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: const ChurchSeal(size: 52),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(settings == null ? context.tr('appName') : context.pick(settings.nameAr, settings.nameEn),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(context, size: 17, color: context.pal.onPrimary, height: 1.4)),
                ),
                IconButton(
                  tooltip: context.tr('close'),
                  color: context.pal.onPrimary,
                  style: IconButton.styleFrom(backgroundColor: context.pal.onPrimary.withValues(alpha: 0.14)),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            if (church.isNotEmpty) group(context.tr('navChurch'), church),
            if (services.isNotEmpty) group(context.tr('churchServices'), services),
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }
}
