import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/push_env.dart';
import '../../core/theme.dart';
import '../../data/error_reporting.dart';
import '../../data/web_push_repository.dart' deferred as web_push;
import '../../domain/features.dart';
import '../../domain/reminders.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/reminder_sheet.dart';

/// Strings only this deferred chunk uses (registered before it builds).
const Map<String, List<String>> notificationsPageStrings = {
  'adminPushTypesLabel': ['أنواع الإشعارات المتاحة للمستخدمين', 'Notification types offered to visitors'],
  'notificationsAllowBrowserButton': ['السماح بإشعارات المتصفح', 'Allow browser notifications'],
  'notificationsAllowPromptBody': ['اضغط على الزر أدناه للسماح للمتصفح بإرسال إشعارات وتنبيهات الكنيسة عند نشر التنبيهات ومواعيد القداسات.', 'Tap below to allow your browser to deliver church updates, schedules, and reminders.'],
  'notificationsAllowPromptTitle': ['تفعيل إشعارات المتصفح', 'Enable browser notifications'],
  'notificationsBlockedChrome': ['اضغط أيقونة 🔒 بجوار عنوان الموقع ← الأذونات ← الإشعارات ← سماح', 'Tap the 🔒 icon next to the address bar → Permissions → Notifications → Allow'],
  'notificationsBlockedIos': ['من إعدادات الهاتف ← الإشعارات ← كنيسة مكسيموس ودوماديوس ← السماح بالإشعارات', 'Go to iPhone Settings → Notifications → Church App → Allow Notifications'],
  'notificationsBlockedTitle': ['الإشعارات محظورة في متصفحك', 'Notifications are blocked in your browser'],
  'notificationsComingSoon': ['خدمة الإشعارات عبر المتصفح قادمة قريبًا', 'Web push notifications are coming soon'],
  'notificationsCopyFailed': ['تعذّر النسخ التلقائي — انسخ الرابط يدويًا:', 'Auto-copy blocked — copy link manually:'],
  'notificationsCopyLink': ['نسخ الرابط للمتصفح', 'Copy link for browser'],
  'notificationsPermissionDisabled': [
    'الإشعارات غير مفعلة. يُرجى السماح بالإشعارات من إعدادات المتصفح أو النظام.',
    'Notifications disabled. Please allow notifications in device or browser settings.',
  ],
  'notificationsEnableButton': ['تفعيل الإشعارات', 'Enable notifications'],
  'notificationsEnabledChip': ['الإشعارات مفعلة', 'Notifications enabled'],
  'notificationsExplainerBody': ['اختر التنبيهات التي تهمك لتصلك مواعيد القداسات، تنبيهات مواسم الصوم وأسبوع الآلام، والتذكيرات التي تحددها بنفسك. لا نجمع أي بيانات شخصية ويمكنك إيقاف الإشعارات في أي وقت.', 'Choose the updates you care about: mass schedules, fasting seasons & Holy Week alerts, and reminders you set yourself. No personal data is collected and you can disable notifications at any time.'],
  'notificationsExplainerTitle': ['إشعارات وتنبيهات الكنيسة', 'Church notifications & alerts'],
  'notificationsInAppBrowser': ['أنت تفتح الموقع من داخل تطبيق (مثل Facebook أو WhatsApp). للحصول على أفضل تجربة وتفعيل التنبيهات، افتح الموقع في متصفح Safari أو Chrome.', 'You are viewing this site inside an app (such as Facebook or WhatsApp). To enable notifications, open the link in Safari or Chrome.'],
  'notificationsInAppOpenBrowser': ['أنت تفتح الموقع من داخل تطبيق. انسخ الرابط وافتحه في متصفحك الأساسي لتفعيل الإشعارات.', 'You are in an in-app browser. Copy the link and open in Chrome or Safari to enable notifications.'],
  'notificationsInboxClear': ['مسح السجل', 'Clear history'],
  'notificationsInboxEmpty': ['لا توجد إشعارات سابقة في هذا المتصفح.', 'No previous notifications in this browser.'],
  'notificationsInboxTitle': ['سجل الإشعارات المستلمة', 'Received notifications'],
  'notificationsIosAddFirst': ['لتفعيل الإشعارات على iPhone، أضف الموقع أولاً إلى الشاشة الرئيسية.', 'To enable notifications on iPhone, add the site to your Home Screen first.'],
  'notificationsIosFocusNote': ['على iPhone، يُرجى استخدام نمط التركيز (Focus Mode) في إعدادات الهاتف لتحديد ساعات الهدوء.', 'On iPhone, please use Focus Mode in Settings to set quiet hours.'],
  'notificationsIosNeedsInstallBody': ['على iPhone تعمل الإشعارات من iOS 16.4 فأحدث، بعد إضافة الموقع إلى الشاشة الرئيسية. اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية»، ثم افتح التطبيق من الشاشة الرئيسية لتفعيل الإشعارات.', 'On iPhone, notifications need iOS 16.4 or later and the site added to your Home Screen. Tap the Share button, select "Add to Home Screen", then open the app from your home screen to enable notifications.'],
  'notificationsIosNeedsInstallTitle': ['لتفعيل الإشعارات على iPhone', 'To enable notifications on iPhone'],
  'notificationsIosStep1': ['اضغط زر المشاركة (Share) في أسفل شاشة Safari', 'Tap the Share button at the bottom of Safari'],
  'notificationsIosStep2': ['اختر «إضافة إلى الشاشة الرئيسية» (Add to Home Screen)', 'Select "Add to Home Screen"'],
  'notificationsIosStep3': ['افتح التطبيق من الشاشة الرئيسية لتفعيل التنبيهات', 'Open the app from your Home Screen to enable notifications'],
  'notificationsIosTooOld': ['يتطلب تلقي الإشعارات على iPhone تحديث نظام iOS إلى الإصدار 16.4 أو أحدث.', 'Web push notifications on iPhone require iOS 16.4 or later.'],
  'notificationsLinkCopied': ['تم نسخ الرابط', 'Link copied'],
  'notificationsQuietNoteWeb': ['آية اليوم وقراءات القطمارس والأعياد متوفرة مباشرة في الصفحة الرئيسية.', 'Daily verse, Katameros readings, and feast commemorations are available directly on the home page.'],
  'notificationsRecheckButton': ['التحقق من الإذن مجددًا', 'Check permission again'],
  'notificationsRegisterFailed': ['تعذّر تسجيل إشعارات المتصفح حاليًا، يُرجى المحاولة لاحقًا.', 'Could not register browser notifications at this time. Please try again later.'],
  'notificationsTestButton': ['جرّب إشعارًا', 'Test notification'],
  'notificationsTestSent': ['تم إرسال إشعار تجريبي للمتصفح', 'Test notification sent to browser'],
  'notificationsUnsubscribeAll': ['إيقاف كل الإشعارات', 'Turn off all notifications'],
  'notificationsUnsubscribeConfirm': ['تم إيقاف جميع الإشعارات', 'All notifications turned off'],
  'notificationsUnsubscribeFailed': [
    'تعذّر حفظ إيقاف الإشعارات على الخادم؛ ستتم إعادة المحاولة تلقائيًا.',
    'Could not save opt-out on server; it will retry automatically.',
  ],
  'notificationsSyncFailed': [
    'تعذّر مزامنة الإشعارات مع الخادم؛ ستتم إعادة المحاولة تلقائيًا.',
    'Could not sync notifications with server; it will retry automatically.',
  ],
  'notificationsUnsupported': ['هذا المتصفح لا يدعم تلقي الإشعارات.', 'This browser does not support push notifications.'],
};

