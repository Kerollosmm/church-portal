import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/oem_guide.dart';
import '../../state/notify_providers.dart';

/// Screen for OEM battery saver guidance and notification diagnostics (`/notifications/battery`, ADR-058 / §3.6).
class NotificationHealthPage extends ConsumerStatefulWidget {
  const NotificationHealthPage({super.key});

  @override
  ConsumerState<NotificationHealthPage> createState() => _NotificationHealthPageState();
}

class _NotificationHealthPageState extends ConsumerState<NotificationHealthPage> {
  static const MethodChannel _deviceChannel = MethodChannel('church_portal/device');

  OemBrand _detectedBrand = OemBrand.other;
  bool _isLoading = true;
  bool _isBatteryOptimisationIgnored = false;
  bool _exactAlarmsAllowed = true;
  bool _notificationsAllowed = true;
  int _pendingCount = 0;
  String _manufacturer = '';
  String _brandName = '';

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    try {
      final res = await _deviceChannel.invokeMapMethod<String, dynamic>('getDiagnostics');
      if (res != null) {
        _manufacturer = res['manufacturer'] as String? ?? '';
        _brandName = res['brand'] as String? ?? '';
        _detectedBrand = detectOemBrand(_manufacturer, _brandName);
        _isBatteryOptimisationIgnored = res['isIgnoringBatteryOptimizations'] as bool? ?? false;
        _exactAlarmsAllowed = res['canScheduleExactAlarms'] as bool? ?? true;
        _notificationsAllowed = res['notificationsAllowed'] as bool? ?? true;
      }
    } catch (_) {
      // Platform channel not available (e.g. web/desktop/test)
      _detectedBrand = detectOemBrand('Android');
    }

