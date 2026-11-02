import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: '');

Map<String, dynamic> _details({bool enabled = true, bool contacts = true, bool socials = true}) => {
      'detailsEnabled': enabled,
      'showContacts': contacts,
      'showSocials': socials,
      'detailsAr': 'ت' * 400,
      'detailsEn': 'Long details ${'d' * 400}',
      'extraFields': [
        {'titleAr': 'المكان', 'titleEn': 'Place', 'valueAr': 'القاعة الكبرى', 'valueEn': 'Main hall'},
        {'titleAr': '', 'titleEn': '', 'valueAr': '', 'valueEn': ''},
      ],
      'contactPhone': '01011112222',
      'whatsapp': '01033334444',
      'contactNoteEn': 'Call after vespers',
      'whatsappUrl': 'https://chat.whatsapp.com/group-x',
      'facebookUrl': 'https://facebook.com/page-x',
      'youtubeUrl': 'https://youtube.com/@channel-x',
      'instagramUrl': 'https://instagram.com/insta-x',
      'externalUrl': 'https://forms.example.org/register-x',
      'externalLabelEn': 'Register',
      'gallery': [
        {'source': 'url', 'url': 'https://img.example.org/GALLERY-URL.jpg', 'alt': 'GALLERY-ALT'},
        {'source': 'inline', 'mediaId': 'GALLERY-MEDIA-ID', 'alt': 'GALLERY-ALT-2'},
      ],
      'image': {'source': 'inline', 'mediaId': 'COVER-MEDIA-ID', 'alt': 'COVER-ALT'},
    };

