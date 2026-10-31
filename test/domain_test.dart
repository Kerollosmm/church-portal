import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

Liturgy lit(String id, int? weekday, String start, String end,
        {String type = 'mass', String? season, DateTime? date}) =>
    Liturgy(
        id: id,
        type: type,
        nameAr: id,
        nameEn: id,
        weekday: weekday,
        date: date,
        start: start,
        end: end,
        seasonKey: season);

/// Cairo wall time -> UTC instant (via the tz database).
DateTime cairo(int y, int mo, int d, int h, [int mi = 0]) => CairoTime.at(y, mo, d, h * 60 + mi).toUtc();

void main() {
  setUpAll(CairoTime.ensureInitialized);

  final regular = [
    lit('fri1', 5, '06:30', '08:30'),
    lit('fri2', 5, '08:30', '10:30'),
    lit('friKids', 5, '10:30', '12:00'),
    lit('sat1', 6, '07:00', '09:00'),
    lit('satVespers', 6, '18:30', '19:30', type: 'vespers'),
    lit('sun1', 7, '06:00', '08:00'),
    lit('wed1', 3, '07:00', '09:00'),
    lit('thu1', 4, '07:00', '08:30'),
  ];
  final nativity = Season(
    id: 'nat',
    key: 'nativity',
    nameAr: 'الميلاد',
    nameEn: 'Nativity',
    startsAt: cairo(2027, 1, 6, 0),
    endsAt: cairo(2027, 1, 8, 23, 59),
  );
  final seasonal = [
    lit('natEve', null, '20:00', '00:30', season: 'nativity', date: DateTime(2027, 1, 6)),
    lit('natDay', null, '08:00', '10:00', season: 'nativity', date: DateTime(2027, 1, 7)),
  ];
  final all = [...regular, ...seasonal];

  group('Cairo time zone', () {
    test('winter is UTC+2 and summer (DST) is UTC+3', () {
      expect(CairoTime.at(2026, 11, 6, 6 * 60 + 30).timeZoneOffset, const Duration(hours: 2));
      expect(CairoTime.at(2026, 7, 3, 6 * 60 + 30).timeZoneOffset, const Duration(hours: 3));
    });
  });

  group('next mass', () {
    test('during the first Friday liturgy -> happening now + next is the second', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2026, 11, 6, 7, 0));
      expect(r.happeningNow?.liturgy.id, 'fri1');
      expect(r.next?.liturgy.id, 'fri2');
      expect(r.next?.dayOffset, 0);
    });

    test('after the last liturgy today -> tomorrow\'s first', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2026, 11, 6, 21, 0));
      expect(r.happeningNow, isNull);
      expect(r.next?.liturgy.id, 'sat1');
      expect(r.next?.dayOffset, 1);
    });

    test('vespers are ignored by default but included on request', () {
      final now = cairo(2026, 11, 7, 12, 0);
      expect(computeNextMass(liturgies: all, seasons: const [], now: now).next?.liturgy.id, 'sun1');
      expect(
          computeNextMass(liturgies: all, seasons: const [], now: now, types: {'mass', 'vespers'}).next?.liturgy.id,
          'satVespers');
    });

    test('DST: summer Friday 06:30 Cairo is 03:30 UTC', () {
      final r = computeNextMass(liturgies: all, seasons: const [], now: cairo(2026, 7, 3, 6, 0));
      expect(r.next?.liturgy.id, 'fri1');
      expect(r.next!.start.toUtc(), DateTime.utc(2026, 7, 3, 3, 30));
    });

    test('skips days without liturgies (Monday night -> Wednesday)', () {
      // Mon 9 Nov 2026 22:00; Tuesday has none, Wednesday has wed1.
      final r = computeNextMass(liturgies: regular, seasons: const [], now: cairo(2026, 11, 9, 22));
      expect(r.next?.liturgy.id, 'wed1');
      expect(r.next?.dayOffset, 2);
    });

    test('active season replaces the regular liturgies of that day', () {
      // Wed 6 Jan 2027 05:00: regular wed1 (07:00) is replaced by the eve liturgy.
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'natEve');
      expect(r.activeSeasons.map((s) => s.key), ['nativity']);
    });

    test('a liturgy crossing midnight is happening now on both sides of midnight', () {
      expect(computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 6, 23, 30)).happeningNow?.liturgy.id,
          'natEve');
      final after = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 7, 0, 15));
      expect(after.happeningNow?.liturgy.id, 'natEve');
      expect(after.next?.liturgy.id, 'natDay');
    });

    test('inactive season flag is ignored', () {
      final off = Season(
          id: 'nat', key: 'nativity', nameAr: '', nameEn: '', startsAt: nativity.startsAt, endsAt: nativity.endsAt, active: false);
      final r = computeNextMass(liturgies: all, seasons: [off], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'wed1');
      expect(r.activeSeasons, isEmpty);
    });

    test('a season starting mid-day keeps the regular services before it', () {
      // Wed 13 Jan 2027: season from 18:00, seasonal service 19:00.
      final evening = Season(
        id: 'rev',
        key: 'revival_maximus',
        nameAr: '',
        nameEn: '',
        startsAt: cairo(2027, 1, 13, 18),
        endsAt: cairo(2027, 1, 14, 23, 59),
      );
      final ls = [...regular, lit('revEve', 3, '19:00', '20:30', type: 'mass', season: 'revival_maximus')];
      final morning = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 13, 5));
      expect(morning.next?.liturgy.id, 'wed1'); // regular 07:00 is before the season starts
      final afternoon = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 13, 12));
      expect(afternoon.next?.liturgy.id, 'revEve');
      // Thursday is fully inside the season but has no seasonal service -> regular.
      final thu = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 14, 5));
      expect(thu.next?.liturgy.id, 'thu1');
    });

    test('a seasonal service before its season starts is not used', () {
      final late = Season(
        id: 'n2',
        key: 'nativity',
        nameAr: '',
        nameEn: '',
        startsAt: cairo(2027, 1, 6, 21),
        endsAt: cairo(2027, 1, 7, 23, 59),
      );
      // natEve (20:00) starts before the 21:00 season start -> regular wed1 stays.
      final r = computeNextMass(liturgies: all, seasons: [late], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'wed1');
    });

    test('regular days outside the season are unaffected', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 9, 5)); // Saturday
      expect(r.next?.liturgy.id, 'sat1');
    });

    test('schedule tabs group weekdays and exclude vespers', () {
      expect(regularLiturgiesForTab(all, ScheduleTab.friday).map((l) => l.id), ['fri1', 'fri2', 'friKids']);
      expect(regularLiturgiesForTab(all, ScheduleTab.other).map((l) => l.id), ['thu1']);
      expect(regularLiturgiesForTab(all, ScheduleTab.saturday).map((l) => l.id), ['sat1']);
      expect(vespersAndPraise(all).map((l) => l.id), ['satVespers']);
      expect(seasonalSchedule([nativity], all)[nativity]!.map((l) => l.id), ['natEve', 'natDay']);
    });
  });

  group('alerts', () {
    final now = cairo(2026, 11, 1, 12);
    final alerts = [
      Alert(id: 'low', titleAr: '', titleEn: '', active: true, priority: 1, startsAt: cairo(2026, 10, 1, 0), endsAt: cairo(2026, 12, 1, 0)),
      Alert(id: 'high', titleAr: '', titleEn: '', active: true, priority: 5, startsAt: cairo(2026, 10, 30, 0), endsAt: cairo(2026, 11, 3, 0)),
      Alert(id: 'inactive', titleAr: '', titleEn: '', active: false, priority: 9),
      Alert(id: 'future', titleAr: '', titleEn: '', active: true, priority: 9, startsAt: cairo(2026, 12, 1, 0)),
      Alert(id: 'expired', titleAr: '', titleEn: '', active: true, priority: 9, endsAt: cairo(2026, 10, 1, 0)),
      const Alert(id: 'open', titleAr: '', titleEn: '', active: true, priority: 1),
    ];
    test('only active & in-window alerts, highest priority first', () {
      expect(visibleAlerts(alerts, now).map((a) => a.id), ['high', 'low', 'open']);
    });
  });

  group('clinics', () {
    final clinics = [
      const Clinic(id: 'd1', specialty: 'dental', specialtyAr: 'أسنان', specialtyEn: 'Dental', doctorName: 'B', days: [7]),
      const Clinic(id: 'p1', specialty: 'pediatrics', specialtyAr: 'أطفال', specialtyEn: 'Pediatrics', doctorName: 'A', days: [5, 7]),
      const Clinic(id: 'p2', specialty: 'pediatrics', specialtyAr: 'أطفال', specialtyEn: 'Pediatrics', doctorName: 'C', days: [1]),
      const Clinic(id: 'x', specialty: 'dental', specialtyAr: 'أسنان', specialtyEn: 'Dental', doctorName: 'Z', days: [5], active: false),
    ];
    final friday = cairo(2026, 11, 6, 9);
    test('available today uses the Cairo weekday', () {
      expect(isClinicAvailableToday(clinics[1], friday), isTrue);
      expect(isClinicAvailableToday(clinics[0], friday), isFalse);
      // 23:30 UTC Thursday is already Friday 01:30 in Cairo.
      expect(cairoWeekday(DateTime.utc(2026, 11, 5, 23, 30)), 5);
    });
    test('filter by specialty, hide inactive, open-today first', () {
      expect(filterClinics(clinics, now: friday).map((c) => c.id), ['p1', 'd1', 'p2']);
      expect(filterClinics(clinics, specialty: 'pediatrics', now: friday).map((c) => c.id), ['p1', 'p2']);
      expect(filterClinics(clinics, specialty: 'dental', now: friday).map((c) => c.id), ['d1']);
      expect(clinicSpecialties(clinics).keys, ['dental', 'pediatrics']);
    });
    test('links', () {
      expect(whatsappLink('0101 234 5678'), 'https://wa.me/201012345678');
      expect(whatsappLink('+20 101 234 5678'), 'https://wa.me/201012345678');
      expect(whatsappLink('٠١٠١٢٣٤٥٦٧٨'), 'https://wa.me/201012345678');
      expect(telLink('03 555 1234'), 'tel:035551234');
    });
  });

  group('contact form', () {
    test('valid with Arabic-digit mobile', () {
      final v = validateContactForm(const ContactFormInput(name: '  مينا  عادل ', phone: '٠١٢٢٣٤٥٦٧٨٩', message: 'أريد موعد القداس'));
      expect(v.isValid, isTrue);
      expect(v.payload!['name'], 'مينا عادل');
      expect(v.payload!['phone'], '01223456789');
    });
    test('valid with email only, landline and +20 forms', () {
      expect(validateContactForm(const ContactFormInput(name: 'Mina', email: 'mina@example.com', message: 'Hello there')).isValid, isTrue);
      expect(isValidEgyptianPhone('03 555 1234'), isTrue);
      expect(isValidEgyptianPhone('+201012345678'), isTrue);
      expect(isValidEgyptianPhone('0020 115 123 4567'), isTrue);
      expect(isValidEgyptianPhone('0131234567'), isFalse);
      expect(isValidEgyptianPhone('12345'), isTrue); // hotline
      expect(isValidEgyptianPhone('abc'), isFalse);
      // Bare 20 country prefix (no +) for landlines and mobiles.
      expect(normalizeEgyptianPhone('2035551234'), '035551234');
      expect(normalizeEgyptianPhone('20225551234'), '0225551234');
      expect(normalizeEgyptianPhone('201012345678'), '01012345678');
    });
    test('mobile vs landline', () {
      expect(isEgyptianMobile('0101 234 5678'), isTrue);
      expect(isEgyptianMobile('+201012345678'), isTrue);
      expect(isEgyptianMobile('03 555 1234'), isFalse);
      expect(isEgyptianMobile(''), isFalse);
    });
    test('errors', () {
      final v = validateContactForm(const ContactFormInput(name: 'M', message: 'hey'));
      expect(v.isValid, isFalse);
      expect(v.errors[ContactField.name], ContactError.nameLength);
      expect(v.errors[ContactField.contact], ContactError.phoneOrEmailRequired);
      expect(v.errors[ContactField.message], ContactError.messageLength);
      final v2 = validateContactForm(ContactFormInput(name: 'Mina', phone: '0123', email: 'bad@', message: 'x' * 1001));
      expect(v2.errors[ContactField.phone], ContactError.phoneInvalid);
      expect(v2.errors[ContactField.email], ContactError.emailInvalid);
      expect(v2.errors[ContactField.message], ContactError.messageLength);
      expect(v2.errors.containsKey(ContactField.contact), isFalse);
    });
    test('rate limiter', () {
      final rl = ContactRateLimiter();
      final t0 = DateTime(2026, 11, 1, 10);
      expect(rl.canSubmit(t0), isTrue);
      rl.recordSubmission(t0);
      expect(rl.canSubmit(t0.add(const Duration(seconds: 30))), isFalse);
      expect(rl.waitTime(t0.add(const Duration(seconds: 30))), const Duration(seconds: 30));
      rl.recordSubmission(t0.add(const Duration(minutes: 2)));
      rl.recordSubmission(t0.add(const Duration(minutes: 4)));
      expect(rl.canSubmit(t0.add(const Duration(minutes: 10))), isFalse); // 3 in the hour
      expect(rl.canSubmit(t0.add(const Duration(minutes: 61))), isTrue);
    });
  });

  group('formatting', () {
    test('times in Latin and Arabic digits', () {
      expect(formatTimeLatin('06:30'), '06:30 AM');
      expect(formatTimeLatin('18:30'), '06:30 PM');
      expect(formatTimeLatin('00:15'), '12:15 AM');
      expect(formatTimeArabic('06:30'), '٠٦:٣٠ ص');
      expect(formatTimeArabic('18:30'), '٠٦:٣٠ م');
      expect(formatRangeLatin('06:30', '08:30'), '06:30 AM – 08:30 AM');
      expect(weekdayName(5, arabic: true), 'الجمعة');
      expect(normalizeDigits('٢٠٢٦'), '2026');
    });
  });

  group('models', () {
    test('fromMap tolerates missing / string values', () {
      final l = Liturgy.fromMap('a', {'weekday': '5', 'start': '06:30', 'end': '08:30', 'nameAr': 'x'});
      expect(l.type, 'mass');
      expect(l.weekday, 5);
      expect(l.startMinutes, 390);
      final s = Season.fromMap('s', {'key': 'summer', 'startsAt': '2026-06-15T00:00:00+03:00', 'active': true});
      expect(s.startsAt, DateTime.utc(2026, 6, 14, 21));
      expect(parseHm('25:00'), isNull);
    });
  });
}
