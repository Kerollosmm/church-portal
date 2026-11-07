// Review fixes for PR B (ADR-058): what the background worker reads back must match the foreground.

import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/state/notify_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planner snapshot keeps the admin push offer and day events (FeatureSettings.toMap omits them)', () {
    final features = FeatureSettings.fromMap({
      'push': true,
      'pushTypes': ['verse_daily', 'reminders'],
      'reminderLeads': [15, 60],
      'reminderDefaultLead': 15,
      'seasonVerses': ['fast\u001fطوبى للجياع\u001fمت ٥: ٦\u001fBlessed are the hungry\u001fMatt 5:6'],
      'dayEvents': [
        'not-a-valid-event', // index 0 is skipped: the next event keeps id e1
        ['2026-11-20', '', '18:00', '21:00', 'نهضة', 'Revival', '', '', '', '', '', '', ''].join(DayEvent.sep),
      ],
    });
    expect(features.dayEvents.single.id, 'e1');

    final back = FeatureSettings.fromMap(snapshotFeaturesMap(features));
    expect(back.pushSettings.enabled, isTrue);
    expect(back.pushSettings.offered, [NotifyType.verse_daily, NotifyType.reminders]);
    expect(back.pushSettings.reminderLeads, [15, 60]);
    expect(back.pushSettings.defaultLead, 15);
    final e = back.dayEvents.single;
    expect(e.id, 'e1', reason: 'day- reminder keys depend on the stored position');
    expect(e.start, '18:00');
    expect(e.titleAr, 'نهضة');
    expect(e.firstDay, features.dayEvents.single.firstDay);
    expect(back.seasonVerses.versesFor('fast').single.refEn, 'Matt 5:6');
  });

  test('Android install env keeps what it stores (no longer a no-op stub)', () {
    const env = PlatformInstallEnv();
    env.writeJson('church_portal_test_key', {'a': 1});
    expect(env.readJson('church_portal_test_key'), {'a': 1});
    env.remove('church_portal_test_key');
    expect(env.readJson('church_portal_test_key'), isNull);
  });
}
