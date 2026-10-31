import 'package:material_ui/material_ui.dart';

/// Non-web platforms: show the static fallback (tap opens Google Maps).
Widget buildMapView(BuildContext context, String embedUrl, Widget fallback) => fallback;
