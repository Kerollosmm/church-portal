import 'dart:ui_web' as ui_web;

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

final Set<String> _registered = {};

/// Web: keyless Google Maps iframe embed.
Widget buildMapView(BuildContext context, String embedUrl, Widget fallback) {
  final viewType = 'church-map-${embedUrl.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final iframe = web.HTMLIFrameElement()
        ..src = embedUrl
        ..title = 'Google Map'
        ..referrerPolicy = 'no-referrer-when-downgrade'
        ..loading = 'lazy'
        ..allowFullscreen = true;
      iframe.style
        ..border = '0'
        ..position = 'absolute'
        ..top = '0'
        ..left = '0'
        ..right = '0'
        ..bottom = '0'
        ..width = '100%'
        ..height = '100%';
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
