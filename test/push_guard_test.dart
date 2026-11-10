import 'package:church_portal/data/push_messaging_io.dart';
import 'package:church_portal/domain/notify_plan.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockLocalNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  final List<({int id, String? title, String? body, String? payload})> shown = [];

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FCM Client Guard & Dedup (ADR-059 / PR C)', () {
    late MockLocalNotificationsPlugin mockPlugin;

    setUp(() {
      mockPlugin = MockLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({});
    });

    RemoteMessage createMessage({
      required String type,
      String? nid,
      String? eventKey,
      String title = 'تنبيه',
      String body = 'نص التنبيه',
      String link = '/about',
    }) {
      return RemoteMessage(
        messageId: nid ?? 'msg_1',
        data: {
          'type': type,
          'nid': ?nid,
          'eventKey': ?eventKey,
          'title': title,
          'body': body,
          'link': link,
        },
      );
    }

    test('Client guard drops local-owned and unknown types on Android', () async {
      final prefs = await SharedPreferences.getInstance();

      // Local-owned types must be dropped to prevent duplicate alerts
      for (final localType in ['verse_daily', 'katameros_daily', 'feasts', 'reminders']) {
        final msg = createMessage(type: localType, nid: 'n_$localType');
        final accepted = await PushMessaging.handleIncomingMessage(
          msg,
          plugin: mockPlugin,
          prefs: prefs,
        );
        expect(accepted, isFalse, reason: '$localType must be dropped by client guard');
        expect(mockPlugin.shown, isEmpty);
      }

      // Unknown types must also be dropped
      final badMsg = createMessage(type: 'urgent_broadcast', nid: 'n_urgent');
      final acceptedBad = await PushMessaging.handleIncomingMessage(
        badMsg,
        plugin: mockPlugin,
        prefs: prefs,
      );
      expect(acceptedBad, isFalse);
      expect(mockPlugin.shown, isEmpty);
    });

    test('Client guard accepts remote types (announcements & seasons)', () async {
      final prefs = await SharedPreferences.getInstance();

      final annMsg = createMessage(
        type: 'announcements',
        nid: 'nid_ann_1',
        title: 'تنويه هام',
        body: 'اجتماع عام',
        link: '/announcements',
      );
      final acceptedAnn = await PushMessaging.handleIncomingMessage(
        annMsg,
        plugin: mockPlugin,
        prefs: prefs,
      );
      expect(acceptedAnn, isTrue);
      expect(mockPlugin.shown.length, 1);
      expect(mockPlugin.shown.first.title, 'تنويه هام');
      expect(mockPlugin.shown.first.payload, '/announcements');

      final seasonMsg = createMessage(
        type: 'seasons',
        nid: 'nid_season_1',
        title: 'صوم الرسل',
        body: 'كل عام وأنتم بخير',
        link: '/seasons',
      );
      final acceptedSeason = await PushMessaging.handleIncomingMessage(
        seasonMsg,
        plugin: mockPlugin,
        prefs: prefs,
      );
      expect(acceptedSeason, isTrue);
      expect(mockPlugin.shown.length, 2);
      expect(mockPlugin.shown.last.title, 'صوم الرسل');
    });

    test('Seen NID deduplication drops repeated notifications within 100-item ring buffer', () async {
      final prefs = await SharedPreferences.getInstance();

      final msg1 = createMessage(type: 'announcements', nid: 'nid_repeat_42');
      final firstAttempt = await PushMessaging.handleIncomingMessage(
        msg1,
        plugin: mockPlugin,
        prefs: prefs,
      );
      expect(firstAttempt, isTrue);
      expect(mockPlugin.shown.length, 1);

      // Repeat of same nid must be dropped
      final secondAttempt = await PushMessaging.handleIncomingMessage(
        msg1,
        plugin: mockPlugin,
        prefs: prefs,
      );
      expect(secondAttempt, isFalse);
      expect(mockPlugin.shown.length, 1); // Not shown again
    });

    test('Seen NID ring buffer caps at 100 items and preserves most recent', () async {
      final prefs = await SharedPreferences.getInstance();

      // Populate 105 NIDs
      for (int i = 1; i <= 105; i++) {
        final msg = createMessage(type: 'announcements', nid: 'nid_$i');
        await PushMessaging.handleIncomingMessage(
          msg,
          plugin: mockPlugin,
          prefs: prefs,
        );
      }

      final stored = prefs.getStringList(seenNidsKey);
      expect(stored, isNotNull);
      expect(stored!.length, 100);

      // Oldest (nid_1 .. nid_5) should have been pruned out
      expect(stored.contains('nid_1'), isFalse);
      expect(stored.contains('nid_5'), isFalse);
      // Newest should be preserved
      expect(stored.contains('nid_6'), isTrue);
      expect(stored.contains('nid_105'), isTrue);
    });

    test('Slot sharing shares event:X slot so admin push and reminder replace instead of stack', () async {
      final prefs = await SharedPreferences.getInstance();

      const eventKey = 'lit-holy-mass-fri';
      final expectedSlotId = notificationIdFor('event:$eventKey');

      final msgWithEvent = createMessage(
        type: 'announcements',
        nid: 'nid_evt_1',
        eventKey: eventKey,
        title: 'تعديل موعد القداس',
        body: 'يبدأ الساعة ٧ ص',
      );

      final accepted = await PushMessaging.handleIncomingMessage(
        msgWithEvent,
        plugin: mockPlugin,
        prefs: prefs,
      );

      expect(accepted, isTrue);
      expect(mockPlugin.shown.length, 1);
      expect(mockPlugin.shown.first.id, equals(expectedSlotId));
    });
  });
}
