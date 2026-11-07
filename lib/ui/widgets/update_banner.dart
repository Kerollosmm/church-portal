import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/app_update.dart';
import '../../state/providers.dart';

/// In-app update notification banner shown at top of the app (ADR-058 / PR B §3.3).
class UpdateBanner extends ConsumerStatefulWidget {
  final UpdateDecision? decision;
  final bool autoStartDownload;

  const UpdateBanner({
    super.key,
    this.decision,
    this.autoStartDownload = true,
  });

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  bool _dismissedLocally = false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && widget.decision == null) {
      return const SizedBox.shrink();
    }

    final decision = widget.decision ?? ref.watch(updateDecisionProvider).value;
    if (decision == null || !decision.hasUpdate) {
      return const SizedBox.shrink();
    }

    if (_dismissedLocally && !decision.isForced) {
      return const SizedBox.shrink();
    }

    final pal = context.pal;

    return Semantics(
      container: true,
      label: context.tr('updateAvailable', {'version': decision.targetVersion}),
      child: Container(
        key: const Key('appUpdateBanner'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: pal.notice,
          border: Border(
            bottom: BorderSide(color: pal.noticeEdge, width: 1.0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;

            final contentText = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_rounded, size: 20, color: pal.noticeInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('updateAvailable', {'version': decision.targetVersion}),
                    style: TextStyle(
                      color: pal.noticeInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  key: const Key('updateNowButton'),
                  onPressed: () => _openUpdateSheet(context, decision),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.primary,
                    foregroundColor: pal.onBar,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: Text(
                    context.tr('updateNow'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!decision.isForced) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('dismissUpdateButton'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: pal.noticeInk,
                    tooltip: context.tr('updateDismiss'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _dismiss(decision),
                  ),
                ],
              ],
            );

            if (isNarrow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  contentText,
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: contentText),
                const SizedBox(width: 8),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  void _dismiss(UpdateDecision decision) async {
    setState(() => _dismissedLocally = true);
    final updater = ref.read(appUpdaterProvider);
    await updater.dismissUpdate(decision.targetBuild);
    ref.invalidate(updateDecisionProvider);
  }

  void _openUpdateSheet(BuildContext context, UpdateDecision decision) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => UpdateSheet(
        decision: decision,
        autoStart: widget.autoStartDownload,
      ),
    );
  }
}

enum _UpdateStatus {
  idle,
  downloading,
  permissionNeeded,
  installing,
  readyToInstall,
  error,
}

/// Modal bottom sheet guiding the in-app update download and installation.
class UpdateSheet extends ConsumerStatefulWidget {
  final UpdateDecision decision;
  final bool autoStart;

  const UpdateSheet({
    super.key,
    required this.decision,
    this.autoStart = true,
  });

  @override
  ConsumerState<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<UpdateSheet> {
  _UpdateStatus _status = _UpdateStatus.idle;
  UpdateDownloadProgress? _progress;
  String? _errorMessage;
  String? _downloadedFilePath;
  StreamSubscription<UpdateDownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart && widget.decision.asset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDownload();
      });
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  void _startDownload() {
    final asset = widget.decision.asset;
    if (asset == null) {
      setState(() {
        _status = _UpdateStatus.error;
        _errorMessage = context.tr('updateFailed');
      });
      return;
    }

    setState(() {
      _status = _UpdateStatus.downloading;
      _errorMessage = null;
    });

    final updater = ref.read(appUpdaterProvider);
    _downloadSub?.cancel();
    _downloadSub = updater.downloadUpdate(asset, build: widget.decision.targetBuild).listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
        });
        if (progress.isDone && progress.filePath != null) {
          _onDownloadComplete(progress.filePath!);
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _status = _UpdateStatus.error;
          if (err is UpdateIntegrityException) {
            _errorMessage = context.tr('updateIntegrityError');
          } else {
            _errorMessage = context.tr('updateFailed');
          }
        });
      },
    );
  }

  void _cancelDownload() {
    _downloadSub?.cancel();
    setState(() {
      _status = _UpdateStatus.idle;
      _progress = null;
    });
  }

  void _onDownloadComplete(String filePath) async {
    _downloadedFilePath = filePath;
    final updater = ref.read(appUpdaterProvider);

    final canInstall = await updater.canRequestPackageInstalls();
    if (!canInstall) {
      if (!mounted) return;
      setState(() {
        _status = _UpdateStatus.permissionNeeded;
      });
      return;
    }

    _install(filePath);
  }

  void _install(String filePath) async {
    setState(() {
      _status = _UpdateStatus.installing;
      _errorMessage = null;
    });

    final updater = ref.read(appUpdaterProvider);
    try {
      await updater.installDownloadedUpdate(
        filePath,
        expectedCertSha256:
            widget.decision.certSha256.isNotEmpty ? widget.decision.certSha256 : null,
      );
    } on UpdateSignatureException {
      if (!mounted) return;
      setState(() {
        _status = _UpdateStatus.error;
        _errorMessage = context.tr('updateSignatureError');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _UpdateStatus.error;
        _errorMessage = context.tr('updateFailed');
      });
    }
  }

  void _requestPermission() async {
    final updater = ref.read(appUpdaterProvider);
    await updater.openManageUnknownApps();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final notes = context.pick(widget.decision.notesAr, widget.decision.notesEn);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: pal.hairline, width: 1.0),
              boxShadow: pal.panelShadow,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: pal.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header row
                  Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: pal.primary, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('updateSheetTitle'),
                              style: TextStyle(
                                color: pal.ink,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              'v${widget.decision.targetVersion}',
                              style: TextStyle(
                                color: pal.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.decision.isForced)
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: pal.muted,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: pal.hairline, height: 1),
                  const SizedBox(height: 14),

                  // Release notes section
                  if (notes.isNotEmpty) ...[
                    Text(
                      context.tr('updateWhatsNew'),
                      style: TextStyle(
                        color: pal.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: pal.notice.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        notes,
                        style: TextStyle(color: pal.ink, fontSize: 13, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Dynamic state widgets
                  _buildStateContent(context, pal),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(BuildContext context, dynamic pal) {
    switch (_status) {
      case _UpdateStatus.idle:
        return Column(
          children: [
            FilledButton.icon(
              key: const Key('startDownloadButton'),
              onPressed: _startDownload,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(context.tr('updateNow')),
              style: FilledButton.styleFrom(
                backgroundColor: pal.primary,
                foregroundColor: pal.onBar,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );

      case _UpdateStatus.downloading:
        final currentMb = (_progress?.downloadedBytes ?? 0) / (1024 * 1024);
        final totalMb = (_progress?.totalBytes ?? widget.decision.asset?.size ?? 1) / (1024 * 1024);
        final pct = ((_progress?.percent ?? 0.0) * 100).clamp(0, 100).toStringAsFixed(0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('updateDownloading'),
              style: TextStyle(color: pal.ink, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const Key('updateDownloadProgress'),
              value: _progress?.percent,
              backgroundColor: pal.hairline,
              color: pal.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${currentMb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB ($pct%)',
                  style: TextStyle(color: pal.muted, fontSize: 12.5),
                ),
                TextButton(
                  key: const Key('cancelDownloadButton'),
                  onPressed: _cancelDownload,
                  style: TextButton.styleFrom(foregroundColor: pal.alert),
                  child: Text(context.tr('updateCancel')),
                ),
              ],
            ),
          ],
        );

      case _UpdateStatus.permissionNeeded:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pal.alertGround,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pal.alert.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.security_rounded, color: pal.alert, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('updatePermissionRequired'),
                      style: TextStyle(color: pal.alert, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('updatePermissionGuide'),
                style: TextStyle(color: pal.ink, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('openSettingsButton'),
                      onPressed: _requestPermission,
                      child: Text(context.tr('updateOpenSettings')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('retryInstallButton'),
                    onPressed: () {
                      if (_downloadedFilePath != null) {
                        _onDownloadComplete(_downloadedFilePath!);
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: pal.primary, foregroundColor: pal.onBar),
                    child: Text(context.tr('updateInstall')),
                  ),
                ],
              ),
            ],
          ),
        );

      case _UpdateStatus.installing:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: pal.primary),
              ),
              const SizedBox(width: 12),
              Text(
                context.tr('updateInstall'),
                style: TextStyle(color: pal.ink, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );

      case _UpdateStatus.readyToInstall:
        return Column(
          children: [
            Text(
              context.tr('updateReadyToInstall'),
              style: TextStyle(color: pal.success, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('readyInstallButton'),
              onPressed: () {
                if (_downloadedFilePath != null) {
                  _install(_downloadedFilePath!);
                }
              },
              icon: const Icon(Icons.install_mobile_rounded),
              label: Text(context.tr('updateInstall')),
              style: FilledButton.styleFrom(
                backgroundColor: pal.primary,
                foregroundColor: pal.onBar,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              ),
            ),
          ],
        );

      case _UpdateStatus.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pal.alertGround,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pal.alert.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: pal.alert, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage ?? context.tr('updateFailed'),
                      style: TextStyle(color: pal.alert, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  key: const Key('retryButton'),
                  onPressed: _startDownload,
                  child: Text(context.tr('updateRetry')),
                ),
              ),
            ],
          ),
        );
    }
  }
}
