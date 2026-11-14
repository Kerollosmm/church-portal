import '../../core/l10n.dart';

/// Localization strings used exclusively by the deferred `/admin` chunk.
/// Registering via [registerAdminStrings] keeps admin-only copy out of
/// `main.dart.js` so public visitors do not download it (Golden Rule 12).
const Map<String, List<String>> adminStrings = {
  'visibleTag': ['ظاهر', 'Visible'],
  'stoppedTag': ['موقوف', 'Stopped'],
  'expiredTag': ['منتهي', 'Expired'],
  'sampleTag': ['بيانات تجريبية', 'Sample'],
  // Written-state switches (ADR-050 / PR 3B / Packet P1-09)
  'switch_visible': ['ظاهر', 'Visible'],
  'switch_hidden': ['مخفي', 'Hidden'],
  'switch_enabled': ['مفعّل', 'Enabled'],
  'switch_disabled': ['مقفول', 'Off'],
  'switch_active': ['نشط', 'Active'],
  'switch_stopped': ['موقوف', 'Stopped'],
  'switch_sample': ['بيانات تجريبية', 'Sample'],
  'switch_confirmed': ['مؤكد', 'Confirmed'],
  'switch_replaces_on': ['يحل محل قداسات اليوم', 'Replaces masses'],
  'switch_replaces_off': ['لا يحل محل اليوم', 'Does not replace'],
  'switch_nav_on': ['ظاهر في القائمة', 'In navigation'],
  'switch_nav_off': ['مخفي من القائمة', 'Not in navigation'],
  // Liturgy preview for replacesDay (Packet P1-10)
  'replacesPreviewHeadingDate': ['القداسات دي مش هتظهر يوم {d}:', 'These regular masses will not be shown on {d}:'],
  'replacesPreviewHeadingWeekday': ['القداسات دي مش هتظهر يوم {w}:', 'These regular masses will not be shown on {w}:'],
  'replacesPreviewHeadingFallback': ['القداسات دي مش هتظهر في اليوم المحدد:', 'These regular masses will not be shown on the selected day:'],
  'replacesPreviewEmpty': ['مفيش قداسات معتادة مسجلة في اليوم ده', 'No regular masses scheduled on this day'],
  'replacesPreviewNoDay': ['حدد تاريخ أو يوم لمعاينة القداسات المعتادة', 'Select a date or weekday to preview replaced masses'],
  'replacesPreviewHidden': [
    'القداس مخفي حاليًا — مش هيستبدل أي قداسات لحد ما يتفعل ظهوره',
    'Hidden right now — will not replace regular masses until shown',
  ],
  // Admin status & session policy (PR 3C / Packets P1-12, P1-13)
  'activeStatus': ['نشط', 'Active'],
  'stoppedStatus': ['موقوف', 'Stopped'],
  'pauseAdmin': ['إيقاف المشرف', 'Pause admin'],
  'resumeAdmin': ['تفعيل المشرف', 'Re-enable admin'],
  'confirmPauseAdmin': [
    'إيقاف هذا المشرف مؤقتًا؟ لن يتمكن من التعديل حتى يُعاد تفعيله.',
    'Pause this admin? They will not be able to edit until re-enabled.'
  ],
  'confirmResumeAdmin': ['إعادة تفعيل صلاحية هذا المشرف؟', 'Re-enable this admin\'s access?'],
  'adminExpiresAt': ['تاريخ انتهاء الصلاحية (اختياري)', 'End date (optional)'],
  'adminNoExpiry': ['بدون تاريخ انتهاء', 'No end date'],
  'adminExpiresOn': ['ينتهي في {d}', 'Ends on {d}'],
  'adminExpiredOn': ['انتهى في {d}', 'Expired on {d}'],
  'clearEndDate': ['إزالة تاريخ الانتهاء', 'Clear end date'],
  'adminStoppedAccount': ['تم إيقاف هذا الحساب مؤقتًا من مالك اللوحة.', 'This admin account is currently paused by an owner.'],
  'adminExpiredAccount': ['انتهت صلاحية هذا الحساب المؤقت.', 'This temporary admin access has expired.'],
  'rememberMe': ['افتكرني (جهاز شخصي)', 'Remember me (personal device)'],
  'sessionWarnTitle': ['هتخرج تلقائيًا بعد {s} ثانية', 'Signing out in {s} seconds'],
  'sessionWarnBody': ['مفيش نشاط بقالك شوية. عايز تفضل مسجّل؟', 'No activity for a while. Stay signed in?'],
  'staySignedIn': ['خليك مسجّل', 'Stay signed in'],
};

/// Idempotently registers [adminStrings] in the runtime localization table.
void registerAdminStrings() => registerStrings(adminStrings);
