// Pure domain logic for OEM battery saver guidance and diagnostic checks (ADR-058 / PR B §3.6).
//
// Many Android OEMs (Xiaomi, Oppo, Realme, Vivo, Huawei, Samsung) aggressively
// kill background tasks and delay alarms. This module maps device manufacturer
// and brand to targeted step-by-step instructions and platform intent actions.

enum OemBrand {
  xiaomi,
  oppo,
  vivo,
  huawei,
  samsung,
  other;

  String get displayName => switch (this) {
        OemBrand.xiaomi => 'Xiaomi / Redmi / POCO',
        OemBrand.oppo => 'Oppo / Realme / OnePlus',
        OemBrand.vivo => 'Vivo / iQOO',
        OemBrand.huawei => 'Huawei / Honor',
        OemBrand.samsung => 'Samsung',
        OemBrand.other => 'Android',
      };
}

/// Identifies the OEM brand from Android's `Build.MANUFACTURER` and `Build.BRAND`.
OemBrand detectOemBrand(String manufacturer, [String? brand]) {
  final m = manufacturer.trim().toLowerCase();
  final b = (brand ?? '').trim().toLowerCase();
  final combined = '$m $b';

  if (combined.contains('xiaomi') ||
      combined.contains('redmi') ||
      combined.contains('poco') ||
      combined.contains('blackshark')) {
    return OemBrand.xiaomi;
  }
  if (combined.contains('oppo') ||
      combined.contains('realme') ||
      combined.contains('oneplus') ||
      combined.contains('oplus')) {
    return OemBrand.oppo;
  }
  if (combined.contains('vivo') || combined.contains('iqoo')) {
    return OemBrand.vivo;
  }
  if (combined.contains('huawei') || combined.contains('honor')) {
    return OemBrand.huawei;
  }
  if (combined.contains('samsung')) {
    return OemBrand.samsung;
  }
  return OemBrand.other;
}

class OemStep {
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String? actionKey;

  const OemStep({
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    this.actionKey,
  });

  String title(bool isAr) => isAr ? titleAr : titleEn;
  String body(bool isAr) => isAr ? bodyAr : bodyEn;
}

/// Known intent try-lists per action key for the Kotlin platform channel.
const Map<String, List<String>> oemIntentTryLists = {
  'autostart_xiaomi': [
    'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
    'com.miui.securitycenter/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
  ],
  'battery_xiaomi': [
    'com.miui.powerkeeper/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
    'com.miui.securitycenter/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
  ],
  'autostart_oppo': [
    'com.coloros.safecenter/.permission.startup.StartupAppListActivity',
    'com.coloros.safecenter/com.coloros.safecenter.permission.startup.FakeActivity',
    'com.coloros.safecenter/com.coloros.safecenter.permission.startupapp.StartupAppListActivity',
    'com.oplus.battery/.OplusBatteryMainActivity',
  ],
  'battery_oppo': [
    'com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity',
    'com.oplus.battery/.OplusBatteryMainActivity',
  ],
  'autostart_vivo': [
    'com.vivo.permissionmanager/.activity.BgStartUpManagerActivity',
    'com.iqoo.secure/.ui.phoneoptimize.AddWhiteListActivity',
    'com.iqoo.secure/.safeguard.PurviewTabActivity',
  ],
  'autostart_huawei': [
    'com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity',
    'com.huawei.systemmanager/com.huawei.systemmanager.optimize.process.ProtectActivity',
  ],
  'battery_samsung': [
    'com.samsung.android.lool/com.samsung.android.sm.ui.battery.BatteryActivity',
    'com.samsung.android.sm/com.samsung.android.sm.ui.battery.BatteryActivity',
  ],
};