    try {
      _pendingCount = await ref.read(localNotifierProvider).pendingCount();
    } catch (_) {
      _pendingCount = 0;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerOemAction(String actionKey) async {
    try {
      await _deviceChannel.invokeMethod('openOemSettings', {'actionKey': actionKey});
    } catch (_) {
      // Fallback: open standard application details settings
      try {
        await _deviceChannel.invokeMethod('openAppSettings');
      } catch (_) {}
    }
  }

  Future<void> _scheduleTwoMinTest() async {
    try {
      final mode = await _deviceChannel.invokeMethod<Object?>('scheduleTestAlarm', {'minutes': 2});
      if (!mounted) return;
      // 'inexact' = exact alarms are off for the app: the test (like reminders) may arrive a few
      // minutes late, which is itself useful diagnostic information.
      final inexact = mode == 'inexact';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inexact
                ? (context.isAr
                    ? 'تمت جدولة إشعار تجريبي بعد دقيقتين تقريبًا (المنبّهات الدقيقة غير مسموح بها، فقد يتأخر قليلًا). يمكنك إغلاق التطبيق الآن.'
                    : 'Test notification scheduled in about 2 minutes (exact alarms are off, so it may arrive a little late). You can close the app now.')
                : (context.isAr
                    ? 'تمت جدولة إشعار تجريبي بعد دقيقتين. يمكنك إغلاق التطبيق الآن.'
                    : 'Test notification scheduled in 2 minutes. You can close the app now.'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.isAr
                ? 'ميزة الاختبار متاحة عند تشغيل التطبيق على الهاتف'
                : 'Test feature is available when running on the phone app',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final isAr = context.isAr;

    return Scaffold(
      backgroundColor: pal.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: pal.surface,
                border: Border(bottom: BorderSide(color: pal.hairline)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: pal.primary),
                    tooltip: isAr ? 'الرجوع' : 'Back',
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/notifications');
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr ? 'إذا لم تصلك الإشعارات' : 'Notification Health & Battery',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: pal.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: pal.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Diagnostics Card («افحص الإشعارات»)
                          _buildDiagnosticsCard(pal, isAr),
                          const SizedBox(height: 20),

                          // Brand Guidance Section
                          _buildBrandGuidance(pal, isAr),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsCard(OccasionColors pal, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(color: pal.ornamentLine),
        boxShadow: pal.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: pal.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                isAr ? 'فحص حالة الإشعارات' : 'Notification Health Check',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pal.primary),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildDiagRow(
            title: isAr ? 'إذن الإشعارات' : 'Notification Permission',
            ok: _notificationsAllowed,
            detail: _notificationsAllowed
                ? (isAr ? 'مسموح به' : 'Granted')
                : (isAr ? 'محظور في إعدادات الهاتف' : 'Blocked in settings'),
            pal: pal,
            isAr: isAr,
            actionKey: 'open_app_settings',
          ),
          const Divider(height: 16),

          _buildDiagRow(
            title: isAr ? 'المنبّهات الدقيقة للتذكيرات' : 'Exact Alarms',
            ok: _exactAlarmsAllowed,
            detail: _exactAlarmsAllowed
                ? (isAr ? 'مسموح به (دقيق)' : 'Allowed (Exact)')
                : (isAr ? 'غير مسموح — يصل التذكير مبكرًا بضع دقائق' : 'Denied — arrives a few minutes early'),
            pal: pal,
            isAr: isAr,
          ),
          const Divider(height: 16),

          _buildDiagRow(
            title: isAr ? 'استثناء توفير البطارية' : 'Battery Optimisation',
            ok: _isBatteryOptimisationIgnored,
            detail: _isBatteryOptimisationIgnored
                ? (isAr ? 'بدون قيود' : 'Unrestricted')
                : (isAr ? 'قد يوقف الهاتف الإشعارات لتوفير الطاقة' : 'System may throttle alarms'),
            pal: pal,
            isAr: isAr,
            actionKey: 'battery_generic',
          ),
          const Divider(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAr ? 'الإشعارات المجدولة حاليًا' : 'Scheduled Alarms',
                style: TextStyle(fontSize: 13.5, color: pal.ink),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pal.hairline),
                ),
                child: Text(
                  '$_pendingCount',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: pal.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Two-minute test alarm button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('twoMinTestButton'),
              onPressed: _scheduleTwoMinTest,
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: Text(isAr ? 'اختبار بعد دقيقتين' : 'Test in 2 minutes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow({
    required String title,
    required bool ok,
    required String detail,
    required OccasionColors pal,
    required bool isAr,
    String? actionKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          color: ok ? pal.success : pal.alert, // palette roles (occasion themes incl. dark Holy Week)
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.ink)),
              const SizedBox(height: 2),
              Text(detail, style: TextStyle(fontSize: 12, color: pal.muted)),
            ],
          ),
        ),
        if (!ok && actionKey != null)
          TextButton(
            onPressed: () => _triggerOemAction(actionKey),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(isAr ? 'إصلاح' : 'Fix'),
          ),
      ],
    );
  }

  Widget _buildBrandGuidance(OccasionColors pal, bool isAr) {
    final detectedSteps = oemStepsForBrand(_detectedBrand);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isAr ? 'خطوات ضبط الهاتف حسب نوعه' : 'Brand-Specific Setup Instructions',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pal.primary),
        ),
        const SizedBox(height: 10),

        // Detected brand card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.panel,
            borderRadius: BorderRadius.circular(kPanelRadius),
            border: Border.all(color: pal.primary, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_android_rounded, color: pal.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${isAr ? "نوع هاتفك:" : "Detected device:"} ${_detectedBrand.displayName}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: pal.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < detectedSteps.length; i++) ...[
                _buildStepItem(i + 1, detectedSteps[i], pal, isAr),
                if (i < detectedSteps.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Other brands accordion
        Text(
          isAr ? 'أنواع هواتف أخرى' : 'Other Device Brands',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: pal.muted),
        ),
        const SizedBox(height: 8),

        for (final brand in OemBrand.values)
          if (brand != _detectedBrand && brand != OemBrand.other)
            ExpansionTile(
              title: Text(brand.displayName, style: TextStyle(fontSize: 13.5, color: pal.ink)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (int i = 0; i < oemStepsForBrand(brand).length; i++) ...[
                  _buildStepItem(i + 1, oemStepsForBrand(brand)[i], pal, isAr),
                  if (i < oemStepsForBrand(brand).length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
      ],
    );
  }

  Widget _buildStepItem(int stepNumber, OemStep step, OccasionColors pal, bool isAr) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: pal.primary,
          child: Text(
            '$stepNumber',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pal.onPrimary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title(isAr),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: pal.ink),
              ),
              const SizedBox(height: 2),
              Text(
                step.body(isAr),
                style: TextStyle(fontSize: 12.5, color: pal.muted, height: 1.4),
              ),
              if (step.actionKey != null) ...[
                const SizedBox(height: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () => _triggerOemAction(step.actionKey!),
                  child: Text(isAr ? 'افتح الإعدادات' : 'Open Settings', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
