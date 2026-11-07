import 'package:church_portal/domain/push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('channelOf and isLocalOwned', () {
    test('APK (app) channel ownership', () {
      expect(channelOf(NotifyType.verse_daily, 'app'), PlatformOwnerChannel.local);
      expect(channelOf(NotifyType.katameros_daily, 'app'), PlatformOwnerChannel.local);
      expect(channelOf(NotifyType.feasts, 'app'), PlatformOwnerChannel.local);
      expect(channelOf(NotifyType.reminders, 'app'), PlatformOwnerChannel.local);

      expect(channelOf(NotifyType.announcements, 'app'), PlatformOwnerChannel.remote);
      expect(channelOf(NotifyType.seasons, 'app'), PlatformOwnerChannel.remote);

      expect(isLocalOwned(NotifyType.verse_daily, 'app'), isTrue);
      expect(isLocalOwned(NotifyType.katameros_daily, 'app'), isTrue);
      expect(isLocalOwned(NotifyType.feasts, 'app'), isTrue);
      expect(isLocalOwned(NotifyType.reminders, 'app'), isTrue);
      expect(isLocalOwned(NotifyType.announcements, 'app'), isFalse);
      expect(isLocalOwned(NotifyType.seasons, 'app'), isFalse);
    });

    test('Web / iPhone PWA channel ownership', () {
      expect(channelOf(NotifyType.verse_daily, 'web'), PlatformOwnerChannel.none);
      expect(channelOf(NotifyType.katameros_daily, 'web'), PlatformOwnerChannel.none);
      expect(channelOf(NotifyType.feasts, 'web'), PlatformOwnerChannel.none);

      expect(channelOf(NotifyType.announcements, 'web'), PlatformOwnerChannel.remote);
      expect(channelOf(NotifyType.seasons, 'web'), PlatformOwnerChannel.remote);
      expect(channelOf(NotifyType.reminders, 'web'), PlatformOwnerChannel.remote);

      expect(isLocalOwned(NotifyType.verse_daily, 'web'), isFalse);
      expect(isLocalOwned(NotifyType.katameros_daily, 'web'), isFalse);
      expect(isLocalOwned(NotifyType.feasts, 'web'), isFalse);
      expect(isLocalOwned(NotifyType.reminders, 'web'), isFalse);
    });
  });

  group('topicFor', () {
    test('computes remote fixed topics for app and web', () {
      expect(topicFor(NotifyType.announcements, 'ar', 'web'), 'web_announcements_ar');
      expect(topicFor(NotifyType.announcements, 'en', 'web'), 'web_announcements_en');
      expect(topicFor(NotifyType.seasons, 'ar', 'web'), 'web_seasons_ar');
      expect(topicFor(NotifyType.seasons, 'en', 'web'), 'web_seasons_en');

      expect(topicFor(NotifyType.announcements, 'ar', 'app'), 'app_announcements_ar');
      expect(topicFor(NotifyType.seasons, 'ar', 'app'), 'app_seasons_ar');
    });

    test('refuses local-owned or unowned types on both platforms', () {
      for (final type in [NotifyType.verse_daily, NotifyType.katameros_daily, NotifyType.feasts]) {
        expect(() => topicFor(type, 'ar', 'app'), throwsArgumentError);
        expect(() => topicFor(type, 'ar', 'web'), throwsArgumentError);
      }
    });

    test('refuses reminders on APK and redirects to reminderTopic on web', () {
      expect(() => topicFor(NotifyType.reminders, 'ar', 'app'), throwsArgumentError);
      expect(() => topicFor(NotifyType.reminders, 'ar', 'web'), throwsArgumentError);
    });

    test('computed topic strings match FCM constraints', () {
      final fcmPattern = RegExp(r'^[a-zA-Z0-9-_.~%]+$');
      final topics = [
        topicFor(NotifyType.announcements, 'ar', 'web'),
        topicFor(NotifyType.announcements, 'en', 'web'),
        topicFor(NotifyType.seasons, 'ar', 'web'),
        topicFor(NotifyType.announcements, 'ar', 'app'),
        topicFor(NotifyType.seasons, 'ar', 'app'),
      ];
      for (final t in topics) {
        expect(fcmPattern.hasMatch(t), isTrue, reason: '$t must be a valid FCM topic');
      }
    });
  });

  group('reminderTopic', () {
    test('formats single occurrence reminder topic', () {
      final topic = reminderTopic(
        eventKey: 'lit-123',
        occurrence: '2027-04-30',
        lead: 60,
        lang: 'ar',
      );
      expect(topic, 'web_rem_lit-123_20270430_60_ar');
      expect(RegExp(r'^[a-zA-Z0-9-_.~%]+$').hasMatch(topic), isTrue);
    });

    test('formats recurring every-time reminder topic', () {
      final topic = reminderTopic(
        eventKey: 'lit-sunday-morning',
        occurrence: '2027-04-30',
        lead: 15,
        lang: 'en',
        every: true,
      );
      expect(topic, 'web_rem_lit-sunday-morning_15_en');
      expect(RegExp(r'^[a-zA-Z0-9-_.~%]+$').hasMatch(topic), isTrue);
    });
  });

  group('PushPrefs', () {
    test('JSON roundtrip serialization', () {
      final original = PushPrefs(
        types: {NotifyType.announcements, NotifyType.seasons},
        lang: 'en',
        quiet: const QuietHours(from: '23:00', to: '06:30'),
        updatedAt: DateTime.utc(2026, 11, 7, 10, 30),
      );

      final json = original.toJson();
      final decoded = PushPrefs.fromJson(json);

      expect(decoded, equals(original));
      expect(decoded.types, {NotifyType.announcements, NotifyType.seasons});
      expect(decoded.lang, 'en');
      expect(decoded.quiet.from, '23:00');
      expect(decoded.quiet.to, '06:30');
      expect(decoded.updatedAt, original.updatedAt);
    });

    test('handles null, empty, or corrupt JSON gracefully', () {
      final fromNull = PushPrefs.fromJson(null);
      expect(fromNull.types, isEmpty);
      expect(fromNull.lang, 'ar');
      expect(fromNull.quiet.from, '22:00');

      final fromCorrupt = PushPrefs.fromJson({
        'types': 'not a list',
        'lang': 1234,
        'quiet': 'not a map',
        'updatedAt': 'not a date',
      });
      expect(fromCorrupt.types, isEmpty);
      expect(fromCorrupt.lang, 'ar');
      expect(fromCorrupt.quiet.from, '22:00');
    });

    test('drops unknown types and filters by offered types', () {
      final parsed = PushPrefs.fromJson(
        {
          'types': ['announcements', 'occasions', 'unknown_type', 'seasons', 'feasts'],
        },
        offered: [NotifyType.announcements, NotifyType.seasons],
      );

      expect(parsed.types, {NotifyType.announcements, NotifyType.seasons});
    });
  });

  group('safeNotificationLink', () {
    test('allows relative in-app paths', () {
      expect(safeNotificationLink('/mass-schedule'), '/mass-schedule');
      expect(safeNotificationLink('/page/liturgies?view=list#today'), '/page/liturgies?view=list#today');
      expect(safeNotificationLink('/'), '/');
    });

    test('rejects external URLs, protocol links, and scheme-relative URLs', () {
      expect(safeNotificationLink('https://evil.com'), '/');
      expect(safeNotificationLink('http://example.com/mass-schedule'), '/');
      expect(safeNotificationLink('javascript:alert(1)'), '/');
      expect(safeNotificationLink('data:text/html,evil'), '/');
      expect(safeNotificationLink('//evil.com/phish'), '/');
      expect(safeNotificationLink(''), '/');
      expect(safeNotificationLink(null), '/');
    });
  });

  group('PushSettings fromMap', () {
    test('handles null and empty map with default values', () {
      expect(PushSettings.fromMap(null), PushSettings.defaults);
      expect(PushSettings.fromMap({}), PushSettings.defaults);
    });

    test('parses custom valid fields', () {
      final s = PushSettings.fromMap({
        'push': true,
        'pushVapidKey': 'BKAGkFj27-exampleVapidKey890123456789012345678901234567890123456789012345678901234567890',
        'pushTypes': ['announcements', 'seasons', 'reminders'],
        'reminderLeads': [0, 15, 60],
        'reminderDefaultLead': 15,
      });

      expect(s.enabled, isTrue);
      expect(s.webReady, isTrue);
      expect(s.offered, [NotifyType.announcements, NotifyType.seasons, NotifyType.reminders]);
      expect(s.reminderLeads, [0, 15, 60]);
      expect(s.defaultLead, 15);
    });

    test('sanitizes unsupported leads and out-of-bounds defaultLead', () {
      final s = PushSettings.fromMap({
        'reminderLeads': [7, 45, 999], // None in allowed ReminderLeads
        'reminderDefaultLead': 99,
      });

      expect(s.reminderLeads, [0, 15, 60, 1440]);
      expect(s.defaultLead, 60);
    });
  });
}