String _build({
  FeatureSettings f = FeatureSettings.defaults,
  Map<String, dynamic> d = const {},
  List<Milestone> milestones = const [],
  List<Clinic>? clinics,
  List<Meeting>? meetings,
  List<Activity>? activities,
}) =>
    buildAssistantInstruction(
      settings: _settings,
      liturgies: const [],
      seasons: const [],
      clinics: clinics ?? [Clinic.fromMap('c', {'specialtyAr': 'الأسنان', 'doctorName': 'د. مينا', 'bookingPhone': '0355', ...d})],
      meetings: meetings ?? [Meeting.fromMap('m', {'stage': 'youth', 'nameAr': 'اجتماع الشباب', ...d})],
      activities: activities ?? [Activity.fromMap('a', {'titleAr': 'الكورال', 'link': 'https://fb.example.org/choir', ...d})],
      facilities: [Facility.fromMap('f', {'nameAr': 'الحضانة', 'phone': '0366', ...d})],
      priests: [Priest.fromMap('p', {'name': 'أبونا يوسف', ...d})],
      saints: [Saint.fromMap('s', {'nameAr': 'الأنبا موسى', ...d})],
      milestones: milestones,
      now: CairoTime.at(2026, 11, 2, 600),
      features: f,
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('milestones', () {
    final ms = [
      Milestone.fromMap('v', {'titleAr': 'زيارة البابا', 'titleEn': "The Pope's visit", 'descEn': 'First pastoral visit', 'year': 2025}),
      Milestone.fromMap('h', {'titleAr': 'محطة مخفية', 'year': 1990}),
    ];

    test('are grounded when the section is on', () {
      final t = _build(milestones: ms);
      expect(t, contains('## Our story (milestones)'));
      expect(t, contains("- 2025: The Pope's visit (زيارة البابا): First pastoral visit"));
      expect(t, contains('- 1990: محطة مخفية'));
    });

    test('are left out when the section is off or there are none', () {
      expect(_build(milestones: ms, f: FeatureSettings.fromMap({'sections': {'milestones': false}})),
          isNot(contains('## Our story')));
      expect(_build(), isNot(contains('## Our story')));
    });
  });

  group('item details', () {
    test('details (clipped to 300 chars per language) and custom fields are grounded for enabled pages', () {
      final t = _build(d: _details());
      expect(t, contains('Details: Long details ${'d' * 287}…'));
      expect(t, contains('ت' * 300));
      expect(t, isNot(contains('ت' * 301)));
      expect(t, contains('Place (المكان): Main hall (القاعة الكبرى)'));
      // Every one of the 7 collections carries them.
      expect('Place (المكان): Main hall'.allMatches(t).length, 6); // + milestones below
      final withMs = _build(d: _details(), milestones: [Milestone.fromMap('x', {'titleAr': 'م', 'year': 2000, ..._details()})]);
      expect('Place (المكان): Main hall'.allMatches(withMs).length, 7);
    });

    test('a page that is not enabled adds nothing', () {
      // (Activities keep their own contactPhone field, grounded as before.)
      final t = _build(d: _details(enabled: false), activities: const []);
      expect(t, isNot(contains('Details:')));
      expect(t, isNot(contains('Main hall')));
      expect(t, isNot(contains('01011112222')));
      expect(t, isNot(contains('youtube.com/@channel-x')));
    });

    test('item contacts follow showContacts', () {
      final on = _build(d: _details());
      expect(on, contains('01011112222'));
      expect(on, contains('01033334444'));
      expect(on, contains('Call after vespers'));
      expect(on, contains('booking 0355'));
      expect(on, contains('Phone 0366'));
      final off = _build(d: _details(contacts: false));
      for (final n in ['01011112222', '01033334444', 'Call after vespers', '0355', '0366']) {
        expect(off, isNot(contains(n)), reason: n);
      }
    });

    test('item links follow showSocials and the socials section', () {
      final links = [
        'chat.whatsapp.com/group-x', 'facebook.com/page-x', 'youtube.com/@channel-x', 'instagram.com/insta-x', //
        'forms.example.org/register-x', 'fb.example.org/choir',
      ];
      final on = _build(d: _details());
      for (final l in links) {
        expect(on, contains(l), reason: l);
      }
      expect(on, contains('Register: https://forms.example.org/register-x'));
      for (final off in [
        _build(d: _details(socials: false)),
        _build(d: _details(), f: FeatureSettings.fromMap({'sections': {'socials': false}})),
      ]) {
        for (final l in links) {
          expect(off, isNot(contains(l)), reason: l);
        }
      }
      // Without detail fields the activity link is still grounded (as before).
      expect(_build(), contains('Link: https://fb.example.org/choir'));
    });

    test('never carries image or gallery data', () {
      final t = _build(d: _details(), milestones: [Milestone.fromMap('x', {'titleAr': 'م', ..._details()})]);
      for (final s in ['GALLERY-URL', 'GALLERY-ALT', 'GALLERY-MEDIA-ID', 'COVER-MEDIA-ID', 'COVER-ALT', 'img.example.org']) {
        expect(t, isNot(contains(s)), reason: s);
      }
    });

    test('documents without detail fields ground exactly as before', () {
      final m = Meeting.fromMap('m', {
        'stage': 'youth',
        'nameAr': 'اجتماع',
        'facebookUrl': 'https://facebook.com/m',
        'whatsappUrl': 'https://chat.whatsapp.com/m',
      });
      final t = _build(meetings: [m]);
      expect(t, contains('- اجتماع [youth]: no fixed day (ask the church) ; Facebook https://facebook.com/m; WhatsApp https://chat.whatsapp.com/m'));
    });

    test('custom-field titles and values are clipped per language', () {
      final d = {
        ..._details(),
        'extraFields': [
          {'titleAr': 'ع' * 150, 'titleEn': 'T' * 150, 'valueAr': 'ق' * 2000, 'valueEn': 'V' * 2000},
        ],
      };
      final t = _build(d: d, clinics: const [], meetings: const [], activities: const []);
      expect(t, contains('${'T' * 100}…'));
      expect(t, isNot(contains('T' * 101)));
      expect(t, contains('${'V' * 300}…'));
      expect(t, isNot(contains('V' * 301)));
      expect(t, isNot(contains('ق' * 301)));
    });

    test('detail signature changes when details, contacts or links are withdrawn', () {
      String sig(Map<String, dynamic> d, [FeatureSettings f = FeatureSettings.defaults]) => assistantDetailSignature(
            features: f,
            meetings: [Meeting.fromMap('m', {'stage': 'youth', 'nameAr': 'اجتماع', ...d})],
          );
      final on = sig(_details());
      expect(sig(_details()), on);
      expect(sig(_details(enabled: false)), isNot(on));
      expect(sig(_details(contacts: false)), isNot(on));
      expect(sig(_details(socials: false)), isNot(on));
      expect(sig(_details(), FeatureSettings.fromMap({'sections': {'socials': false}})), isNot(on));
      expect(sig({..._details(), 'detailsEn': 'edited'}), isNot(on));
      // A disabled page still tracks the contact / link toggles of the item's own fields.
      expect(sig(_details(enabled: false, contacts: false)), isNot(sig(_details(enabled: false))));
    });
  });
}
