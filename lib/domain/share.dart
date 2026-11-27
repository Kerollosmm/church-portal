// Pure helpers for plain-link sharing with zero tracking parameters.

/// Builds a WhatsApp share URI (`https://wa.me/?text=...`) containing [title]
/// (if non-empty) and the plain canonical URL formed by [origin] + [path].
Uri whatsappShareUri({
  required String title,
  required String path,
  String origin = 'https://maximos-domadios-church.web.app',
}) {
  final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  final cleanPath = path.isEmpty ? '/' : (path.startsWith('/') ? path : '/$path');
  final canonical = '$base$cleanPath';
  final trimmed = title.trim();
  final text = trimmed.isEmpty ? canonical : '$trimmed\n$canonical';
  return Uri.https('wa.me', '/', {'text': text});
}
