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
              Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
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
          color: AppColors.parchment,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.map_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(context.tr('location'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
