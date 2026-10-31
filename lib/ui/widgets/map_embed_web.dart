import 'dart:ui_web' as ui_web;

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

/// One registered view type per distinct embed URL (collision-free: the
/// type is derived from a counter, not the URL's hash).
final Map<String, String> _viewTypes = {};

/// Web: keyless Google Maps iframe embed. The location card ([fallback]) is
/// painted underneath, so it shows while the iframe loads and whenever the
/// iframe stays blank (e.g. blocked by a content blocker).
Widget buildMapView(BuildContext context, String embedUrl, Widget fallback) {
  var isNew = false;
  final viewType = _viewTypes.putIfAbsent(embedUrl, () {
    isNew = true;
    return 'church-map-${_viewTypes.length}';
  });
  if (isNew) {
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
  return Stack(fit: StackFit.expand, children: [
    fallback,
    HtmlElementView(viewType: viewType),
  ]);
}