/// Step-by-step guidance content per brand.
List<OemStep> oemStepsForBrand(OemBrand brand) => switch (brand) {
      OemBrand.xiaomi => const [
          OemStep(
            titleAr: 'التشغيل التلقائي (Autostart)',
            titleEn: 'Enable Autostart',
            bodyAr: 'افتح إعدادات الأذونات وفعل «التشغيل التلقائي» لتطبيق الكنيسة لضمان وصول الإشعارات في موعدها.',
            bodyEn: 'Open permissions and enable "Autostart" for the church app to ensure notifications fire on time.',
            actionKey: 'autostart_xiaomi',
          ),
          OemStep(
            titleAr: 'توفير البطارية: بدون قيود',
            titleEn: 'Battery saver: No restrictions',
            bodyAr: 'اختر «توفير البطارية» واضبطه على «لا توجد قيود» حتى لا يوقف النظام المنبهات عند انخفاض الطاقة.',
            bodyEn: 'Set battery saver to "No restrictions" so the system does not kill alarms when conserving battery.',
            actionKey: 'battery_xiaomi',
          ),
          OemStep(
            titleAr: 'قفل التطبيق في قائمة التطبيقات الحديثة',
            titleEn: 'Lock app in Recents',
            bodyAr: 'افتح شاشة التطبيقات الحديثة، اضغط مطولاً على تطبيق الكنيسة واختر أيقونة القفل.',
            bodyEn: 'Open Recents screen, long-press the church app card, and tap the lock icon.',
          ),
        ],
      OemBrand.oppo => const [
          OemStep(
            titleAr: 'السماح بالتشغيل التلقائي',
            titleEn: 'Allow Autostart',
            bodyAr: 'فعل «السماح بالتشغيل التلقائي» و«السماح بنشاط الخلفية» لتطبيق الكنيسة.',
            bodyEn: 'Enable "Allow Autostart" and "Allow background activity" for the church app.',
            actionKey: 'autostart_oppo',
          ),
          OemStep(
            titleAr: 'استهلاك البطارية في الخلفية',
            titleEn: 'Background battery usage',
            bodyAr: 'في إعدادات البطارية، اضبط استخدام الخلفية على «بدون قيود».',
            bodyEn: 'In battery settings, allow unrestricted background usage.',
            actionKey: 'battery_oppo',
          ),
        ],
      OemBrand.vivo => const [
          OemStep(
            titleAr: 'التشغيل التلقائي والنشاط في الخلفية',
            titleEn: 'Autostart & Background activity',
            bodyAr: 'فعل «التشغيل التلقائي» و«استهلاك طاقة مرتفع في الخلفية» لتطبيق الكنيسة.',
            bodyEn: 'Enable "Autostart" and "High background power consumption" for the church app.',
            actionKey: 'autostart_vivo',
          ),
        ],
      OemBrand.huawei => const [
          OemStep(
            titleAr: 'إدارة بدء التشغيل يدوياً',
            titleEn: 'Manual Launch management',
            bodyAr: 'في «إدارة التشغيل»، عطل الإدارة التلقائية واختر «إدارة يدوية»: تشغيل تلقائي، تشغيل ثانوي، تشغيل في الخلفية.',
            bodyEn: 'In "App Launch", turn off automatic and enable all 3 manual switches: auto-launch, secondary launch, run in background.',
            actionKey: 'autostart_huawei',
          ),
        ],
      OemBrand.samsung => const [
          OemStep(
            titleAr: 'البطارية: بدون قيود',
            titleEn: 'Battery: Unrestricted',
            bodyAr: 'في إعدادات التطبيق ← البطارية ← اختر «غير مقيد» (Unrestricted).',
            bodyEn: 'In App info → Battery → select "Unrestricted".',
            actionKey: 'battery_samsung',
          ),
          OemStep(
            titleAr: 'استبعاد من وضع السكون',
            titleEn: 'Remove from Sleeping apps',
            bodyAr: 'تأكد من عدم وجود التطبيق في قائمة «التطبيقات في وضع السكون» أو «السكون العميق».',
            bodyEn: 'Ensure the church app is not in "Sleeping apps" or "Deep sleeping apps".',
          ),
        ],
      OemBrand.other => const [
          OemStep(
            titleAr: 'تحسين البطارية (Battery Optimisation)',
            titleEn: 'Battery Optimisation',
            bodyAr: 'اختر «غير مقيد» (Unrestricted) أو استبعد التطبيق من تحسين البطارية ليصلك التنبيه بدقة.',
            bodyEn: 'Choose "Unrestricted" or ignore battery optimisation so notifications arrive promptly.',
            actionKey: 'battery_generic',
          ),
        ],
    };

/// Diagnostic check item representing one row on the health screen.
class DiagnosticCheckResult {
  final String key;
  final String titleAr;
  final String titleEn;
  final String detailAr;
  final String detailEn;
  final bool isOk;
  final bool isWarning;
  final String? fixActionKey;

  const DiagnosticCheckResult({
    required this.key,
    required this.titleAr,
    required this.titleEn,
    required this.detailAr,
    required this.detailEn,
    required this.isOk,
    this.isWarning = false,
    this.fixActionKey,
  });

  String title(bool isAr) => isAr ? titleAr : titleEn;
  String detail(bool isAr) => isAr ? detailAr : detailEn;
}
