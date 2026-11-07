import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/rules.dart' show toArabicDigits;

/// Shows the step-by-step visual sideload guide modal (ADR-057).
Future<void> showApkInstallGuide(BuildContext context, {double? apkSizeMb}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ApkInstallGuideSheet(apkSizeMb: apkSizeMb),
  );
}

class _ApkInstallGuideSheet extends StatefulWidget {
  final double? apkSizeMb;

  const _ApkInstallGuideSheet({this.apkSizeMb});

  @override
  State<_ApkInstallGuideSheet> createState() => _ApkInstallGuideSheetState();
}

class _ApkInstallGuideSheetState extends State<_ApkInstallGuideSheet> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 5;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    if (step >= 0 && step < _totalSteps) {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final sizeStr = widget.apkSizeMb != null && widget.apkSizeMb! > 0
        ? widget.apkSizeMb!.toStringAsFixed(1)
        : '18.4';

    return SafeArea(
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
                  // Top grabber
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

                  // Header with close button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('apkGuideTitle'),
                          style: AppFonts.heading(size: 20, color: pal.primaryDeep),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: context.tr('installDismiss'),
                        onPressed: () => Navigator.of(context).pop(),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Step indicator text
                  Text(
                    context.tr('apkGuideStep', {
                      'current': context.isAr ? toArabicDigits('${_currentStep + 1}') : '${_currentStep + 1}',
                      'total': context.isAr ? toArabicDigits('$_totalSteps') : '$_totalSteps',
                    }),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: pal.goldText,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Progress dot indicators
                  Row(
                    children: List.generate(_totalSteps, (i) {
                      final active = i == _currentStep;
                      return Expanded(
                        child: Container(
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: active ? pal.primary : pal.hairline.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 16),

                  // PageView for the 5 steps
                  SizedBox(
                    height: 380,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _totalSteps,
                      onPageChanged: (i) => setState(() => _currentStep = i),
                      itemBuilder: (ctx, index) {
                        final stepNum = index + 1;
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Screenshot frame / placeholder
                              _buildStepImage(ctx, pal, stepNum),

                              const SizedBox(height: 14),

                              // Step Title
                              Text(
                                context.tr('apkGuideStep${stepNum}Title'),
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: pal.ink,
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Step Body
                              Text(
                                context.tr('apkGuideStep${stepNum}Body', {'size': sizeStr}),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: pal.muted,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Note about appearance variations
                  Text(
                    context.tr('apkGuideDiffersNote'),
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: pal.muted.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 14),

                  // Safety Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pal.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: pal.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 18, color: pal.goldText),
                            const SizedBox(width: 6),
                            Text(
                              context.tr('apkGuideSafetyBoxTitle'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: pal.goldText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildSafetyBullet(pal, context.tr('apkGuideSafetyBox1')),
                        const SizedBox(height: 4),
                        _buildSafetyBullet(pal, context.tr('apkGuideSafetyBox2')),
                        const SizedBox(height: 4),
                        _buildSafetyBullet(pal, context.tr('apkGuideSafetyBox3')),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Navigation buttons
                  Row(
                    children: [
                      if (_currentStep > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _goTo(_currentStep - 1),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            child: Text(context.tr('apkGuidePrev')),
                          ),
                        ),
                      if (_currentStep > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () {
                            if (_currentStep < _totalSteps - 1) {
                              _goTo(_currentStep + 1);
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          child: Text(
                            _currentStep < _totalSteps - 1
                                ? context.tr('apkGuideNext')
                                : context.tr('apkGuideDone'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepImage(BuildContext context, dynamic pal, int stepNum) {
    final lang = context.isAr ? 'ar' : 'en';
    final imageUrl = 'web/install-guide/android-$stepNum-$lang.webp';

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: pal.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (ctx, err, stack) => _buildPlaceholder(context, pal, stepNum),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, dynamic pal, int stepNum) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 40, color: pal.goldText.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Text(
            context.tr('apkGuidePlaceholderCaption', {'n': '$stepNum'}),
            style: TextStyle(
              fontSize: 13,
              color: pal.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyBullet(dynamic pal, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: TextStyle(color: pal.goldText, fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.4, color: pal.ink),
          ),
        ),
      ],
    );
  }
}
