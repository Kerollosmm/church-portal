import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import '../domain/rules.dart';

Future<void> openUrl(String url) async {
  if (url.isEmpty) return;
  var uri = Uri.tryParse(url.trim());
  if (uri == null) return;
  // Scheme-less links (e.g. "facebook.com/church" or "//example.org") would be
  // resolved relative to the portal on web; treat them as https.
  if (!uri.hasScheme) {
    final t = url.trim();
    uri = Uri.tryParse(t.startsWith('//') ? 'https:$t' : 'https://$t');
    if (uri == null) return;
  }
  final external = uri.scheme == 'http' || uri.scheme == 'https';
  await launchUrl(uri, mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault, webOnlyWindowName: external ? '_blank' : '_self');
}

Future<void> callPhone(String number) => openUrl(telLink(number));

Future<void> openWhatsApp(String number, {String? text}) => openUrl(whatsappLink(number, text: text));

/// Google Maps search URL for the church.
String mapsSearchUrl(ChurchSettings s) {
  if (s.mapsUrl.isNotEmpty) return s.mapsUrl;
  final q = s.mapsQuery.isNotEmpty ? s.mapsQuery : s.addressAr;
  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}';
}

/// Turn-by-turn directions from the visitor's current GPS position.
String mapsDirectionsUrl(ChurchSettings s) {
  final dest = s.mapsQuery.isNotEmpty
      ? s.mapsQuery
      : (s.lat != null && s.lng != null ? '${s.lat},${s.lng}' : s.addressAr);
  return 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(dest)}&travelmode=driving';
}

/// Keyless embeddable map URL (iframe); [lang] sets the map labels' language
/// (`hl`), so English visitors get English labels.
String mapsEmbedUrl(ChurchSettings s, {String lang = 'ar'}) {
  final q = s.mapsQuery.isNotEmpty ? s.mapsQuery : s.addressAr;
  return 'https://maps.google.com/maps?q=${Uri.encodeComponent(q)}&z=16&output=embed&hl=${Uri.encodeComponent(lang)}';
}
