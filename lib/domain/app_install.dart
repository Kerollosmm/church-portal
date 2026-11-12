// Domain logic for app install detection and banner decisions (ADR-057).
// Pure Dart: no Flutter / web imports, so it is fully unit-tested.

/// Operating system category for app install offering.
enum InstallOs {
  android,
  ios,
  desktop,
  other,
}

/// OS detection result including in-app browser detection.
class InstallOsInfo {
  final InstallOs os;
  final bool inAppBrowser;

  const InstallOsInfo({
    required this.os,
    required this.inAppBrowser,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstallOsInfo && other.os == os && other.inAppBrowser == inAppBrowser;

  @override
  int get hashCode => Object.hash(os, inAppBrowser);

  @override
  String toString() => 'InstallOsInfo(os: $os, inAppBrowser: $inAppBrowser)';
}

/// An APK link as the browser should open it: a root-relative path set in the
/// admin (e.g. `/app/android/church.apk` on our Hosting) is resolved against
/// the portal origin [base]; absolute URLs are returned unchanged.
String resolveInstallUrl(String url, Uri base) {
  final t = url.trim();
  if (t.startsWith('/') && !t.startsWith('//')) return base.resolve(t).toString();
  return t;
}

/// iOS / iPadOS version from a Safari user agent as `major * 100 + minor`
/// (16.4 -> 1604), from `OS 16_4` (iPhone / iPad) or, for iPadOS desktop
/// mode, `Version/16.4`; `null` when the agent carries neither.
int? iosVersionFromUserAgent(String ua) {
  final m = RegExp(r'OS (\d+)_(\d+)').firstMatch(ua) ?? RegExp(r'Version/(\d+)\.(\d+)').firstMatch(ua);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 100 + int.parse(m.group(2)!);
}

/// Web push on iPhone / iPad needs iOS 16.4+ and the app on the Home Screen.
/// True only when the version is known and older (unknown is not "too old").
bool iosTooOldForPush(String ua) {
  final v = iosVersionFromUserAgent(ua);
  return v != null && v < 1604;
}

/// Detects the visitor's operating system and in-app browser status.
///
/// Handles iPadOS desktop UA where Safari reports "Macintosh" / "MacIntel"
/// but exposes [maxTouchPoints] > 1.
InstallOsInfo detectInstallOs({
  required String userAgent,
  String platform = '',
  int maxTouchPoints = 0,
}) {
  final ua = userAgent;
  final plat = platform;

  // In-app browsers: Facebook, Instagram, WhatsApp, Line, WeChat, Telegram, TikTok, WebViews.
  final isInApp = ua.contains('FBAN') ||
      ua.contains('FBAV') ||
      ua.contains('Instagram') ||
      ua.contains('WhatsApp') ||
      ua.contains('Line/') ||
      ua.contains('MicroMessenger') ||
      ua.contains('Telegram') ||
      ua.contains('; wv') ||
      ua.contains('ByteLocale');

  // Android
  if (ua.contains('Android')) {
    return InstallOsInfo(os: InstallOs.android, inAppBrowser: isInApp);
  }

  // iOS: iPhone, iPad, iPod
  if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) {
    return InstallOsInfo(os: InstallOs.ios, inAppBrowser: isInApp);
  }

  // iPadOS desktop-mode quirk: reports Macintosh / MacIntel, but maxTouchPoints > 1.
  final isMacPlatform = plat == 'MacIntel' || plat == 'Macintosh';
  final isMacUa = ua.contains('Macintosh') || ua.contains('Mac OS X');
  if ((isMacPlatform || isMacUa) && maxTouchPoints > 1) {
    return InstallOsInfo(os: InstallOs.ios, inAppBrowser: isInApp);
  }

  // Desktop platforms
  if (ua.contains('Windows') ||
      ua.contains('Macintosh') ||
      ua.contains('Mac OS X') ||
      ua.contains('Linux') ||
      ua.contains('CrOS') ||
      ua.contains('X11')) {
    return InstallOsInfo(os: InstallOs.desktop, inAppBrowser: isInApp);
  }

  return InstallOsInfo(os: InstallOs.other, inAppBrowser: isInApp);
}

/// The concrete install action to offer on the banner.
enum InstallAction {
  /// Open the direct APK download link.
  apk,

  /// Trigger the browser's native beforeinstallprompt prompt().
  pwaPrompt,

  /// Show Android step-by-step fallback (e.g. 3-dots menu).
  androidSteps,

  /// Show iOS 3-step bottom sheet (Share -> Add to Home Screen).
  iosSteps,

