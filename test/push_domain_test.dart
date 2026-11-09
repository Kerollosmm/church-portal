import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotifyConfig & Templates', () {
    test('NotifyConfig defaults for all 6 types', () {
      const features = FeatureSettings();
      final cfg = NotifyConfig.fromFeatures(features);

      expect(cfg.specs.length, 6);
      expect(cfg.specFor(NotifyType.verse_daily).time, '07:00');
      expect(cfg.specFor(NotifyType.katameros_daily).time, '06:30');
      expect(cfg.specFor(NotifyType.feasts).time, '07:30');
      expect(cfg.specFor(NotifyType.seasons).time, '09:00');
      expect(cfg.specFor(NotifyType.seasons).daysBefore, 3);

      // Built-in links
      expect(cfg.specFor(NotifyType.verse_daily).defaultLink, '/');
      expect(cfg.specFor(NotifyType.katameros_daily).defaultLink, '/today');
      expect(cfg.specFor(NotifyType.seasons).defaultLink, '/mass-schedule');
      expect(cfg.specFor(NotifyType.reminders).defaultLink, '/mass-schedule');
    });

    test('NotifyConfig parses custom notifyTypes rows', () {
      final features = const FeatureSettings().copyWith(
        notifyTypes: [
          'verse_daily\u001f08:15\u001f\u001fآية الصباح\u001fMorning Verse\u001f{verse}\u001f{verse}',
          'feasts\u001f09:00\u001f5\u001fعيد قادم\u001fUpcoming Feast\u001fبعد {days} أيام\u001fIn {days} days',
        ],
      );
      final cfg = NotifyConfig.fromFeatures(features);

      final verseSpec = cfg.specFor(NotifyType.verse_daily);
      expect(verseSpec.time, '08:15');
      expect(verseSpec.titleAr, 'آية الصباح');
      expect(verseSpec.titleEn, 'Morning Verse');
      expect(verseSpec.bodyAr, '{verse}');

      final feastSpec = cfg.specFor(NotifyType.feasts);
      expect(feastSpec.time, '09:00');
      expect(feastSpec.daysBefore, 5);
      expect(feastSpec.titleAr, 'عيد قادم');
      expect(feastSpec.bodyAr, 'بعد {days} أيام');
    });

    test('renderTemplate replaces placeholders correctly', () {
      const template = 'تذكير: {event} الساعة {time} في {place}';
      final vars = {
        'event': 'القداس الإلهي',
        'time': '٠٧:٠٠ ص',
        'place': 'المذبح الرئيسي',
      };
      final rendered = renderTemplate(template, vars);
      expect(rendered, 'تذكير: القداس الإلهي الساعة ٠٧:٠٠ ص في المذبح الرئيسي');
    });

    test('unknownPlaceholders identifies illegal placeholders for type', () {
      expect(unknownPlaceholders('verse_daily', 'آية {verse} من {ref}'), isEmpty);
      expect(unknownPlaceholders('verse_daily', 'حدث {event} في {place}'), containsAll(['{event}', '{place}']));
      expect(unknownPlaceholders('reminders', '{event} - {time} - {place} - {lead}'), isEmpty);
      expect(unknownPlaceholders('reminders', '{verse}'), contains('{verse}'));
    });

    test('isReminderSourceEnabled respects reminderSources string', () {
      final cfg1 = NotifyConfig.fromFeatures(const FeatureSettings(reminderSources: 'lit,mtg,day'));
      expect(cfg1.isReminderSourceEnabled('lit-st-mark'), isTrue);
      expect(cfg1.isReminderSourceEnabled('meeting-youth'), isTrue);
      expect(cfg1.isReminderSourceEnabled('mtg-scouts'), isTrue);
      expect(cfg1.isReminderSourceEnabled('day-5d16df6bbc'), isTrue);

      final cfg2 = NotifyConfig.fromFeatures(const FeatureSettings(reminderSources: 'lit'));
      expect(cfg2.isReminderSourceEnabled('lit-st-mark'), isTrue);
      expect(cfg2.isReminderSourceEnabled('meeting-youth'), isFalse);
      expect(cfg2.isReminderSourceEnabled('day-5d16df6bbc'), isFalse);

      final cfg3 = NotifyConfig.fromFeatures(const FeatureSettings(reminderSources: ''));
      expect(cfg3.isReminderSourceEnabled('lit-st-mark'), isFalse);
    });
  });

  group('ScheduledNotification & NotifySchedule', () {
    test('ScheduledNotification parses 9-field serialized format', () {
      const serialized =
          'row1\u001f2026-11-08T19:00:00Z\u001fall\u001fعنوان\u001fTitle\u001fنص\u001fBody\u001f/contact\u001flit-123';
      final row = ScheduledNotification.fromRow(serialized)!;

      expect(row.id, 'row1');
      expect(row.atUtc, DateTime.parse('2026-11-08T19:00:00Z'));
      expect(row.targets, 'all');
      expect(row.titleAr, 'عنوان');
      expect(row.titleEn, 'Title');
      expect(row.bodyAr, 'نص');
      expect(row.bodyEn, 'Body');
      expect(row.link, '/contact');
      expect(row.eventKey, 'lit-123');

      expect(row.toRow(), serialized);
    });

    test('ScheduledNotification handles safeNotificationLink fallback on external or malformed URL', () {
      const bad =
          'row1\u001f2026-11-08T19:00:00Z\u001fall\u001fعنوان\u001fTitle\u001fنص\u001fBody\u001fhttps://malicious.site/phish\u001f';
      final row = ScheduledNotification.fromRow(bad)!;
      expect(row.link, '/');
    });

    test('isExpiredAt returns true when past 24h from scheduled time and state != ok', () {
      final at = DateTime.utc(2026, 11, 8, 10, 0);
      final row = ScheduledNotification(
        id: 'r1',
        atUtc: at,
        targets: 'all',
        titleAr: 'ت',
        titleEn: 'T',
        bodyAr: 'ن',
        bodyEn: 'B',
        link: '/',
        eventKey: '',
      );

      final scheduleError = NotifySchedule(
        schedule: [row],
        status: {'r1': const RowSendStatus(state: 'error')},
      );
      final scheduleOk = NotifySchedule(
        schedule: [row],
        status: {'r1': const RowSendStatus(state: 'ok')},
      );

      final before24h = at.add(const Duration(hours: 23));
      final after24h = at.add(const Duration(hours: 25));

      expect(scheduleError.isExpiredAt('r1', before24h), isFalse);
      expect(scheduleError.isExpiredAt('r1', after24h), isTrue);
      // If already ok, never expired
      expect(scheduleOk.isExpiredAt('r1', after24h), isFalse);
    });

    test('dueNow returns rows due and not currently sending or ok', () {
      final now = DateTime.utc(2026, 11, 8, 12, 0);
      final dueRow = ScheduledNotification(
        id: 'due1',
        atUtc: now.subtract(const Duration(minutes: 5)),
        targets: 'all',
        titleAr: 'د',
        titleEn: 'D',
        bodyAr: 'ب',
        bodyEn: 'B',
        link: '/',
        eventKey: '',
      );
      final futureRow = ScheduledNotification(
        id: 'future1',
        atUtc: now.add(const Duration(hours: 1)),
        targets: 'all',
        titleAr: 'ف',
        titleEn: 'F',
        bodyAr: 'ب',
        bodyEn: 'B',
        link: '/',
        eventKey: '',
      );
      final doneRow = ScheduledNotification(
        id: 'done1',
        atUtc: now.subtract(const Duration(minutes: 10)),
        targets: 'all',
        titleAr: 'ت',
        titleEn: 'T',
        bodyAr: 'ب',
        bodyEn: 'B',
        link: '/',
        eventKey: '',
      );

      final schedule = NotifySchedule(
        schedule: [dueRow, futureRow, doneRow],
        status: {
          'done1': const RowSendStatus(state: 'ok'),
          'due1': const RowSendStatus(state: 'partial'),
        },
      );

      final dueList = schedule.dueNow(now);
      expect(dueList.map((r) => r.id), ['due1']);
    });

    test('canDeleteRow allows deletion for any non-sending row', () {
      final schedule = NotifySchedule(
        schedule: [],
        status: {
          'r_sending': const RowSendStatus(state: 'sending'),
          'r_ok': const RowSendStatus(state: 'ok'),
          'r_partial': const RowSendStatus(state: 'partial'),
          'r_error': const RowSendStatus(state: 'error'),
          'r_unconfirmed': const RowSendStatus(state: 'unconfirmed'),
        },
      );

      expect(schedule.canDeleteRow('r_sending'), isFalse);
      expect(schedule.canDeleteRow('r_ok'), isTrue);
      expect(schedule.canDeleteRow('r_partial'), isTrue);
      expect(schedule.canDeleteRow('r_error'), isTrue);
      expect(schedule.canDeleteRow('r_unconfirmed'), isTrue);
      expect(schedule.canDeleteRow('r_future'), isTrue);
    });

    test('cloneDraftForRetry narrows targets when one platform completely succeeded', () {
      final src = ScheduledNotification(
        id: 'src1',
        atUtc: DateTime.utc(2026, 11, 8, 10, 0),
        targets: 'all',
        titleAr: 'عنوان',
        titleEn: 'Title',
        bodyAr: 'نص',
        bodyEn: 'Body',
        link: '/about',
        eventKey: 'lit-456',
      );

      // Web completely succeeded, app failed
      final statusWebOk = const RowSendStatus(
        state: 'partial',
        web: TopicSendState(state: 'ok'),
        app: TopicSendState(state: 'error'),
      );

      final scheduleWebOk = NotifySchedule(schedule: [src], status: {'src1': statusWebOk});
      final clonedForApp = scheduleWebOk.cloneDraftForRetry(src, 'new_id_app', DateTime.utc(2026, 11, 8, 15, 0));
      expect(clonedForApp.id, 'new_id_app');
      expect(clonedForApp.targets, 'app');
      expect(clonedForApp.titleAr, 'عنوان');
      expect(clonedForApp.link, '/about');
      expect(clonedForApp.eventKey, 'lit-456');

      // App completely succeeded, web failed
      final statusAppOk = const RowSendStatus(
        state: 'partial',
        app: TopicSendState(state: 'ok'),
        web: TopicSendState(state: 'error'),
      );

      final scheduleAppOk = NotifySchedule(schedule: [src], status: {'src1': statusAppOk});
      final clonedForWeb = scheduleAppOk.cloneDraftForRetry(src, 'new_id_web', DateTime.utc(2026, 11, 8, 15, 0));
      expect(clonedForWeb.targets, 'web');
    });

    test('fromDoc parses both serialized string and map sentLog entries', () {
      final doc = {
        'sentLog': [
          'r1\u001f2026-11-08T12:00:00.000Z\u001fok\u001fعنوان عربي\u001fcron',
          {
            'id': 'r2',
            'sentAt': '2026-11-08T13:00:00.000Z',
            'titleAr': 'عنوان ثاني',
            'webState': 'partial',
            'appState': 'ok',
          },
        ],
      };
      final schedule = NotifySchedule.fromDoc(doc);
      expect(schedule.sentLog.length, 2);
      expect(schedule.sentLog[0].id, 'r1');
      expect(schedule.sentLog[0].titleAr, 'عنوان عربي');
      expect(schedule.sentLog[0].webState, 'ok');
      expect(schedule.sentLog[1].id, 'r2');
      expect(schedule.sentLog[1].titleAr, 'عنوان ثاني');
      expect(schedule.sentLog[1].webState, 'partial');
    });
  });

  group('safeNotificationLink Security', () {
    test('allows relative in-app paths starting with /', () {
      expect(safeNotificationLink('/'), '/');
      expect(safeNotificationLink('/about'), '/about');
      expect(safeNotificationLink('/mass-schedule?date=2026-11-08'), '/mass-schedule?date=2026-11-08');
      expect(safeNotificationLink('/about/priests/fr-maximos'), '/about/priests/fr-maximos');
    });

    test('rejects external URLs, protocol-relative, javascript:, and invalid schemes', () {
      expect(safeNotificationLink('https://evil.com'), '/');
      expect(safeNotificationLink('http://evil.com'), '/');
      expect(safeNotificationLink('//evil.com/phish'), '/');
      expect(safeNotificationLink('javascript:alert(1)'), '/');
      expect(safeNotificationLink('data:text/html,...'), '/');
      expect(safeNotificationLink('file:///etc/passwd'), '/');
      expect(safeNotificationLink('about:blank'), '/');
      expect(safeNotificationLink(null), '/');
      expect(safeNotificationLink(''), '/');
      expect(safeNotificationLink('   '), '/');
    });
  });

  group('ADR-060: Web Push Domain & Sync Logic', () {
    setUpAll(() {
      CairoTime.ensureInitialized();
    });

    test('kPushDeliveryShipped is true', () {
      expect(kPushDeliveryShipped, isTrue);
    });

    test('topicKey canonicalization and {1,40} length clamping', () {
      // Valid prefixes
      expect(topicKey('lit-sun1'), 'lit-sun1');
      expect(topicKey('LIT-Sun1'), 'lit-sun1');
      expect(topicKey('meeting-youth-123'), 'meeting-youth-123');
      expect(topicKey('day-5d16df6bbc'), 'day-5d16df6bbc');
      expect(topicKey('season-pascha'), 'season-pascha');

      // Replaces non [a-z0-9-] with -
      expect(topicKey('meeting-youth_group.sub%1'), 'meeting-youth-group-sub-1');

      // Clamps ID portion to 40 chars
      final longId = 'a' * 50;
      final keyed = topicKey('lit-$longId');
      expect(keyed, 'lit-${'a' * 40}');
      expect(keyed.length, 44); // 'lit-' (4) + 40 = 44

      // Invalid prefixes or empty id
      expect(topicKey('unknown-123'), '');
      expect(topicKey('app-lit-1'), '');
      expect(topicKey('lit-'), '');
      expect(topicKey(''), '');
    });

    test('isValidWebReminderTopic matches rule regex', () {
      // Valid recurring topics
      expect(isValidWebReminderTopic('web_rem_lit-sun1_60_ar'), isTrue);
      expect(isValidWebReminderTopic('web_rem_meeting-youth-1_15_en'), isTrue);
      expect(isValidWebReminderTopic('web_rem_season-pascha_1440_ar'), isTrue);
      expect(isValidWebReminderTopic('web_rem_day-5d16df6bbc_0_en'), isTrue);

      // Valid once-off topics with 8-digit date
      expect(isValidWebReminderTopic('web_rem_lit-sun1_20261115_60_ar'), isTrue);
      expect(isValidWebReminderTopic('web_rem_day-5d16df6bbc_20261115_15_en'), isTrue);

      // Invalid: uppercase characters
      expect(isValidWebReminderTopic('web_rem_lit-SUN1_60_ar'), isFalse);

      // Invalid: bad prefix
      expect(isValidWebReminderTopic('web_rem_other-123_60_ar'), isFalse);
      expect(isValidWebReminderTopic('app_rem_lit-1_60_ar'), isFalse);

      // Invalid: non-allowed lead
      expect(isValidWebReminderTopic('web_rem_lit-1_7_ar'), isFalse);
      expect(isValidWebReminderTopic('web_rem_lit-1_25_ar'), isFalse);

      // Invalid: bad date format (not 8 digits)
      expect(isValidWebReminderTopic('web_rem_lit-1_202611_60_ar'), isFalse);
      expect(isValidWebReminderTopic('web_rem_lit-1_2026-11-15_60_ar'), isFalse);

      // Invalid: suffix > 40 chars
      expect(isValidWebReminderTopic('web_rem_lit-${'a' * 41}_60_ar'), isFalse);
    });

    test('isWebLeadTooSoon clamps lead firing within 40 minutes', () {
      final now = DateTime.utc(2026, 11, 9, 10, 0); // 10:00

      // Starts at 10:30 (in 30 min): lead 0 fires at 10:30 (< 10:40 -> too soon)
      expect(isWebLeadTooSoon(startsAt: DateTime.utc(2026, 11, 9, 10, 30), lead: 0, now: now), isTrue);

      // Starts at 11:00 (in 60 min): lead 30 fires at 10:30 (< 10:40 -> too soon)
      expect(isWebLeadTooSoon(startsAt: DateTime.utc(2026, 11, 9, 11, 0), lead: 30, now: now), isTrue);

      // Starts at 11:00: lead 15 fires at 10:45 (>= 10:40 -> not too soon)
      expect(isWebLeadTooSoon(startsAt: DateTime.utc(2026, 11, 9, 11, 0), lead: 15, now: now), isFalse);

      // Starts at 12:00: lead 60 fires at 11:00 (>= 10:40 -> not too soon)
      expect(isWebLeadTooSoon(startsAt: DateTime.utc(2026, 11, 9, 12, 0), lead: 60, now: now), isFalse);
    });

    test('computeWebTopicSync computes want, rem, drop, prevToken and pre-filters invalid topics', () {
      final now = CairoTime.at(2026, 11, 9, 10 * 60);
      final prefs = PushPrefs(
        types: {NotifyType.announcements, NotifyType.reminders},
        lang: 'ar',
        updatedAt: now,
      );

      final r1 = Reminder(
        eventKey: 'lit-sun1',
        occurrence: null,
        lead: 60,
        every: true, // recurring
        title: const {'ar': 'قداس الأحد'},
        startsAt: CairoTime.at(2026, 11, 15, 8 * 60),
        createdAt: now,
      );

      final r2 = Reminder(
        eventKey: 'meeting-youth',
        occurrence: null,
        lead: 15,
        every: false, // weekly meeting call site passed occurrence: null with every: false
        title: const {'ar': 'اجتماع الشباب'},
        startsAt: CairoTime.at(2026, 11, 12, 19 * 60),
        createdAt: now,
      );

      final r3Invalid = Reminder(
        eventKey: 'custom-unsupported-event',
        occurrence: '2026-11-12',
        lead: 60,
        every: false,
        title: const {'ar': 'حدث خاص'},
        startsAt: CairoTime.at(2026, 11, 12, 18 * 60),
        createdAt: now,
      );

      final previousRemTopics = {
        'web_rem_lit-sun1_60_ar',
        'web_rem_day-old_20261101_15_ar',
        'web_invalid_topic_to_drop', // Should be filtered out by isValidWebReminderTopic
      };

      final plan = computeWebTopicSync(
        prefs: prefs,
        currentReminders: [r1, r2, r3Invalid],
        previousRemTopics: previousRemTopics,
        now: now,
        currentToken: 'new_token_123',
        previousSyncedToken: 'old_token_000',
      );

      // want has announcements in Arabic only
      expect(plan.want, ['web_announcements_ar']);

      // rem has r1 (recurring: web_rem_lit-sun1_60_ar) and r2 (effectiveOcc: web_rem_meeting-youth_20261112_15_ar)
      // r3Invalid is skipped because its topic fails isValidWebReminderTopic
      expect(plan.rem.contains('web_rem_lit-sun1_60_ar'), isTrue);
      expect(plan.rem.contains('web_rem_meeting-youth_20261112_15_ar'), isTrue);
      expect(plan.rem.contains('custom-unsupported'), isFalse);

      // drop has web_rem_day-old_20261101_15_ar (no longer wanted) and excludes web_invalid_topic_to_drop
      expect(plan.drop, 'web_rem_day-old_20261101_15_ar');

      // prevToken is passed because token changed
      expect(plan.prevToken, 'old_token_000');
    });

    test('WebInboxItem json roundtrip and link normalization', () {
      final item = WebInboxItem.fromJson({
        'nid': 'ann-1',
        'title': 'تنبيه جديد',
        'body': 'نص التنبيه',
        'link': 'https://malicious.com',
        'receivedAt': '2026-11-09T10:00:00.000Z',
      });

      expect(item.nid, 'ann-1');
      expect(item.title, 'تنبيه جديد');
      expect(item.body, 'نص التنبيه');
      expect(item.link, '/'); // normalized to safe root path
      expect(item.receivedAt, DateTime.utc(2026, 11, 9, 10, 0));

      final json = item.toJson();
      expect(json['nid'], 'ann-1');
      expect(json['link'], '/');
    });
  });
}