/// The visitor's notification preferences and reminders page (`/notifications`, ADR-057).
class NotificationsPage extends ConsumerStatefulWidget {
  final bool? isWeb;
  const NotificationsPage({super.key, this.isWeb});

  /// Preloads the deferred web-push library outside `FakeAsync` test zones
  /// so Dart VM deferred loading does not stall across `testWidgets` cases.
  @visibleForTesting
  static Future<void> preloadWebPushForTest() => web_push.loadLibrary();

  /// Returns a shareable notifications URL matching the active web deployment
  /// (preview channel or prod) without query parameters or URL fragments.
  @visibleForTesting
  static String shareableNotificationsUrlForUri(Uri base) {
    if ((base.scheme == 'http' || base.scheme == 'https') && base.host.isNotEmpty) {
      final path = base.path.isEmpty ? '/notifications' : base.path;
      return Uri(
        scheme: base.scheme,
        userInfo: base.userInfo,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: path,
      ).toString();
    }
    return 'https://maximos-domadios-church.web.app/notifications';
  }

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  dynamic _webPushRepo;
  PushEnv? _webPushEnv;
  Future<bool>? _syncInFlight;
  bool _copyFailed = false;

  @override
  void initState() {
    super.initState();
    final isWeb = widget.isWeb ?? kIsWeb;
    if (isWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !context.mounted) return;
        final pushEnv = ref.read(pushEnvProvider);
        final state = readWebPushStorageState(pushEnv);
        if (state == null || !state.pendingSync || state.syncedToken == null) return;
        final prefs = ref.read(pushPrefsProvider);
        if (pushEnv.permission != 'granted' && prefs.types.isNotEmpty) return;
        final pushSettings = ref.read(pushSettingsProvider);
        if (!pushSettings.webReady) return;
        try {
          await web_push.loadLibrary();
          final repo = _repoFor(pushEnv);
          if (!repo.canWriteInEnvironment) return;
          final reminders = mounted ? ref.read(userRemindersProvider) : <Reminder>[];
          await repo.resumePendingSync(prefs: prefs, reminders: reminders);
        } catch (e, st) {
          ErrorReporting.capture(e, st, section: 'notifications', source: 'web_push_resume');
        }
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      final pending = _syncInFlight;
      final repo = _webPushRepo;
      if (pending != null) {
        pending.whenComplete(() {
          if (repo != null) repo.dispose();
        });
      } else if (repo != null) {
        repo.dispose();
      }
    }
    super.dispose();
  }

  dynamic _repoFor(PushEnv pushEnv) {
    if (_webPushRepo == null || !identical(_webPushEnv, pushEnv)) {
      _webPushEnv = pushEnv;
      _webPushRepo = web_push.WebPushRepository.sharedFor(pushEnv);
    }
    return _webPushRepo;
  }

  PushPermissionState _resolveState({
    required InstallOsInfo osInfo,
    required String userAgent,
    required bool isStandalone,
    required PushEnv pushEnv,
    required String permission,
    required bool isWeb,
  }) {
    // The phone app's own notification permission arrives with PR B; until
    // then never claim notifications are on.
    if (!isWeb) return PushPermissionState.unsupported;

    if (osInfo.os == InstallOs.ios && iosTooOldForPush(userAgent)) {
      // iOS < 16.4 has no web push at all, installed or not.
      return PushPermissionState.iosTooOld;
    }

    if (osInfo.inAppBrowser) {
      return PushPermissionState.inAppBrowser;
    }

    if (osInfo.os == InstallOs.ios) {
      if (!isStandalone) {
        return PushPermissionState.iosNeedsInstall;
      }
      if (!pushEnv.isSupported) {
        return PushPermissionState.iosTooOld;
      }
    }

    if (!pushEnv.isSupported) {
      return PushPermissionState.unsupported;
    }

    final p = permission;
    if (p == 'granted') return PushPermissionState.granted;
    if (p == 'denied') return PushPermissionState.denied;
    return PushPermissionState.defaultState;
  }

  void _showSyncErrorIfNeeded(BuildContext context, bool syncOk) {
    if (!syncOk && _webPushRepo?.syncedToken != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('notificationsSyncFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _currentLang(BuildContext context) => context.isAr ? 'ar' : 'en';

  Future<bool> _syncWebPush(
    BuildContext context,
    WidgetRef ref,
    PushEnv pushEnv,
    PushSettings pushSettings, {
    PushPrefs? overridePrefs,
    bool isWeb = kIsWeb,
  }) {
    if (!isWeb) return Future.value(true);
    // Capture fallback snapshots synchronously before any await so unmounting
    // mid-flight never aborts the server sync or touches a disposed WidgetRef.
    final fallbackLang = _currentLang(context);
    final PushPrefs fallbackPrefs = overridePrefs ?? ref.read(pushPrefsProvider);
    final List<Reminder> fallbackReminders = ref.read(userRemindersProvider);
    final prev = _syncInFlight;
    final next = () async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      return _syncWebPushSerialized(
        ref,
        pushEnv,
        pushSettings,
        fallbackLang: fallbackLang,
        fallbackPrefs: fallbackPrefs,
        fallbackReminders: fallbackReminders,
        overridePrefs: overridePrefs,
      );
    }();
    _syncInFlight = next;
    return next.whenComplete(() {
      if (identical(_syncInFlight, next)) _syncInFlight = null;
    });
  }

  Future<bool> _syncWebPushSerialized(
    WidgetRef ref,
    PushEnv pushEnv,
    PushSettings pushSettings, {
    required String fallbackLang,
    required PushPrefs fallbackPrefs,
    required List<Reminder> fallbackReminders,
    PushPrefs? overridePrefs,
  }) async {
    try {
      await web_push.loadLibrary();
      final repo = _repoFor(pushEnv);
      if (!repo.canWriteInEnvironment) return true;
      final hadTokenBefore = repo.syncedToken != null;
      final liveLang = mounted && context.mounted ? _currentLang(context) : fallbackLang;
      PushPrefs prefs = overridePrefs ?? (mounted ? ref.read(pushPrefsProvider) : fallbackPrefs);
      if (prefs.lang != liveLang) {
        if (mounted) {
          ref.read(pushPrefsProvider.notifier).setLang(liveLang);
        }
        prefs = prefs.copyWith(lang: liveLang);
      }

      if (repo.syncedToken == null) {
        if (prefs.types.isEmpty) {
          return true;
        }
        final token = await repo.enable(vapidKey: pushSettings.vapidKey);
        if (token == null) {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr('notificationsRegisterFailed')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return false;
        }
        // Reconcile against any opt-out / toggle changes made while enable() ran.
        if (overridePrefs == null) {
          final postEnableLang = mounted && context.mounted ? _currentLang(context) : liveLang;
          prefs = mounted ? ref.read(pushPrefsProvider) : fallbackPrefs;
          if (prefs.lang != postEnableLang) {
            if (mounted) {
              ref.read(pushPrefsProvider.notifier).setLang(postEnableLang);
            }
            prefs = prefs.copyWith(lang: postEnableLang);
          }
        }
      }

      if (repo.syncedToken != null) {
        final reminders = mounted ? ref.read(userRemindersProvider) : fallbackReminders;
        final immediate = !hadTokenBefore || prefs.types.isEmpty;
        return (await repo.syncPreferences(
              prefs: prefs,
              reminders: reminders,
              immediate: immediate,
            )) ==
            true;
      }
      return false;
    } catch (e, st) {
      ErrorReporting.capture(e, st, section: 'notifications', source: 'web_push_sync');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    registerStrings(notificationsPageStrings);
    setDocumentRouteMeta(
      path: '/notifications',
      indexable: false,
    );

    final pushSettings = ref.watch(pushSettingsProvider);
    if (!pushSettings.enabled) {
      return PageBody(
        children: [
          EmptyState(
            icon: Icons.notifications_off_outlined,
            message: context.tr('notificationsUnsupported'),
          ),
        ],
      );
    }

    final pal = context.pal;
    final installEnv = ref.watch(installEnvProvider);
    final pushEnv = ref.watch(pushEnvProvider);
    final prefs = ref.watch(pushPrefsProvider);
    final prefsNotifier = ref.read(pushPrefsProvider.notifier);

    final osInfo = detectInstallOs(
      userAgent: installEnv.userAgent,
      platform: installEnv.platform,
      maxTouchPoints: installEnv.maxTouchPoints,
    );

    final web = widget.isWeb ?? kIsWeb;
    final permState = _resolveState(
      osInfo: osInfo,
      userAgent: installEnv.userAgent,
      isStandalone: installEnv.isStandalone,
      pushEnv: pushEnv,
      permission: ref.watch(pushPermissionProvider),
      isWeb: web,
    );

    // Platform filtering: on web, verse, katameros and feasts are on Home
    final platformKey = web ? 'web' : 'app';
    final availableTypes = pushSettings.offered.where((t) {
      final ch = channelOf(t, platformKey);
      return ch != PlatformOwnerChannel.none;
    }).toList();

    return PageBody(
      header: CustomizablePageHeader(
          pageKey: CustomizablePages.notifications,
          title: context.tr('notifications'),
          icon: Icons.notifications_active_outlined,
        ),
        children: [
          const PageIntro(pageKey: CustomizablePages.notifications),

          // Explainer card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: pal.goldText, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('notificationsExplainerTitle'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pal.primaryDeep),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('notificationsExplainerBody'),
                  style: TextStyle(fontSize: 13.5, color: pal.muted, height: 1.6),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Status & Permission card
          _buildStatusCard(
            context,
            pal,
            permState,
            pushSettings,
            pushEnv,
            prefsNotifier,
            ref,
            // Re-read the browser permission so a denial shows the
            // blocked-permission steps right away.
            () => ref.invalidate(pushPermissionProvider),
            isWeb: web,
          ),

          const SizedBox(height: 20),

          // Per-type toggles section
          Text(
            context.tr('adminPushTypesLabel'),
            style: AppFonts.heading(size: 18, color: pal.primaryDeep),
          ),
          const SizedBox(height: 10),

          Material(
            color: pal.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: pal.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < availableTypes.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: pal.hairline),
                  _buildTypeTile(
                    context,
                    pal,
                    availableTypes[i],
                    prefs,
                    prefsNotifier,
                    permState,
                    pushEnv,
                    pushSettings,
                    ref,
                    isWeb: web,
                  ),
                ],
              ],
            ),
          ),

          // Muted note about web home-page readings
          if (kIsWeb)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 10, start: 4, end: 4),
              child: Text(
                context.tr('notificationsQuietNoteWeb'),
                style: TextStyle(fontSize: 12.5, color: pal.muted.withValues(alpha: 0.9), height: 1.4),
              ),
            ),

          if (prefs.types.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: pal.alert,
                  side: BorderSide(color: pal.alert),
                ),
                onPressed: () async {
                  prefsNotifier.clearAll();
                  var ok = true;
                  if (web) {
                    ok = await _syncWebPush(
                      context,
                      ref,
                      pushEnv,
                      pushSettings,
                      overridePrefs: PushPrefs(
                        types: const {},
                        lang: context.isAr ? 'ar' : 'en',
                        updatedAt: DateTime.now().toUtc(),
                      ),
                      isWeb: web,
                    );
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr(ok ? 'notificationsUnsubscribeConfirm' : 'notificationsUnsubscribeFailed'),
                        ),
                      ),
                    );
                  }
                },
                child: Text(context.tr('notificationsUnsubscribeAll')),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // My Reminders section
          const MyRemindersSection(),

          if (kIsWeb) ...[
            const SizedBox(height: 28),
            _WebPushInboxSection(pushEnv: pushEnv),
          ],

          const SizedBox(height: 32),
        ],
      );
  }

  Widget _buildStatusCard(
    BuildContext context,
    dynamic pal,
    PushPermissionState state,
    PushSettings pushSettings,
    PushEnv pushEnv,
    PushPrefsNotifier prefsNotifier,
    WidgetRef ref,
    VoidCallback onPermissionChanged, {
    required bool isWeb,
  }) {
    switch (state) {
      case PushPermissionState.inAppBrowser:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.alert.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.alert.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.open_in_browser, color: pal.alert, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('notificationsInAppBrowser'),
                      style: TextStyle(fontSize: 13, color: pal.ink, height: 1.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(context.tr('notificationsCopyLink')),
                onPressed: () async {
                  final url = NotificationsPage.shareableNotificationsUrlForUri(Uri.base);
                  try {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (mounted) setState(() => _copyFailed = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('notificationsLinkCopied')),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (_) {
                    if (mounted) setState(() => _copyFailed = true);
                  }
                },
              ),
              if (_copyFailed) ...[
                const SizedBox(height: 10),
                Text(
                  context.tr('notificationsCopyFailed'),
                  style: TextStyle(fontSize: 12.5, color: pal.muted),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  NotificationsPage.shareableNotificationsUrlForUri(Uri.base),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.primaryDeep),
                ),
              ],
            ],
          ),
        );

      case PushPermissionState.iosNeedsInstall:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.apple, color: pal.goldText, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('notificationsIosNeedsInstallTitle'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: pal.ink),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('notificationsIosNeedsInstallBody'),
                style: TextStyle(fontSize: 13, color: pal.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              _buildIosStep(
                context,
                pal,
                icon: Icons.ios_share,
                text: context.tr('notificationsIosStep1'),
              ),
              const SizedBox(height: 8),
              _buildIosStep(
                context,
                pal,
                icon: Icons.add_box_outlined,
                text: context.tr('notificationsIosStep2'),
              ),
              const SizedBox(height: 8),
              _buildIosStep(
                context,
                pal,
                icon: Icons.open_in_new,
                text: context.tr('notificationsIosStep3'),
              ),
            ],
          ),
        );

      case PushPermissionState.iosTooOld:
        return _buildAlertBox(
          pal,
          Icons.system_update_alt,
          context.tr('notificationsIosTooOld'),
          pal.alert,
        );

      case PushPermissionState.unsupported:
        return _buildAlertBox(
          pal,
          Icons.notifications_off_outlined,
          context.tr('notificationsUnsupported'),
          pal.muted,
        );

      case PushPermissionState.denied:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.alert.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.alert.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.block, color: pal.alert, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('notificationsBlockedTitle'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: pal.alert),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('notificationsBlockedChrome'),
                style: TextStyle(fontSize: 12.5, color: pal.ink, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('notificationsBlockedIos'),
                style: TextStyle(fontSize: 12.5, color: pal.ink, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.tr('notificationsRecheckButton')),
                onPressed: onPermissionChanged,
              ),
            ],
          ),
        );

      case PushPermissionState.defaultState:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: pal.goldText, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('notificationsAllowPromptTitle'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pal.primaryDeep),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('notificationsAllowPromptBody'),
                style: TextStyle(fontSize: 13.5, color: pal.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.notifications_active),
                label: Text(context.tr('notificationsAllowBrowserButton')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: pushSettings.canRequestPermission
                    ? () async {
                        final res = await pushEnv.requestPermission();
                        if (!mounted) return;
                        if (res == 'granted') {
                          prefsNotifier.firstOptIn();
                          if (isWeb && context.mounted) {
                            final syncOk = await _syncWebPush(
                              context,
                              ref,
                              pushEnv,
                              pushSettings,
                              isWeb: isWeb,
                            );
                            if (!mounted || !context.mounted) return;
                            _showSyncErrorIfNeeded(context, syncOk);
                          }
                        }
                        if (!mounted) return;
                        onPermissionChanged();
                      }
                    : null,
              ),
              if (!pushSettings.canRequestPermission)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr('notificationsComingSoon'),
                    style: TextStyle(fontSize: 12, color: pal.muted),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );

      case PushPermissionState.granted:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: pal.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: pal.success.withValues(alpha: 0.4)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final isNarrow = constraints.maxWidth < 320 || textScale >= 1.4;
              final textItem = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, color: pal.success, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      context.tr('notificationsEnabledChip'),
                      style: TextStyle(fontWeight: FontWeight.bold, color: pal.success, fontSize: 14),
                    ),
                  ),
                ],
              );
              final testBtn = kIsWeb
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: pal.primary,
                      ),
                      icon: const Icon(Icons.notifications_none, size: 16),
                      label: Text(context.tr('notificationsTestButton'), style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        await pushEnv.showSwTestNotification(
                          title: context.isAr ? 'اختبار الإشعارات' : 'Notification Test',
                          body: context.isAr
                              ? 'إشعار تجريبي يعمل بنجاح على هذا المتصفح'
                              : 'Test notification received successfully on this browser',
                          link: '/notifications',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.tr('notificationsTestSent'))),
                          );
                        }
                      },
                    )
                  : null;

              if (isNarrow && testBtn != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textItem,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: testBtn,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: textItem),
                  ?testBtn,
                ],
              );
            },
          ),
        );
    }
  }

  Widget _buildAlertBox(dynamic pal, IconData icon, String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: pal.ink, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIosStep(
    BuildContext context,
    dynamic pal, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: pal.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: pal.ink, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeTile(
    BuildContext context,
    dynamic pal,
    NotifyType type,
    PushPrefs prefs,
    PushPrefsNotifier prefsNotifier,
    PushPermissionState permState,
    PushEnv pushEnv,
    PushSettings pushSettings,
    WidgetRef ref, {
    required bool isWeb,
  }) {
    final isSelected = prefs.types.contains(type);
    final title = context.isAr ? type.labelAr : type.labelEn;
    final desc = context.isAr ? type.descriptionAr : type.descriptionEn;

    return SwitchListTile(
      value: isSelected,
      onChanged: (turnOn) async {
        if (turnOn && permState != PushPermissionState.granted) {
          if (isWeb) {
            if (!pushSettings.canRequestPermission) return;
            if (permState == PushPermissionState.iosNeedsInstall) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('notificationsIosAddFirst')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return;
            }
            if (permState == PushPermissionState.inAppBrowser) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('notificationsInAppOpenBrowser')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return;
            }
            final res = await pushEnv.requestPermission();
            if (!mounted) return;
            if (res == 'granted') {
              prefsNotifier.toggleType(type);
              var syncOk = true;
              if (context.mounted) {
                syncOk = await _syncWebPush(context, ref, pushEnv, pushSettings, isWeb: isWeb);
              }
              if (!mounted || !context.mounted) return;
              ref.invalidate(pushPermissionProvider);
              _showSyncErrorIfNeeded(context, syncOk);
            } else {
              ref.invalidate(pushPermissionProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('notificationsPermissionDisabled')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          } else {
            // Native platforms: toggle type directly!
            prefsNotifier.toggleType(type);
          }
        } else {
          prefsNotifier.toggleType(type);
          if (isWeb &&
              (permState == PushPermissionState.granted || readWebPushStorageState(pushEnv)?.syncedToken != null) &&
              context.mounted) {
            final syncOk = await _syncWebPush(context, ref, pushEnv, pushSettings, isWeb: isWeb);
            if (!mounted || !context.mounted) return;
            _showSyncErrorIfNeeded(context, syncOk);
          }
        }
      },
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: pal.ink),
      ),
      subtitle: Text(
        desc,
        style: TextStyle(fontSize: 12.5, color: pal.muted, height: 1.4),
      ),
      activeThumbColor: pal.primary,
    );
  }
}

class _WebPushInboxSection extends StatefulWidget {
  final PushEnv pushEnv;
  const _WebPushInboxSection({required this.pushEnv});

  @override
  State<_WebPushInboxSection> createState() => _WebPushInboxSectionState();
}

class _WebPushInboxSectionState extends State<_WebPushInboxSection> {
  List<WebInboxItem> _items = const [];
  bool _loading = true;
  StreamSubscription<WebInboxItem>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.pushEnv.inboxEvents.listen((item) {
      if (mounted) {
        setState(() {
          _items = [item, ..._items];
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.pushEnv.readInbox();
      if (mounted) {
        setState(() {
          _items = res;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    await widget.pushEnv.clearInbox();
    if (mounted) {
      setState(() {
        _items = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    if (_loading) return const SizedBox.shrink();
    if (_items.isEmpty) return const SizedBox.shrink();

    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              context.tr('notificationsInboxTitle'),
              style: AppFonts.heading(size: 18, color: pal.primaryDeep),
            ),
            TextButton(
              onPressed: _clear,
              child: Text(context.tr('notificationsInboxClear')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final item in _items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pal.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pal.ink),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(fontSize: 13, color: pal.muted),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

