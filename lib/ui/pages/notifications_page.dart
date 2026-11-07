import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/push_env.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/remind_me.dart';

/// The visitor's notification preferences and reminders page (`/notifications`, ADR-057).
class NotificationsPage extends ConsumerWidget {
  final bool? isWeb;
  const NotificationsPage({super.key, this.isWeb});

  PushPermissionState _resolveState({
    required InstallOsInfo osInfo,
    required bool isStandalone,
    required PushEnv pushEnv,
    required bool isWeb,
  }) {
    if (!isWeb) return PushPermissionState.granted;

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

    final p = pushEnv.permission;
    if (p == 'granted') return PushPermissionState.granted;
    if (p == 'denied') return PushPermissionState.denied;
    return PushPermissionState.defaultState;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final web = isWeb ?? kIsWeb;
    final permState = _resolveState(
      osInfo: osInfo,
      isStandalone: installEnv.isStandalone,
      pushEnv: pushEnv,
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
          _buildStatusCard(context, pal, permState, pushSettings, pushEnv, prefsNotifier),

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
                  _buildTypeTile(context, pal, availableTypes[i], prefs, prefsNotifier),
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
                onPressed: () {
                  prefsNotifier.clearAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('notificationsUnsubscribeConfirm'))),
                  );
                },
                child: Text(context.tr('notificationsUnsubscribeAll')),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // My Reminders section
          const MyRemindersSection(),

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
  ) {
    switch (state) {
      case PushPermissionState.inAppBrowser:
        return _buildAlertBox(
          pal,
          Icons.open_in_browser,
          context.tr('notificationsInAppBrowser'),
          pal.alert,
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
              FilledButton.icon(
                icon: const Icon(Icons.notifications_active),
                label: Text(context.tr('notificationsEnableButton')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: pushSettings.webReady
                    ? () async {
                        final res = await pushEnv.requestPermission();
                        if (res == 'granted') {
                          prefsNotifier.firstOptIn();
                        }
                      }
                    : null,
              ),
              if (!pushSettings.webReady)
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
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: pal.success, size: 20),
              const SizedBox(width: 10),
              Text(
                context.tr('notificationsEnabledChip'),
                style: TextStyle(fontWeight: FontWeight.bold, color: pal.success, fontSize: 14),
              ),
            ],
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

  Widget _buildTypeTile(
    BuildContext context,
    dynamic pal,
    NotifyType type,
    PushPrefs prefs,
    PushPrefsNotifier prefsNotifier,
  ) {
    final isSelected = prefs.types.contains(type);
    final title = context.isAr ? type.labelAr : type.labelEn;
    final desc = context.isAr ? type.descriptionAr : type.descriptionEn;

    return SwitchListTile(
      value: isSelected,
      onChanged: (_) => prefsNotifier.toggleType(type),
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
