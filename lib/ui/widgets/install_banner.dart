import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/install_env.dart';
import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/app_install.dart';
import '../../state/providers.dart';
import 'apk_install_guide.dart';

/// App install banner shown at the bottom of the viewport on mobile web (ADR-057).
class InstallBanner extends ConsumerStatefulWidget {
  final String currentPath;
  final Duration delay;
  final bool? isWeb;

  const InstallBanner({
    super.key,
    required this.currentPath,
    this.delay = const Duration(seconds: 4),
    this.isWeb,
  });

  @override
  ConsumerState<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends ConsumerState<InstallBanner> {
  Timer? _timer;
  bool _readyToDisplay = false;
  bool _dismissedThisSession = false;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (widget.delay == Duration.zero) {
      _readyToDisplay = true;
      return;
    }
    // Shown 4 seconds after content arrives
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _readyToDisplay = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime? _readDismissedUntil(InstallEnv env) {
    final json = env.readJson(installStorageKey);
    if (json == null) return null;
    final untilStr = json['until'];
    if (untilStr is String) {
      try {
        return DateTime.parse(untilStr);
      } catch (_) {}
    }
    return null;
  }

  void _dismiss({required int days, required InstallEnv env}) {
    setState(() => _dismissedThisSession = true);
    final now = DateTime.now().toUtc();
    final until = days == 0
        ? DateTime.utc(2099, 1, 1)
        : now.add(Duration(days: days));
    env.writeJson(installStorageKey, {'until': until.toIso8601String()});
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) return const SizedBox.shrink();

    final isContentReady = ref.watch(contentReadyProvider);
    if (!isContentReady || !_readyToDisplay) return const SizedBox.shrink();

    final env = ref.watch(installEnvProvider);
    final settings = ref.watch(installSettingsProvider);

    final osInfo = detectInstallOs(
      userAgent: env.userAgent,
      platform: env.platform,
      maxTouchPoints: env.maxTouchPoints,
    );

    final dismissedUntil = _readDismissedUntil(env);
    final now = DateTime.now().toUtc();

    final shouldShow = shouldShowInstallBanner(
      settings: settings,
      os: osInfo.os,
      isStandalone: env.isStandalone,
      installedEventReceived: env.installedEventReceived,
      dismissedUntil: dismissedUntil,
      now: now,
      path: widget.currentPath,
      isWeb: widget.isWeb ?? kIsWeb,
    );

    if (!shouldShow) return const SizedBox.shrink();

    final pal = context.pal;
    final action = resolveInstallAction(
      os: osInfo.os,
      androidUrl: settings.androidUrl,
      hasPrompt: env.hasDeferredPrompt,
    );

    final title = context.pick(settings.titleAr, settings.titleEn);
    final body = context.pick(settings.bodyAr, settings.bodyEn);

    return Semantics(
      liveRegion: true,
      container: true,
      child: SafeArea(
        top: false,
        child: Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: pal.card,
              elevation: 6,
              shadowColor: pal.shadow(0.5),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: pal.hairline),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top row: seal + title + close button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: pal.hairline),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/branding/seal_light.png',
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) =>
                                Icon(Icons.church_outlined, color: pal.goldText, size: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isNotEmpty ? title : context.tr('installAppTitle'),
                                style: AppFonts.heading(size: 16, color: pal.primaryDeep),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                body.isNotEmpty ? body : context.tr('installAppBody'),
                                style: TextStyle(fontSize: 13, color: pal.muted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: context.tr('installDismiss'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () => _dismiss(days: settings.reshowDays, env: env),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Actions row
                    _buildActions(context, pal, settings, action, env),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    dynamic pal,
    InstallSettings settings,
    InstallAction action,
    InstallEnv env,
  ) {
    final versionStr = settings.apkVersion.isNotEmpty ? 'v${settings.apkVersion}' : '';
    final sizeStr = settings.apkSizeMb > 0 ? '${settings.apkSizeMb.toStringAsFixed(1)} MB' : '';
    final detailsCaption = versionStr.isNotEmpty && sizeStr.isNotEmpty
        ? '$versionStr • $sizeStr'
        : (versionStr.isNotEmpty ? versionStr : sizeStr);

    Widget primaryButton;
    switch (action) {
      case InstallAction.apk:
        primaryButton = FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: () {
            openUrl(settings.androidUrl);
            showApkInstallGuide(context, apkSizeMb: settings.apkSizeMb);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('installDownloadApk')),
              if (detailsCaption.isNotEmpty)
                Text(
                  detailsCaption,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                ),
            ],
          ),
        );
        break;

      case InstallAction.pwaPrompt:
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const Icon(Icons.download, size: 18),
          label: Text(context.tr('installDownloadApk')),
          onPressed: () async {
            await env.promptInstall();
          },
        );
        break;

      case InstallAction.androidSteps:
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const Icon(Icons.info_outline, size: 18),
          label: Text(context.tr('installOpenMethod')),
          onPressed: () => showApkInstallGuide(context, apkSizeMb: settings.apkSizeMb),
        );
        break;

      case InstallAction.iosSteps:
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(context.tr('installIosAction')),
          onPressed: () => showIosInstallSteps(context),
        );
        break;

      case InstallAction.none:
        return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: primaryButton),
            const SizedBox(width: 10),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => _dismiss(days: settings.remindDays, env: env),
              child: Text(context.tr('installLater')),
            ),
          ],
        ),
        if (action == InstallAction.apk && settings.androidUrl32.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton(
                onPressed: () {
                  openUrl(settings.androidUrl32);
                  showApkInstallGuide(context, apkSizeMb: settings.apkSize32Mb);
                },
                child: Text(
                  context.tr('installOlderPhone'),
                  style: TextStyle(fontSize: 12, color: pal.goldText),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows the 3-step iOS Add-to-Home-Screen instructions sheet.
///
/// NEVER touches Notification / PushManager APIs.
Future<void> showIosInstallSteps(BuildContext context) {
  final pal = context.pal;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: pal.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    ctx.tr('iosInstallTitle'),
                    style: AppFonts.heading(size: 19, color: pal.primaryDeep),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildIosStep(
                    context: ctx,
                    pal: pal,
                    number: 1,
                    icon: Icons.ios_share,
                    text: ctx.tr('iosInstallStep1'),
                  ),
                  const SizedBox(height: 12),
                  _buildIosStep(
                    context: ctx,
                    pal: pal,
                    number: 2,
                    icon: Icons.add_box_outlined,
                    text: ctx.tr('iosInstallStep2'),
                  ),
                  const SizedBox(height: 12),
                  _buildIosStep(
                    context: ctx,
                    pal: pal,
                    number: 3,
                    icon: Icons.add,
                    text: ctx.tr('iosInstallStep3'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pal.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: pal.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app_outlined, size: 20, color: pal.goldText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ctx.tr('iosInstallOpenIcon'),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: pal.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ctx.tr('iosInstallSafariNote'),
                    style: TextStyle(fontSize: 12, color: pal.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(ctx.tr('iosInstallDone')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildIosStep({
  required BuildContext context,
  required dynamic pal,
  required int number,
  required IconData icon,
  required String text,
}) {
  return Row(
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: pal.bar,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: TextStyle(
            color: pal.onBar,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Icon(icon, size: 22, color: pal.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: pal.ink,
          ),
        ),
      ),
    ],
  );
}
