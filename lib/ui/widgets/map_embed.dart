import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import 'map_embed_stub.dart' if (dart.library.js_interop) 'map_embed_web.dart' as platform;

/// Builds the map view for an embed URL (iframe on web, [fallback] elsewhere).
typedef MapViewBuilder = Widget Function(BuildContext context, String embedUrl, Widget fallback);

/// Embedded Google Map (iframe on web, static card elsewhere) with
/// "Open in Google Maps" and GPS directions buttons.
class ChurchMap extends StatelessWidget {
  final ChurchSettings settings;
  final double height;

  /// Map adapter (tests inject a fake that records the embed URL).
  final MapViewBuilder mapView;
  const ChurchMap({super.key, required this.settings, this.height = 300, this.mapView = platform.buildMapView});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: height,
          child: mapView(context, mapsEmbedUrl(settings, lang: context.isAr ? 'ar' : 'en'), _fallback(context)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.location_on, color: context.pal.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(context.pick(settings.addressAr, settings.addressEn),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => openUrl(mapsSearchUrl(settings)),
                icon: const Icon(Icons.map_outlined),
                label: Text(context.tr('openInMaps')),
              ),
              OutlinedButton.icon(
                onPressed: () => openUrl(mapsDirectionsUrl(settings)),
                icon: const Icon(Icons.directions),
                label: Text(context.tr('directions')),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _fallback(BuildContext context) => InkWell(
        onTap: () => openUrl(mapsSearchUrl(settings)),
        child: Container(
          color: context.pal.surfaceAlt,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.map_rounded, size: 56, color: context.pal.primary),
              const SizedBox(height: 8),
              Text(context.tr('location'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Wraps a map view with click-to-interact protection:
/// When inactive, scroll and wheel events pass through freely.
/// Tapping unlocks interactivity, displaying a lock button to relock.
class MapInteractionGuard extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onActiveChanged;
  final bool initialActive;

  const MapInteractionGuard({
    super.key,
    required this.child,
    this.onActiveChanged,
    this.initialActive = false,
  });

  @override
  State<MapInteractionGuard> createState() => _MapInteractionGuardState();
}

class _MapInteractionGuardState extends State<MapInteractionGuard> {
  late bool _active;

  @override
  void initState() {
    super.initState();
    _active = widget.initialActive;
  }

  void _setActive(bool value) {
    if (_active == value) return;
    setState(() => _active = value);
    widget.onActiveChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) {
        if (_active) _setActive(false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (!_active)
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: const Key('mapInteractShield'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setActive(true),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.pal.bar,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(color: context.pal.shadow(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app_rounded, color: context.pal.onBar, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('mapTapToInteract'),
                            style: TextStyle(
                              color: context.pal.onBar,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_active)
            PositionedDirectional(
              top: 12,
              end: 12,
              child: FilledButton.icon(
                key: const Key('mapLockScrollBtn'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.pal.bar,
                  foregroundColor: context.pal.onBar,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  elevation: 4,
                ),
                onPressed: () => _setActive(false),
                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                label: Text(
                  context.tr('mapLockScroll'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
