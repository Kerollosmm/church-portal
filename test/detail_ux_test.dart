// PR #14: detail pages are on by default (opt-out), plus the pure helpers
// behind the richer detail page (add-to-calendar link, share URL, related items).

import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/item_detail.dart';
import 'package:church_portal/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('opt-out detail pages', () {
    test('a missing detailsEnabled means ON; only an explicit false turns it off', () {
      expect(ItemDetails.fromMap(const {}).detailsEnabled, isTrue);
      expect(const ItemDetails().detailsEnabled, isTrue);
      expect(ItemDetails.none.detailsEnabled, isTrue);
      expect(ItemDetails.fromMap(const {'detailsEnabled': false}).detailsEnabled, isFalse);
      expect(ItemDetails.fromMap(const {'detailsEnabled': true}).detailsEnabled, isTrue);
      // Untouched legacy items (no field at all) get a page.
      expect(const Meeting(id: 'x', stage: 'family', nameAr: 'ا', nameEn: '').details.detailsEnabled, isTrue);
    });

    test('detailStateFor: untouched items are available, explicit off is not', () {
      const f = FeatureSettings();
      expect(detailStateFor(ItemDetails.fromMap(const {}), features: f), DetailState.available);
      expect(detailStateFor(const ItemDetails(detailsEnabled: false), features: f), DetailState.unavailable);
    });
  });

  group('weeklyCalendarUrl (Google Calendar "add event" link)', () {
    // Monday 2 Nov 2026, 21:53 Cairo: Monday 19:00 has already passed.
    final now = CairoTime.at(2026, 11, 2, 21 * 60 + 53).toUtc();

    Map<String, String> q(String? url) => Uri.parse(url!).queryParameters;

    test('next occurrence in Cairo time, weekly recurrence, Cairo zone', () {
      final url = weeklyCalendarUrl(
          title: 'اجتماع الأسرة', weekdays: const [1], start: '19:00', end: '20:30', now: now,
          details: 'https://example.org/x', location: 'Church');
      final p = q(url);
      expect(Uri.parse(url!).host, 'calendar.google.com');
      expect(p['action'], 'TEMPLATE');
      expect(p['text'], 'اجتماع الأسرة');
      expect(p['dates'], '20261109T190000/20261109T203000'); // today's has passed -> next Monday
      expect(p['ctz'], 'Africa/Cairo');
      expect(p['recur'], 'RRULE:FREQ=WEEKLY;BYDAY=MO');
      expect(p['details'], 'https://example.org/x');
      expect(p['location'], 'Church');
    });

    test('later today counts; several days -> earliest, BYDAY sorted', () {
      final early = CairoTime.at(2026, 11, 2, 9 * 60).toUtc();
      expect(q(weeklyCalendarUrl(title: 't', weekdays: const [3, 1], start: '17:00', end: '20:00', now: early))['dates'],
          '20261102T170000/20261102T200000');
      final p = q(weeklyCalendarUrl(title: 't', weekdays: const [3, 1], start: '17:00', end: '20:00', now: now));
      expect(p['dates'], '20261104T170000/20261104T200000'); // Wednesday
      expect(p['recur'], 'RRULE:FREQ=WEEKLY;BYDAY=MO,WE');
    });

    test('no end -> one hour; overnight end rolls to the next day; Sunday = SU', () {
      expect(q(weeklyCalendarUrl(title: 't', weekdays: const [7], start: '08:00', now: now))['dates'],
          '20261108T080000/20261108T090000');
      expect(q(weeklyCalendarUrl(title: 't', weekdays: const [7], start: '23:00', end: '01:00', now: now))['dates'],
          '20261108T230000/20261109T010000');
      expect(q(weeklyCalendarUrl(title: 't', weekdays: const [7], start: '23:00', now: now))['recur'],
          'RRULE:FREQ=WEEKLY;BYDAY=SU');
    });

    test('no usable day or start time -> no link', () {
      expect(weeklyCalendarUrl(title: 't', weekdays: const [], start: '19:00', now: now), isNull);
      expect(weeklyCalendarUrl(title: 't', weekdays: const [1], start: '', now: now), isNull);
      expect(weeklyCalendarUrl(title: 't', weekdays: const [1], start: '7pm', now: now), isNull);
      expect(weeklyCalendarUrl(title: 't', weekdays: const [9], start: '19:00', now: now), isNull);
    });
  });

  test('absoluteDetailUrl: canonical origin, encoded id, ?lang=en for English', () {
    expect(absoluteDetailUrl('https://x.app', DetailKind.meeting, 'family'), 'https://x.app/church-education/family');
    expect(absoluteDetailUrl('https://x.app', DetailKind.priest, 'a b', english: true),
        'https://x.app/about/priests/a%20b?lang=en');
  });

  test('pickRelated: excludes the item, same group first, keeps order, max 3', () {
    final all = ['a1', 'b1', 'a2', 'b2', 'a3', 'a4'];
    expect(pickRelated(all, 'a1', sameGroup: (s) => s.startsWith('a')), ['a2', 'a3', 'a4']);
    expect(pickRelated(all, 'b1', sameGroup: (s) => s.startsWith('b')), ['b2', 'a1', 'a2']);
    expect(pickRelated(all, 'a1'), ['b1', 'a2', 'b2']);
    expect(pickRelated(['only'], 'only'), isEmpty);
    expect(pickRelated(all, 'a1', max: 1, sameGroup: (s) => s.startsWith('b')), ['b1']);
  });
}
