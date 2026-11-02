import 'dart:io';

import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _inline = {'source': 'inline', 'mediaId': 'm1', 'alt': 'Photo'};
const _url = {'source': 'url', 'url': 'https://img.example.org/a.jpg'};

Map<String, dynamic> _field(int i) => {'titleAr': 'عنوان $i', 'titleEn': 'Title $i', 'valueAr': 'قيمة', 'valueEn': 'Value'};

void main() {
  group('CustomField', () {
    test('parses tolerantly and round-trips', () {
      final f = CustomField.fromMap(const {'titleAr': 'المكان', 'titleEn': 'Place', 'valueAr': 'القاعة', 'valueEn': 7});
      expect(f.titleAr, 'المكان');
      expect(f.titleEn, 'Place');
      expect(f.valueAr, 'القاعة');
      expect(f.valueEn, '7');
      expect(f.isEmpty, isFalse);
      expect(CustomField.fromMap(f.toMap()).toMap(), f.toMap());
      expect(f.toMap().keys, ['titleAr', 'titleEn', 'valueAr', 'valueEn']);
    });

    test('blank fields are empty', () {
      expect(const CustomField().isEmpty, isTrue);
      expect(CustomField.fromMap(const {'titleAr': '  ', 'valueEn': '\n'}).isEmpty, isTrue);
      expect(CustomField.fromMap(const {'valueEn': 'x'}).isEmpty, isFalse);
    });
  });

  group('ItemDetails', () {
    test('missing fields: detail page on (opt-out, PR #14), images/contacts/socials on', () {
      for (final d in [ItemDetails.fromMap(const {}), const ItemDetails(), ItemDetails.none]) {
        expect(d.detailsEnabled, isTrue);
        expect(d.showDetailImages, isTrue);
        expect(d.showContacts, isTrue);
        expect(d.showSocials, isTrue);
        expect(d.detailsAr, '');
        expect(d.detailsEn, '');
        expect(d.extraFields, isEmpty);
        expect(d.gallery, isEmpty);
        expect(d.contactPhone, '');
        expect(d.externalUrl, '');
      }
    });

    test('non-bool toggles fall back to their defaults', () {
      final d = ItemDetails.fromMap(const {
        'detailsEnabled': 'yes',
        'showDetailImages': 0,
        'showContacts': null,
        'showSocials': 'no',
      });
      expect(d.detailsEnabled, isTrue);
      expect(d.showDetailImages, isTrue);
      expect(d.showContacts, isTrue);
      expect(d.showSocials, isTrue);
    });

    test('parses every detail field', () {
      final d = ItemDetails.fromMap({
        'detailsEnabled': true,
        'showDetailImages': false,
        'showContacts': false,
        'showSocials': false,
        'detailsAr': 'تفاصيل',
        'detailsEn': 'Details',
        'extraFields': [_field(1)],
        'gallery': [_inline, _url],
        'contactPhone': '01000000000',
        'whatsapp': '01111111111',
        'whatsappUrl': 'https://chat.whatsapp.com/x',
        'facebookUrl': 'https://facebook.com/x',
        'youtubeUrl': 'https://youtube.com/x',
        'instagramUrl': 'https://instagram.com/x',
        'externalUrl': 'https://forms.example.org/x',
        'externalLabelAr': 'نموذج التسجيل',
        'externalLabelEn': 'Register',
        'contactNoteAr': 'اتصل بعد العشية',
        'contactNoteEn': 'Call after vespers',
      });
      expect(d.detailsEnabled, isTrue);
      expect(d.showDetailImages, isFalse);
      expect(d.showContacts, isFalse);
      expect(d.showSocials, isFalse);
      expect(d.detailsAr, 'تفاصيل');
      expect(d.detailsEn, 'Details');
      expect(d.extraFields.single.titleEn, 'Title 1');
      expect(d.gallery, [MediaImage.fromMap(_inline), MediaImage.fromMap(_url)]);
      expect(d.contactPhone, '01000000000');
      expect(d.whatsapp, '01111111111');
      expect(d.whatsappUrl, 'https://chat.whatsapp.com/x');
      expect(d.facebookUrl, 'https://facebook.com/x');
      expect(d.youtubeUrl, 'https://youtube.com/x');
      expect(d.instagramUrl, 'https://instagram.com/x');
      expect(d.externalUrl, 'https://forms.example.org/x');
      expect(d.externalLabelAr, 'نموذج التسجيل');
      expect(d.externalLabelEn, 'Register');
      expect(d.contactNoteAr, 'اتصل بعد العشية');
      expect(d.contactNoteEn, 'Call after vespers');
    });

    test('drops empty / invalid entries and caps the lists', () {
      final d = ItemDetails.fromMap({
        'extraFields': [
          {'titleAr': ' ', 'valueAr': ''},
          'junk',
          for (var i = 0; i < 20; i++) _field(i),
        ],
        'gallery': [
          {'source': 'url', 'url': 'http://insecure.example.org/a.jpg'},
          {'source': 'inline', 'mediaId': 'bad id!'},
          7,
          for (var i = 0; i < 12; i++) {'source': 'inline', 'mediaId': 'm$i'},
        ],
      });
      expect(d.extraFields, hasLength(MediaLimits.maxExtraFields));
      expect(d.extraFields.first.titleEn, 'Title 0');
      expect(d.gallery, hasLength(MediaLimits.maxGalleryItems));
      expect(d.gallery.first.mediaId, 'm0');
      expect(ItemDetails.fromMap(const {'extraFields': 'x', 'gallery': {'a': 1}}).extraFields, isEmpty);
    });
  });

  group('the 7 detail collections', () {
    const detail = {
      'detailsEnabled': true,
      'detailsAr': 'تفاصيل',
      'contactPhone': '01000000000',
      'externalUrl': 'https://forms.example.org/x',
      'gallery': [_inline],
    };

    test('every target model carries ItemDetails (defaults when absent)', () {
      final parsed = <String, ItemDetails Function(Map<String, dynamic>)>{
        'meeting': (m) => Meeting.fromMap('x', {'stage': 'youth', 'nameAr': 'ا', ...m}).details,
        'activity': (m) => Activity.fromMap('x', {'titleAr': 'ا', ...m}).details,
        'clinic': (m) => Clinic.fromMap('x', {'specialty': 'dental', 'specialtyAr': 'ا', 'doctorName': 'د', ...m}).details,
        'facility': (m) => Facility.fromMap('x', {'nameAr': 'ا', ...m}).details,
        'priest': (m) => Priest.fromMap('x', {'name': 'ا', ...m}).details,
        'milestone': (m) => Milestone.fromMap('x', {'titleAr': 'ا', ...m}).details,
        'saint': (m) => Saint.fromMap('x', {'nameAr': 'ا', ...m}).details,
      };
      for (final e in parsed.entries) {
        final none = e.value(const {});
        expect(none.detailsEnabled, isTrue, reason: e.key);
        expect(none.showDetailImages, isTrue, reason: e.key);
        final d = e.value(detail);
        expect(d.detailsEnabled, isTrue, reason: e.key);
        expect(d.detailsAr, 'تفاصيل', reason: e.key);
        expect(d.gallery.single.mediaId, 'm1', reason: e.key);
      }
      // Const constructors default to "page on, nothing extra".
      expect(const Meeting(id: 'x', stage: 's', nameAr: 'ا', nameEn: '').details.detailsEnabled, isTrue);
      expect(const Saint(id: 'x', nameAr: 'ا', nameEn: '').details, same(ItemDetails.none));
    });

    test('meetings, clinics and facilities gain an optional cover image', () {
      expect(Meeting.fromMap('x', const {'stage': 's', 'nameAr': 'ا'}).image, isNull);
      expect(Clinic.fromMap('x', const {'doctorName': 'د'}).image, isNull);
      expect(Facility.fromMap('x', const {'nameAr': 'ا'}).image, isNull);
      expect(Meeting.fromMap('x', const {'nameAr': 'ا', 'image': _inline}).image?.mediaId, 'm1');
      expect(Clinic.fromMap('x', const {'doctorName': 'د', 'image': _url}).image?.url, 'https://img.example.org/a.jpg');
      expect(Facility.fromMap('x', const {'nameAr': 'ا', 'image': {'source': 'bogus'}}).image, isNull);
    });

    test('clinics and facilities resolve the primary phone from their existing field', () {
      expect(Clinic.fromMap('x', const {'doctorName': 'د', 'bookingPhone': '0123'}).details.contactPhone, '0123');
      expect(Facility.fromMap('x', const {'nameAr': 'ا', 'phone': '0456'}).details.contactPhone, '0456');
      expect(Priest.fromMap('x', const {'name': 'ا', 'contactPhone': '0789'}).details.contactPhone, '0789');
      expect(Activity.fromMap('x', const {'titleAr': 'ا', 'contactPhone': '0789'}).details.contactPhone, '0789');
    });

    test('activities fall back to their existing link for the external button', () {
      final a = Activity.fromMap('x', const {'titleAr': 'ا', 'link': 'https://fb.example.org/choir'});
      expect(a.details.externalUrl, 'https://fb.example.org/choir');
      expect(Saint.fromMap('x', const {'nameAr': 'ا', 'link': 'https://x.org'}).details.externalUrl, '');
    });

    test('meetings keep their existing social links in the same keys', () {
      final m = Meeting.fromMap('x', const {
        'stage': 's',
        'nameAr': 'ا',
        'facebookUrl': 'https://facebook.com/m',
        'whatsappUrl': 'https://chat.whatsapp.com/m',
      });
      expect(m.facebookUrl, m.details.facebookUrl);
      expect(m.whatsappUrl, m.details.whatsappUrl);
      // Clinics keep their WhatsApp number in the shared `whatsapp` key.
      expect(Clinic.fromMap('x', const {'doctorName': 'د', 'whatsapp': '010'}).details.whatsapp, '010');
    });
  });

  group('firestore.rules lockstep (detail keys)', () {
    final rules = File('firestore.rules').readAsStringSync();
    Set<String> quoted(String fn) {
      final start = rules.indexOf('function $fn(');
      expect(start, greaterThan(0), reason: fn);
      final body = rules.substring(start, rules.indexOf('}', start));
      return RegExp(r"'([A-Za-z]+)'").allMatches(body).map((m) => m.group(1)!).toSet();
    }

    test('the 7 detail collections allow every key ItemDetails reads, and no other collection does', () {
      const detailKeys = {
        'detailsEnabled', 'showDetailImages', 'showContacts', 'showSocials', 'detailsAr', 'detailsEn', 'extraFields', //
        'gallery', 'whatsapp', 'whatsappUrl', 'facebookUrl', 'youtubeUrl', 'instagramUrl', 'externalLabelAr',
        'externalLabelEn', 'contactNoteAr', 'contactNoteEn',
      };
      expect(quoted('detailKeys'), detailKeys);
      const fns = {
        'meetings': 'validMeeting', 'activities': 'validActivity', 'clinics': 'validClinic', //
        'facilities': 'validFacility', 'priests': 'validPriest', 'milestones': 'validMilestone', 'saints': 'validSaint',
      };
      for (final e in fns.entries) {
        final start = rules.indexOf('function ${e.value}(');
        final body = rules.substring(start, rules.indexOf('}', start));
        expect(body, contains('concat(detailKeys())'), reason: e.key);
        expect(body, contains('validDetailCommon(d, changed)'), reason: e.key);
        final own = quoted(e.value);
        expect(own, contains('image'), reason: '${e.key}.image');
        // The primary phone / external link: a new key, or the existing field.
        expect(own, contains(['clinics', 'facilities'].contains(e.key) ? (e.key == 'clinics' ? 'bookingPhone' : 'phone') : 'contactPhone'),
            reason: '${e.key} phone');
        expect(own, contains(e.key == 'activities' ? 'link' : 'externalUrl'), reason: '${e.key} link');
      }
      for (final fn in ['validAlert', 'validSeason', 'validLiturgy']) {
        final start = rules.indexOf('function $fn(');
        expect(rules.substring(start, rules.indexOf('}', start)), isNot(contains('detailKeys')), reason: fn);
      }
    });

    test('rules caps match the client limits', () {
      expect(rules, contains("optList(d, 'gallery', ${MediaLimits.maxGalleryItems})"));
      expect(rules, contains("optList(d, 'extraFields', ${MediaLimits.maxExtraFields})"));
      expect(rules, contains('d.keys().size() <= 80'));
    });
  });
}