  /// No banner action.
  none,
}

/// Determines the primary action on the install banner.
InstallAction resolveInstallAction({
  required InstallOs os,
  String androidUrl = '',
  bool hasPrompt = false,
}) {
  if (os == InstallOs.android) {
    if (androidUrl.trim().isNotEmpty) {
      return InstallAction.apk;
    }
    if (hasPrompt) {
      return InstallAction.pwaPrompt;
    }
    return InstallAction.androidSteps;
  }
  if (os == InstallOs.ios) {
    return InstallAction.iosSteps;
  }
  return InstallAction.none;
}

/// Admin settings for the app install banner (settings/features).
class InstallSettings {
  final bool enabled;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String androidUrl;
  final String androidUrl32;
  final String apkVersion;
  final int apkBuild;
  final double apkSizeMb;
  final double apkSize32Mb;
  final int reshowDays;
  final int remindDays;

  const InstallSettings({
    this.enabled = true,
    this.titleAr = 'تطبيق الكنيسة على هاتفك',
    this.titleEn = 'Church app on your phone',
    this.bodyAr = 'تابع القداسات والصلوات والمواسم وتلقّ التنبيهات بسهولة من هاتفك.',
    this.bodyEn = 'Follow liturgies, prayers and seasons with easy updates on your phone.',
    this.androidUrl = '',
    this.androidUrl32 = '',
    this.apkVersion = '',
    this.apkBuild = 0,
    this.apkSizeMb = 0.0,
    this.apkSize32Mb = 0.0,
    this.reshowDays = 30,
    this.remindDays = 3,
  });

  static const defaults = InstallSettings();

  factory InstallSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;

    bool enabled = true;
    if (m.containsKey('installPrompt') && m['installPrompt'] is bool) {
      enabled = m['installPrompt'] as bool;
    }

    String strVal(String k, String fallback, int maxLen) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) {
        final t = v.trim();
        return t.length <= maxLen ? t : t.substring(0, maxLen);
      }
      return fallback;
    }

    String optStr(String k, int maxLen) {
      final v = m[k];
      if (v is String) {
        final t = v.trim();
        return t.length <= maxLen ? t : t.substring(0, maxLen);
      }
      return '';
    }

    int intVal(String k, int fallback, int min, int max) {
      final v = m[k];
      if (v is int && v >= min && v <= max) return v;
      if (v is num && v.toInt() >= min && v.toInt() <= max) return v.toInt();
      return fallback;
    }

    double doubleVal(String k, double fallback, double min, double max) {
      final v = m[k];
      if (v is num && v.toDouble() >= min && v.toDouble() <= max) {
        return v.toDouble();
      }
      return fallback;
    }

    return InstallSettings(
      enabled: enabled,
      titleAr: strVal('installTitleAr', defaults.titleAr, 120),
      titleEn: strVal('installTitleEn', defaults.titleEn, 120),
      bodyAr: strVal('installBodyAr', defaults.bodyAr, 300),
      bodyEn: strVal('installBodyEn', defaults.bodyEn, 300),
      androidUrl: optStr('installAndroidUrl', 500),
      androidUrl32: optStr('installAndroidUrl32', 500),
      apkVersion: optStr('installApkVersion', 20),
      apkBuild: intVal('installApkBuild', 0, 0, 999999),
      apkSizeMb: doubleVal('installApkSizeMb', 0.0, 0.0, 200.0),
      apkSize32Mb: doubleVal('installApkSize32Mb', 0.0, 0.0, 200.0),
      reshowDays: intVal('installReshowDays', 30, 0, 365),
      remindDays: intVal('installRemindDays', 3, 1, 60),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstallSettings &&
          other.enabled == enabled &&
          other.titleAr == titleAr &&
          other.titleEn == titleEn &&
          other.bodyAr == bodyAr &&
          other.bodyEn == bodyEn &&
          other.androidUrl == androidUrl &&
          other.androidUrl32 == androidUrl32 &&
          other.apkVersion == apkVersion &&
          other.apkBuild == apkBuild &&
          other.apkSizeMb == apkSizeMb &&
          other.apkSize32Mb == apkSize32Mb &&
          other.reshowDays == reshowDays &&
          other.remindDays == remindDays;

  @override
  int get hashCode => Object.hash(
        enabled,
        titleAr,
        titleEn,
        bodyAr,
        bodyEn,
        androidUrl,
        androidUrl32,
        apkVersion,
        apkBuild,
        apkSizeMb,
        apkSize32Mb,
        reshowDays,
        remindDays,
      );
}

/// Decides whether the install banner should be rendered.
///
/// Pure logic: checks platform, admin enable toggle, standalone display mode,
/// whether appinstalled event was already received, dismiss cooldown, and route.
bool shouldShowInstallBanner({
  required InstallSettings settings,
  required InstallOs os,
  required bool isStandalone,
  required bool installedEventReceived,
  required DateTime? dismissedUntil,
  required DateTime now,
  required String path,
  required bool isWeb,
}) {
  if (!isWeb) return false;
  if (!settings.enabled) return false;
  if (isStandalone) return false;
  if (installedEventReceived) return false;
  if (path.startsWith('/admin')) return false;
  if (os != InstallOs.android && os != InstallOs.ios) return false;
  if (dismissedUntil != null && now.isBefore(dismissedUntil)) return false;
  return true;
}
