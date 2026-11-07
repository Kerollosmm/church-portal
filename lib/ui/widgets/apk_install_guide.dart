import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/rules.dart' show toArabicDigits;

/// Strings only this deferred chunk uses (registered before it builds).
const Map<String, List<String>> installGuideStrings = {
  'iosInstallTitle': ['إضافة الموقع للشاشة الرئيسية', 'Add site to Home Screen'],
  'iosInstallStep1': ['اضغط زر المشاركة في أسفل المتصفح', 'Tap the Share button at the bottom of Safari'],
  'iosInstallStep2': ['اختر «إضافة إلى الشاشة الرئيسية»', 'Select "Add to Home Screen"'],
  'iosInstallStep3': ['اضغط «إضافة» في أعلى الشاشة', 'Tap "Add" in the top right'],
  'iosInstallOpenIcon': ['افتح الكنيسة من الأيقونة الجديدة على شاشتك', 'Open the church app from the new icon on your home screen'],
  'iosInstallSafariNote': ['إذا لم يظهر الخيار، تأكد من فتح الموقع في متصفح Safari.', 'If the option does not appear, make sure to open the site in Safari.'],
  'androidInstallTitle': ['تثبيت التطبيق من المتصفح', 'Install from the browser'],
  'androidInstallStep1': ['اضغط زر القائمة ⋮ أعلى المتصفح', 'Tap the ⋮ menu at the top of the browser'],
  'androidInstallStep2': ['اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية»', 'Choose "Install app" or "Add to Home screen"'],
  'androidInstallNote': ['قد يختلف اسم الخيار قليلًا حسب المتصفح.', 'The option name may differ slightly between browsers.'],
  'iosInstallDone': ['تم', 'Done'],
  'apkGuideTitle': ['دليل تثبيت تطبيق الكنيسة (APK)', 'Church app install guide (APK)'],
  'apkGuideStep': ['الخطوة {current} من {total}', 'Step {current} of {total}'],
  'apkGuideNext': ['التالي', 'Next'],
  'apkGuidePrev': ['السابق', 'Back'],
  'apkGuideDone': ['تم، فهمت الخطوات', 'Done, I understand'],
  'apkGuideDiffersNote': ['قد يختلف الشكل قليلًا حسب نوع هاتفك ونظام Android', 'Appearance may vary slightly depending on your phone and Android version'],
  'apkGuideStep1Title': ['رسالة «قد يكون الملف ضارًا»', '"File might be harmful" warning'],
  'apkGuideStep1Body': ['يعرضها المتصفح لأي تطبيق من خارج متجر Play. تأكد أن العنوان في الأعلى هو maximos-domadios-church.web.app ثم اضغط «تنزيل على أي حال»', 'The browser shows this for any app from outside the Play Store. Check that the address bar shows maximos-domadios-church.web.app, then tap "Download anyway"'],
  'apkGuideStep2Title': ['افتح الملف بعد التنزيل', 'Open the downloaded file'],
  'apkGuideStep2Body': ['من إشعار «اكتمل التنزيل» أو من مجلد «التنزيلات» اضغط على ملف تطبيق الكنيسة. حجم الملف تقريبًا {size} م.ب', 'From the "Download complete" notification or Downloads folder, tap the church app file. File size is approx {size} MB'],
  'apkGuideStep2BodyNoSize': ['من إشعار «اكتمل التنزيل» أو من مجلد «التنزيلات» اضغط على ملف تطبيق الكنيسة', 'From the "Download complete" notification or Downloads folder, tap the church app file'],
  'apkGuideStep3Title': ['اسمح بالتثبيت لهذا التطبيق مرة واحدة', 'Allow install from this source once'],
  'apkGuideStep3Body': ['اضغط «الإعدادات» ← فعّل «السماح من هذا المصدر» للتطبيق الظاهر في الصفحة — المتصفح (مثل Chrome) إذا فتحت الملف من إشعار التنزيل، أو «الملفات» / «ملفاتي» إذا فتحته من مدير الملفات ← ارجع', 'Tap "Settings" → turn on "Allow from this source" for the app shown on that page — the browser (e.g. Chrome) if you opened the file from the download notification, or Files / My Files if you opened it from a file manager → go back'],
  'apkGuideStep4Title': ['تحذير Google Play Protect', 'Google Play Protect'],
  'apkGuideStep4Body': ['قد يقترح فحص التطبيق — اسمح بالفحص. إذا قال إنه لا يعرف المطوّر: «مزيد من التفاصيل» ← «التثبيت على أي حال». هذا طبيعي لتطبيق من خارج المتجر', 'Google Play Protect may offer to scan the app — allow the scan. If it says the developer is unknown: "More details" → "Install anyway". Normal for an app from outside the store'],
  'apkGuideStep5Title': ['افتح التطبيق وأعد الأمان', 'Open the app & restore security'],
  'apkGuideStep5Body': ['افتح التطبيق، ثم (اختياري وأكثر أمانًا) ارجع إلى الإعدادات ← التطبيقات ← نفس التطبيق الذي سمحت له في الخطوة ٣ (المتصفح أو مدير الملفات) ← «تثبيت التطبيقات غير المعروفة» وأوقف «السماح من هذا المصدر»', 'Open the app, then (optional, safer) go to Settings → Apps → the same app you allowed in step 3 (browser or file manager) → "Install unknown apps" and switch "Allow from this source" off again'],
  'apkGuidePlaceholderCaption': ['صورة توضيحية للخطوة {n}', 'Illustration for step {n}'],
  'apkGuideSafetyBoxTitle': ['للأمان والسلامة', 'For your safety'],
  'apkGuideSafetyBox1': ['حمّل التطبيق من موقع الكنيسة فقط، لا من ملفات مرسلة على واتساب أو فيسبوك', 'Only download the app from the church website, never from forwarded files on WhatsApp or Facebook'],
  'apkGuideSafetyBox2': ['الكنيسة لا تطلب أبدًا إيقاف Play Protect بالكامل أو منح أذونات غير معتادة', 'The church will never ask you to disable Play Protect entirely or grant unusual permissions'],
  'apkGuideSafetyBox3': ['تأكد أن رقم الإصدار والحجم يطابقان ما هو معلن على الموقع', 'Ensure version number and file size match what is stated on the site'],
};

