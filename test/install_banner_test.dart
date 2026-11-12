import 'package:church_portal/domain/app_install.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectInstallOs UA Matrix', () {
    test('Android Chrome mobile', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.64 Mobile Safari/537.36';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isFalse);
    });

    test('Samsung Internet on Android', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 13; SAMSUNG SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.5790.166 Mobile Safari/537.36';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isFalse);
    });

    test('Firefox on Android', () {
      const ua = 'Mozilla/5.0 (Android 14; Mobile; rv:123.0) Gecko/123.0 Firefox/123.0';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux aarch64');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isFalse);
    });

    test('iPhone Safari iOS 17', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isFalse);
    });

    test('iPhone Safari iOS 16', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isFalse);
    });

    test('iPhone Safari iOS 15', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.7 Mobile/15E148 Safari/604.1';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isFalse);
    });

    test('iPad Safari (classic mobile UA)', () {
      const ua =
          'Mozilla/5.0 (iPad; CPU OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1';
      final res = detectInstallOs(userAgent: ua, platform: 'iPad', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isFalse);
    });

    test('iPadOS desktop UA (reports MacIntel, maxTouchPoints > 1)', () {
      const ua =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';
      final res = detectInstallOs(userAgent: ua, platform: 'MacIntel', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isFalse);
    });

    test('macOS desktop Safari (reports MacIntel, maxTouchPoints == 0)', () {
      const ua =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';
      final res = detectInstallOs(userAgent: ua, platform: 'MacIntel', maxTouchPoints: 0);
      expect(res.os, InstallOs.desktop);
      expect(res.inAppBrowser, isFalse);
    });

    test('Windows 11 Chrome', () {
      const ua =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
      final res = detectInstallOs(userAgent: ua, platform: 'Win32');
      expect(res.os, InstallOs.desktop);
      expect(res.inAppBrowser, isFalse);
    });

    test('Windows Edge', () {
      const ua =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.2365.66';
      final res = detectInstallOs(userAgent: ua, platform: 'Win32');
      expect(res.os, InstallOs.desktop);
      expect(res.inAppBrowser, isFalse);
    });

    test('Linux Desktop Firefox', () {
      const ua = 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux x86_64');
      expect(res.os, InstallOs.desktop);
      expect(res.inAppBrowser, isFalse);
    });

    test('ChromeOS (CrOS)', () {
      const ua =
          'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux x86_64');
      expect(res.os, InstallOs.desktop);
      expect(res.inAppBrowser, isFalse);
    });

    test('Facebook in-app browser on iPhone', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/21D50 [FBAN/FBIOS;FBAV/450.0.0.32.109;FBBV/568128212;]';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isTrue);
    });

    test('Instagram in-app browser on Android', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 14; SM-S918B; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/122.0.6261.64 Mobile Safari/537.36 Instagram 320.0.0.38.107 Android';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isTrue);
    });

    test('WhatsApp in-app browser on iPhone', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WhatsApp/24.4.79';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isTrue);
    });

    test('WeChat (MicroMessenger) in-app browser', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.5481.153 Mobile Safari/537.36 MicroMessenger/8.0.38';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isTrue);
    });

    test('Telegram in-app browser on Android', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.64 Mobile Safari/537.36 Telegram-Android/10.9.1';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isTrue);
    });

    test('Telegram in-app browser on iOS', () {
      const ua =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram/10.9.1';
      final res = detectInstallOs(userAgent: ua, platform: 'iPhone', maxTouchPoints: 5);
      expect(res.os, InstallOs.ios);
      expect(res.inAppBrowser, isTrue);
    });

    test('Generic Android WebView (; wv token)', () {
      const ua =
          'Mozilla/5.0 (Linux; U; Android 13; en-us; SM-A536B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/115.0.5790.166 Mobile Safari/537.36';
      final res = detectInstallOs(userAgent: ua, platform: 'Linux armv8l');
      expect(res.os, InstallOs.android);
      expect(res.inAppBrowser, isTrue);
    });

    test('Unknown or bot UA', () {
      const ua = 'curl/8.4.0';
      final res = detectInstallOs(userAgent: ua, platform: '');
      expect(res.os, InstallOs.other);
      expect(res.inAppBrowser, isFalse);
    });
  });

  group('resolveInstallAction', () {
    test('Android with APK URL returns apk', () {
      expect(
        resolveInstallAction(os: InstallOs.android, androidUrl: 'https://example.com/app.apk'),
        InstallAction.apk,
      );
    });

    test('Android without APK URL but with prompt returns pwaPrompt', () {
      expect(
        resolveInstallAction(os: InstallOs.android, androidUrl: '', hasPrompt: true),
        InstallAction.pwaPrompt,
      );
    });

    test('Android without APK URL and without prompt returns androidSteps', () {
      expect(
        resolveInstallAction(os: InstallOs.android, androidUrl: '', hasPrompt: false),
        InstallAction.androidSteps,
      );
    });

    test('iOS returns iosSteps regardless of URL or prompt', () {
      expect(
        resolveInstallAction(os: InstallOs.ios, androidUrl: 'https://example.com/app.apk', hasPrompt: true),
        InstallAction.iosSteps,
      );
    });

    test('Desktop and other return none', () {
      expect(resolveInstallAction(os: InstallOs.desktop), InstallAction.none);
      expect(resolveInstallAction(os: InstallOs.other), InstallAction.none);
    });
  });

  group('shouldShowInstallBanner', () {
    final now = DateTime(2026, 11, 7, 12, 0);
    const settings = InstallSettings();

    test('returns true on mobile web when not dismissed or installed', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isTrue,
      );

      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.ios,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/schedule',
          isWeb: true,
        ),
        isTrue,
      );
    });

    test('returns false when not web (APK build)', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('returns false when disabled in settings', () {
      expect(
        shouldShowInstallBanner(
          settings: const InstallSettings(enabled: false),
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('returns false when standalone or minimal-ui', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: true,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('returns false when appinstalled event received in this session', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: true,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('returns false on /admin route', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/admin',
          isWeb: true,
        ),
        isFalse,
      );

      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/admin/settings',
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('returns false on desktop and other OS', () {
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.desktop,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );

      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.other,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: null,
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('respects dismissedUntil cooldown', () {
      // Future date -> hidden
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: now.add(const Duration(days: 3)),
          now: now,
          path: '/',
          isWeb: true,
        ),
        isFalse,
      );

      // Past date -> shown again
      expect(
        shouldShowInstallBanner(
          settings: settings,
          os: InstallOs.android,
          isStandalone: false,
          installedEventReceived: false,
          dismissedUntil: now.subtract(const Duration(minutes: 1)),
          now: now,
          path: '/',
          isWeb: true,
        ),
        isTrue,
      );
    });
  });

  group('InstallSettings fromMap', () {
    test('handles null and empty map with default values', () {
      expect(InstallSettings.fromMap(null), InstallSettings.defaults);
      expect(InstallSettings.fromMap({}), InstallSettings.defaults);
    });

    test('parses custom valid fields', () {
      final s = InstallSettings.fromMap({
        'installPrompt': false,
        'installTitleAr': 'حمّل التطبيق',
        'installTitleEn': 'Download App',
        'installBodyAr': 'وصف تجريبي',
        'installBodyEn': 'Test description',
        'installAndroidUrl': 'https://example.com/church.apk',
        'installAndroidUrl32': 'https://example.com/church32.apk',
        'installApkVersion': '1.1.0',
        'installApkBuild': 42,
        'installApkSizeMb': 18.4,
        'installApkSize32Mb': 17.9,
        'installReshowDays': 14,
        'installRemindDays': 5,
      });

      expect(s.enabled, isFalse);
      expect(s.titleAr, 'حمّل التطبيق');
      expect(s.titleEn, 'Download App');
      expect(s.bodyAr, 'وصف تجريبي');
      expect(s.bodyEn, 'Test description');
      expect(s.androidUrl, 'https://example.com/church.apk');
      expect(s.androidUrl32, 'https://example.com/church32.apk');
      expect(s.apkVersion, '1.1.0');
      expect(s.apkBuild, 42);
      expect(s.apkSizeMb, 18.4);
      expect(s.apkSize32Mb, 17.9);
      expect(s.reshowDays, 14);
      expect(s.remindDays, 5);
    });

    test('clamps invalid values to fallback defaults', () {
      final s = InstallSettings.fromMap({
        'installApkBuild': -5,
        'installApkSizeMb': 500.0, // max 200
        'installReshowDays': 999, // max 365
        'installRemindDays': 0, // min 1
      });

      expect(s.apkBuild, 0);
      expect(s.apkSizeMb, 0.0);
      expect(s.reshowDays, 30);
      expect(s.remindDays, 3);
    });
  });
}
