import 'models.dart';

/// Categories shown in the admin home "Needs your attention" card (P2-23).
enum AttentionKind {
  newMessages,
  expiringAlerts,
  unconfirmedData,
  streamWithoutLink,
  missingEnglish,
}

/// One actionable item surfaced on the admin home screen.
class AttentionItem {
  final AttentionKind kind;
  final int count;
  final String targetScreenId;

  const AttentionItem({
    required this.kind,
    required this.count,
    required this.targetScreenId,
  });
}

/// Window within which an active alert counts as "about to end".
const _alertExpiringWindow = Duration(hours: 48);

/// Computes the ordered list of items needing admin attention (P2-23):
/// 1. New / open visitor messages
/// 2. Visible active alerts ending within 48 hours of [now]
/// 3. Unconfirmed ("sample") items
/// 4. Live-stream banner switched on with no link
/// 5. (When [englishOn]) items missing their English fields
List<AttentionItem> attentionItems({
  required int newMessages,
  required List<Alert> alerts,
  required int unconfirmed,
  required bool streamOn,
  required String streamUrl,
  required bool englishOn,
  required int missingEnglish,
  required DateTime now,
  String unconfirmedTarget = 'liturgies',
  String missingEnglishTarget = 'liturgies',
}) {
  final nowUtc = now.toUtc();
  final cutoffUtc = nowUtc.add(_alertExpiringWindow);

  var expiringAlerts = 0;
  for (final a in alerts) {
    final ends = a.endsAt?.toUtc();
    if (!a.visible || !a.active || ends == null) continue;
    if (!ends.isBefore(nowUtc) && !ends.isAfter(cutoffUtc)) {
      expiringAlerts++;
    }
  }

  return [
    if (newMessages > 0)
      AttentionItem(
        kind: AttentionKind.newMessages,
        count: newMessages,
        targetScreenId: 'messages',
      ),
    if (expiringAlerts > 0)
      AttentionItem(
        kind: AttentionKind.expiringAlerts,
        count: expiringAlerts,
        targetScreenId: 'alerts',
      ),
    if (unconfirmed > 0)
      AttentionItem(
        kind: AttentionKind.unconfirmedData,
        count: unconfirmed,
        targetScreenId: unconfirmedTarget,
      ),
    if (streamOn && streamUrl.trim().isEmpty)
      const AttentionItem(
        kind: AttentionKind.streamWithoutLink,
        count: 1,
        targetScreenId: 'today',
      ),
    if (englishOn && missingEnglish > 0)
      AttentionItem(
        kind: AttentionKind.missingEnglish,
        count: missingEnglish,
        targetScreenId: missingEnglishTarget,
      ),
  ];
}

/// Returns true when at least one Arabic/English field pair in [data] has
/// non-empty Arabic text and empty or missing English text (P2-27b).
bool docMissingEnglish(
  Map<String, dynamic> data,
  List<(String arKey, String enKey)> pairs,
) {
  for (final (arKey, enKey) in pairs) {
    final ar = data[arKey]?.toString().trim() ?? '';
    if (ar.isEmpty) continue;
    final en = data[enKey]?.toString().trim() ?? '';
    if (en.isEmpty) return true;
  }
  return false;
}
