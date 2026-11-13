import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/error_reporting.dart';
import '../../core/install_env.dart';
import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/app_install.dart';
import '../../state/providers.dart';
// The sideload guide and the install-steps sheets ship in their own web
// chunk, fetched on tap (ADR-057 size budget).
import 'apk_install_guide.dart' deferred as guide;

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
  void Function()? _unlistenInstall;

  @override
  void initState() {
    super.initState();
    // A prompt that arrives late, or an install from the browser menu,
    // re-evaluates the banner (its action or whether it shows at all).
    _unlistenInstall = ref.read(installEnvProvider).listenInstallChanges(() {
      if (mounted) setState(() {});
    });
    // The reading delay starts when the content arrives (not at app start),
    // so a slow first load never pops the banner over a spinner.
    if (ref.read(contentReadyProvider)) {
      _startTimerIfNeeded();
    } else {
      ref.listenManual<bool>(contentReadyProvider, (prev, ready) {
        if (ready && _timer == null && !_readyToDisplay) _startTimerIfNeeded();
      });
    }
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (widget.delay == Duration.zero) {
      if (mounted) setState(() => _readyToDisplay = true);
      return;
    }
    // Shown [delay] (4 s) after content arrives
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _readyToDisplay = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _unlistenInstall?.call();
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
    try {
      env.writeJson(installStorageKey, {'until': until.toIso8601String()});
    } catch (_) {
      // Storage refused: hidden for this session only.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) return const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).height < kLandscapeShortHeight) return const SizedBox.shrink();

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
                            // Parish seal. Flutter web requests assets/assets/branding/<file>.
                            // seal_light.png does not exist, so that URL 404'd.
                            'assets/branding/seal.png',
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

  /// Loads the guide chunk, then opens [show] (nothing on a failed fetch).
  Future<void> _guide(BuildContext context, Future<void> Function(BuildContext) show) async {
    try {
      await guide.loadLibrary();
    } catch (e, st) {
      ErrorReporting.capture(e, st, section: 'deferred_chunk', source: 'apk_install_guide');
      return;
    }
    if (context.mounted) await show(context);
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
            openUrl(resolveInstallUrl(settings.androidUrl, Uri.base));
            _guide(context, (c) => guide.showApkInstallGuide(c, apkSizeMb: settings.apkSizeMb));
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
            // The deferred prompt is single-use: hide the banner for this
            // session once it has been shown (installed or declined).
            final shown = await env.promptInstall();
            if (shown && mounted) setState(() => _dismissedThisSession = true);
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
          // No APK and no browser prompt: the browser-menu steps (⋮ → Install).
          onPressed: () => _guide(context, (c) => guide.showAndroidInstallSteps(c)),
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
          onPressed: () => _guide(context, (c) => guide.showIosInstallSteps(c)),
        );
        break;

      case InstallAction.none:
        return const SizedBox.shrink();
    }

    final laterButton = TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () => _dismiss(days: settings.remindDays, env: env),
      child: Text(context.tr('installLater')),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final stack = constraints.maxWidth < 260 || textScale >= 1.6;
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primaryButton,
                  const SizedBox(height: 6),
                  laterButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: primaryButton),
                const SizedBox(width: 10),
                laterButton,
              ],
            );
          },
        ),
        if (action == InstallAction.apk && settings.androidUrl32.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton(
                onPressed: () {
                  openUrl(resolveInstallUrl(settings.androidUrl32, Uri.base));
                  _guide(context, (c) => guide.showApkInstallGuide(c, apkSizeMb: settings.apkSize32Mb));
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