/// Shows the step-by-step visual sideload guide modal (ADR-057).
Future<void> showApkInstallGuide(BuildContext context, {double? apkSizeMb}) {
  registerStrings(installGuideStrings);
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
    final hasPositiveSize = widget.apkSizeMb != null && widget.apkSizeMb! > 0;
    final sizeStr = hasPositiveSize ? widget.apkSizeMb!.toStringAsFixed(1) : '';

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
                        final bodyKey = (stepNum == 2 && !hasPositiveSize)
                            ? 'apkGuideStep2BodyNoSize'
                            : 'apkGuideStep${stepNum}Body';
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
                                context.tr(bodyKey, {'size': sizeStr}),
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
    // Served from Hosting's root (`web/` is only the source folder).
    final imageUrl = '/install-guide/android-$stepNum-$lang.webp';

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

/// Shows the 3-step iOS Add-to-Home-Screen instructions sheet.
///
/// NEVER touches Notification / PushManager APIs.
Future<void> showIosInstallSteps(BuildContext context) => _showInstallSteps(
      context,
      titleKey: 'iosInstallTitle',
      steps: const [
        (Icons.ios_share, 'iosInstallStep1'),
        (Icons.add_box_outlined, 'iosInstallStep2'),
        (Icons.add, 'iosInstallStep3'),
      ],
      noteKey: 'iosInstallSafariNote',
    );

/// Android without an APK link or a browser install prompt: install from the
/// browser menu (⋮ → «تثبيت التطبيق» / «إضافة إلى الشاشة الرئيسية»).
Future<void> showAndroidInstallSteps(BuildContext context) => _showInstallSteps(
      context,
      titleKey: 'androidInstallTitle',
      steps: const [
        (Icons.more_vert, 'androidInstallStep1'),
        (Icons.add_to_home_screen, 'androidInstallStep2'),
      ],
      noteKey: 'androidInstallNote',
    );

Future<void> _showInstallSteps(
  BuildContext context, {
  required String titleKey,
  required List<(IconData, String)> steps,
  required String noteKey,
}) {
  registerStrings(installGuideStrings);
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
                    ctx.tr(titleKey),
                    style: AppFonts.heading(size: 19, color: pal.primaryDeep),
                    textAlign: TextAlign.center,
                  ),
                  for (var i = 0; i < steps.length; i++) ...[
                    SizedBox(height: i == 0 ? 16 : 12),
                    _buildIosStep(
                      context: ctx,
                      pal: pal,
                      number: i + 1,
                      icon: steps[i].$1,
                      text: ctx.tr(steps[i].$2),
                    ),
                  ],
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
                    ctx.tr(noteKey),
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
