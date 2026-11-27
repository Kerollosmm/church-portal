import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:fake_async/fake_async.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/ui/admin/admin_access.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/advanced_owner_screen.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/contact_admin.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/admin/notifications_admin.dart';
import 'package:church_portal/ui/admin/pending_delete.dart';
import 'package:church_portal/ui/admin/season_preset_admin.dart';
import 'package:church_portal/ui/admin/session_policy.dart';
import 'package:church_portal/ui/admin/state_switch.dart';
import 'package:church_portal/ui/admin/unsaved_bar.dart';
import 'package:church_portal/ui/admin/unsaved_guard.dart';
import 'package:church_portal/ui/admin/web_push_health.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';


FieldDef _f(FieldType t, {bool required = false, num? min, num? max, bool allowPath = false, int maxLength = 0}) =>
    FieldDef('k', 'ك', 'k', t, required: required, min: min, max: max, allowPath: allowPath, maxLength: maxLength);

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

Future<void> _confirmDeleteTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm-ok')));
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('field validation', () {
    test('validateScheduledNotificationFields maps each invalid field to its exact key and preserves wrapper precedence',
        () {
      ScheduledNotification row({
        String id = 'n1',
        String targets = 'all',
        String titleAr = 'عنوان تجربة',
        String titleEn = '',
        String bodyAr = 'نص تجربة',
        String bodyEn = '',
        String link = '/',
        String eventKey = '',
      }) =>
          ScheduledNotification(
            id: id,
            atUtc: DateTime.utc(2026, 12, 1, 9, 0),
            targets: targets,
            titleAr: titleAr,
            titleEn: titleEn,
            bodyAr: bodyAr,
            bodyEn: bodyEn,
            link: link,
            eventKey: eventKey,
          );

      // Simultaneous empty Arabic title and body -> both mapped, wrapper returns title required
      final emptyBoth = row(titleAr: '   ', bodyAr: '');
      expect(
        validateScheduledNotificationFields(emptyBoth),
        {'titleAr': 'err_title_required', 'bodyAr': 'err_body_required'},
      );
      expect(validateScheduledNotification(emptyBoth), 'err_title_required');

      // Surrogate-pair emoji / UTF-16 > 120 in titleEn maps ONLY to titleEn (never titleAr)
      final longTitleEn = row(titleEn: '🙏' * 61); // 122 UTF-16 code units, 61 grapheme clusters
      expect(validateScheduledNotificationFields(longTitleEn), {'titleEn': 'err_title_length'});
      expect(validateScheduledNotification(longTitleEn), 'err_title_length');

      // bodyEn > 300 maps ONLY to bodyEn (never bodyAr)
      final longBodyEn = row(bodyEn: 'a' * 301);
      expect(validateScheduledNotificationFields(longBodyEn), {'bodyEn': 'err_body_length'});
      expect(validateScheduledNotification(longBodyEn), 'err_body_length');

      // Separator \u001f in bodyEn and titleAr maps to each offending field
      expect(
        validateScheduledNotificationFields(row(titleAr: 'أ\u001fب', bodyEn: 'x\u001fy')),
        {'titleAr': 'err_bad_char', 'bodyEn': 'err_bad_char'},
      );
      expect(validateScheduledNotification(row(bodyEn: 'x\u001fy')), 'err_bad_char');

      // Link & eventKey
      expect(validateScheduledNotificationFields(row(link: 'https://evil.com')), {'link': 'err_bad_link'});
      expect(validateScheduledNotification(row(link: 'https://evil.com')), 'err_bad_link');
      expect(validateScheduledNotificationFields(row(eventKey: 'bad-key')), {'link': 'err_invalid_event_key'});
      expect(validateScheduledNotification(row(eventKey: 'bad-key')), 'err_invalid_event_key');

      // Targets & ID
      expect(validateScheduledNotificationFields(row(targets: 'sms')), {'targets': 'err_invalid_targets'});
      expect(validateScheduledNotification(row(targets: 'sms')), 'err_invalid_targets');
      expect(validateScheduledNotificationFields(row(id: 'BAD ID!')), {'id': 'err_invalid_id'});
      expect(validateScheduledNotification(row(id: 'BAD ID!')), 'err_invalid_id');

      // Precedence when length error in EN co-occurs with bad char in AR
      final mixed = row(titleAr: 'أ\u001fب', titleEn: 'e' * 121);
      expect(validateScheduledNotification(mixed), 'err_title_length');

      // Valid row -> empty map and null wrapper
      expect(validateScheduledNotificationFields(row()), isEmpty);
      expect(validateScheduledNotification(row()), isNull);
    });

    test('validateHeadingBlock and heading in validateDocument', () {
      expect(validateHeadingBlock({'textAr': ''}, BlockTypes.heading), 'required');
      expect(validateHeadingBlock({'textAr': '   '}, BlockTypes.heading), 'required');
      expect(validateHeadingBlock({'textAr': 'عنوان'}, BlockTypes.heading), isNull);
      expect(validateHeadingBlock({'textAr': ''}, BlockTypes.paragraph), isNull);

      final pagesDef = collectionById('pages')!;
      expect(
        validateDocument(pagesDef, {
          'blocks': [
            {'type': 'heading', 'textAr': ''}
          ]
        }),
        'blockHeadingRequired',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [
            {'type': 'heading', 'textAr': 'عنوان'}
          ]
        }),
        isNull,
      );
    });

    test('validateListBlock and list blocks in validateDocument', () {
      expect(
        validateListBlock(
          arItems: const ['تجربة أولى', 'تجربة ثانية'],
          enItems: const ['First', 'Second'],
          style: ListStyles.bullet,
        ),
        isEmpty,
      );
      expect(
        validateListBlock(
          arItems: const ['تجربة أولى'],
          style: ListStyles.numbered,
        ),
        isEmpty,
      );

      // 0 items -> blockListEmpty
      expect(
        validateListBlock(arItems: const []),
        [(itemIndex: null, isEn: false, code: 'blockListEmpty')],
      );

      // Blank / whitespace / separator-only item -> blockListItemRequired with index
      expect(
        validateListBlock(arItems: const ['تجربة', '   ', '\u001e\u001f']),
        [
          (itemIndex: 1, isEn: false, code: 'blockListItemRequired'),
          (itemIndex: 2, isEn: false, code: 'blockListItemRequired'),
        ],
      );

      // > 20 items -> blockListTooMany (both AR and EN)
      expect(
        validateListBlock(arItems: List.filled(listBlockMaxItems + 1, 'تجربة')).first.code,
        'blockListTooMany',
      );
      expect(
        validateListBlock(arItems: const ['تجربة'], enItems: List.filled(listBlockMaxItems + 1, 'Test')).first.code,
        'blockListTooMany',
      );

      // > 200 chars -> blockListItemTooLong (AR and EN)
      expect(
        validateListBlock(arItems: ['أ' * (listItemMax + 1)]),
        [(itemIndex: 0, isEn: false, code: 'blockListItemTooLong')],
      );
      expect(
        validateListBlock(arItems: const ['تجربة'], enItems: ['a' * (listItemMax + 1)]),
        [(itemIndex: 0, isEn: true, code: 'blockListItemTooLong')],
      );

      // Bad style -> invalid
      expect(
        validateListBlock(arItems: const ['تجربة'], style: 'square'),
        [(itemIndex: null, isEn: false, code: 'invalid')],
      );

      // validateDocument integration on encoded and map blocks
      final pagesDef = collectionById('pages')!;
      final validEncoded = PageBlock.list(
        items: const [(ar: 'تجربة أولى', en: 'First'), (ar: 'تجربة ثانية', en: 'Second')],
        style: ListStyles.numbered,
      ).encode();
      expect(validateDocument(pagesDef, {'blocks': [validEncoded]}), isNull);

      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: '').encode()]
        }),
        'blockListEmpty',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: 'تجربة\u001e   ').encode()]
        }),
        'blockListItemRequired',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [
            {
              'type': BlockTypes.list,
              'textAr': List.filled(listBlockMaxItems + 1, 'تجربة').join(PageBlock.listSeparator),
            }
          ]
        }),
        'blockListTooMany',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [
            PageBlock.list(items: [(ar: 'أ' * (listItemMax + 1), en: '')]).encode()
          ]
        }),
        'blockListItemTooLong',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [
            PageBlock.list(items: const [(ar: 'تجربة', en: '')], style: ListStyles.bullet)
                .toMap()
              ..['textEn'] = 'a' * (listItemMax + 1),
          ]
        }),
        'blockListItemTooLong',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: 'تجربة', account: 'bad').encode()]
        }),
        'invalid',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: 'تجربة', url: 'https://example.org').encode()]
        }),
        'invalid',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: 'تجربة', instapay: 'x@instapay').encode()]
        }),
        'invalid',
      );
      expect(
        validateDocument(pagesDef, {
          'blocks': [const PageBlock(type: BlockTypes.list, textAr: 'تجربة', wallet: '01000000000').encode()]
        }),
        'invalid',
      );
    });

    test('validateDocument blocks a cover image with an invalid link', () {
      final pagesDef = collectionById('pages')!;
      // A usable https link is fine.
      expect(
        validateDocument(pagesDef, {
          'image': {'source': 'url', 'url': 'https://example.org/cover.jpg'},
        }),
        isNull,
      );
      // http, a host without a dot, and a link with a space all block the save.
      expect(
        validateDocument(pagesDef, {
          'image': {'source': 'url', 'url': 'http://example.org/cover.jpg'},
        }),
        'invalidCoverImage',
      );
      expect(
        validateDocument(pagesDef, {
          'image': {'source': 'url', 'url': 'https://localhost/cover.jpg'},
        }),
        'invalidCoverImage',
      );
      expect(
        validateDocument(pagesDef, {
          'image': {'source': 'url', 'url': 'https://example.org/cover image.jpg'},
        }),
        'invalidCoverImage',
      );
      // No image at all is fine (images are optional everywhere).
      expect(validateDocument(pagesDef, {'image': null}), isNull);
      expect(validateDocument(pagesDef, {}), isNull);
    });

    test('formatAdminError handles FirebaseException and generic errors', () {
      final fbe = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
      expect(formatAdminError(fbe), '[permission-denied] Missing or insufficient permissions.');

      final codeOnly = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: null,
      );
      expect(formatAdminError(codeOnly), '[permission-denied]');

      final msgOnly = FirebaseException(
        plugin: 'cloud_firestore',
        code: '',
        message: 'Something went wrong',
      );
      expect(formatAdminError(msgOnly), 'Something went wrong');

      final emptyFbe = FirebaseException(
        plugin: 'cloud_firestore',
        code: '',
        message: '',
      );
      expect(formatAdminError(emptyFbe), '[cloud_firestore]');

      expect(formatAdminError(Exception('custom error')), 'Exception: custom error');
    });
    test('required and length', () {
      expect(validateFieldValue(_f(FieldType.text, required: true), '  '), 'required');
      expect(validateFieldValue(_f(FieldType.text), ''), isNull);
      expect(validateFieldValue(_f(FieldType.text, maxLength: 3), 'abcd'), 'tooLong');
      expect(validateFieldValue(_f(FieldType.multiline), 'x' * 5000), isNull);
      expect(validateFieldValue(_f(FieldType.multiline), 'x' * 5001), 'tooLong');
    });

    test('time, dates and loose dates', () {
      expect(validateFieldValue(_f(FieldType.time), '06:30'), isNull);
      expect(validateFieldValue(_f(FieldType.time), '6:30'), isNull);
      expect(parseFieldValue(_f(FieldType.time), '6:30'), '06:30');
      expect(validateFieldValue(_f(FieldType.time), '٠٩:٣٠'), isNull);
      expect(parseFieldValue(_f(FieldType.time), '٠٩:٣٠'), '09:30');
      expect(validateFieldValue(_f(FieldType.time), '24:00'), 'invalidTime');
      expect(validateFieldValue(_f(FieldType.time), '25:00'), 'invalidTime');
      expect(validateFieldValue(_f(FieldType.date), '2027-02-30'), 'invalidDate');
      expect(validateFieldValue(_f(FieldType.date), '2027-01-06'), isNull);
      expect(validateFieldValue(_f(FieldType.date), '٢٠٢٧-٠١-٠٦'), isNull);
      expect(validateFieldValue(_f(FieldType.dateTime), '2027-01-06 20:00'), isNull);
      expect(validateFieldValue(_f(FieldType.dateTime), '٢٠٢٧-٠١-٠٦ ٢٠:٠٠'), isNull);
      expect(validateFieldValue(_f(FieldType.dateTime), '2027-01-06 25:00'), 'invalidDate');
      for (final ok in ['1998', '1998-03', '1998-03-21']) {
        expect(validateFieldValue(_f(FieldType.looseDate), ok), isNull, reason: ok);
      }
      for (final bad in ['98', '1998-13', '1998-02-30', '21/03/1998']) {
        expect(validateFieldValue(_f(FieldType.looseDate), bad), 'invalidDate', reason: bad);
      }
    });

    test('numbers with ranges (Arabic digits accepted)', () {
      expect(validateFieldValue(_f(FieldType.integer, min: 1, max: 7), '٣'), isNull);
      expect(parseFieldValue(_f(FieldType.integer), '٣'), 3);
      expect(validateFieldValue(_f(FieldType.integer, min: 1, max: 7), '9'), 'outOfRange');
      expect(validateFieldValue(_f(FieldType.integer), '1.5'), 'invalid');
      expect(validateFieldValue(_f(FieldType.decimal, min: -90, max: 90), '31.260138'), isNull);
      expect(validateFieldValue(_f(FieldType.decimal, min: -90, max: 90), '91'), 'outOfRange');
      expect(parseFieldValue(_f(FieldType.decimal), ' 30.01129 '), 30.01129);
      expect(parseFieldValue(_f(FieldType.integer), ''), isNull);
    });

    test('urls and phones', () {
      expect(validateFieldValue(_f(FieldType.url), 'https://www.facebook.com/x'), isNull);
      expect(validateFieldValue(_f(FieldType.url), 'facebook.com/x'), 'invalidUrl');
      expect(validateFieldValue(_f(FieldType.url), 'javascript:alert(1)'), 'invalidUrl');
      expect(validateFieldValue(_f(FieldType.url), '/church-education'), 'invalidUrl');
      expect(validateFieldValue(_f(FieldType.url, allowPath: true), '/church-education'), isNull);
      expect(validateFieldValue(_f(FieldType.url, allowPath: true), '//evil.com'), 'invalidUrl');
      expect(validateFieldValue(_f(FieldType.phone), '03 536 8888'), isNull);
      expect(validateFieldValue(_f(FieldType.phone), '٠١٠١٢٣٤٥٦٧٨'), isNull);
      expect(parseFieldValue(_f(FieldType.phone), '+20 100-123 4567'), '+201001234567');
      expect(validateFieldValue(_f(FieldType.phone), 'call me'), 'invalidPhone');
      // Length is measured on the stored (normalized) digits, not the separators.
      expect(validateFieldValue(_f(FieldType.phone), '+20 (100) 123-4567-89'), isNull);
    });

    test('cross-field document checks', () {
      final lit = collectionById('liturgies')!;
      expect(validateDocument(lit, {'weekday': null, 'date': null}), 'needWeekdayOrDate');
      expect(validateDocument(lit, {'weekday': 5, 'start': '23:00', 'end': '01:00'}), isNull); // crosses midnight
      final meeting = collectionById('meetings')!;
      expect(validateDocument(meeting, {'start': '20:00', 'end': '16:00'}), 'endBeforeStart');
      expect(validateDocument(meeting, {'start': '16:00', 'end': '20:00'}), isNull);
      final alert = collectionById('alerts')!;
      expect(
          validateDocument(alert, {'startsAt': DateTime.utc(2027, 1, 2), 'endsAt': DateTime.utc(2027, 1, 1)}),
          'endBeforeStart');
    });
  });

  group('changed fields', () {
    test('only differing keys are written (deep compare)', () {
      final initial = {
        'name': 'a', 'days': [1, 2], 'visible': true, 'when': DateTime.utc(2027), //
        'phones': [{'number': '1'}],
      };
      expect(changedFields(initial, {...initial}), isEmpty);
      expect(changedFields(initial, {...initial, 'days': [1, 2, 3]}), {'days': [1, 2, 3]});
      expect(changedFields(initial, {...initial, 'phones': [{'number': '2'}]}).keys, ['phones']);
      expect(changedFields(initial, {...initial, 'when': DateTime.utc(2028)}).keys, ['when']);
      expect(sameValue([{'a': 1}], [{'a': 1}]), isTrue);
    });
  });

  group('schema', () {
    test('every public content collection has an editor, with visibility where it is shown publicly', () {
      final names = adminCollections.map((c) => c.name).toSet();
      expect(names, containsAll(['alerts', 'seasons', 'liturgies', 'meetings', 'activities', 'facilities', //
        'priests', 'milestones', 'saints']));
      for (final c in adminCollections.where((c) => c.name != 'seasons')) {
        expect(c.hasVisible, isTrue, reason: c.id);
      }
      expect({for (final c in adminCollections) c.id}.length, adminCollections.length, reason: 'unique ids');
      for (final c in adminCollections.where((c) => c.orderable)) {
        expect(c.fields.any((f) => f.key == 'order'), isTrue, reason: c.id);
      }
    });

    test('church info exposes instagram, bishop, phones and altars', () {
      final keys = churchInfoDoc.fields.map((f) => f.key);
      expect(keys, containsAll(['instagram', 'bishopAr', 'bishopEn', 'phones', 'altars', 'lat', 'lng', 'facebook']));
    });

    test('priests collection includes serving & departed; departedPriests is merged', () {
      expect(collectionById('departedPriests'), isNull);
      final priests = collectionById('priests')!;
      expect(priests.matches({'status': 'departed'}), isTrue);
      expect(priests.matches({'status': 'serving'}), isTrue);
      expect(priests.matches(const {}), isTrue);
      expect(priests.fields.firstWhere((f) => f.key == 'status').defaultOption, 'serving');
      expect(priestStatus({'status': 'departed'}), 'departed');
      expect(priestStatus(const {}), 'serving');
      expect(reorderBase(priests), 0);
      expect(reorderBase(priests, status: 'departed'), 1000);
    });

    test('firestore.rules allow-lists cover every admin field and every seed key', () {
      final rules = File('firestore.rules').readAsStringSync();
      Set<String> allowed(String fn) {
        final start = rules.indexOf('function $fn(');
        expect(start, greaterThan(0), reason: fn);
        final body = rules.substring(start, rules.indexOf('}', start));
        final list = RegExp(r"(?:keysAllowed\(|changed\.hasOnly\()\[([^\]]*)\]").firstMatch(body)!.group(1)!;
        final keys = RegExp(r"'([A-Za-z]+)'").allMatches(list).map((m) => m.group(1)!).toSet();
        if (body.contains('concat(meta())')) keys.addAll(['visible', 'sample', 'order', 'updatedAt', 'updatedBy']);
        // PR #11: the 7 detail-page collections also allow the shared detail keys.
        // ADR-041: liturgies, meetings and seasons allow the programme keys.
        if (body.contains('concat(programKeys())')) {
          final start = rules.indexOf('function programKeys()');
          final prog = rules.substring(start, rules.indexOf('}', start));
          keys.addAll(RegExp(r"'([A-Za-z]+)'").allMatches(prog).map((m) => m.group(1)!));
        }
        if (body.contains('concat(detailKeys())')) {
          final start = rules.indexOf('function detailKeys()');
          final detail = rules.substring(start, rules.indexOf('}', start));
          keys.addAll(RegExp(r"'([A-Za-z]+)'").allMatches(detail).map((m) => m.group(1)!));
        }
        return keys;
      }

      const fnFor = {
        'alerts': 'validAlert', 'seasons': 'validSeason', 'liturgies': 'validLiturgy', 'meetings': 'validMeeting', //
        'activities': 'validActivity', 'facilities': 'validFacility',
        'priests': 'validPriest', 'milestones': 'validMilestone', 'saints': 'validSaint',
      };
      final seed = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
      for (final e in fnFor.entries) {
        final keys = allowed(e.value);
        for (final c in adminCollections.where((c) => c.name == e.key)) {
          for (final f in c.fields) {
            expect(keys, contains(f.key), reason: '${e.key}.${f.key} (admin field)');
          }
        }
        for (final doc in (seed[e.key] as Map).values) {
          for (final k in (doc as Map).keys) {
            expect(keys, contains(k), reason: '${e.key}.$k (seed)');
          }
        }
      }
      final church = allowed('validChurch');
      for (final f in churchInfoDoc.fields) {
        expect(church, contains(f.key), reason: 'settings/church.${f.key}');
      }
      for (final k in (seed['settings']['church'] as Map).keys) {
        expect(church, contains(k), reason: 'settings/church.$k (seed)');
      }
      // settings/features: every key the app writes.
      final featuresBlock = rules.substring(rules.indexOf('function validFeatures('));
      for (final k in FeatureSettings.defaults.toMap().keys) {
        expect(featuresBlock, contains("'$k'"), reason: 'settings/features.$k');
      }
      final sectionKeys = rules.substring(rules.indexOf('function sectionKeys()'), rules.indexOf('function validSections('));
      for (final s in Sections.all) {
        expect(sectionKeys, contains("'$s'"), reason: 'section $s');
      }
      for (final t in ThemePresets.all.keys) {
        expect(featuresBlock, contains("'$t'"), reason: 'theme $t');
      }
    });
  });

  group('PR #12: customization schema', () {
    const detailCols = ['meetings', 'activities', 'facilities', 'priests', 'milestones', 'saints'];
    FieldDef fd(CollectionDef c, String k) => c.fields.firstWhere((f) => f.key == k, orElse: () => throw k);

    test('imageList type, field groups and the image collections', () {
      expect(FieldType.values, contains(FieldType.imageList));
      expect(FieldGroup.values, [
        FieldGroup.basic,
        FieldGroup.program,
        FieldGroup.details,
        FieldGroup.media,
        FieldGroup.location,
        FieldGroup.contacts,
        FieldGroup.hero,
        FieldGroup.history,
      ]);
      expect(const FieldDef('x', 'x', 'x', FieldType.text).group, FieldGroup.basic);
      expect(imageCollections,
          ['alerts', 'seasons', 'meetings', 'activities', 'facilities', 'priests', 'milestones', 'saints',
            'entries', 'pages']);
      for (final c in adminCollections) {
        expect(c.fields.any((f) => f.key == 'image'), imageCollections.contains(c.name), reason: c.id);
      }
    });

    test('the 6 detail collections carry grouped details, media and contacts fields', () {
      for (final c in adminCollections.where((c) => detailCols.contains(c.name))) {
        final keys = c.fields.map((f) => f.key).toList();
        expect(keys.toSet().length, keys.length, reason: '${c.id}: duplicate keys');
        final enabled = fd(c, 'detailsEnabled');
        expect([enabled.group, enabled.type, enabled.missingBool, enabled.newBool],
            [FieldGroup.details, FieldType.boolean, true, true], reason: c.id); // opt-out (PR #14)
        expect(enabled.hintAr, isNotEmpty, reason: c.id);
        expect(enabled.hintEn, contains('On by default'), reason: c.id);
        for (final k in ['detailsAr', 'detailsEn']) {
          expect([fd(c, k).group, fd(c, k).type, fd(c, k).effectiveMaxLength],
              [FieldGroup.details, FieldType.multiline, 10000], reason: '${c.id}.$k');
        }
        final extra = fd(c, 'extraFields');
        expect([extra.group, extra.type, extra.maxRows], [FieldGroup.details, FieldType.objectList, 15], reason: c.id);
        expect(extra.subFields.map((f) => f.key), ['titleAr', 'titleEn', 'valueAr', 'valueEn']);
        expect(extra.subFields.map((f) => f.effectiveMaxLength), [150, 150, 2000, 2000]);
        // A title in either language (validExtraField in firestore.rules).
        expect(extra.subFields.map((f) => f.required), [false, false, false, false]);
        expect(extra.rowRequireAnyOf, ['titleAr', 'titleEn'], reason: c.id);
        expect(extra.subFields.skip(2).map((f) => f.type), everyElement(FieldType.multiline));

        expect(fd(c, 'image').group, FieldGroup.basic, reason: c.id);
        final show = fd(c, 'showDetailImages');
        expect([show.group, show.missingBool, show.newBool], [FieldGroup.media, true, true], reason: c.id);
        final gallery = fd(c, 'gallery');
        expect([gallery.group, gallery.type, gallery.maxRows], [FieldGroup.media, FieldType.imageList, 8], reason: c.id);

        for (final k in ['showContacts', 'showSocials']) {
          expect([fd(c, k).group, fd(c, k).missingBool, fd(c, k).newBool], [FieldGroup.contacts, true, true],
              reason: '${c.id}.$k');
        }
        // One input per stored key: the collection's own phone / link field
        // doubles as the primary phone / external link (ItemDetails.fromMap).
        final phone = c.name == 'facilities' ? 'phone' : 'contactPhone';
        final link = c.name == 'activities' ? 'link' : 'externalUrl';
        final phoneGroup =
            ['saints', 'milestones'].contains(c.name) ? FieldGroup.contacts : FieldGroup.basic;
        expect(fd(c, phone).group, phoneGroup, reason: '${c.id}.$phone');
        for (final k in ['whatsapp', 'whatsappUrl', 'facebookUrl', 'youtubeUrl', 'instagramUrl', link,
          'externalLabelAr', 'externalLabelEn', 'contactNoteAr', 'contactNoteEn']) {
          expect(fd(c, k).group, FieldGroup.contacts, reason: '${c.id}.$k');
        }
        if (['facilities'].contains(c.name)) expect(keys, isNot(contains('contactPhone')));
        if (c.name == 'activities') expect(keys, isNot(contains('externalUrl')));
        for (final k in [phone, 'whatsapp']) {
          expect(fd(c, k).type, FieldType.phone, reason: '${c.id}.$k');
        }
        for (final k in ['whatsappUrl', 'facebookUrl', 'youtubeUrl', 'instagramUrl', link]) {
          expect(fd(c, k).type, FieldType.url, reason: '${c.id}.$k');
        }
        expect([fd(c, 'externalLabelAr').effectiveMaxLength, fd(c, 'contactNoteEn').effectiveMaxLength], [80, 500]);
        // Everything else stays in the always-open basic group.
        for (final f in c.fields.where((f) => f.group == FieldGroup.basic)) {
          expect(f.type, isNot(FieldType.imageList), reason: '${c.id}.${f.key}');
        }
      }
      for (final c in adminCollections.where((c) => !detailCols.contains(c.name))) {
        // Liturgies / seasons also carry the programme group (ADR-041).
        expect(c.fields.every((f) => f.group == FieldGroup.basic || f.group == FieldGroup.program), isTrue, reason: c.id);
        expect(c.fields.map((f) => f.key), isNot(contains('detailsEnabled')), reason: c.id);
      }
    });

    test("BR-11: meetings' image and gallery warn about children's photos", () {
      final m = collectionById('meetings')!;
      for (final k in ['image', 'gallery']) {
        expect(fd(m, k).hintAr, contains('خصوصية الأطفال'), reason: k);
        expect(fd(m, k).hintEn, contains("Children's privacy"), reason: k);
      }
      expect(fd(collectionById('saints')!, 'gallery').hintEn, isEmpty);
    });

    test('image lists need no text validation', () {
      expect(validateFieldValue(const FieldDef('gallery', 'g', 'g', FieldType.imageList), null), isNull);
    });
  });

  group('PR #12: save split & detail links', () {
    final img = {'source': 'inline', 'mediaId': 'g1'};
    final row = {'titleAr': 'ع', 'titleEn': '', 'valueAr': 'ق', 'valueEn': ''};

    test('gallery and extraFields go in their own writes (rules expression budget)', () {
      expect(splitSavePayload(const {}), isEmpty);
      expect(splitSavePayload({'nameAr': 'x'}), [
        {'nameAr': 'x'}
      ]);
      expect(splitSavePayload({'nameAr': 'x', 'gallery': [img], 'extraFields': [row], 'detailsAr': 'd'}), [
        {'nameAr': 'x', 'detailsAr': 'd'},
        {'gallery': [img]},
        {'extraFields': [row]},
      ]);
      expect(splitSavePayload({'gallery': [img]}), [
        {'gallery': [img]}
      ]);
      expect(splitSavePayload({'extraFields': [row], 'gallery': [img]}), [
        {'gallery': [img]},
        {'extraFields': [row]},
      ]);
      // Today form (ADR-044): 20 church events go after the other Today keys.
      expect(splitSavePayload({'liveEnabled': true, 'dayEvents': ['e'], 'liveBadgeHideOnHome': false}), [
        {'liveEnabled': true, 'liveBadgeHideOnHome': false},
        {'dayEvents': ['e']},
      ]);
      expect(splitSavePayload({'liveEnabled': false, 'dayEvents': []}), [
        {'liveEnabled': false, 'dayEvents': []}
      ]);
      // Empty or cleared lists cost almost nothing: they stay in the first write.
      expect(splitSavePayload({'nameAr': 'x', 'gallery': [], 'extraFields': null}), [
        {'nameAr': 'x', 'gallery': [], 'extraFields': null}
      ]);
    });

    test('an extra-field row needs a title in Arabic or English, not both', () {
      final extra = collectionById('saints')!.fields.firstWhere((f) => f.key == 'extraFields');
      expect(validateRowAnyOf(extra, {'titleAr': 'ع', 'titleEn': ''}), isNull);
      expect(validateRowAnyOf(extra, {'titleAr': '', 'titleEn': 'Feast'}), isNull);
      expect(validateRowAnyOf(extra, {'titleAr': ' ', 'titleEn': '  ', 'valueAr': 'ق'}), 'requiredTitleAnyLang');
      expect(validateRowAnyOf(extra, const {}), 'requiredTitleAnyLang');
      expect(validateRowAnyOf(const FieldDef('phones', 'p', 'p', FieldType.objectList), const {}), isNull);
    });

    test('rows with a detail page open the item detail URL', () {
      String? path(String id, String col, Map<String, dynamic> data, {bool english = false}) =>
          itemPublicPathFor(collectionById(col)!, id, data, english: english);
      const on = {'detailsEnabled': true};
      expect(path('m1', 'meetings', on), '/church-education/m1');
      expect(path('a1', 'activities', on), '/church-activities/a1');
      expect(path('m1', 'meetings', on, english: true), '/church-education/m1?lang=en');
      expect(path('f1', 'facilities', on), '/public-services/f1');
      expect(path('p1', 'priests', on), '/about/priests/p1');
      expect(path('p2', 'priests', {...on, 'status': 'departed'}), '/about/priests/p2');
      expect(path('s1', 'saints', on), '/about/saints/s1');
      expect(path('h1', 'milestones', on), '/about/milestones/h1');
      // Untouched items (no field) have a page since PR #14.
      expect(path('m1', 'meetings', const {}), '/church-education/m1');
      // No detail page (switched off, hidden, or a collection without one): no link.
      expect(path('m1', 'meetings', const {'detailsEnabled': false}), isNull);
      expect(path('m1', 'meetings', const {'detailsEnabled': true, 'visible': false}), isNull);
      expect(path('l1', 'liturgies', on), isNull);
      expect(path('x/y', 'meetings', on), '/church-education/x%2Fy');
    });
  });

  group('admin list helpers', () {
    final def = collectionById('facilities')!;
    final docs = [
      const AdminDoc('a', {'nameEn': 'Nursery', 'nameAr': 'الحضانة', 'order': 20, 'visible': false}),
      const AdminDoc('b', {'nameEn': 'Library', 'nameAr': 'المكتبة', 'order': 10, 'sample': true}),
      const AdminDoc('c', {'nameEn': 'Halls', 'nameAr': 'القاعات'}),
    ];

    test('sorts orderable collections by order, unordered last', () {
      expect(sortAdminDocs(def, docs).map((d) => d.id), ['b', 'a', 'c']);
    });

    test('search and filters', () {
      expect(filterAdminDocs(def, docs, query: 'nursery').map((d) => d.id), ['a']);
      expect(filterAdminDocs(def, docs, query: 'المكتبة').map((d) => d.id), ['b']);
      expect(filterAdminDocs(def, docs, filter: ListFilter.hidden).map((d) => d.id), ['a']);
      expect(filterAdminDocs(def, docs, filter: ListFilter.visible).map((d) => d.id), ['b', 'c']);
      expect(filterAdminDocs(def, docs, filter: ListFilter.unconfirmed).map((d) => d.id), ['b']);
    });

    test('admin UIDs are validated', () {
      expect(isValidAdminUid('kD3x9Qa1bC2dE3fG4hI5jK6lM7n2'), isTrue);
      expect(isValidAdminUid('a/b'), isFalse);
      expect(isValidAdminUid(''), isFalse);
    });

    test('owners get the Admins screen, editors do not', () {
      expect(adminDestinations(AdminRoles.owner).map((d) => d.id), contains('admins'));
      expect(adminDestinations(AdminRoles.editor).map((d) => d.id), isNot(contains('admins')));
      expect(adminDestinations(AdminRoles.editor).map((d) => d.id), containsAll(['features', 'church', 'messages']));
    });
  });

  group('DocEditor widget', () {
    testWidgets('blocks save on invalid input, then saves typed + parsed values', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('facilities')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Add service',
        fields: def.fields,
        def: def,
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Required'), findsWidgets);

      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'الحضانة');
      // Primary phone sits at the top in the open basic section (P2-24);
      // order sits inside the collapsible "Advanced options" card.
      await tester.enterText(find.byKey(const ValueKey('field-phone')), '010 1234 5678');
      await tester.tap(find.byKey(const ValueKey('group-advanced')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-order')), 'abc'); // invalid
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(find.byKey(const ValueKey('field-order')), '30');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['nameAr'], 'الحضانة');
      // New doc: every field, except an unset image style (ADR-023: missing =
      // section default, so a new doc does not write it).
      expect(saved!.keys, containsAll(def.fields.map((f) => f.key).where((k) => k != 'imageStyle')));
      expect(saved!.containsKey('imageStyle'), isFalse);
      expect(saved!['phone'], '01012345678');
      expect(saved!['order'], 30);
      expect(saved!['visible'], isTrue); // new items start visible
      expect(saved!['sample'], isFalse);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('edits an object list (church phones)', (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final phones = FieldDef('phones', 'أرقام', 'Phones', FieldType.objectList,
          subFields: churchInfoDoc.fields.firstWhere((f) => f.key == 'phones').subFields);
      await tester.pumpWidget(_app(DocEditor(
        title: 'Church',
        fields: [phones],
        data: const {
          'phones': [
            {'labelAr': 'الكنيسة', 'labelEn': 'Church', 'number': '035368888', 'isMobile': false},
          ],
        },
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.tap(find.text('Add row'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: 'new row has a required number');
      final numberFields = find.byKey(const ValueKey('field-number'));
      expect(numberFields, findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('field-labelAr')).last, 'أبونا');
      await tester.enterText(numberFields.last, '01012345678');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved!['phones'], hasLength(2));
      expect((saved!['phones'] as List).last['number'], '01012345678');
      expect(saved!.keys, ['phones']); // existing doc: only what changed
    });

    testWidgets('invalid cover link blocks the save, then removing the image saves', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('pages')!;
      await tester.pumpWidget(_app(
        DocEditor(
          title: 'صفحة تجربة',
          fields: def.fields,
          def: def,
          data: const {
            'titleAr': 'صفحة تجربة',
            'slug': 'tajriba',
            'image': {'source': 'url', 'url': 'http://example.org/cover.jpg'},
          },
          docId: 'p1',
          popOnSave: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // The bad link is shown as an error in the field, not dropped silently.
      expect(find.text('لينك الصورة مش صالح — صلّح اللينك أو امسح الصورة.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: 'an invalid cover link must block the save');
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);

      // Tapping the error scrolls to the image field (both fixes are there).
      await tester.tap(find.byKey(const ValueKey('error-summary-image')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imageUrlBtn')), findsOneWidget);
      expect(find.byKey(const Key('imageRemoveBtn')), findsOneWidget);

      // «امسح الصورة» unblocks the save, and the image is gone.
      await tester.tap(find.byKey(const Key('imageRemoveBtn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['image'], isNull);
    });

    testWidgets('an invalid cover link can be fixed from the URL dialog, then saves', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('pages')!;
      await tester.pumpWidget(_app(
        DocEditor(
          title: 'صفحة تجربة',
          fields: def.fields,
          def: def,
          data: const {
            'titleAr': 'صفحة تجربة',
            'slug': 'tajriba',
            'image': {'source': 'url', 'url': 'http://example.org/cover.jpg'},
          },
          docId: 'p1',
          popOnSave: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('imageUrlBtn')));
      await tester.pumpAndSettle();
      // The bad link is offered back for editing.
      expect(find.byKey(const Key('imageUrlInput')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('imageUrlInput')), 'https://example.org/cover.jpg');
      await tester.tap(find.byKey(const Key('imageUrlOk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect((saved!['image'] as Map)['url'], 'https://example.org/cover.jpg');
    });

    testWidgets('an invalid cover link can be replaced by uploading a new image, then saves', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('pages')!;
      await tester.pumpWidget(_app(
        DocEditor(
          title: 'صفحة تجربة',
          fields: def.fields,
          def: def,
          data: const {
            'titleAr': 'صفحة تجربة',
            'slug': 'tajriba',
            'image': {'source': 'url', 'url': 'http://example.org/cover.jpg'},
          },
          docId: 'p1',
          popOnSave: false,
          media: _TestMediaRepo(),
          pickImage: () async => Uint8List.fromList([1, 2, 3, 4]),
          // A real 1x1 PNG: the pending preview decodes these bytes.
          prepareImage: (_) async => EncodedImage(
                base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
                'image/png',
                1,
                1,
              ),
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // The bad link blocks the save first.
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);

      // Uploading a replacement — without removing the old image first —
      // clears the error and unblocks the save (PR #86 review).
      await tester.tap(find.byKey(const Key('imageUploadBtn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imagePreviewPending')), findsOneWidget);
      expect(find.text('لينك الصورة مش صالح — صلّح اللينك أو امسح الصورة.'), findsNothing);
      expect(find.byKey(const Key('editor-error-summary')), findsNothing);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect((saved!['image'] as Map)['mediaId'], 'm1');
    });

    testWidgets('placement options show a one-line hint under each choice', (tester) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final def = collectionById('pages')!;
      await tester.pumpWidget(_app(
        DocEditor(
          title: 'صفحة تجربة',
          fields: def.fields,
          def: def,
          data: const {'titleAr': 'صفحة تجربة', 'slug': 'tajriba'},
          popOnSave: false,
          onSave: (d) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field-placement')));
      await tester.pumpAndSettle();
      expect(find.text('لينك بس'), findsWidgets);
      expect(find.text('الصفحة ليها لينك، ومش ظاهرة في القوايم.'), findsOneWidget);
      expect(find.text('في القايمة'), findsWidgets);
      expect(find.text('تظهر في قايمة الموقع.'), findsOneWidget);
      expect(find.text('جوه قسم'), findsWidgets);
      expect(find.text('تظهر جوه قسم تختاره.'), findsOneWidget);
    });
  });

  group('DocEditor edits', () {
    testWidgets('saving an existing doc writes only the edited field', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      final def = collectionById('milestones')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Edit',
        fields: def.fields,
        def: def,
        data: const {'titleAr': 'قديم', 'year': 1980, 'visible': false, 'order': 1},
        docId: 'm1',
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('No changes to save'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-titleAr')), 'جديد');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, {'titleAr': 'جديد'}); // visible:false is not written back
    });
  });

  group('FeaturesEditor widget', () {
    testWidgets('switching a section off and saving writes the flag', (tester) async {
      // Tall enough for the theme chips below the sections card (it grew with
      // the ADR-052 sub-switch), clear of the floating Save button.
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FeatureSettings? saved;
      await tester.pumpWidget(_app(Scaffold(
        body: FeaturesEditor(initial: FeatureSettings.defaults, onSave: (f) async => saved = f),
      )));
      final meetingsSwitch = find.descendant(
          of: find.byKey(const ValueKey('section-meetings')), matching: find.byType(Switch));
      await tester.tap(meetingsSwitch);
      await tester.tap(find.byKey(const ValueKey('theme-navy')));
      await tester.enterText(find.byKey(const ValueKey('features-bannerEn')), 'Christmas times are out');
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.enabled(Sections.meetings), isFalse);
      expect(saved!.enabled(Sections.schedule), isTrue);
      expect(saved!.theme, 'navy');
      expect(saved!.bannerEn, 'Christmas times are out');
    });

    testWidgets('rejects an invalid banner link', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FeatureSettings? saved;
      await tester.pumpWidget(_app(Scaffold(
        body: FeaturesEditor(initial: FeatureSettings.defaults, onSave: (f) async => saved = f),
      )));
      await tester.enterText(find.byKey(const ValueKey('features-bannerLink')), 'not a link');
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
    });
  });

  group('PR #12: page headers & footer (FR-G-04) in FeaturesEditor', () {
    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder page(String p, String k) => find.byKey(ValueKey('features-page-$p-$k'));

    testWidgets('edits a page header, resets another and keeps the rest', (tester) async {
      await tall(tester);
      FeatureSettings? saved;
      final initial = FeatureSettings.defaults.copyWith(pageHeaders: {
        'ask': const PageCustom(titleEn: 'Ask us', introAr: 'مقدمة'),
        'about': const PageCustom(subtitleAr: 'تاريخنا'),
      });
      await tester.pumpWidget(_app(Scaffold(body: FeaturesEditor(initial: initial, onSave: (f) async => saved = f))));
      await tester.pumpAndSettle();
      for (final p in CustomizablePages.all) {
        expect(find.byKey(ValueKey('page-$p')), findsOneWidget, reason: p);
      }
      expect(find.byKey(const ValueKey('pageCustomized-ask')), findsOneWidget);
      expect(find.byKey(const ValueKey('pageCustomized-about')), findsOneWidget);
      expect(find.byKey(const ValueKey('pageCustomized-education')), findsNothing);
      expect(find.text('Customized'), findsNWidgets(2));
      // Collapsed rows keep their fields mounted.
      expect(page('education', 'titleEn'), findsNothing);
      expect(page('education', 'titleEn').hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-education')));
      await tester.pumpAndSettle();
      await tester.enterText(page('education', 'titleEn'), 'Our education');
      await tester.enterText(page('education', 'introAr'), 'اجتماعات الكنيسة');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageCustomized-education')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pageReset-ask')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageCustomized-ask')), findsNothing);
      expect(find.byKey(const ValueKey('pageReset-ask')), findsNothing, reason: 'nothing left to reset');
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.pageHeaders.keys, ['about', 'education']);
      expect(saved!.pageHeader('education'), const PageCustom(titleEn: 'Our education', introAr: 'اجتماعات الكنيسة'));
      expect(saved!.pageHeader('about'), const PageCustom(subtitleAr: 'تاريخنا'));
      expect(saved!.toMap()['pageHeaders'], {
        'about': const PageCustom(subtitleAr: 'تاريخنا').toMap(),
        'education': const PageCustom(titleEn: 'Our education', introAr: 'اجتماعات الكنيسة').toMap(),
      });
    });

    testWidgets('page header lengths match the rules; an error opens its collapsed page', (tester) async {
      await tall(tester);
      FeatureSettings? saved;
      final initial = FeatureSettings.defaults.copyWith(pageHeaders: {'contact': PageCustom(introEn: 'x' * 1501)});
      await tester.pumpWidget(_app(Scaffold(body: FeaturesEditor(initial: initial, onSave: (f) async => saved = f))));
      await tester.pumpAndSettle();
      expect(page('contact', 'introEn').hitTestable(), findsNothing);
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(page('contact', 'introEn').hitTestable(), findsOneWidget);
      expect(find.text('Too long'), findsOneWidget);
      await tester.enterText(page('contact', 'introEn'), 'x' * 1500);
      await tester.enterText(page('contact', 'titleAr'), 'ع' * 201);
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(page('contact', 'titleAr'), 'ع' * 200);
      await tester.enterText(page('contact', 'subtitleEn'), 's' * 300);
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.pageHeader('contact').introEn.length, 1500);
    });

    testWidgets('footer switches and notes round-trip', (tester) async {
      await tall(tester);
      FeatureSettings? saved;
      final initial = FeatureSettings.defaults.copyWith(footer: const FooterConfig(showSocials: false, noteEn: 'Old'));
      await tester.pumpWidget(_app(Scaffold(body: FeaturesEditor(initial: initial, onSave: (f) async => saved = f))));
      await tester.pumpAndSettle();
      Switch sw(String k) => tester.widget<Switch>(
          find.descendant(of: find.byKey(ValueKey('footer-$k')), matching: find.byType(Switch)));
      expect([sw('showPhones').value, sw('showSocials').value, sw('showQuickLinks').value], [true, false, true]);
      await tester.tap(find.byKey(const ValueKey('footer-showPhones')));
      await tester.tap(find.byKey(const ValueKey('footer-showSocials')));
      await tester.enterText(find.byKey(const ValueKey('footer-noteAr')), 'جميع الخدمات مجانية');
      await tester.enterText(find.byKey(const ValueKey('footer-noteEn')), 'x' * 501);
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: 'note over 500 chars');
      await tester.enterText(find.byKey(const ValueKey('footer-noteEn')), '  All services are free  ');
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.footer.toMap(), {
        'showPhones': false,
        'showSocials': true,
        'showQuickLinks': true,
        'noteAr': 'جميع الخدمات مجانية',
        'noteEn': 'All services are free',
      });
    });

    test('the page headers are saved in their own write, only when they changed', () {
      const ask = PageCustom(titleEn: 'Ask us');
      final next = FeatureSettings.defaults.copyWith(pageHeaders: {'ask': ask}, theme: 'navy');
      final stored = {...FeatureSettings.defaults.toMap(), 'pageHeaders': {'ask': ask.toMap()}};
      final writes = featuresSaveWrites(next, stored);
      expect(writes, hasLength(1));
      expect(writes.single.keys, isNot(contains('pageHeaders')));
      expect(writes.single['theme'], 'navy');
      expect(writes.single['footer'], const FooterConfig().toMap());
      // Changed, missing in the stored doc, or no doc yet: a second write.
      final changed = featuresSaveWrites(FeatureSettings.defaults, stored);
      expect(changed.last, {'pageHeaders': <String, dynamic>{}});
      expect(featuresSaveWrites(next, FeatureSettings.defaults.toMap()..remove('pageHeaders')).last, {
        'pageHeaders': {'ask': ask.toMap()}
      });
      expect(featuresSaveWrites(next, null), hasLength(2));
      // Blank stored entries read as "not customised".
      final blank = {...stored, 'pageHeaders': {'ask': ask.toMap(), 'about': PageCustom.empty.toMap()}};
      expect(featuresSaveWrites(next, blank), hasLength(1));
    });

    testWidgets('collect() round-trips every stored page header and the footer unchanged', (tester) async {
      await tall(tester);
      final initial = FeatureSettings.defaults.copyWith(
        pageHeaders: {
          for (final p in CustomizablePages.all)
            p: PageCustom(titleAr: 'ع $p', titleEn: 'T $p', subtitleAr: 'س', subtitleEn: 'S', introAr: 'م', introEn: 'I'),
        },
        footer: const FooterConfig(showPhones: false, showQuickLinks: false, noteAr: 'م', noteEn: 'N'),
      );
      await tester.pumpWidget(_app(Scaffold(body: FeaturesEditor(initial: initial, onSave: (f) async {}))));
      await tester.pumpAndSettle();
      final state = tester.state<FeaturesEditorState>(find.byType(FeaturesEditor));
      expect(sameValue(state.collect().toMap(), initial.toMap()), isTrue);
      expect(state.dirty, isFalse);
    });
  });

  group('PR #10: selected chip contrast & narrow 200% reflow', () {
    testWidgets('selected theme ChoiceChip and weekday FilterChip use a white label', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Scaffold(
        body: FeaturesEditor(initial: FeatureSettings.defaults, onSave: (f) async {}),
      )));
      final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('theme-goldenHour')));
      expect(chip.selected, isTrue);
      expect(chip.labelStyle?.color, Colors.white);
      expect(contrastRatio(Colors.white, AppColors.burgundy), greaterThanOrEqualTo(4.5));

      final def = CollectionDef('days_test', 'أيام', 'Days', [
        FieldDef('days', 'الأيام', 'Days', FieldType.weekdays),
      ], ['days']);
      await tester.pumpWidget(_app(DocEditor(
        title: 'Days',
        fields: def.fields,
        def: def,
        data: const {'days': [5]},
        popOnSave: false,
        onSave: (d) async {},
      )));
      await tester.pumpAndSettle();
      final friday = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Friday'));
      expect(friday.selected, isTrue);
      expect(friday.labelStyle?.color, Colors.white);
      expect(friday.checkmarkColor, Colors.white);
    });

    testWidgets('FeaturesEditor at 320 px x 200% text: no overflow, move buttons still tappable', (tester) async {
      tester.view.physicalSize = const Size(320, 4000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      FeatureSettings? saved;
      await tester.pumpWidget(_app(Scaffold(
        body: FeaturesEditor(initial: FeatureSettings.defaults, onSave: (f) async => saved = f),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final down = find.byKey(const ValueKey('home-banner-down'));
      await tester.scrollUntilVisible(down, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-banner-up')), findsOneWidget);
      await tester.tap(down);
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(saved!.homeOrder.indexOf('banner'), 1);
      // PR #12: an open page-header row and the footer card reflow too.
      final pageRow = find.byKey(const ValueKey('page-education'));
      await tester.scrollUntilVisible(pageRow, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(pageRow);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('footer-noteEn')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DocEditor image field at 320 px x 200% text: no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final def = collectionById('priests')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Priest',
        fields: def.fields,
        def: def,
        popOnSave: false,
        onSave: (d) async {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final media = find.byKey(const ValueKey('group-media'));
      await tester.scrollUntilVisible(media, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(media);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('imageUploadBtn')), findsOneWidget);
    });
  });

  group('confirmDiscardChanges', () {
    testWidgets('shows «متابعة التعديل» as FilledButton and «تجاهل» as TextButton', (tester) async {
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await confirmDiscardChanges(ctx),
          child: const Text('Open'),
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
      expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('discard-keep'))), isNotNull);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('discard-confirm'))), isNotNull);

      await tester.tap(find.byKey(const ValueKey('discard-keep')));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('UnsavedGuard', () {
    testWidgets('in DocEditor intercepts pop when dirty and asks to discard', (tester) async {
      final def = collectionById('priests')!;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DocEditor(
                title: 'Priest',
                fields: def.fields,
                def: def,
                popOnSave: true,
                onSave: (_) async {},
              ),
            ));
          },
          child: const Text('Open'),
        );
      })));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);

      // Make dirty
      await tester.enterText(find.byKey(const Key('field-name')), 'Fr. Test');
      await tester.pump();

      // Attempt to pop
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.maybePop();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
      // Tap keep editing -> remains on page
      await tester.tap(find.byKey(const ValueKey('discard-keep')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);

      // Attempt to pop again and confirm discard
      nav.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsNothing);
    });

    testWidgets('side menu switch in AdminDashboard asks if dirty', (tester) async {
      tester.view.physicalSize = const Size(1200, 2500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialDocs: {
        'settings/church': {'nameAr': 'كنيسة'},
      });
      await tester.pumpWidget(ProviderScope(
        child: _app(AdminDashboard(
          repo: repo,
          uid: 'u1',
          email: 'test@church.org',
          role: AdminRoles.owner,
          onSignOut: () {},
          initial: 'church',
        )),
      ));
      await tester.pumpAndSettle();

      // Make dirty
      await tester.enterText(find.byKey(const Key('field-nameAr')), 'كنيسة جديدة');
      await tester.pump();

      // Tap another nav item (e.g. Priests)
      await tester.tap(find.byKey(const ValueKey('nav-priests')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
      // Cancel -> remains on church
      await tester.tap(find.byKey(const ValueKey('discard-keep')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('field-nameAr')), findsOneWidget);

      // Tap again and discard -> switches to Priests
      await tester.tap(find.byKey(const ValueKey('nav-priests')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionListScreen), findsOneWidget);
    });
  });

  group('PendingDelete', () {
    test('schedule, undo within window, expiry and dispose', () async {
      final pd = PendingDelete(window: const Duration(milliseconds: 100));
      int commits = 0;
      pd.schedule('item1', () async => commits++);
      expect(pd.hasPending, isTrue);
      expect(pd.pendingIds, {'item1'});
      expect(pd.isPending('item1'), isTrue);

      // Undo removes and cancels commit
      expect(pd.undo('item1'), isTrue);
      expect(pd.hasPending, isFalse);
      expect(pd.pendingIds, isEmpty);
      expect(pd.isPending('item1'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(commits, 0);

      // Expiry runs commit
      pd.schedule('item2', () async => commits++);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(commits, 1);
      expect(pd.hasPending, isFalse);

      // Dispose cancels local timers without committing
      pd.schedule('item4', () async => commits++);
      expect(pd.hasPending, isTrue);
      pd.dispose();
      expect(pd.hasPending, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(commits, 1);
    });

    test('holdCount ref-counts overlapping holds', () {
      fakeAsync((async) {
        final pd = PendingDelete(window: const Duration(milliseconds: 120));
        final committed = <String>[];

        // Overlapping holdAll / releaseHold ref-counts holds cleanly across concurrent renewals.
        pd.schedule('x', () async => committed.add('x'));
        async.elapse(const Duration(milliseconds: 80));
        pd.holdAll(['x']); // hold #1
        pd.holdAll(['x']); // hold #2
        async.elapse(const Duration(milliseconds: 60)); // original deadline passes while held
        expect(committed.contains('x'), isFalse);

        // First renewal finishes without extending -> x MUST stay held because hold #2 is still active.
        unawaited(pd.releaseHold('x', extend: false));
        async.flushMicrotasks();
        expect(committed.contains('x'), isFalse);

        // Second renewal releases without extending -> expiredWhileHeld triggers immediate commit.
        unawaited(pd.releaseHold('x', extend: false));
        async.flushMicrotasks();
        expect(committed, contains('x'));

        // Stale hold token acquired before undo must never release or commit a replacement entry.
        pd.schedule('y', () async => committed.add('y1'));
        final staleTokens = pd.holdAll(['y']);
        pd.undo('y');
        pd.schedule('y', () async => committed.add('y2'));
        final freshTokens = pd.holdAll(['y']);
        async.elapse(const Duration(milliseconds: 120)); // replacement expires while held by freshTokens
        unawaited(pd.releaseHold('y', extend: false, token: staleTokens['y']));
        async.flushMicrotasks();
        expect(committed.contains('y2'), isFalse);
        unawaited(pd.releaseHold('y', extend: false, token: freshTokens['y']));
        async.flushMicrotasks();
        expect(committed, contains('y2'));

        // Anchor timer aligns successful renewal expiry with hold acquisition (backend deletedAt + window),
        // and commits immediately if the anchor already elapsed during a slow renewal (window = 120ms).
        pd.schedule('z', () async => committed.add('z'));
        async.elapse(const Duration(milliseconds: 50));
        final zHold = pd.holdAll(['z']); // anchor deadline = +120ms from now (t+170ms)
        async.elapse(const Duration(milliseconds: 80)); // original t+120ms elapsed; anchor still has 40ms left
        unawaited(pd.releaseHold('z', extend: true, token: zHold['z']));
        async.flushMicrotasks();
        expect(committed.contains('z'), isFalse);
        async.elapse(const Duration(milliseconds: 35)); // 5ms before anchor deadline
        expect(committed.contains('z'), isFalse);
        async.elapse(const Duration(milliseconds: 10)); // crosses anchor deadline -> commits at backend deadline
        expect(committed, contains('z'));

        pd.schedule('w', () async => committed.add('w'));
        final wHold = pd.holdAll(['w']);
        async.elapse(const Duration(milliseconds: 130)); // slow RPC finishes AFTER 120ms anchor elapsed
        unawaited(pd.releaseHold('w', extend: true, token: wHold['w']));
        async.flushMicrotasks();
        expect(committed, contains('w'));

        // Adopted anchor timer stays active across subsequent failed renewals:
        // (a) H1 succeeds -> adopts H1's 120ms anchor; H2 starts then fails BEFORE anchor expires -> commits at H1 anchor.
        pd.schedule('a', () async => committed.add('a'));
        final aHold1 = pd.holdAll(['a']);
        async.elapse(const Duration(milliseconds: 50));
        unawaited(pd.releaseHold('a', extend: true, token: aHold1['a'])); // ~70ms remaining
        async.flushMicrotasks();
        expect(committed.contains('a'), isFalse);
        final aHold2 = pd.holdAll(['a']);
        async.elapse(const Duration(milliseconds: 20)); // ~50ms remaining on H1 anchor
        unawaited(pd.releaseHold('a', extend: false, token: aHold2['a']));
        async.flushMicrotasks();
        expect(committed.contains('a'), isFalse);
        async.elapse(const Duration(milliseconds: 45)); // 5ms before H1 anchor deadline
        expect(committed.contains('a'), isFalse);
        async.elapse(const Duration(milliseconds: 10)); // crosses H1 anchor deadline
        expect(committed, contains('a'));

        // (b) H1 succeeds -> adopts H1's 120ms anchor; H2 spans PAST H1's anchor deadline then fails -> commits on release.
        pd.schedule('b', () async => committed.add('b'));
        final bHold1 = pd.holdAll(['b']);
        async.elapse(const Duration(milliseconds: 50));
        unawaited(pd.releaseHold('b', extend: true, token: bHold1['b'])); // ~70ms remaining
        async.flushMicrotasks();
        final bHold2 = pd.holdAll(['b']);
        async.elapse(const Duration(milliseconds: 90)); // H1 anchor expires while held by H2
        async.flushMicrotasks();
        expect(committed.contains('b'), isFalse);
        unawaited(pd.releaseHold('b', extend: false, token: bHold2['b']));
        async.flushMicrotasks();
        expect(committed, contains('b'));
      });
    });

    testWidgets('_syncUndoBarAfterExpiry preserves newer SnackBar when slow delete completes after undo expiry',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'visible': true, 'order': 20}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final delHold = repo.holdDelete('saints', 's1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      expect(find.text('تراجع'), findsOneWidget);

      // Let the 10 s undo bar expire while repo.delete is still in flight.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('تراجع'), findsNothing);

      // Show a fresh informational visibility SnackBar before delHold completes.
      await tester.tap(find.byKey(const ValueKey('visibility-s2')));
      await tester.pump();
      expect(find.text('أصبح العنصر مخفيًا'), findsOneWidget);

      delHold.complete();
      await tester.pumpAndSettle();
      expect(find.text('أصبح العنصر مخفيًا'), findsOneWidget);

      // Failed commit also syncs the Undo bar state cleanly before surfacing the error SnackBar.
      final failHold = repo.holdDelete('saints', 's2');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();
      expect(find.text('تراجع'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      failHold.completeError(StateError('delete failed'));
      await tester.pumpAndSettle();
      expect(find.text('تراجع'), findsNothing);
      expect(find.textContaining('delete failed'), findsOneWidget);
    });

    testWidgets('slow batch renewal aligns with backend deletedAt and deferred visibility error survives Undo refresh',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'visible': true, 'order': 20}),
          AdminDoc('s3', {'nameAr': 'مارمينا', 'visible': true, 'order': 30}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Delete s1 at t=0, advance 2s, then delete s2 at t=2s while holding s1's renewal.
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final s1Renew = repo.hold('saints', 's1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();

      // Fail a visibility toggle on s3 while Undo bar is active -> deferred error survives bar refresh.
      final visFail = repo.hold('saints', 's3');
      await tester.tap(find.byKey(const ValueKey('visibility-s3')));
      await tester.pump();
      visFail.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Denied'));
      await tester.pump();

      // Complete s1's renewal at t=11s -> anchor deadline from t=2s (+10s) expires at t=12s (aligned with s2).
      await tester.pump(const Duration(seconds: 9));
      s1Renew.complete();
      await tester.pump();
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Advance past t=12s -> both s1 and s2 commit together at backend deadline, and deferred error surfaces!
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, containsAll(['saints/s1', 'saints/s2']));
      expect(find.textContaining('permission-denied'), findsOneWidget);
    });

    testWidgets('deferred visibility error flushes immediately when Undo closes even if restore write stalls',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'visible': true, 'order': 20}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('تراجع'), findsOneWidget);

      final visFail = repo.hold('saints', 's2');
      await tester.tap(find.byKey(const ValueKey('visibility-s2')));
      await tester.pump();
      visFail.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Denied'));
      await tester.pump();
      expect(find.textContaining('permission-denied'), findsNothing);

      final restoreHold = repo.hold('saints', 's1');
      await tester.tap(find.text('تراجع'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('permission-denied'), findsOneWidget);

      restoreHold.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('refreshing Undo bar preserves queued SnackBar and failed batch commit errors', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'visible': true, 'order': 20}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Delete s1 at t=0, then delete s2 at t=5s with s1's renewal held & failing so s1 expires at t=10s
      // (calling _syncUndoBarAfterExpiry -> _presentUndoSnackBar(clearQueue: false)) while s2 stays until t=15s.
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      final s1Renew = repo.hold('saints', 's1');
      final s1DelHold = repo.holdDelete('saints', 's1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      s1Renew.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Offline'));
      await tester.pump();

      final scaffoldCtx = tester.element(find.byType(FloatingActionButton));
      ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
        const SnackBar(content: Text('Queued external note'), duration: Duration(seconds: 2)),
      );
      await tester.pump();

      // Advance to t=10s so s1 attempts commit and fails -> _syncUndoBarAfterExpiry refreshes Undo
      // with clearQueue: false, preserving both Queued external note and s1's deferred commit error.
      await tester.pump(const Duration(seconds: 5));
      s1DelHold.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'aborted', message: 'Aborted'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Queued external note'), findsOneWidget);

      // After Queued external note (2s) and s2 expiry (t=15s), deferred s1 aborted error surfaces too.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(repo.deletedIds, contains('saints/s2'));
      expect(find.textContaining('aborted'), findsOneWidget);
    });

    testWidgets('CollectionListScreen multi-delete extends batch window so undoAll at 12s restores both items', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'order': 20}),
        ],
      });
      final def = collectionById('saints')!;
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Delete s1 at t = 0
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      expect(find.text('مارمرقس'), findsNothing);

      // Advance 6s, then delete s2
      await tester.pump(const Duration(seconds: 6));
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Advance 6s (t = 12s since s1 delete, 6s since s2 delete): neither committed yet!
      await tester.pump(const Duration(seconds: 6));
      expect(repo.deletedIds, isEmpty);
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Tap Undo all at t = 12s -> restores both items cleanly
      await tester.tap(find.text('تراجع عن الكل'));
      await tester.pumpAndSettle();
      expect(find.text('مارمرقس'), findsOneWidget);
      expect(find.text('مارجرجس'), findsOneWidget);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's1').data), isFalse);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's2').data), isFalse);

      // Wait another 12s -> neither hard-deleted
      await tester.pump(const Duration(seconds: 12));
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('CollectionListScreen 10s undo SnackBar, soft-delete immediately, undo restores row, expiry commits, lazy purge on dispose', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'order': 20}),
        ],
      });
      final def = collectionById('saints')!;
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('مارمرقس'), findsOneWidget);

      // Delete s1: immediately marked with deletedAt, hidden from UI
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Immediately hidden and soft-deleted
      expect(find.text('مارمرقس'), findsNothing);
      expect(repo.deletedIds, isEmpty);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's1').data), isTrue);
      expect(find.text('تم مسح «مارمرقس»'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      // Tap Undo -> restores row and clears deletedAt
      await tester.tap(find.byType(SnackBarAction));
      await tester.pump();
      expect(find.text('مارمرقس'), findsOneWidget);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's1').data), isFalse);
      expect(repo.deletedIds, isEmpty);

      // Delete s1 again and wait 10s -> commits hard delete
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('مارمرقس'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, contains('saints/s1'));

      // Delete s2 and unmount/dispose -> cancels local timers, doc remains soft-deleted, lazy purge purges it
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(repo.deletedIds.contains('saints/s2'), isFalse);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's2').data), isTrue);

      // Unmount CollectionListScreen
      await tester.pumpWidget(_app(
        const SizedBox.shrink(),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      // Dispose cancels without running fire-and-forget delete
      expect(repo.deletedIds.contains('saints/s2'), isFalse);

      // Lazy purge on expired soft delete purges it deterministically
      await purgeExpiredSoftDeletes(
        repo,
        def,
        repo.collections['saints']!,
        clock: () => DateTime.now().toUtc().add(const Duration(seconds: 15)),
      );
      expect(repo.deletedIds, contains('saints/s2'));
    });

    testWidgets('CollectionListScreen pending-delete item slug remains in takenSlugs for new docs', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'pages': [
          AdminDoc('p1', {'titleAr': 'عن الكنيسة', 'slug': 'about-church', 'visible': true}),
        ],
      });
      final def = collectionById('pages')!;
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('عن الكنيسة'), findsOneWidget);

      // Delete p1 (starts 10s undo window)
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('عن الكنيسة'), findsNothing);

      // Open editor for a new page
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addPage-blank')));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);

      // Expand «متقدم» and enter the slug of the pending-deleted page
      await tester.tap(find.byKey(const ValueKey('group-advanced')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('field-slug')), 'about-church');
      await tester.pump();

      // Should be rejected as already taken
      expect(find.text('هذا الرابط مستخدم بالفعل'), findsOneWidget);
    });

    testWidgets('PendingDelete in CollectionListScreen captures original repo and def on commit', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo1 = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'order': 10}),
        ],
      });
      final repo2 = _TestAdminBackend();
      final defSaints = collectionById('saints')!;
      final defPriests = collectionById('priests')!;

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo1, def: defSaints),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Delete s1
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();

      // Swap widget to repo2 / defPriests before commit
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo2, def: defPriests),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Wait 10s for scheduled commit on original repo1 and defSaints
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      // s1 commit should have deleted from original repo1 and defSaints
      expect(repo1.deletedIds, contains('saints/s1'));
      expect(repo2.deletedIds, isEmpty);
    });

    test('purgeExpiredSoftDeletes purges only expired docs, respects isLocalPending and purging set', () async {
      final now = DateTime.utc(2026, 11, 14, 12, 0, 0);
      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('fresh', {'nameAr': 'مارمرقس', 'deletedAt': now.subtract(const Duration(seconds: 4))}),
          AdminDoc('expired', {'nameAr': 'مارجرجس', 'deletedAt': now.subtract(const Duration(seconds: 12))}),
          AdminDoc('pending', {'nameAr': 'الأنبا أنطونيوس', 'deletedAt': now.subtract(const Duration(seconds: 15))}),
          AdminDoc('in_flight', {'nameAr': 'الأنبا بولا', 'deletedAt': now.subtract(const Duration(seconds: 20))}),
        ],
      });
      final def = collectionById('saints')!;
      final purging = <String>{'in_flight'};

      await purgeExpiredSoftDeletes(
        repo,
        def,
        repo.collections['saints']!,
        clock: () => now,
        isLocalPending: (id) => id == 'pending',
        purging: purging,
      );

      // Only 'expired' was purged
      expect(repo.deletedIds, ['saints/expired']);
      expect(repo.collections['saints']!.map((d) => d.id), containsAll(['fresh', 'pending', 'in_flight']));
    });

    testWidgets('consecutive deletes refresh backend deletedAt so other admin screens do not early-purge extended items',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارجرجس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارمرقس', 'visible': true, 'order': 20}),
        ],
      });
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      final t0 = repo.updates.firstWhere((u) => u.id == 's1').data['deletedAt'] as DateTime;

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();
      final s1Updates = repo.updates.where((u) => u.id == 's1' && u.data['deletedAt'] != null).toList();
      expect(s1Updates.length, greaterThanOrEqualTo(2));
      final t1 = s1Updates.last.data['deletedAt'] as DateTime;
      expect(t1.isAfter(t0), isTrue);
      expect(isExpiredSoftDelete({'deletedAt': t1}, t0.add(const Duration(seconds: 10))), isFalse);
    });

    testWidgets('held or failed prior deletedAt refresh protects before expiry and never falsely extends failed items',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Part 1: Held prior renewal never blocks B's immediate Undo bar, protects s1 past t=10s
      // while held, and commits s1 if renewal fails after original deadline while updating Undo bar.
      final repo = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارجرجس', 'visible': true, 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارمرقس', 'visible': true, 'order': 20}),
          AdminDoc('s3', {'nameAr': 'مارمينا', 'visible': true, 'order': 30}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Trigger an informational visibility SnackBar, then immediately delete s1:
      // Undo SnackBar must clear/preempt queued info SnackBars immediately.
      await tester.tap(find.byKey(const ValueKey('visibility-s3')));
      await tester.pump();
      expect(find.text('أصبح العنصر مخفيًا'), findsOneWidget);

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('تراجع'), findsOneWidget);
      expect(find.text('أصبح العنصر مخفيًا'), findsNothing);

      await tester.pump(const Duration(seconds: 8));

      final refreshHold = repo.hold('saints', 's1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Undo action for s2 is shown immediately without waiting for s1's renewal.
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3)); // t = 11 s > original 10 s window, refresh still held!
      expect(repo.deletedIds.contains('saints/s1'), isFalse);

      // Failing after original expiry commits s1 cleanly and updates the SnackBar from "undoAll" to "undo".
      refreshHold.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Offline'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, contains('saints/s1'));
      expect(find.text('تراجع عن الكل'), findsNothing);
      expect(find.text('تراجع'), findsOneWidget);

      // Part 2: Failing renewal BEFORE original expiry (s2 at t=0, s3 at t=2s) keeps s2
      // recoverable until t=10s (no premature commit at t=2s), shows "تراجع عن الكل" while both
      // remain recoverable, and shrinks back to single-item "تراجع" once s2 expires at t=10s.
      await tester.pump(const Duration(seconds: 2));
      final s2Fail = repo.hold('saints', 's2');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-s3')));
      await tester.pump();
      s2Fail.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Offline'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds.contains('saints/s2'), isFalse);
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // +8.5 s from s3 delete -> s2 expires (> 10 s), commits, and SnackBar shrinks to single "تراجع" for s3.
      await tester.pump(const Duration(seconds: 8, milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.deletedIds, contains('saints/s2'));
      expect(repo.deletedIds.contains('saints/s3'), isFalse);
      expect(find.text('تراجع عن الكل'), findsNothing);
      expect(find.text('تراجع'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(repo.deletedIds, contains('saints/s3'));
    });

    test('overlapping holds keep newest extending anchor across out-of-order releases and undo cancels extendingHold timer', () {
      fakeAsync((async) {
        final pd = PendingDelete(window: const Duration(milliseconds: 120));
        final committed = <String>[];
        pd.schedule('a', () async => committed.add('a'));

        final h1 = pd.holdAll(['a']); // anchor fires at t = 120ms
        async.elapse(const Duration(milliseconds: 50));
        final h2 = pd.holdAll(['a']); // anchor fires at t = 170ms

        // Out-of-order: newer h2 finishes first, older h1 finishes second -> newer h2 (170ms) MUST win.
        unawaited(pd.releaseHold('a', extend: true, token: h2['a']));
        async.flushMicrotasks();
        unawaited(pd.releaseHold('a', extend: true, token: h1['a']));
        async.flushMicrotasks();

        // Cross older h1 deadline (t = 130ms): must NOT commit yet!
        async.elapse(const Duration(milliseconds: 80));
        expect(committed, isEmpty);

        // Cross newer h2 deadline (t = 175ms): commits cleanly.
        async.elapse(const Duration(milliseconds: 45));
        expect(committed, ['a']);

        // Undo while extendingHold is already stored cancels its anchor timer cleanly (zero pending timers).
        pd.schedule('b', () async => committed.add('b'));
        final b1 = pd.holdAll(['b']);
        final b2 = pd.holdAll(['b']);
        unawaited(pd.releaseHold('b', extend: true, token: b1['b']));
        async.flushMicrotasks();
        expect(pd.undo('b'), isTrue);
        expect(b2['b'], isNotNull);
        async.elapse(const Duration(milliseconds: 200));
        expect(committed, ['a']);
      });
    });

    testWidgets('3 rapid deletes on liturgies -> undoAll restores all 3 atomically with 0 Firestore delete writes', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {'type': 'mass', 'nameAr': 'قداس أول', 'weekday': 7, 'start': '07:00', 'visible': true}),
          AdminDoc('l2', {'type': 'mass', 'nameAr': 'قداس ثاني', 'weekday': 7, 'start': '09:00', 'visible': true}),
          AdminDoc('l3', {'type': 'vespers', 'nameAr': 'عشية', 'weekday': 6, 'start': '18:00', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Hold the 3rd delete write & prior renewal to simulate real Firestore network latency (~2s burst).
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l1')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('قداس أول'), findsNothing);
      expect(find.text('تراجع'), findsOneWidget);

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l2')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('قداس ثاني'), findsNothing);
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      final l3WriteHold = repo.hold('liturgies', 'l3');
      final l1RenewHold = repo.hold('liturgies', 'l1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l3')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('عشية'), findsNothing);
      expect(find.textContaining('تم مسح 3 عناصر'), findsOneWidget);
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Tap "تراجع عن الكل" while l3's initial write & l1's renewal are still in flight!
      await tester.tap(find.text('تراجع عن الكل'));
      await tester.pump();

      // All 3 rows return immediately in UI, and bar NEVER falls back to single-item undo.
      expect(find.text('قداس أول'), findsOneWidget);
      expect(find.text('قداس ثاني'), findsOneWidget);
      expect(find.text('عشية'), findsOneWidget);
      expect(find.text('تراجع'), findsNothing);
      expect(find.text('تراجع عن الكل'), findsNothing);

      // Settle the in-flight writes -> restore writes clear deletedAt on all 3 and never re-open an Undo bar.
      l3WriteHold.complete();
      l1RenewHold.complete();
      await tester.pumpAndSettle();

      expect(find.text('تراجع'), findsNothing);
      expect(find.text('تراجع عن الكل'), findsNothing);
      for (final id in ['l1', 'l2', 'l3']) {
        final doc = repo.collections['liturgies']!.firstWhere((d) => d.id == id);
        expect(isSoftDeleted(doc.data), isFalse, reason: '$id should have deletedAt cleared');
      }
      expect(repo.deletedIds, isEmpty);

      // Wait well past the 10s grace window -> still ZERO Firestore delete writes.
      await tester.pump(const Duration(seconds: 15));
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('2 deletes on liturgies -> undoAll 8s after first delete restores both with 0 Firestore delete writes', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {'type': 'mass', 'nameAr': 'قداس أول', 'weekday': 7, 'start': '07:00', 'visible': true}),
          AdminDoc('l2', {'type': 'mass', 'nameAr': 'قداس ثاني', 'weekday': 7, 'start': '09:00', 'visible': true}),
        ],
      });

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Delete l1 at t = 0s, then delete l2 at t = 2s.
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l1')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l2')));
      await tester.pump();
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Advance to t = 8s from first delete (6s after second delete): both still pending, 0 delete writes.
      await tester.pump(const Duration(seconds: 6));
      expect(repo.deletedIds, isEmpty);
      expect(find.text('تراجع عن الكل'), findsOneWidget);

      // Tap "تراجع عن الكل" at t = 8s -> restores both cleanly with 0 delete writes.
      await tester.tap(find.text('تراجع عن الكل'));
      await tester.pumpAndSettle();
      expect(find.text('قداس أول'), findsOneWidget);
      expect(find.text('قداس ثاني'), findsOneWidget);
      expect(isSoftDeleted(repo.collections['liturgies']!.firstWhere((d) => d.id == 'l1').data), isFalse);
      expect(isSoftDeleted(repo.collections['liturgies']!.firstWhere((d) => d.id == 'l2').data), isFalse);
      expect(repo.deletedIds, isEmpty);

      await tester.pump(const Duration(seconds: 15));
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('FAB stays >=48px above Undo SnackBar and ignores stray follow-up taps at vacated Undo spot (desktop & 342px)', (tester) async {
      for (final size in const [Size(1100, 800), Size(342, 700)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final repo = _TestAdminBackend(initialCollections: {
          'liturgies': [
            for (var i = 1; i <= 8; i++)
              AdminDoc('l$i', {
                'type': 'mass',
                'nameAr': 'قداس $i',
                'weekday': 7,
                'start': '07:00',
                'visible': true,
              }),
          ],
        });

        await tester.pumpWidget(_app(
          CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        final fabFinder = find.byType(FloatingActionButton);
        final restingFabRect = tester.getRect(fabFinder);

        // Delete 2 items -> FAB must sit clearly above Undo SnackBar (>= 48 px gap).
        await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l1')));
        await tester.pumpAndSettle();
        await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l2')));
        await tester.pumpAndSettle();

        final snackRect = tester.getRect(find.byType(SnackBar));
        final actionRect = tester.getRect(find.byType(SnackBarAction));
        final elevatedFabRect = tester.getRect(fabFinder);
        expect(elevatedFabRect.overlaps(snackRect), isFalse, reason: 'width=${size.width}');
        expect(elevatedFabRect.overlaps(actionRect), isFalse, reason: 'width=${size.width}');
        expect(snackRect.top - elevatedFabRect.bottom, greaterThanOrEqualTo(48.0),
            reason: 'FAB must keep >=48px gap above Undo SnackBar at width=${size.width}');

        // Record exact Undo button tap spot, tap Undo, then tap that same spot twice right after close.
        final undoSpot = actionRect.center;
        await tester.tapAt(undoSpot);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(SnackBar), findsNothing);

        // Follow-up taps at +100ms and +350ms MUST NOT hit the FAB or open an empty DocEditor!
        await tester.tapAt(undoSpot);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tapAt(undoSpot);
        await tester.pump();
        expect(find.byType(DocEditor), findsNothing,
            reason: 'Stray follow-up taps at vacated Undo spot must not open DocEditor (width=${size.width})');
        expect(tester.getRect(fabFinder).overlaps(actionRect), isFalse);

        // After the 650ms cooldown finishes, FAB returns cleanly to its resting position.
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect((tester.getRect(fabFinder).bottom - restingFabRect.bottom).abs(), lessThanOrEqualTo(1.0));

        // Scroll to the bottom -> _listBottomPadding still keeps last card's Delete button clear of FAB.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final lastDeleteRect = tester.getRect(find.byKey(const ValueKey('delete-l8')));
        final bottomFabRect = tester.getRect(fabFinder);
        expect(bottomFabRect.overlaps(lastDeleteRect), isFalse, reason: 'width=${size.width}');
        expect(lastDeleteRect.bottom, lessThanOrEqualTo(bottomFabRect.top - 4), reason: 'width=${size.width}');
      }
    });

    testWidgets('soft-delete writes deletedAt immediately with 0 repo.delete on 2s dispose/refresh; lazy purge runs only after 10s', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {'type': 'mass', 'nameAr': 'قداس الأحد', 'weekday': 7, 'start': '07:00', 'visible': true}),
        ],
      });
      final def = collectionById('liturgies')!;

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // t = 0s: soft-delete writes deletedAt via update, zero repo.delete calls.
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l1')));
      await tester.pump();
      expect(repo.deletedIds, isEmpty);
      expect(isSoftDeleted(repo.collections['liturgies']!.first.data), isTrue);

      // t = 2s: simulate page refresh (unmount/dispose + remount).
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(_app(const SizedBox.shrink(), locale: const Locale('ar')));
      await tester.pumpAndSettle();
      // dispose() cancels local timers without flushing repo.delete.
      expect(repo.deletedIds, isEmpty);

      // Remount at t = 2s: item remains hidden (soft-deleted) and still NOT hard-deleted.
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('قداس الأحد'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(repo.deletedIds, isEmpty);

      // Only once >=10s have elapsed since deletedAt does lazy purge hard-delete the doc.
      await purgeExpiredSoftDeletes(
        repo,
        def,
        repo.collections['liturgies']!,
        clock: () => DateTime.now().toUtc().add(const Duration(seconds: 12)),
      );
      expect(repo.deletedIds, ['liturgies/l1']);
    });

    testWidgets('_checkLazyPurge skips documents actively restoring during undo even if snapshot deletedAt expired', (tester) async {
      final repo = _ControlledUpdateBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {
            'type': 'mass',
            'nameAr': 'قداس الأحد',
            'weekday': 7,
            'start': '07:00',
            'end': '09:30',
            'visible': true,
          }),
        ],
      });
      addTearDown(repo.dispose);
      final def = collectionById('liturgies')!;

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Hold the soft-delete write so Undo must await it while _restoringIds is active.
      final holdSoft = repo.hold('liturgies', 'l1');
      await _confirmDeleteTap(tester, find.byKey(const ValueKey('delete-l1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Trigger Undo while soft-delete write is still unacknowledged.
      await tester.tap(find.widgetWithText(SnackBarAction, 'تراجع'));
      await tester.pump();

      // Simulate a rebuild receiving an expired deletedAt snapshot (>10s old) while
      // _undoAllPending is still awaiting the in-flight write / restore.
      repo.collections['liturgies']!.first.data['deletedAt'] =
          DateTime.now().toUtc().subtract(const Duration(seconds: 20));
      repo.emitSnapshot('liturgies');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must NOT hard-delete while restoring.
      expect(repo.deletedIds, isEmpty);
      expect(find.text('قداس الأحد'), findsOneWidget);

      // Hold the subsequent restore write as well and emit another expired snapshot.
      final holdRestore = repo.hold('liturgies', 'l1');
      holdSoft.complete();
      await tester.pump();
      repo.collections['liturgies']!.first.data['deletedAt'] =
          DateTime.now().toUtc().subtract(const Duration(seconds: 25));
      repo.emitSnapshot('liturgies');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.deletedIds, isEmpty);

      // Complete restore and verify zero hard-deletes and item restored cleanly.
      holdRestore.complete();
      await tester.pumpAndSettle();
      expect(repo.deletedIds, isEmpty);
      expect(find.text('قداس الأحد'), findsOneWidget);
      expect(repo.collections['liturgies']!.first.data['deletedAt'], isNull);
    });

    testWidgets('CollectionListScreen confirms named delete: cancel leaves untouched, confirm soft-deletes with 10s undo',
        (tester) async {
      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
        ],
      });
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-s1')));
      await tester.pumpAndSettle();

      // Dialog shows the item title and destructive confirmation action.
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('مارمرقس')), findsOneWidget);

      // Cancel closes the dialog with zero writes and zero Undo SnackBars.
      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.updates, isEmpty);
      expect(repo.deletedIds, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('مارمرقس'), findsOneWidget);

      // Tap delete again and confirm -> soft-deletes and shows 10s Undo SnackBar.
      await tester.tap(find.byKey(const ValueKey('delete-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(isSoftDeleted(repo.collections['saints']!.single.data), isTrue);
      expect(repo.deletedIds, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('تراجع'), findsOneWidget);

      // Tapping Undo restores the item cleanly.
      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(isSoftDeleted(repo.collections['saints']!.single.data), isFalse);
      expect(find.text('مارمرقس'), findsOneWidget);
    });

    testWidgets('CollectionListScreen custom-category sub-entry (_entryRow) requires named delete confirmation with 10s undo',
        (tester) async {
      final repo = _TestAdminBackend(initialCollections: {
        'categories': [
          AdminDoc('cat1', {'nameAr': 'قسم الشباب', 'slug': 'youth', 'visible': true, 'order': 10}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'cat1', 'titleAr': 'اجتماع الخدام', 'visible': true, 'order': 10}),
        ],
      });
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('deleteEntry-e1')));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('اجتماع الخدام')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
      await tester.pumpAndSettle();
      expect(repo.updates, isEmpty);
      expect(repo.deletedIds, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('اجتماع الخدام'), findsOneWidget);

      await _confirmDeleteTap(tester, find.byKey(const ValueKey('deleteEntry-e1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(isSoftDeleted(repo.collections['entries']!.single.data), isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('تراجع'), findsOneWidget);

      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(isSoftDeleted(repo.collections['entries']!.single.data), isFalse);
      expect(find.text('اجتماع الخدام'), findsOneWidget);
    });

    testWidgets('CollectionListScreen aborts delete if repository changes while confirmation dialog is open',
        (tester) async {
      final repo1 = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
        ],
      });
      final repo2 = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارجرجس', 'visible': true, 'order': 10}),
        ],
      });
      final def = collectionById('saints')!;

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo1, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-s1')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Swap underlying repo while dialog is open, then confirm.
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo2, def: def),
        locale: const Locale('ar'),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await tester.pumpAndSettle();

      expect(repo1.updates, isEmpty);
      expect(repo1.deletedIds, isEmpty);
      expect(repo2.updates, isEmpty);
      expect(repo2.deletedIds, isEmpty);
    });
  });

  group('UnsavedBar', () {
    testWidgets('hidden when clean, shown on edit in DocEditor, FeaturesEditor, ContactCategoriesScreen', (tester) async {
      final def = collectionById('priests')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Priest',
        fields: def.fields,
        def: def,
        popOnSave: false,
        onSave: (_) async {},
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);

      await tester.enterText(find.byKey(const Key('field-name')), 'Fr. New');
      await tester.pump();
      expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

      // Cancel reverts to clean
      await tester.tap(find.byKey(const ValueKey('unsaved-bar-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
    });

    testWidgets('UnsavedBar at 320 px in RTL Arabic & LTR English: zero overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final saving in const [false, true]) {
          await tester.pumpWidget(_app(
            Scaffold(
              bottomNavigationBar: UnsavedBar(
                dirty: true,
                saving: saving,
                onSave: () {},
                onCancel: () {},
              ),
            ),
            locale: locale,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);
          if (saving) {
            expect(find.text(locale.languageCode == 'ar' ? 'جارٍ الحفظ…' : 'Saving…'), findsOneWidget);
          }
        }
      }
    });

    testWidgets('delayed prepareImage completing after discard does not restore image or re-mark dirty', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fields = [
        FieldDef('name', 'الاسم', 'Name', FieldType.text),
        FieldDef('photo', 'الصورة', 'Photo', FieldType.image),
      ];
      final completer = Completer<EncodedImage>();
      final mediaRepo = _TestMediaRepo();

      await tester.pumpWidget(_app(DocEditor(
        title: 'Item',
        fields: fields,
        popOnSave: false,
        media: mediaRepo,
        pickImage: () async => Uint8List.fromList([1, 2, 3, 4]),
        prepareImage: (_) => completer.future,
        onSave: (_) async {},
      )));
      await tester.pumpAndSettle();

      // Edit a field so UnsavedBar is shown
      await tester.enterText(find.byKey(const Key('field-name')), 'Fr. Test');
      await tester.pump();
      expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

      // Start image upload; pick completes and prepareImage is awaiting
      await tester.tap(find.byKey(const Key('imageUploadBtn')));
      await tester.pump();

      // Cancel edits via UnsavedBar and confirm discard
      await tester.tap(find.byKey(const ValueKey('unsaved-bar-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();

      // Form is now reset and clean
      expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);

      // Delayed image preparation completes after discard
      completer.complete(EncodedImage(Uint8List(100), 'image/jpeg', 100, 100));
      await tester.pumpAndSettle();

      // Verify delayed preparation did not restore dirty or show unsaved bar or set pending preview
      expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
      expect(find.byKey(const Key('imagePreviewPending')), findsNothing);
    });

    testWidgets('DocEditor keeps UnsavedGuard dirty while save() is in flight', (tester) async {
      final saveCompleter = Completer<void>();
      final fields = [FieldDef('name', 'الاسم', 'Name', FieldType.text)];
      final reg = UnsavedGuardRegistry();
      addTearDown(reg.dispose);

      await tester.pumpWidget(_app(UnsavedGuardScope(
        registry: reg,
        child: DocEditor(
          title: 'Item',
          fields: fields,
          popOnSave: false,
          onSave: (_) => saveCompleter.future,
        ),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-name')), 'Fr. Test');
      await tester.pump();
      expect(reg.isDirty, isTrue);

      await tester.tap(find.byKey(const ValueKey('unsaved-bar-save')));
      await tester.pump();
      // Still dirty in UnsavedGuard while save is awaiting completion
      expect(reg.isDirty, isTrue);

      saveCompleter.complete();
      await tester.pumpAndSettle();
      expect(reg.isDirty, isFalse);
    });

    testWidgets('CollectionListScreen multi-delete preserves Undo all and failed delete restores row', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'saints': [
          AdminDoc('s1', {'nameAr': 'مارمرقس', 'order': 10}),
          AdminDoc('s2', {'nameAr': 'مارجرجس', 'order': 20}),
        ],
      });
      final def = collectionById('saints')!;
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: def),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      // Delete first, then second -> combined "Undo all" action
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('مارمرقس'), findsNothing);
      expect(find.text('مارجرجس'), findsNothing);
      expect(find.text('Undo all'), findsOneWidget);

      await tester.tap(find.text('Undo all'));
      await tester.pumpAndSettle();
      expect(find.text('مارمرقس'), findsOneWidget);
      expect(find.text('مارجرجس'), findsOneWidget);
      expect(repo.deletedIds, isEmpty);

      // Failed hard-delete restores row visibility cleanly
      repo.failDelete = true;
      await _confirmDeleteTap(tester, find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('مارمرقس'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('مارمرقس'), findsOneWidget);
    });
  });

  group('AdminStateSwitch and written states (P1-09 & P1-10)', () {
    test('zero raw SwitchListTile across lib/ui/admin/', () {
      final adminDir = Directory('lib/ui/admin');
      final dartFiles = adminDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('SwitchListTile'),
          isFalse,
          reason: '${file.path} still contains SwitchListTile, must use AdminStateSwitch',
        );
      }
    });

    testWidgets('AdminStateSwitch at 320 px x 200% text scale in RTL Arabic and LTR English', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      bool switchVal = true;
      // RTL Arabic
      await tester.pumpWidget(_app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AdminStateSwitch(
              value: switchVal,
              onLabel: 'مفعّل',
              offLabel: 'مقفول',
              title: const Text('الخدمة التفاعلية'),
              subtitle: const Text('وصف تفصيلي للخدمة'),
              onChanged: (v) => setState(() => switchVal = v),
            ),
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('مفعّل'), findsOneWidget);
      expect(find.text('مقفول'), findsNothing);

      // Tap to toggle off
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(switchVal, isFalse);
      expect(find.text('مقفول'), findsOneWidget);
      expect(find.text('مفعّل'), findsNothing);

      // LTR English
      switchVal = true;
      await tester.pumpWidget(_app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AdminStateSwitch(
              value: switchVal,
              onLabel: 'Active',
              offLabel: 'Paused',
              title: const Text('Interactive Service'),
              onChanged: (v) => setState(() => switchVal = v),
            ),
          ),
        ),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Paused'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(switchVal, isFalse);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
    });

    testWidgets('CollectionListScreen displays written status tags (ظاهر, مخفي, موقوف, منتهي, بيانات تجريبية)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {
            'type': 'mass',
            'nameAr': 'قداس الأحد',
            'visible': false,
            'sample': true,
            'active': true,
          }),
          AdminDoc('l2', {
            'type': 'mass',
            'nameAr': 'قداس الجمعة',
            'visible': true,
            'sample': false,
            'active': true,
          }),
          AdminDoc('l3', {
            'type': 'mass',
            'nameAr': 'قداس الأربعاء',
            'visible': false,
            'sample': false,
            'active': false,
          }),
          AdminDoc('l4', {
            'type': 'mass',
            'nameAr': 'قداس منتهي',
            'date': '2020-01-01',
            'visible': true,
          }),
        ],
        'alerts': [
          AdminDoc('a1', {
            'title': 'تنويه منتهي',
            'endsAt': '2020-01-01 12:00',
            'visible': true,
          }),
        ],
      });

      // 1. Liturgies collection
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      Finder inRow(String id, String text) => find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.text(text),
          );

      // l1 has visible: false -> مخفي, sample: true -> بيانات تجريبية
      expect(inRow('l1', 'مخفي'), findsOneWidget);
      expect(inRow('l1', 'ظاهر'), findsNothing);
      expect(inRow('l1', 'بيانات تجريبية'), findsOneWidget);

      // l2 has visible: true -> ظاهر
      expect(inRow('l2', 'ظاهر'), findsOneWidget);
      expect(inRow('l2', 'مخفي'), findsNothing);
      expect(inRow('l2', 'بيانات تجريبية'), findsNothing);

      // l3 has active: false -> موقوف
      expect(inRow('l3', 'مخفي'), findsOneWidget);
      expect(inRow('l3', 'موقوف'), findsOneWidget);

      // l4 has past date -> منتهي
      expect(inRow('l4', 'ظاهر'), findsOneWidget);
      expect(inRow('l4', 'منتهي'), findsOneWidget);

      // 2. Alerts collection with past endsAt -> منتهي
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('alerts')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(inRow('a1', 'منتهي'), findsOneWidget);
    });

    testWidgets('DocEditor liturgy replacesDay preview renders overridden regular masses with 12-hour Cairo times', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final liturgyDef = collectionById('liturgies')!;
      final existingDocs = [
        AdminDoc('reg1', {
          'type': 'mass',
          'nameAr': 'قداس باكر',
          'weekday': 5, // Friday
          'start': '07:00',
          'end': '09:00',
          'visible': true,
          'replacesDay': false,
        }),
      ];

      final initialValues = {
        'type': 'mass',
        'nameAr': 'قداس عيد الميلاد',
        'date': '2026-12-25', // Friday
        'start': '00:00',
        'end': '03:00',
        'visible': true,
        'replacesDay': false,
      };

      await tester.pumpWidget(_app(
        DocEditor(
          title: 'قداس',
          fields: liturgyDef.fields,
          data: initialValues,
          existingDocs: existingDocs,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Initially replacesDay is false -> preview card is not present
      expect(find.byKey(const ValueKey('replacesDayPreview')), findsNothing);

      // Toggle replacesDay on
      await tester.tap(find.byKey(const ValueKey('field-replacesDay')));
      await tester.pumpAndSettle();

      // Preview card is now visible
      expect(find.byKey(const ValueKey('replacesDayPreview')), findsOneWidget);
      // Overridden regular mass is listed
      expect(find.textContaining('قداس باكر'), findsOneWidget);
      // Cairo 12-hour formatted time with Arabic period indicator
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('replacesDayPreview')),
          matching: find.textContaining('07:00 ص'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('DocEditor replacesDayPreview updates when date text field changes after _dirty is true', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final liturgyDef = collectionById('liturgies')!;
      final existingDocs = [
        AdminDoc('fri', {
          'type': 'mass',
          'nameAr': 'قداس الجمعة',
          'weekday': 5, // Friday
          'start': '07:00',
          'end': '09:00',
          'visible': true,
          'replacesDay': false,
        }),
        AdminDoc('sat', {
          'type': 'mass',
          'nameAr': 'قداس السبت',
          'weekday': 6, // Saturday
          'start': '08:00',
          'end': '10:00',
          'visible': true,
          'replacesDay': false,
        }),
      ];

      final initialValues = {
        'type': 'mass',
        'nameAr': 'قداس استثنائي',
        'date': '2026-11-06', // Friday
        'start': '07:00',
        'end': '09:00',
        'visible': true,
        'replacesDay': false,
      };

      await tester.pumpWidget(_app(
        DocEditor(
          title: 'قداس',
          fields: liturgyDef.fields,
          data: initialValues,
          existingDocs: existingDocs,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Toggle replacesDay on -> marks _dirty = true and reveals preview
      await tester.tap(find.byKey(const ValueKey('field-replacesDay')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replacesDayPreview')), findsOneWidget);
      expect(find.textContaining('قداس الجمعة'), findsOneWidget);
      expect(find.textContaining('قداس السبت'), findsNothing);

      // Now date controller changes to 2026-11-07 (Saturday) while _dirty is already true
      final dateField = find.byKey(const ValueKey('field-date'));
      tester.widget<TextFormField>(dateField).controller!.text = '2026-11-07';
      await tester.pumpAndSettle();

      // ListenableBuilder updates preview immediately: shows Saturday mass, not Friday mass
      expect(find.textContaining('قداس السبت'), findsOneWidget);
      expect(find.textContaining('قداس الجمعة'), findsNothing);

      // Change date to a weekday with no regular masses (e.g. 2026-11-09 Monday)
      tester.widget<TextFormField>(dateField).controller!.text = '2026-11-09';
      await tester.pumpAndSettle();
      expect(find.textContaining('قداس الجمعة'), findsNothing);
      expect(find.textContaining('قداس السبت'), findsNothing);
      expect(find.textContaining('مفيش قداسات معتادة مسجلة'), findsOneWidget);
    });

    testWidgets('DocEditor replacesDayPreview omits regular masses when seasonal liturgy belongs to inactive season', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final liturgyDef = collectionById('liturgies')!;
      final existingDocs = [
        AdminDoc('fri', {
          'type': 'mass',
          'nameAr': 'قداس الجمعة',
          'weekday': 5,
          'start': '07:00',
          'end': '09:00',
          'visible': true,
          'replacesDay': false,
        }),
      ];

      await tester.pumpWidget(_app(
        DocEditor(
          title: 'قداس',
          fields: liturgyDef.fields,
          data: {
            'type': 'mass',
            'nameAr': 'قداس موسمي',
            'date': '2026-11-06', // Friday
            'start': '07:00',
            'end': '09:00',
            'seasonKey': 'lent',
            'visible': true,
            'replacesDay': true,
          },
          existingDocs: existingDocs,
          seasons: const [
            Season(
              id: 's1',
              key: 'lent',
              nameAr: 'الصوم',
              nameEn: 'Lent',
              active: false,
            ),
          ],
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replacesDayPreview')), findsOneWidget);
      expect(find.textContaining('قداس الجمعة'), findsNothing);
      expect(find.textContaining('مفيش قداسات معتادة مسجلة'), findsOneWidget);
    });

    testWidgets('DocEditor replacesDayPreview explains when replacing liturgy is hidden and ignores soft-deleted masses',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final liturgyDef = collectionById('liturgies')!;
      final existingDocs = [
        AdminDoc('fri-active', {
          'type': 'mass',
          'nameAr': 'قداس الجمعة النشط',
          'weekday': 5,
          'start': '07:00',
          'end': '09:00',
          'visible': true,
          'replacesDay': false,
        }),
        AdminDoc('fri-deleted', {
          'type': 'mass',
          'nameAr': 'قداس الجمعة المحذوف',
          'weekday': 5,
          'start': '09:30',
          'end': '11:00',
          'visible': true,
          'replacesDay': false,
          'deletedAt': DateTime.utc(2026, 11, 5),
        }),
      ];

      await tester.pumpWidget(_app(
        DocEditor(
          title: 'قداس',
          fields: liturgyDef.fields,
          data: {
            'type': 'mass',
            'nameAr': 'قداس مخفي',
            'date': '2026-11-06',
            'start': '07:00',
            'end': '09:00',
            'visible': false,
            'replacesDay': true,
          },
          existingDocs: existingDocs,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Hidden replacing liturgy shows dedicated explanation instead of empty-day copy.
      expect(find.byKey(const ValueKey('replacesDayPreview')), findsOneWidget);
      expect(find.textContaining('القداس مخفي حاليًا'), findsOneWidget);
      expect(find.textContaining('قداس الجمعة النشط'), findsNothing);

      // Toggle visible ON -> active mass shows, soft-deleted mass stays excluded.
      final listScrollable = find.byType(Scrollable).first;
      final visibleFinder = find.byKey(const ValueKey('field-visible'));
      await tester.scrollUntilVisible(visibleFinder, 200, scrollable: listScrollable);
      await tester.tap(visibleFinder);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('replacesDayPreview')), -200, scrollable: listScrollable);
      expect(find.textContaining('قداس الجمعة النشط'), findsOneWidget);
      expect(find.textContaining('قداس الجمعة المحذوف'), findsNothing);
    });

    testWidgets('AdminStateSwitch merges semantics, keeps single focus stop, and dims when disabled', (tester) async {
      final semHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(
          Column(
            children: [
              AdminStateSwitch(
                key: const ValueKey('enabled-sw'),
                value: true,
                onLabel: 'Shown',
                offLabel: 'Hidden',
                title: const Text('Visible on site'),
                subtitle: const Text('Controls public visibility'),
                onChanged: (_) {},
              ),
              const AdminStateSwitch(
                key: ValueKey('disabled-sw'),
                value: false,
                onLabel: 'Shown',
                offLabel: 'Hidden',
                title: Text('Locked setting'),
                subtitle: Text('Disabled hint'),
                onChanged: null,
              ),
            ],
          ),
        ));
        await tester.pumpAndSettle();

        // Single merged semantic node combines title and switch state
        final enabledFinder = find.byKey(const ValueKey('enabled-sw'));
        final sem = tester.getSemantics(find.descendant(of: enabledFinder, matching: find.byType(Switch)));
        expect(sem.label, contains('Visible on site'));
        expect(sem.flagsCollection.isToggled, Tristate.isTrue);

        // InkWell does not register an extra keyboard focus target
        final inkWell = tester.widget<InkWell>(find.descendant(of: enabledFinder, matching: find.byType(InkWell)));
        expect(inkWell.canRequestFocus, isFalse);
        expect(inkWell.excludeFromSemantics, isTrue);

        // Disabled branch dims title, subtitle, and badge with Theme.disabledColor
        final disabledFinder = find.byKey(const ValueKey('disabled-sw'));
        final disabledThemeColor = Theme.of(tester.element(disabledFinder)).disabledColor;
        final badgeText = tester.widget<Text>(find.descendant(of: disabledFinder, matching: find.text('Hidden')));
        expect(badgeText.style?.color, disabledThemeColor);
        final titleStyle = DefaultTextStyle.of(tester.element(find.text('Locked setting'))).style;
        expect(titleStyle.color, disabledThemeColor);
      } finally {
        semHandle.dispose();
      }
    });
  });

  group('PR 3C: P1-12 admin status & optional expiry', () {
    test('evaluateAdminAccess handles active, stopped, expired, and none', () {
      final now = DateTime.utc(2026, 11, 14, 12, 0);
      expect(evaluateAdminAccess(null, now).status, AdminAccountStatus.none);
      expect(evaluateAdminAccess(null, now).isAllowed, isFalse);

      final missingFlags = evaluateAdminAccess({'email': 'e@x.org', 'role': 'editor'}, now);
      expect(missingFlags.status, AdminAccountStatus.active);
      expect(missingFlags.role, AdminRoles.editor);
      expect(missingFlags.isAllowed, isTrue);

      final ownerActive = evaluateAdminAccess({'role': 'owner', 'active': true}, now);
      expect(ownerActive.status, AdminAccountStatus.active);
      expect(ownerActive.role, AdminRoles.owner);
      expect(ownerActive.isAllowed, isTrue);

      final stoppedWithFuture = evaluateAdminAccess({
        'role': 'editor',
        'active': false,
        'expiresAt': now.add(const Duration(days: 3)),
      }, now);
      expect(stoppedWithFuture.status, AdminAccountStatus.stopped);
      expect(stoppedWithFuture.isAllowed, isFalse);

      final futureExpiry = evaluateAdminAccess({
        'role': 'editor',
        'active': true,
        'expiresAt': now.add(const Duration(seconds: 1)),
      }, now);
      expect(futureExpiry.status, AdminAccountStatus.active);
      expect(futureExpiry.isAllowed, isTrue);

      final exactExpiry = evaluateAdminAccess({
        'role': 'editor',
        'active': true,
        'expiresAt': now,
      }, now);
      expect(exactExpiry.status, AdminAccountStatus.expired);
      expect(exactExpiry.isAllowed, isFalse);

      final pastExpiry = evaluateAdminAccess({
        'role': 'editor',
        'expiresAt': now.subtract(const Duration(minutes: 5)),
      }, now);
      expect(pastExpiry.status, AdminAccountStatus.expired);
      expect(pastExpiry.isAllowed, isFalse);
    });

    testWidgets('AdminsScreen displays active/stopped switches, confirms toggles, clears expiry, and fits 320px at 200%', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final ctrl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(ctrl.close);

      final futureDate = DateTime.utc(2099, 5, 20, 20, 59, 59);
      final pastDate = DateTime.utc(2020, 1, 1, 21, 59, 59);
      final repo = _ReactiveAdminBackend(
        controller: ctrl,
        initialCollections: {
          'admins': [
            AdminDoc('own', {'email': 'owner@church.org', 'role': 'owner', 'active': true}),
            AdminDoc('ed1', {
              'email': 'active@church.org',
              'role': 'editor',
              'active': true,
              'expiresAt': futureDate,
            }),
            AdminDoc('ed2', {
              'email': 'paused@church.org',
              'role': 'editor',
              'active': false,
              'expiresAt': pastDate,
            }),
          ],
        },
      );

      await tester.pumpWidget(_app(
        AdminsScreen(repo: repo, selfUid: 'own'),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Zero layout overflow at 320 px x 200%
      expect(tester.takeException(), isNull);

      // Check cards in alphabetical order: active@ (ed1) -> owner@ (own) -> paused@ (ed2)
      final outerScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('admin-active-ed1')), 200, scrollable: outerScroll);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('admin-active-ed1')), matching: find.text('نشط')),
        findsOneWidget,
      );

      // Self active status renders styled badge instead of disabled switch
      await tester.scrollUntilVisible(find.byKey(const ValueKey('admin-self-active-own')), 200, scrollable: outerScroll);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-self-active-own')), findsOneWidget);
      expect(find.text('حسابك (نشط)'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-active-own')), findsNothing);
      expect(find.byKey(const ValueKey('admin-expiry-own')), findsNothing);

      // ed2 (paused@) comes after own
      await tester.scrollUntilVisible(find.byKey(const ValueKey('admin-active-ed2')), 200, scrollable: outerScroll);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('admin-active-ed2')), matching: find.text('موقوف')),
        findsOneWidget,
      );

      // Scroll back up to ed1 and tap active switch
      await tester.scrollUntilVisible(find.byKey(const ValueKey('admin-active-ed1')), -200, scrollable: outerScroll);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('admin-active-ed1')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(find.textContaining('active@church.org'), findsWidgets);
      expect(find.text('إيقاف المشرف'), findsOneWidget);

      // Cancelling leaves active unchanged
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('admin-active-ed1')), matching: find.text('نشط')),
        findsOneWidget,
      );

      // Confirming pauses the admin
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('admin-active-ed1')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إيقاف المشرف'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('admin-active-ed1')), matching: find.text('موقوف')),
        findsOneWidget,
      );

      // Clearing ed1 expiry removes expiresAt without sending an 'active' field
      repo.updates.clear();
      await tester.ensureVisible(find.byKey(const ValueKey('admin-clear-expiry-ed1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-clear-expiry-ed1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-clear-expiry-ed1')), findsNothing);
      expect(repo.updates, isNotEmpty);
      expect(repo.updates.last.data.containsKey('active'), isFalse);
      expect(repo.updates.last.data['expiresAt'], isNull);
    });

    testWidgets('AdminsScreen hides expiry picker for owners, allows clearing legacy owner expiry, and clears expiresAt on promotion', (tester) async {
      final ctrl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(ctrl.close);

      final futureDate = DateTime.utc(2099, 5, 20, 20, 59, 59);
      final repo = _ReactiveAdminBackend(
        controller: ctrl,
        initialCollections: {
          'admins': [
            AdminDoc('own', {'email': 'a-own@church.org', 'role': 'owner', 'active': true}),
            AdminDoc('own2', {'email': 'b-own2@church.org', 'role': 'owner', 'active': true}),
            AdminDoc('own3', {
              'email': 'c-legacy-owner@church.org',
              'role': 'owner',
              'active': true,
              'expiresAt': futureDate,
            }),
            AdminDoc('ed1', {
              'email': 'd-ed@church.org',
              'role': 'editor',
              'active': true,
              'expiresAt': futureDate,
            }),
          ],
        },
      );

      await tester.pumpWidget(_app(
        AdminsScreen(repo: repo, selfUid: 'own'),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Another owner without expiresAt has no expiry chip
      expect(find.byKey(const ValueKey('admin-expiry-own2')), findsNothing);

      // Legacy owner with expiresAt disables setting expiry, but still allows clearing it
      final legacyChip = tester.widget<ActionChip>(find.byKey(const ValueKey('admin-expiry-own3')));
      expect(legacyChip.onPressed, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('admin-clear-expiry-own3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-clear-expiry-own3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-expiry-own3')), findsNothing);
      expect(repo.updates.last.data.containsKey('active'), isFalse);

      // Promoting an editor who has expiresAt to owner clears expiresAt cleanly
      repo.updates.clear();
      repo.setAdminCalls.clear();
      await tester.ensureVisible(find.text('محرر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('محرر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مالك (يدير المشرفين)').last);
      await tester.pumpAndSettle();
      expect(repo.setAdminCalls.last.uid, 'ed1');
      expect(repo.setAdminCalls.last.role, 'owner');
      expect(repo.updates.any((u) => u.id == 'ed1' && u.data.containsKey('expiresAt') && u.data['expiresAt'] == null), isTrue);
    });

    testWidgets('AdminCheckGate blocks stopped/expired admins, revokes live, handles stream errors, chunks >24d timers, and unlocks when expiry is extended', (tester) async {
      final repo = _TestAdminBackend();
      var signedOut = 0;

      // 1. Stopped admin
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u1',
            email: 'stopped@church.org',
            loadAccess: () async => const AdminAccess(role: 'editor', status: AdminAccountStatus.stopped),
            accessChanges: const Stream.empty(),
            rememberMe: false,
            onSignOut: () => signedOut++,
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('تم إيقاف هذا الحساب مؤقتًا من مالك اللوحة.'), findsOneWidget);
      await tester.tap(find.text('تسجيل الخروج'));
      expect(signedOut, 1);

      // 2. Expired admin
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u2',
            email: 'exp@church.org',
            loadAccess: () async => AdminAccess(
              role: 'editor',
              status: AdminAccountStatus.expired,
              expiresAt: DateTime.utc(2020, 1, 1),
            ),
            accessChanges: const Stream.empty(),
            rememberMe: false,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('انتهت صلاحية هذا الحساب المؤقت.'), findsOneWidget);

      // 3. Live revocation via accessChanges while dashboard is open; stream error preserves last live decision
      final liveCtrl = StreamController<AdminAccess>.broadcast();
      addTearDown(liveCtrl.close);
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u3',
            email: 'live@church.org',
            loadAccess: () async => const AdminAccess(role: 'editor', status: AdminAccountStatus.active),
            accessChanges: liveCtrl.stream,
            rememberMe: true, // keep idle timer off in this test
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsOneWidget);

      liveCtrl.add(const AdminAccess(role: 'editor', status: AdminAccountStatus.stopped));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsNothing);
      expect(find.text('تم إيقاف هذا الحساب مؤقتًا من مالك اللوحة.'), findsOneWidget);

      // Stream error after live stopped decision must NOT revert to initial active loadAccess
      liveCtrl.addError(StateError('network blip'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsNothing);
      expect(find.text('تم إيقاف هذا الحساب مؤقتًا من مالك اللوحة.'), findsOneWidget);

      // Stream error before any live decision shows retry error screen instead of stale initialData
      final errCtrl = StreamController<AdminAccess>.broadcast();
      addTearDown(errCtrl.close);
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u3-err',
            email: 'err@church.org',
            loadAccess: () async => const AdminAccess(role: 'editor', status: AdminAccountStatus.active),
            accessChanges: errCtrl.stream,
            rememberMe: true,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      errCtrl.addError(StateError('stream denied'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      // 4. Expiry timer locks open dashboard once expiresAt elapses, and unlocks when extended
      final timerCtrl = StreamController<AdminAccess>.broadcast();
      addTearDown(timerCtrl.close);
      final soon = DateTime.now().toUtc().add(const Duration(seconds: 5));
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u4',
            email: 'timer@church.org',
            loadAccess: () async => AdminAccess(role: 'editor', status: AdminAccountStatus.active, expiresAt: soon),
            accessChanges: timerCtrl.stream,
            rememberMe: true,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsNothing);
      expect(find.textContaining('انتهت صلاحية هذا الحساب المؤقت.'), findsOneWidget);

      // Extending expiresAt to a later timestamp unlocks immediately
      final extended = DateTime.now().toUtc().add(const Duration(hours: 2));
      timerCtrl.add(AdminAccess(role: 'editor', status: AdminAccountStatus.active, expiresAt: extended));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsOneWidget);

      // 5. >30-day expiresAt does NOT prematurely lock at 25 days, and locks after full 30 days
      final monthAhead = DateTime.now().toUtc().add(const Duration(days: 30));
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u5',
            email: 'month@church.org',
            loadAccess: () async => AdminAccess(role: 'editor', status: AdminAccountStatus.active, expiresAt: monthAhead),
            accessChanges: const Stream.empty(),
            rememberMe: true,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsOneWidget);

      await tester.pump(const Duration(days: 25));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsOneWidget);

      await tester.pump(const Duration(days: 6));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboard), findsNothing);
      expect(find.textContaining('انتهت صلاحية هذا الحساب المؤقت.'), findsOneWidget);
    });
  });

  group('PR 3C: P1-13 session idle policy & remember me', () {
    test('SessionPolicy boundaries match 30-minute idle limit and 60-second warning', () {
      const policy = SessionPolicy();
      expect(policy.idleLimit, const Duration(minutes: 30));
      expect(policy.warnBefore, const Duration(seconds: 60));
      expect(policy.warnAt, const Duration(minutes: 29));
    });

    testWidgets('AdminLoginForm passes rememberMe state on sign in', (tester) async {
      bool? capturedRemember;
      await tester.pumpWidget(_app(
        Scaffold(
          body: AdminLoginForm(
            onSignIn: (email, password, {rememberMe = false}) async {
              capturedRemember = rememberMe;
            },
            onResetPassword: (_) async => true,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Default unticked
      final cb = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('login-remember-me')));
      expect(cb.value, isFalse);

      await tester.enterText(find.byKey(const ValueKey('login-email')), 'a@church.org');
      await tester.enterText(find.byKey(const ValueKey('login-password')), 'secret123');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();
      expect(capturedRemember, isFalse);

      // Ticked -> passes rememberMe: true
      await tester.tap(find.byKey(const ValueKey('login-remember-me')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();
      expect(capturedRemember, isTrue);
    });

    testWidgets('AdminSessionGuard warns at warnAt, signs out at limit, resets on pointer/hover/key/button, preserves child state, and skips when disabled', (tester) async {
      final unsaved = UnsavedGuardRegistry();
      var signedOut = 0;

      Widget buildGuard({required bool enabled, Locale locale = const Locale('ar')}) => _app(
            Scaffold(
              body: AdminSessionGuard(
                enabled: enabled,
                unsaved: unsaved,
                onSignOut: () => signedOut++,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Dashboard Content'),
                    TextField(key: ValueKey('guard-draft-input')),
                  ],
                ),
              ),
            ),
            locale: locale,
          );

      // 1. Enabled -> warns at 29m, preserves child TextField state, pointer/hover/key reset timer
      await tester.pumpWidget(buildGuard(enabled: true));
      await tester.enterText(find.byKey(const ValueKey('guard-draft-input')), 'draft note');
      await tester.pump(const Duration(minutes: 28, seconds: 59));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(signedOut, 0);

      await tester.pump(const Duration(seconds: 2)); // 29:01 idle
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);
      // Child TextField text is preserved across warning mount
      expect(
        tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('guard-draft-input')), matching: find.byType(EditableText))).controller.text,
        'draft note',
      );

      // Pointer hover (without mouse button pressed) resets timer & dismisses warning
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Dashboard Content')));
      await tester.pump();
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(
        tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('guard-draft-input')), matching: find.byType(EditableText))).controller.text,
        'draft note',
      );

      // Trigger warning again, then test tap reset
      await tester.pump(const Duration(minutes: 29));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);
      await tester.tap(find.text('Dashboard Content'));
      await tester.pump();
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);

      // Still signed in 20 minutes after tap (because clock reset)
      await tester.pump(const Duration(minutes: 20));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(signedOut, 0);

      // Advance remaining 9m to trigger warning again, then test key reset
      await tester.pump(const Duration(minutes: 9));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);

      // Advance to warning again, tap Stay Signed In button
      await tester.pump(const Duration(minutes: 29));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-stay-btn')));
      await tester.pump();
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(signedOut, 0);

      // Now let it hit full 30 minutes idle -> signs out
      await tester.pump(const Duration(minutes: 30));
      expect(signedOut, 1);

      // 2. Disabled (Remember me ticked) -> past 30 minutes does not warn or sign out
      signedOut = 0;
      await tester.pumpWidget(buildGuard(enabled: false));
      await tester.pump(const Duration(minutes: 45));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(signedOut, 0);
    });

    testWidgets('AdminSessionGuard asks before signing out when form is dirty and warning fits 320px at 200%', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final unsaved = UnsavedGuardRegistry()..register('doc-1');
      var signedOut = 0;

      await tester.pumpWidget(_app(
        Scaffold(
          body: AdminSessionGuard(
            enabled: true,
            unsaved: unsaved,
            onSignOut: () => signedOut++,
            child: const Center(child: Text('Dirty Form')),
          ),
        ),
        locale: const Locale('ar'),
      ));

      // Trigger warning at 320px x 200% and verify zero overflow
      await tester.pump(const Duration(minutes: 29));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance past 30m limit -> shows unsaved edits confirmation instead of signing out immediately
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(signedOut, 0);
      expect(find.text('متابعة التعديل'), findsOneWidget);

      // Choosing «متابعة التعديل» keeps user signed in and resets timer
      await tester.tap(find.text('متابعة التعديل'));
      await tester.pumpAndSettle();
      expect(signedOut, 0);

      // Let 30m elapse again and choose «تجاهل» -> signs out
      await tester.pump(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجاهل'));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });
  });

  group('PR 3E: P2-18 grouped navigation, badge, season hub & owner guards', () {
    testWidgets('shows 7 editor groups (17 entries) for editor and all 8 groups (22 entries) for owner', (tester) async {
      tester.view.physicalSize = const Size(1280, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final editorDests = adminDestinations(AdminRoles.editor);
      final ownerDests = adminDestinations(AdminRoles.owner);
      expect(editorDests, hasLength(17));
      expect(ownerDests, hasLength(22));
      expect(ownerDests.map((d) => d.icon).toSet(), hasLength(22));
      expect(editorDests.any((d) => d.group == AdminGroup.ownerSettings), isFalse);

      final repo = _TestAdminBackend();
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u-editor',
            email: 'editor@church.org',
            role: AdminRoles.editor,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      for (final g in AdminGroup.values.where((g) => g != AdminGroup.ownerSettings)) {
        expect(find.byKey(ValueKey('nav-group-${g.name}')), findsOneWidget, reason: g.name);
      }
      expect(find.byKey(const ValueKey('nav-group-ownerSettings')), findsNothing);
      for (final d in editorDests) {
        expect(find.byKey(ValueKey('nav-${d.id}')), findsOneWidget, reason: d.id);
      }

      // Now mount as owner and verify 8th group appears with all 5 owner destinations.
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u-owner',
            email: 'owner@church.org',
            role: AdminRoles.owner,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('nav-group-ownerSettings')), findsOneWidget);
      for (final d in ownerDests) {
        expect(find.byKey(ValueKey('nav-${d.id}')), findsOneWidget, reason: d.id);
      }
    });

    testWidgets('nav-messages-badge shows open message count and hides when zero', (tester) async {
      tester.view.physicalSize = const Size(1280, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repoWithMsgs = _TestAdminBackend(initialCollections: {
        'contact_messages': [
          AdminDoc('m1', {'status': 'new', 'message': 'first'}),
          AdminDoc('m2', {'status': 'new', 'message': 'second'}),
          AdminDoc('m3', {'status': 'done', 'message': 'closed'}),
          AdminDoc('m4', {'status': 'new', 'message': 'trashed', 'deletedAt': DateTime.utc(2026, 11, 14)}),
        ],
      });

      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repoWithMsgs,
            uid: 'u1',
            email: 'a@church.org',
            role: AdminRoles.editor,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('nav-messages-badge'));
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);

      // Zero open messages -> badge is hidden.
      final emptyRepo = _TestAdminBackend(initialCollections: {
        'contact_messages': [
          AdminDoc('m1', {'status': 'done', 'message': 'closed'}),
        ],
      });
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: emptyRepo,
            uid: 'u2',
            email: 'b@church.org',
            role: AdminRoles.editor,
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-messages-badge')), findsNothing);
    });

    testWidgets('seasonPreset deep link opens SeasonsHubScreen on preset tab & editor is blocked from owner screens',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend();
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u1',
            email: 'e@church.org',
            role: AdminRoles.editor,
            initial: 'seasonPreset',
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SeasonsHubScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('seasons-tab-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('seasons-tab-preset')), findsOneWidget);
      expect(find.byType(SeasonPresetScreen), findsOneWidget);

      // Owner-only destinations reject non-owner editors.
      for (final ownerScreen in ['admins', 'contactCats', 'assistant', 'seasonSettings', 'advanced']) {
        await tester.pumpWidget(ProviderScope(
          child: _app(
            AdminDashboard(
              key: ValueKey('dash-$ownerScreen'),
              repo: repo,
              uid: 'u1',
              email: 'e@church.org',
              role: AdminRoles.editor,
              initial: ownerScreen,
              onSignOut: () {},
            ),
            locale: const Locale('ar'),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('هذه الصفحة للمالك فقط'), findsOneWidget, reason: ownerScreen);
      }
    });
  });

  group('PR 3E: P2-19 screen title and one-line help headers', () {
    test('every CollectionDef and settings DocDef has non-empty helpAr and helpEn', () {
      for (final c in adminCollections) {
        expect(c.helpAr.trim(), isNotEmpty, reason: '${c.id}.helpAr');
        expect(c.helpEn.trim(), isNotEmpty, reason: '${c.id}.helpEn');
      }
      for (final doc in [
        churchInfoDoc,
        todaySettingsDoc,
        seasonSettingsDoc,
        assistantSettingsDoc,
        appInstallDoc,
      ]) {
        expect(doc.helpAr.trim(), isNotEmpty, reason: '${doc.path} (${doc.labelEn}).helpAr');
        expect(doc.helpEn.trim(), isNotEmpty, reason: '${doc.path} (${doc.labelEn}).helpEn');
      }
    });

    testWidgets('every admin screen renders screen-title and screen-help cleanly at 320px and 200% text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _TestAdminBackend();
      final screens = <String, Widget Function()>{
        'overview': () => OverviewScreen(repo: repo, role: AdminRoles.editor, onOpen: (_) {}),
        'liturgies': () => CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        'church': () => ChurchInfoScreen(repo: repo),
        'features': () => FeaturesScreen(repo: repo),
        'app': () => AppAndNotificationsScreen(repo: repo, role: AdminRoles.editor),
        'seasons': () => SeasonsHubScreen(repo: repo),
        'messages': () => MessagesScreen(repo: repo),
        'contactCats': () => ContactCategoriesScreen(repo: repo),
        'admins': () => AdminsScreen(repo: repo, selfUid: 'self-uid'),
        'advanced': () => AdvancedOwnerScreen(repo: repo, onSendTestError: () async => true),
      };

      for (final locale in [const Locale('ar'), const Locale('en')]) {
        for (final entry in screens.entries) {
          await tester.pumpWidget(_app(Scaffold(body: entry.value()), locale: locale));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('screen-title')),
            findsOneWidget,
            reason: '${entry.key} (${locale.languageCode}) title',
          );
          expect(
            find.byKey(const Key('screen-help')),
            findsOneWidget,
            reason: '${entry.key} (${locale.languageCode}) help',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} (${locale.languageCode}) overflow/exception',
          );
        }
      }
    });
  });

  group('PR 3E: P2-21 owner advanced screen & criterion S3 editor copy', () {
    testWidgets('non-owner editor screens never render Firebase, UID, App Check, Sentry, APK, or HH:mm',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'liturgies': [AdminDoc('l1', {'titleAr': 'قداس الجمعة', 'weekday': 5, 'start': '07:00', 'end': '09:00'})],
        'contact_messages': [AdminDoc('m1', {'status': 'new', 'name': 'زائر', 'message': 'سلام'})],
      });
      final forbidden = RegExp(r'\b(Firebase|UID|App Check|Sentry|APK|HH:mm)\b');

      for (final locale in [const Locale('ar'), const Locale('en')]) {
        for (final d in adminDestinations(AdminRoles.editor)) {
          await tester.pumpWidget(ProviderScope(
            child: _app(
              AdminDashboard(
                key: ValueKey('s3-${locale.languageCode}-${d.id}'),
                repo: repo,
                uid: 'u1',
                email: 'editor@church.org',
                role: AdminRoles.editor,
                initial: d.id,
                onSignOut: () {},
              ),
              locale: locale,
            ),
          ));
          await tester.pumpAndSettle();

          for (final w in tester.widgetList<Text>(find.byType(Text))) {
            final text = w.data ?? '';
            expect(
              forbidden.hasMatch(text),
              isFalse,
              reason: 'Forbidden technical term in editor screen "${d.id}" (${locale.languageCode}): "$text"',
            );
          }
          expect(find.byType(FeaturesScreen).evaluate().length <= 1, isTrue);
          expect(tester.takeException(), isNull, reason: '${d.id} (${locale.languageCode})');
        }
      }
    });

    testWidgets('AdvancedOwnerScreen shows App Check status, validates & saves VAPID, queue cap banner, and APK tab',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialDocs: {
        'settings/features': {'errorReporting': true},
        'meta/push_topics': {
          'cronQueue': {'capReached': true},
        },
        'meta/push_plan': {
          'lastPlanAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      await tester.pumpWidget(_app(
        Scaffold(
          body: AdvancedOwnerScreen(
            repo: repo,
            appCheckActive: true,
            onSendTestError: () async => true,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adv-app-check')), findsOneWidget);
      expect(find.text('مفعّل ✓'), findsOneWidget);
      expect(find.byKey(const ValueKey('adv-vapid-queues')), findsOneWidget);
      // Cap reached banner appears when cronQueue.capReached == true
      expect(find.textContaining('١٠٠٠ تذكير'), findsOneWidget);

      // Invalid VAPID key shows validation error without saving
      await tester.enterText(find.byKey(const ValueKey('vapid')), 'short-bad-key');
      await tester.tap(find.byKey(const ValueKey('adv-save-vapid')));
      await tester.pumpAndSettle();
      expect(repo.savedPaths, isNot(contains('settings/features')));
      expect(find.textContaining('٨٠–١٠٠'), findsOneWidget);

      // Valid VAPID key saves to settings/features
      final validKey = 'B' * 87;
      await tester.enterText(find.byKey(const ValueKey('vapid')), validKey);
      await tester.tap(find.byKey(const ValueKey('adv-save-vapid')));
      await tester.pumpAndSettle();
      expect(repo.savedPaths, contains('settings/features'));
      expect(repo.docs['settings/features']?['pushVapidKey'], validKey);

      // Switch to APK tab -> displays app-install-doc
      await tester.tap(find.byKey(const ValueKey('adv-tab-apk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-install-doc')), findsOneWidget);
    });

    testWidgets('AdvancedOwnerScreen falls back to cronQueue.lastIdleAt for drain health when lastDrainAt is absent',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialDocs: {
        'settings/features': {'errorReporting': true},
        'meta/push_topics': {
          'cronQueue': {
            'lastIdleAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
        'meta/push_plan': {
          'lastPlanAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      await tester.pumpWidget(_app(
        Scaffold(
          body: AdvancedOwnerScreen(
            repo: repo,
            appCheckActive: true,
            onSendTestError: () async => true,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('تفريغ طابور الاشتراكات يعمل بانتظام'), findsOneWidget);
      expect(find.text('طابور الاشتراكات لم يعمل بعد'), findsNothing);
    });

    testWidgets('AdvancedOwnerScreen updates web-push drain & plan rows live when watchDoc emits fresh data after stale cache',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final now = DateTime.now().toUtc();
      final repo = _StreamingDocBackend(initialDocs: {
        'settings/features': {'errorReporting': true},
        'meta/push_topics': {
          'cronQueue': {
            'lastDrainAt': now.subtract(const Duration(days: 10)).toIso8601String(),
          },
        },
        'meta/push_plan': {
          'lastPlanAt': now.subtract(const Duration(days: 10)).toIso8601String(),
        },
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        Scaffold(
          body: AdvancedOwnerScreen(
            repo: repo,
            appCheckActive: true,
            onSendTestError: () async => true,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // First (stale cache) snapshot shows both rows late.
      expect(find.text('تأخر تفريغ طابور الاشتراكات (أكثر من ٤٥ دقيقة)'), findsOneWidget);
      expect(find.text('تأخر مجدول التذكيرات (أكثر من ٧ ساعات)'), findsOneWidget);
      expect(find.text('تفريغ طابور الاشتراكات يعمل بانتظام'), findsNothing);
      expect(find.text('مجدول التذكيرات يعمل بانتظام'), findsNothing);

      // Fresh meta/push_topics arrives -> drain row flips from late to OK.
      repo.emitDoc('meta/push_topics', {
        'cronQueue': {
          'lastDrainAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
        },
      });
      await tester.pumpAndSettle();

      expect(find.text('تفريغ طابور الاشتراكات يعمل بانتظام'), findsOneWidget);
      expect(find.text('تأخر تفريغ طابور الاشتراكات (أكثر من ٤٥ دقيقة)'), findsNothing);
      expect(find.text('تأخر مجدول التذكيرات (أكثر من ٧ ساعات)'), findsOneWidget);

      // Fresh meta/push_plan arrives -> plan row flips from late to OK.
      repo.emitDoc('meta/push_plan', {
        'lastPlanAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      });
      await tester.pumpAndSettle();

      expect(find.text('مجدول التذكيرات يعمل بانتظام'), findsOneWidget);
      expect(find.text('تأخر مجدول التذكيرات (أكثر من ٧ ساعات)'), findsNothing);
    });

    testWidgets('WebPushHealthRows refreshes age every minute, re-binds on repo change, and fits 320px RTL/LTR',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var currentUtc = DateTime.utc(2026, 11, 26, 12, 0);
      final repoA = _StreamingDocBackend(initialDocs: {
        'meta/push_topics': {
          'cronQueue': {
            // 44m30s ago -> initially OK, crosses >45m after 1 minute tick.
            'lastDrainAt': currentUtc.subtract(const Duration(minutes: 44, seconds: 30)).toIso8601String(),
          },
        },
        'meta/push_plan': {
          'lastPlanAt': currentUtc.subtract(const Duration(hours: 1)).toIso8601String(),
        },
      });
      addTearDown(repoA.dispose);

      await tester.pumpWidget(_app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: WebPushHealthRows(repo: repoA, now: () => currentUtc),
            ),
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('تفريغ طابور الاشتراكات يعمل بانتظام'), findsOneWidget);
      expect(find.text('مجدول التذكيرات يعمل بانتظام'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance clock past 45 min threshold and trigger the 1-minute periodic timer.
      currentUtc = currentUtc.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(find.text('تأخر تفريغ طابور الاشتراكات (أكثر من ٤٥ دقيقة)'), findsOneWidget);

      // Swapping repo re-binds subscriptions and resets stale cached data (English LTR check).
      final repoB = _StreamingDocBackend(initialDocs: {
        'meta/push_topics': {
          'cronQueue': {
            'lastDrainAt': currentUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
          },
        },
        'meta/push_plan': {
          'lastPlanAt': currentUtc.subtract(const Duration(hours: 8)).toIso8601String(),
        },
      });
      addTearDown(repoB.dispose);

      await tester.pumpWidget(_app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: WebPushHealthRows(repo: repoB, now: () => currentUtc),
            ),
          ),
        ),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Subscription queue drain is running normally'), findsOneWidget);
      expect(find.text('Reminder planner is delayed (> 7 hours)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AdvancedOwnerScreen registers VAPID edits with UnsavedGuard and preserves edits during pending save',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _SlowSaveBackend(initialDocs: {
        'settings/features': {'errorReporting': true, 'pushVapidKey': ''},
      });
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u-own',
            email: 'owner@church.org',
            role: AdminRoles.owner,
            initial: 'advanced',
            onSignOut: () {},
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();

      final draftKey = 'A' * 87;
      await tester.enterText(find.byKey(const ValueKey('vapid')), draftKey);
      await tester.pump();

      // Navigating to another destination while VAPID is dirty prompts confirmDiscardChanges
      await tester.tap(find.byKey(const ValueKey('nav-overview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-keep')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('vapid'))).controller!.text, draftKey);

      // Start saving -> TextField disables while save is pending
      repo.holdNextSave();
      await tester.tap(find.byKey(const ValueKey('adv-save-vapid')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('vapid'))).enabled, isFalse);

      // Simulate an edit arriving while save is in flight -> dirty stays true and text is not clobbered
      final newerKey = 'C' * 87;
      tester.widget<TextField>(find.byKey(const ValueKey('vapid'))).controller!.text = newerKey;
      repo.releaseNextSave();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('vapid'))).controller!.text, newerKey);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('vapid'))).enabled, isTrue);

      // Save the newer key cleanly -> UnsavedGuard clears so navigation proceeds without prompt
      await tester.tap(find.byKey(const ValueKey('adv-save-vapid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-overview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-keep')), findsNothing);
      expect(find.byKey(const ValueKey('quick-tasks')), findsOneWidget);
    });
  });

  group('PR 3E: P2-23 OverviewScreen attention section and quick tasks', () {
    testWidgets('shows attention-section items and routes on tap, and triggers all 6 quick task buttons',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fixedNow = DateTime.utc(2026, 11, 14, 12, 0);
      final repo = _TestAdminBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': true, 'liveUrl': ''},
        },
        initialCollections: {
          'contact_messages': [
            AdminDoc('m1', {'status': 'new', 'message': 'hi'}),
          ],
          'alerts': [
            AdminDoc('a1', {
              'titleAr': 'تنويه',
              'visible': true,
              'active': true,
              'endsAt': fixedNow.add(const Duration(hours: 12)),
            }),
          ],
          'priests': [
            AdminDoc('p1', {'nameAr': 'أبونا', 'sample': true}),
          ],
        },
      );

      final opened = <String>[];
      await tester.pumpWidget(_app(
        OverviewScreen(
          repo: repo,
          role: AdminRoles.editor,
          onOpen: opened.add,
          now: () => fixedNow,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('attention-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-all-clear')), findsNothing);
      expect(find.byKey(const ValueKey('attention-newMessages')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-expiringAlerts')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-unconfirmedData')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-streamWithoutLink')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('attention-newMessages')));
      await tester.tap(find.byKey(const ValueKey('attention-expiringAlerts')));
      await tester.tap(find.byKey(const ValueKey('attention-unconfirmedData')));
      await tester.tap(find.byKey(const ValueKey('attention-streamWithoutLink')));
      expect(opened, ['messages', 'alerts', 'priests', 'today']);

      opened.clear();
      const quickTargets = [
        ('task-schedules', 'liturgies'),
        ('task-announcement', 'app'),
        ('task-inbox', 'messages'),
        ('task-service', 'facilities'),
        ('task-priest', 'priests'),
        ('task-donations', 'pages'),
      ];
      for (final (btnKey, target) in quickTargets) {
        final finder = find.byKey(ValueKey(btnKey));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
        expect(opened.last, target, reason: btnKey);
      }
    });

    testWidgets('shows attention-all-clear when nothing needs attention', (tester) async {
      final fixedNow = DateTime.utc(2026, 11, 14, 12, 0);
      final repo = _TestAdminBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'liveUrl': ''},
        },
        initialCollections: {
          'contact_messages': [
            AdminDoc('m1', {'status': 'done', 'message': 'ok'}),
          ],
          'alerts': [
            AdminDoc('a1', {
              'titleAr': 'تنويه',
              'titleEn': 'Notice',
              'visible': true,
              'active': true,
              'endsAt': fixedNow.add(const Duration(days: 5)),
            }),
          ],
          'priests': [
            AdminDoc('p1', {'nameAr': 'أبونا', 'sample': false}),
          ],
        },
      );

      await tester.pumpWidget(_app(
        OverviewScreen(
          repo: repo,
          role: AdminRoles.editor,
          onOpen: (_) {},
          now: () => fixedNow,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('attention-all-clear')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-section')), findsNothing);
    });

    testWidgets('waits for all streams before all-clear and offers retry when any stream fails', (tester) async {
      final alertsCtrl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(alertsCtrl.close);
      final repo = _ControllableOverviewBackend(
        alertsStream: () => alertsCtrl.stream,
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'liveUrl': ''},
        },
      );

      await tester.pumpWidget(_app(
        OverviewScreen(
          repo: repo,
          role: AdminRoles.editor,
          onOpen: (_) {},
          now: () => DateTime.utc(2026, 11, 14, 12, 0),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pump();

      // Alerts stream has not emitted yet -> loading indicator shown, NOT all-clear
      expect(find.byKey(const ValueKey('attention-all-clear')), findsNothing);
      expect(find.byKey(const ValueKey('attention-loading')), findsOneWidget);

      // Stream error -> shows retryable error state instead of all-clear or infinite loading
      alertsCtrl.addError(StateError('permission-denied'));
      await tester.pump();
      expect(find.byKey(const ValueKey('attention-all-clear')), findsNothing);
      expect(find.byKey(const ValueKey('attention-loading')), findsNothing);
      expect(find.byKey(const ValueKey('attention-error')), findsOneWidget);

      // Retry with a healthy alerts stream -> transitions to all-clear
      repo.useEmptyAlerts = true;
      await tester.tap(find.byKey(const ValueKey('attention-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attention-error')), findsNothing);
      expect(find.byKey(const ValueKey('attention-all-clear')), findsOneWidget);
    });

    testWidgets('refreshes time-based alert attention automatically as time crosses 48h and expiry boundaries',
        (tester) async {
      var fakeNow = DateTime.utc(2026, 11, 14, 12, 0);
      final endsAt = fakeNow.add(const Duration(hours: 48, seconds: 30));
      final repo = _TestAdminBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'liveUrl': ''},
        },
        initialCollections: {
          'alerts': [
            AdminDoc('a1', {
              'titleAr': 'تنويه',
              'titleEn': 'Notice',
              'visible': true,
              'active': true,
              'endsAt': endsAt,
            }),
          ],
        },
      );

      await tester.pumpWidget(_app(
        OverviewScreen(
          repo: repo,
          role: AdminRoles.editor,
          onOpen: (_) {},
          now: () => fakeNow,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pump();

      // 30s outside the 48h window -> all clear
      expect(find.byKey(const ValueKey('attention-all-clear')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-expiringAlerts')), findsNothing);

      // Advance 1 minute -> enters 48h window without any Firestore snapshot arriving
      fakeNow = fakeNow.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.byKey(const ValueKey('attention-expiringAlerts')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-all-clear')), findsNothing);

      // Advance past endsAt -> warning expires automatically
      fakeNow = endsAt.add(const Duration(seconds: 5));
      await tester.pump(const Duration(minutes: 1));
      expect(find.byKey(const ValueKey('attention-expiringAlerts')), findsNothing);
      expect(find.byKey(const ValueKey('attention-all-clear')), findsOneWidget);
    });

    testWidgets('OverviewScreen shows dash and retry after 10s when features stream stalls, without hiding loaded alerts',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var featuresWatches = 0;
      final featuresCtl = StreamController<AdminDoc?>.broadcast();
      addTearDown(featuresCtl.close);
      final repo = _SilentOverviewBackend(
        initialCollections: {
          'contact_messages': [
            AdminDoc('m1', {'status': 'new', 'message': 'hi'}),
          ],
        },
        onWatchDoc: (path) {
          if (path == 'settings/features') {
            featuresWatches++;
            return featuresCtl.stream;
          }
          return null;
        },
      );

      await tester.pumpWidget(_app(
        OverviewScreen(repo: repo, role: AdminRoles.owner, onOpen: (_) {}),
        locale: const Locale('ar'),
      ));
      await tester.pump();

      expect(featuresWatches, 1);
      // Loaded sections still render while settings/features is pending.
      expect(find.byKey(const ValueKey('attention-newMessages')), findsOneWidget);
      final summaryBefore = find.byKey(const ValueKey('sections-summary'));
      expect(find.descendant(of: summaryBefore, matching: find.text('…')), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));

      expect(find.descendant(of: summaryBefore, matching: find.text('—')), findsOneWidget);
      expect(find.descendant(of: summaryBefore, matching: find.text('…')), findsNothing);
      expect(find.byKey(const ValueKey('attention-newMessages')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('sections-retry')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping Retry re-subscribes and recovers once settings/features emits.
      await tester.ensureVisible(find.byKey(const ValueKey('sections-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sections-retry')));
      await tester.pump();
      expect(featuresWatches, 2);

      featuresCtl.add(AdminDoc('features', const {'liveEnabled': false, 'liveUrl': ''}));
      await tester.pump();
      expect(find.descendant(of: summaryBefore, matching: find.textContaining('${Sections.all.length}/${Sections.all.length}')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('attention-error')), findsNothing);
      expect(find.byKey(const ValueKey('sections-retry')), findsNothing);
    });

    testWidgets('OverviewScreen partial collection stall marks attention error after 10s and cancels timers on dispose',
        (tester) async {
      final messagesCtl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(messagesCtl.close);
      final repo = _SilentOverviewBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'liveUrl': ''},
        },
        onWatchCollection: (name) => name == 'contact_messages' ? messagesCtl.stream : null,
      );

      await tester.pumpWidget(_app(
        OverviewScreen(repo: repo, role: AdminRoles.owner, onOpen: (_) {}),
        locale: const Locale('en'),
      ));
      await tester.pump();

      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('attention-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('attention-retry')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('sections-summary')), matching: find.text('—')),
        findsNothing,
      );

      // Dispose before retry timer fires leaves no leaked active timers.
      await tester.tap(find.byKey(const ValueKey('attention-retry')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 15));
    });
  });

  group('PR 3F: P2-20, P2-22, P2-24 — priests merge, row actions & top-of-form layout', () {
    testWidgets('P2-20: serving/departed filter chips, defaulted add, isolated reorder ranges, & legacy dest',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'priests': [
          AdminDoc('s1', {'name': 'أبونا مينا', 'rank': 'priest', 'order': 10, 'visible': true}), // missing=serving
          AdminDoc('s2', {'name': 'أبونا بشوي', 'rank': 'priest', 'status': 'serving', 'order': 20, 'visible': true}),
          AdminDoc('d1', {'name': 'أبونا مرقس', 'rank': 'hegumen', 'status': 'departed', 'order': 1010, 'visible': true}),
          AdminDoc('d2', {'name': 'أبونا بولس', 'rank': 'priest', 'status': 'departed', 'order': 1020, 'visible': true}),
        ],
      });
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Default 'all' shows all 4, and blocks moving across groups.
      expect(find.text('أبونا مينا'), findsOneWidget);
      expect(find.text('أبونا مرقس'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('moveDown-s2'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('moveUp-d1'))).onPressed, isNull);

      // Reordering s2 up in 'all' view only sends serving IDs with base 0.
      await tester.tap(find.byKey(const ValueKey('moveUp-s2')));
      await tester.pumpAndSettle();
      expect(repo.reorderCalls.last.collection, 'priests');
      expect(repo.reorderCalls.last.ids, ['s2', 's1']);
      expect(repo.reorderCalls.last.base, 0);

      // Serving filter shows only serving priests.
      await tester.tap(find.byKey(const ValueKey('priestFilter-serving')));
      await tester.pumpAndSettle();
      expect(find.text('أبونا مينا'), findsOneWidget);
      expect(find.text('أبونا بشوي'), findsOneWidget);
      expect(find.text('أبونا مرقس'), findsNothing);

      // Departed filter shows only departed priests, reorders with base 1000 only departed IDs.
      await tester.tap(find.byKey(const ValueKey('priestFilter-departed')));
      await tester.pumpAndSettle();
      expect(find.text('أبونا مينا'), findsNothing);
      expect(find.text('أبونا مرقس'), findsOneWidget);
      expect(find.text('أبونا بولس'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moveDown-d1')));
      await tester.pumpAndSettle();
      expect(repo.reorderCalls.last.collection, 'priests');
      expect(repo.reorderCalls.last.ids, ['d2', 'd1']);
      expect(repo.reorderCalls.last.base, 1000);

      // Adding under departed filter defaults status to 'departed' on save.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-name')), 'أبونا يوسف');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(repo.savedDocs.last.data['status'], 'departed');

      // Deep linking legacy 'departedPriests' destination normalizes to 'priests'.
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminDashboard(
            repo: repo,
            uid: 'u-ed',
            email: 'editor@church.org',
            role: AdminRoles.editor,
            onSignOut: () {},
            initial: 'departedPriests',
          ),
          locale: const Locale('ar'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('priestFilter-departed')), findsOneWidget);
    });

    testWidgets('P2-22: row tap opens editor, openItem uses external-link icon, delete is separated & named',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
        'categories': [
          AdminDoc('cat1', {'nameAr': 'قسم الشباب', 'slug': 'youth', 'visible': true, 'order': 10}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'cat1', 'titleAr': 'اجتماع الخدام', 'visible': true, 'order': 10}),
        ],
      });

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // openItem-<id> uses open_in_new_rounded and has a clear Arabic label/tooltip.
      final openBtn = find.byKey(const ValueKey('openItem-p1'));
      expect(openBtn, findsOneWidget);
      expect(find.descendant(of: openBtn, matching: find.byIcon(Icons.open_in_new_rounded)), findsOneWidget);
      expect(find.descendant(of: openBtn, matching: find.text('عرض بالموقع')), findsOneWidget);

      // Delete has visible text label and sits in bottom row, vertically below visibility eye icon.
      final visFinder = find.byKey(const ValueKey('visibility-p1'));
      final delFinder = find.byKey(const ValueKey('delete-p1'));
      expect(find.descendant(of: delFinder, matching: find.text('حذف')), findsOneWidget);
      expect(tester.getTopLeft(delFinder).dy, greaterThan(tester.getBottomLeft(visFinder).dy));

      // Tapping the row opens DocEditor.
      await tester.tap(find.text('أبونا مينا'));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // Categories & sub-entries also separate delete from visibility, and category uses open_in_new_rounded.
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      final visEntry = find.byKey(const ValueKey('visibilityEntry-e1'));
      final delEntry = find.byKey(const ValueKey('deleteEntry-e1'));
      final openCat = find.byKey(const ValueKey('openItem-cat1'));
      expect(find.descendant(of: openCat, matching: find.byIcon(Icons.open_in_new_rounded)), findsOneWidget);
      expect(find.descendant(of: delEntry, matching: find.text('حذف')), findsOneWidget);
      expect(tester.getTopLeft(delEntry).dy, greaterThanOrEqualTo(tester.getBottomLeft(visEntry).dy));
    });

    testWidgets('row visibility eye shows spinner, ignores rapid double-tap, and completes cleanly on all 4 row builders',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا تادرس', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
        'categories': [
          AdminDoc('shared-id', {'nameAr': 'قسم الشباب', 'slug': 'youth', 'visible': true, 'order': 10}),
        ],
        'entries': [
          AdminDoc('shared-id', {'categoryId': 'shared-id', 'titleAr': 'اجتماع الخدام', 'visible': true, 'order': 10}),
        ],
        'pages': [
          AdminDoc('sp1', {
            'titleAr': 'صفحة القسم',
            'slug': 'sec-page',
            'placement': 'section',
            'categoryId': 'shared-id',
            'visible': true,
          }),
        ],
      });
      addTearDown(repo.dispose);

      // 1) Standard _tile on priests
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final p1Completer = repo.hold('priests', 'p1');
      final p1Btn = find.byKey(const ValueKey('visibility-p1'));
      await tester.tap(p1Btn);
      await tester.pump();

      expect(find.descendant(of: p1Btn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(tester.widget<IconButton>(p1Btn).onPressed, isNull);
      expect(tester.widget<IconButton>(p1Btn).tooltip, 'جارٍ الحفظ…');
      await tester.tap(p1Btn, warnIfMissed: false);
      await tester.pump();
      expect(repo.updates.where((u) => u.collection == 'priests' && u.id == 'p1'), hasLength(1));
      expect(find.byType(DocEditor), findsNothing);

      p1Completer.complete();
      await tester.pumpAndSettle();
      expect(p1Btn, findsOneWidget);
      expect(find.descendant(of: p1Btn, matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(find.descendant(of: p1Btn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);
      expect(tester.widget<IconButton>(p1Btn).tooltip, 'إظهار في الموقع');
      expect(find.text('أصبح العنصر مخفيًا'), findsOneWidget);

      // 2) Categories screen: _categoryTile, _sectionPageRow, and _entryRow sharing 'shared-id'
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final catCompleter = repo.hold('categories', 'shared-id');
      final entryCompleter = repo.hold('entries', 'shared-id');
      final pageCompleter = repo.hold('pages', 'sp1');

      final catBtn = find.byKey(const ValueKey('visibility-shared-id'));
      final entryBtn = find.byKey(const ValueKey('visibilityEntry-shared-id'));
      final pageBtn = find.byKey(const ValueKey('visibilitySectionPage-sp1'));

      // Tap category eye -> locked with spinner, while entry & page with same/different IDs stay interactive.
      await tester.tap(catBtn);
      await tester.pump();
      expect(find.descendant(of: catBtn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(tester.widget<IconButton>(catBtn).onPressed, isNull);
      expect(tester.widget<IconButton>(entryBtn).onPressed, isNotNull);
      expect(tester.widget<IconButton>(pageBtn).onPressed, isNotNull);

      await tester.tap(entryBtn);
      await tester.tap(pageBtn);
      await tester.pump();
      expect(find.descendant(of: entryBtn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: pageBtn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      catCompleter.complete();
      entryCompleter.complete();
      pageCompleter.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.descendant(of: catBtn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);
      expect(find.descendant(of: entryBtn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);
      expect(find.descendant(of: pageBtn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);
    });

    testWidgets('row visibility eye rolls back visual state and shows error SnackBar when update fails',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا بولس', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final c = repo.hold('priests', 'p1');
      final btn = find.byKey(const ValueKey('visibility-p1'));
      await tester.tap(btn);
      await tester.pump();
      expect(find.descendant(of: btn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      c.completeError(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Denied',
      ));
      await tester.pumpAndSettle();

      // Reverted to visible: true
      expect(find.descendant(of: btn, matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(find.descendant(of: btn, matching: find.byIcon(Icons.visibility_outlined)), findsOneWidget);
      expect(tester.widget<IconButton>(btn).onPressed, isNotNull);
      expect(tester.widget<IconButton>(btn).tooltip, 'إخفاء من الموقع');
      expect(find.text('ظاهر'), findsOneWidget);
      expect(find.textContaining('[permission-denied]'), findsOneWidget);
    });

    testWidgets('filtered-out visibility toggle clears _optimisticVisible on stream update and sub-row swaps ignore old epoch',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. Filter to Visible, hide 'p1' so it disappears from visible list, then externally stream visible: true.
      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا فلان', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
        'categories': [
          AdminDoc('cat1', {'nameAr': 'قسم ١', 'slug': 'sec1', 'visible': true, 'order': 10}),
        ],
        'entries': [
          AdminDoc('shared-sub', {'categoryId': 'cat1', 'titleAr': 'عنصر مشترك', 'visible': true, 'order': 10}),
        ],
        'pages': [
          AdminDoc('shared-sub', {'categoryId': 'cat1', 'titleAr': 'صفحة مشتركة', 'slug': 'shared-sub', 'visible': true, 'order': 10}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Switch filter to Visible ('الظاهر').
      await tester.tap(find.text('الظاهر'));
      await tester.pumpAndSettle();

      final hideCompleter = repo.hold('priests', 'p1');
      await tester.tap(find.byKey(const ValueKey('visibility-p1')));
      await tester.pump();

      // Verify tap-absorption GestureDetector excludes semantics while button is disabled.
      final p1Gesture = tester.widget<GestureDetector>(
        find.ancestor(of: find.byKey(const ValueKey('visibility-p1')), matching: find.byType(GestureDetector)).first,
      );
      expect(p1Gesture.excludeFromSemantics, isTrue);

      hideCompleter.complete();
      await tester.pumpAndSettle();
      // Under ListFilter.visible, p1 is filtered out of built rows.
      expect(find.byKey(const ValueKey('visibility-p1')), findsNothing);

      // Simulate another admin restoring visible: true via external update while ListFilter.visible is still active.
      await repo.update('priests', 'p1', {'visible': true});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('visibility-p1')), findsOneWidget);
      expect(find.text('ظاهر'), findsOneWidget);
      expect(find.text('مخفي'), findsNothing);

      // Let the previous 2 s SnackBar expire before checking step 2's SnackBar absence.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // 2. Categories sub-row (targetDef != null) in-flight when collection swaps on SAME repo -> ignored cleanly.
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final entryHold = repo.hold('entries', 'shared-sub');
      await tester.tap(find.byKey(const ValueKey('visibilityEntry-shared-sub')));
      await tester.pump();

      // Swap widget.def on SAME repo before entryHold completes!
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('pages')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      entryHold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('newer visibility snapshot with omitted intermediate state releases optimistic override',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا فلان', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Hide completes without delivering the intermediate `visible: false` snapshot first;
      // then a newer authoritative `visible: true` snapshot arrives from another admin.
      repo.emitOnUpdate = false;
      await tester.tap(find.byKey(const ValueKey('visibility-p1')));
      await tester.pumpAndSettle();

      expect(find.text('مخفي'), findsOneWidget);
      expect(find.text('ظاهر'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('visibility-p1')),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsOneWidget,
      );

      repo.collections['priests']![0].data['visible'] = true;
      repo.emitSnapshot('priests');
      await tester.pumpAndSettle();

      expect(find.text('ظاهر'), findsOneWidget);
      expect(find.text('مخفي'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('visibility-p1')), matching: find.byIcon(Icons.visibility_outlined)), findsOneWidget);
    });

    testWidgets(
        'stale snapshot delivered before Hide completes but built afterward does not clear optimistic Hide',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا فلان', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final hideHold = repo.hold('priests', 'p1');
      repo.emitOnUpdate = false;
      await tester.tap(find.byKey(const ValueKey('visibility-p1')));
      await tester.pump();

      // Deliver a stale `visible: true` snapshot at t=0, flush microtasks before completing Hide at t=1ms,
      // and then pump a frame at t=5ms so the frame builds after Hide has already settled.
      repo.emitSnapshot('priests');
      Timer(const Duration(milliseconds: 1), hideHold.complete);
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('مخفي'), findsOneWidget);
      expect(find.text('ظاهر'), findsNothing);

      // A genuinely newer snapshot delivered after Hide settled clears the optimistic override.
      repo.collections['priests']![0].data['visible'] = true;
      repo.emitSnapshot('priests');
      await tester.pumpAndSettle();

      expect(find.text('ظاهر'), findsOneWidget);
      expect(find.text('مخفي'), findsNothing);
    });

    testWidgets(
        'unrelated collection snapshot does not clear pending page optimistic visibility on categories screen',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'categories': [
          AdminDoc('cat1', {'nameAr': 'قسم ١', 'slug': 'sec1', 'visible': true, 'order': 10}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'cat1', 'titleAr': 'عنصر ١', 'visible': true, 'order': 10}),
        ],
        'pages': [
          AdminDoc('sp1', {
            'placement': 'section',
            'categoryId': 'cat1',
            'titleAr': 'صفحة ١',
            'slug': 'sp1',
            'visible': true,
            'order': 10,
          }),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Toggle section page sp1 offline of snapshot delivery so _settledAtStreamSeq['pages:sp1'] stays stamped.
      repo.emitOnUpdate = false;
      final spBtn = find.byKey(const ValueKey('visibilitySectionPage-sp1'));
      await tester.tap(spBtn);
      await tester.pumpAndSettle();
      expect(find.descendant(of: spBtn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);

      // Unrelated snapshot on entries must NOT clear the pending pages:sp1 override.
      repo.collections['entries']![0].data['titleAr'] = 'عنصر ١ محدث';
      repo.emitSnapshot('entries');
      await tester.pumpAndSettle();
      expect(find.descendant(of: spBtn, matching: find.byIcon(Icons.visibility_off_outlined)), findsOneWidget);

      // A newer snapshot on pages itself DOES release the override to the authoritative value.
      repo.collections['pages']![0].data['visible'] = true;
      repo.emitSnapshot('pages');
      await tester.pumpAndSettle();
      expect(find.descendant(of: spBtn, matching: find.byIcon(Icons.visibility_outlined)), findsOneWidget);
    });

    testWidgets(
        'rapid taps on row visibility eye at 320px / 200% keep >=48x48 hit target, write once, and never open DocEditor',
        variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.windows}),
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final repo = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا فلان', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      final btn = find.byKey(const ValueKey('visibility-p1'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      final idleSize = tester.getSize(btn);
      final idleTopLeft = tester.getTopLeft(btn);
      expect(idleSize.width, greaterThanOrEqualTo(48));
      expect(idleSize.height, greaterThanOrEqualTo(48));

      // 4+ rapid taps on eye center, corners, and trailing margin beneath eye must not open DocEditor.
      final c = repo.hold('priests', 'p1');
      await tester.tap(btn);
      await tester.tap(btn); // Tap 2 before rebuild: ignored by _togglingVisibility
      await tester.pump();

      final savingSize = tester.getSize(btn);
      final savingTopLeft = tester.getTopLeft(btn);
      expect(savingSize.width, greaterThanOrEqualTo(48));
      expect(savingSize.height, greaterThanOrEqualTo(48));
      expect((savingTopLeft - idleTopLeft).distance, lessThanOrEqualTo(0.1));
      expect(find.descendant(of: btn, matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      await tester.tap(btn, warnIfMissed: false); // Tap 3 while saving
      final outerCorner = tester.getTopLeft(btn) + const Offset(2, 2);
      await tester.tapAt(outerCorner); // Tap 4 on outer 48x48 rim while saving
      // Trailing space directly beneath eye button is outside ListTile InkWell and never opens DocEditor.
      await tester.tapAt(tester.getRect(btn).bottomCenter + const Offset(0, 6));
      await tester.pump();
      expect(find.byType(DocEditor), findsNothing);

      // Start another tap while saving, finish the backend write BEFORE pointerUp, then release.
      final heldTap = await tester.startGesture(tester.getCenter(btn));
      await tester.pump();
      c.complete();
      await tester.pumpAndSettle();
      await heldTap.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DocEditor), findsNothing);
      expect(repo.updates.where((u) => u.collection == 'priests' && u.id == 'p1'), hasLength(1));

      // Tapping the row body (title) still opens DocEditor normally.
      await tester.tap(find.text('أبونا فلان'));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);
    });

    testWidgets(
        'desktop visibility eye: 5 rapid taps during write toggle once, taps 0.6s apart toggle separately, and never open DocEditor',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _ControlledUpdateBackend(initialCollections: {
        'liturgies': [
          AdminDoc('l1', {'type': 'mass', 'nameAr': 'قداس الأحد', 'weekday': 7, 'start': '07:00', 'visible': true}),
        ],
      });
      addTearDown(repo.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final btn = find.byKey(const ValueKey('visibility-l1'));
      final rect = tester.getRect(btn);

      // 5 rapid taps while write is in flight -> exactly 1 write, 0 DocEditor opens.
      final firstWrite = repo.hold('liturgies', 'l1');
      for (var i = 0; i < 5; i++) {
        await tester.tapAt(i.isEven ? rect.center : rect.topLeft + const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(repo.updates.where((u) => u.collection == 'liturgies' && u.id == 'l1'), hasLength(1));
      expect(find.byType(DocEditor), findsNothing);

      // Finish first write, wait 600ms, then tap again (separate intentional toggle) -> 2nd write, still 0 DocEditor.
      firstWrite.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      final secondWrite = repo.hold('liturgies', 'l1');
      await tester.tap(btn);
      await tester.pump();
      // Tap rim and trailing edge directly beneath eye while second write settles -> still never opens DocEditor.
      await tester.tapAt(rect.bottomRight - const Offset(1, 1));
      await tester.tapAt(rect.bottomCenter + const Offset(0, 4));
      secondWrite.complete();
      await tester.pumpAndSettle();

      final visUpdates = repo.updates.where((u) => u.collection == 'liturgies' && u.id == 'l1').toList();
      expect(visUpdates, hasLength(2));
      expect(visUpdates[0].data['visible'], isFalse);
      expect(visUpdates[1].data['visible'], isTrue);
      expect(find.byType(DocEditor), findsNothing);
    });

    testWidgets('row visibility in-flight completion after dispose or repo swap does not throw', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo1 = _ControlledUpdateBackend(initialCollections: {
        'priests': [
          AdminDoc('p1', {'name': 'أبونا يوحنا', 'rank': 'priest', 'status': 'serving', 'visible': true}),
          AdminDoc('p2', {'name': 'أبونا متى', 'rank': 'priest', 'status': 'serving', 'visible': true}),
        ],
      });
      final repo2 = _ControlledUpdateBackend(initialCollections: {
        'saints': [
          AdminDoc('p1', {'nameAr': 'مارمرقس', 'visible': true, 'order': 10}),
        ],
      });
      addTearDown(repo1.dispose);
      addTearDown(repo2.dispose);

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo1, def: collectionById('priests')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final c1 = repo1.hold('priests', 'p1');
      final c2 = repo1.hold('priests', 'p2');
      await tester.tap(find.byKey(const ValueKey('visibility-p1')));
      await tester.tap(find.byKey(const ValueKey('visibility-p2')));
      await tester.pump();

      // Swap repo & collection while writes are in flight
      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo2, def: collectionById('saints')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Complete and fail old repo writes -> no setState after swap, saints p1 unaffected
      c1.complete();
      c2.completeError(StateError('late error'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('visibility-p1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('visibility-p1')), matching: find.byIcon(Icons.visibility_outlined)), findsOneWidget);

      // Unmount completely during in-flight write
      final c3 = repo2.hold('saints', 'p1');
      await tester.tap(find.byKey(const ValueKey('visibility-p1')));
      await tester.pump();
      await tester.pumpWidget(_app(const SizedBox.shrink(), locale: const Locale('ar')));
      c3.completeError(StateError('after dispose'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('blockSnippetSummary: extracts and formats preview snippet per BlockType', () {
      // 1. Image
      // Caption present -> returns truncated caption
      expect(blockSnippetSummary(type: BlockTypes.image, textAr: 'صورة تجربة'), 'صورة تجربة');
      expect(blockSnippetSummary(type: BlockTypes.image, textEn: 'Test image'), 'Test image');
      // Caption empty, url present -> returns null (suppressed)
      expect(blockSnippetSummary(type: BlockTypes.image, url: 'https://example.com/a.jpg'), isNull);
      // Caption empty, url empty -> returns '' (empty)
      expect(blockSnippetSummary(type: BlockTypes.image), '');

      // 2. Button and Link: textAr / textEn first, then url
      expect(blockSnippetSummary(type: BlockTypes.button, textAr: 'زر تجربة', url: '/home'), 'زر تجربة');
      expect(blockSnippetSummary(type: BlockTypes.button, url: '/contact'), '/contact');
      expect(blockSnippetSummary(type: BlockTypes.button), '');

      expect(blockSnippetSummary(type: BlockTypes.link, textEn: 'Link label', url: 'https://example.com'), 'Link label');
      expect(blockSnippetSummary(type: BlockTypes.link, url: 'https://example.com'), 'https://example.com');
      expect(blockSnippetSummary(type: BlockTypes.link), '');

      // 3. Heading and Paragraph: textAr / textEn only
      expect(blockSnippetSummary(type: BlockTypes.heading, textAr: 'عنوان رئيسي'), 'عنوان رئيسي');
      expect(blockSnippetSummary(type: BlockTypes.heading, url: 'https://ignored.com'), '');

      expect(blockSnippetSummary(type: BlockTypes.paragraph, textEn: 'Paragraph body'), 'Paragraph body');
      expect(blockSnippetSummary(type: BlockTypes.paragraph), '');

      // 4. Donation: textAr, textEn, account, instapay, wallet
      expect(blockSnippetSummary(type: BlockTypes.donation, textAr: 'ملاحظات التبرع'), 'ملاحظات التبرع');
      expect(blockSnippetSummary(type: BlockTypes.donation, account: '123456789'), '123456789');
      expect(blockSnippetSummary(type: BlockTypes.donation, instapay: 'user@instapay'), 'user@instapay');
      expect(blockSnippetSummary(type: BlockTypes.donation, wallet: '01012345678'), '01012345678');
      expect(blockSnippetSummary(type: BlockTypes.donation), '');

      // 5. Whitespace collapsing and 40-character truncation
      const multiLine = '   السطر الأول \n\n  السطر    الثاني \t  ';
      expect(blockSnippetSummary(type: BlockTypes.paragraph, textAr: multiLine), 'السطر الأول السطر الثاني');

      const longText = 'هذا نص طويل جداً جداً جداً جداً جداً جداً جداً جداً يتعدى أربعين حرفاً بالتأكيد';
      final truncated = blockSnippetSummary(type: BlockTypes.paragraph, textAr: longText);
      expect(truncated, isNotNull);
      expect(truncated!.endsWith('…'), isTrue);
      expect(truncated.substring(0, 40), longText.substring(0, 40));

      // 6. List: empty -> '', 1 item -> clipped first item, >1 items -> (+N) AR & EN
      expect(blockSnippetSummary(type: BlockTypes.list), '');
      expect(blockSnippetSummary(type: BlockTypes.list, textAr: '   \u001e  '), '');
      expect(
        blockSnippetSummary(type: BlockTypes.list, textAr: 'تجربة عنصر واحد'),
        'تجربة عنصر واحد',
      );
      expect(
        blockSnippetSummary(
          type: BlockTypes.list,
          textAr: 'تجربة أول\u001eتجربة ثانٍ\u001eتجربة ثالث',
          isAr: true,
        ),
        'تجربة أول (+٢)',
      );
      expect(
        blockSnippetSummary(
          type: BlockTypes.list,
          textAr: 'تجربة أول\u001eتجربة ثانٍ\u001eتجربة ثالث',
          isAr: false,
        ),
        'تجربة أول (+2)',
      );
      final longListSnippet = blockSnippetSummary(
        type: BlockTypes.list,
        textAr: '$longText\u001eتجربة ثانٍ',
        isAr: true,
      );
      expect(longListSnippet, '${longText.substring(0, 40)}… (+١)');
    });

    testWidgets('CollectionListScreen displays "فاضي، مش ظاهر للزوار" chip for categories without visible entries or visible section pages', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'categories': [
          AdminDoc('cat-empty', {
            'nameAr': 'قسم فارغ',
            'nameEn': 'Empty Section',
            'slug': 'empty-cat',
            'order': 10,
            'visible': true,
          }),
          AdminDoc('cat-with-entry', {
            'nameAr': 'قسم فيه عناصر',
            'nameEn': 'With Entries',
            'slug': 'with-entries',
            'order': 20,
            'visible': true,
          }),
          AdminDoc('cat-with-page', {
            'nameAr': 'قسم فيه صفحة',
            'nameEn': 'With Section Page',
            'slug': 'with-page',
            'order': 30,
            'visible': true,
          }),
        ],
        'entries': [
          AdminDoc('e1', {
            'categoryId': 'cat-with-entry',
            'titleAr': 'عنصر 1',
            'visible': true,
          }),
        ],
        'pages': [
          AdminDoc('p1', {
            'categoryId': 'cat-with-page',
            'titleAr': 'صفحة قسم',
            'slug': 'page-sec',
            'placement': 'section',
            'visible': true,
          }),
        ],
      });

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // "فاضي، مش ظاهر للزوار" tag appears on cat-empty, but NOT on cat-with-entry or cat-with-page
      expect(find.text('فاضي، مش ظاهر للزوار'), findsOneWidget);
      final emptyCard = find.byKey(const ValueKey('cat-empty'));
      expect(find.descendant(of: emptyCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsOneWidget);

      final entryCard = find.byKey(const ValueKey('cat-with-entry'));
      expect(find.descendant(of: entryCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsNothing);

      final pageCard = find.byKey(const ValueKey('cat-with-page'));
      expect(find.descendant(of: pageCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsNothing);
    });

    testWidgets('CollectionListScreen(categories) unifies category emptiness and displays linked section pages', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'categories': [
          AdminDoc('cat-church', {
            'nameAr': 'كنيسه',
            'nameEn': 'Church',
            'slug': 'church',
            'order': 10,
            'visible': true,
          }),
          AdminDoc('cat-hidden-page', {
            'nameAr': 'قسم صفحة مخفية',
            'nameEn': 'Section Hidden Page',
            'slug': 'hidden-page-cat',
            'order': 20,
            'visible': true,
          }),
          AdminDoc('cat-empty', {
            'nameAr': 'قسم فارغ تماما',
            'nameEn': 'Empty Section',
            'slug': 'empty-cat',
            'order': 30,
            'visible': true,
          }),
        ],
        'entries': [],
        'pages': [
          AdminDoc('p-donations', {
            'categoryId': 'cat-church',
            'titleAr': 'التبرعات',
            'titleEn': 'Donations',
            'slug': 'donations',
            'placement': 'section',
            'visible': true,
          }),
          AdminDoc('p-hidden', {
            'categoryId': 'cat-hidden-page',
            'titleAr': 'صفحة خاصة',
            'titleEn': 'Private Page',
            'slug': 'private',
            'placement': 'section',
            'visible': false,
          }),
        ],
      });

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('categories')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final churchCard = find.byKey(const ValueKey('cat-church'));
      final hiddenPageCard = find.byKey(const ValueKey('cat-hidden-page'));
      final emptyCard = find.byKey(const ValueKey('cat-empty'));

      // 1. cat-church with 0 entries and 1 visible placement == 'section' page ("التبرعات"):
      // renders "التبرعات" row inside "كنيسه"
      expect(find.descendant(of: churchCard, matching: find.byKey(const Key('sectionPageRow-p-donations'))), findsOneWidget);
      expect(find.descendant(of: churchCard, matching: find.text('التبرعات')), findsOneWidget);
      expect(find.descendant(of: churchCard, matching: find.text('صفحة')), findsOneWidget);
      // hides "مفيش عناصر في القسم ده لسه"
      expect(find.descendant(of: churchCard, matching: find.text('مفيش عناصر في القسم ده لسه')), findsNothing);
      // hides "فاضي، مش ظاهر للزوار" chip
      expect(find.descendant(of: churchCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsNothing);

      // 2. cat-hidden-page with 0 entries and 1 hidden (visible: false) placement == 'section' page:
      // still shows the page row in Admin
      expect(find.descendant(of: hiddenPageCard, matching: find.byKey(const Key('sectionPageRow-p-hidden'))), findsOneWidget);
      expect(find.descendant(of: hiddenPageCard, matching: find.text('صفحة خاصة')), findsOneWidget);
      // hides sectionEmptyItems
      expect(find.descendant(of: hiddenPageCard, matching: find.text('مفيش عناصر في القسم ده لسه')), findsNothing);
      // STILL shows "فاضي، مش ظاهر للزوار" chip (matching isCategoryNonEmpty!)
      expect(find.descendant(of: hiddenPageCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsOneWidget);

      // 3. cat-empty with 0 entries and 0 section pages:
      // shows both "فاضي، مش ظاهر للزوار" and sectionEmptyItems
      expect(find.descendant(of: emptyCard, matching: find.text('فاضي، مش ظاهر للزوار')), findsOneWidget);
      expect(find.descendant(of: emptyCard, matching: find.text('مفيش عناصر في القسم ده لسه')), findsOneWidget);
    });

    testWidgets('AdminLoginPage uses emailLabel from l10n in Arabic and English', (tester) async {
      await tester.pumpWidget(_app(
        Scaffold(
          body: AdminLoginForm(
            onSignIn: (email, password, {rememberMe = false}) async {},
            onResetPassword: (_) async => true,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('البريد الإلكتروني'), findsOneWidget);

      await tester.pumpWidget(_app(
        Scaffold(
          body: AdminLoginForm(
            onSignIn: (email, password, {rememberMe = false}) async {},
            onResetPassword: (_) async => true,
          ),
        ),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('P2-24: phone & photo open at top; advanced card validates while closed & renders cleanly at 320px/200%',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. Facilities: phone field is visible immediately without tapping any ExpansionTile.
      final facDef = collectionById('facilities')!;
      await tester.pumpWidget(_app(
        DocEditor(
            key: const ValueKey('fac-new'),
            title: 'Facility',
            fields: facDef.fields,
            def: facDef,
            popOnSave: false,
            onSave: (_) async {}),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-phone')), findsOneWidget);
      expect(find.byKey(const Key('imageUploadBtn')), findsOneWidget);

      // 2. Priests: photo, name, rank are top fields above groupCard-advanced; Arabic title is "خيارات متقدمة".
      final priestDef = collectionById('priests')!;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('priest-layout'),
          title: 'Priest',
          fields: priestDef.fields,
          def: priestDef,
          popOnSave: false,
          data: const {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving'},
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final photoY = tester.getTopLeft(find.byKey(const Key('imageUploadBtn'))).dy;
      final nameY = tester.getTopLeft(find.byKey(const ValueKey('field-name'))).dy;
      final rankY = tester.getTopLeft(find.byKey(const ValueKey('field-rank'))).dy;
      final advCardY = tester.getTopLeft(find.byKey(const ValueKey('groupCard-advanced'))).dy;
      expect(photoY, lessThan(nameY));
      expect(nameY, lessThan(rankY));
      expect(rankY, lessThan(advCardY));
      expect(find.descendant(of: find.byKey(const ValueKey('groupCard-advanced')), matching: find.text('خيارات متقدمة')),
          findsOneWidget);

      // Put invalid input into advanced field while closed -> save shows error summary; tapping summary opens the card.
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('priest-bad-adv'),
          title: 'Priest',
          fields: priestDef.fields,
          def: priestDef,
          popOnSave: false,
          data: const {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving', 'order': 'bad'},
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-order')).hitTestable(), findsNothing);
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('error-summary-order')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-order')).hitTestable(), findsOneWidget);

      // Valid values under closed advanced card still save without needing to expand it.
      saved = null;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('priest-valid-adv'),
          title: 'Priest',
          fields: priestDef.fields,
          def: priestDef,
          popOnSave: false,
          data: const {'name': 'أبونا مينا', 'rank': 'priest', 'status': 'serving', 'nameEn': 'Fr. Mina', 'order': 15},
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('groupCard-advanced')), matching: find.text('Advanced options')),
          findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-contactPhone')), '01012345678');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, {'contactPhone': '01012345678'});

      // 3. Narrow 320px at 200% text in both RTL & LTR without overflow.
      tester.view.physicalSize = const Size(320, 6000);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        await tester.pumpWidget(_app(
          DocEditor(
              key: ValueKey('priest-320-${locale.languageCode}'),
              title: 'Priest',
              fields: priestDef.fields,
              def: priestDef,
              popOnSave: false,
              onSave: (_) async {}),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale=${locale.languageCode}');
      }
    });
  });

  group('PR 3G: P2-27a & P2-27b — error summary banner & English switch', () {
    testWidgets('P2-27a: two invalid fields show summary of 2, tap opens card + focuses field, fixing clears summary',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final priestDef = collectionById('priests')!;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('err-summary-editor'),
          title: 'الآباء',
          fields: priestDef.fields,
          def: priestDef,
          popOnSave: false,
          data: const {'name': '', 'rank': 'priest', 'status': 'serving', 'order': 'not-int'},
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);
      expect(find.text('فيه حقلين محتاجين تصحيح'), findsOneWidget);
      expect(find.byKey(const ValueKey('error-summary-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('error-summary-order')), findsOneWidget);

      // Tapping the order entry expands the closed advanced card and focuses field-order.
      await tester.tap(find.byKey(const ValueKey('error-summary-order')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-order')).hitTestable(), findsOneWidget);
      final orderFocus = FocusManager.instance.primaryFocus;
      expect(orderFocus, isNotNull);
      expect(
        find.ancestor(of: find.byWidgetPredicate((w) => w is Focus && w.focusNode == orderFocus), matching: find.byKey(const ValueKey('field-order'))),
        findsOneWidget,
      );

      // Fixing both invalid fields clears the error summary automatically.
      await tester.enterText(find.byKey(const ValueKey('field-order')), '5');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);
      expect(find.text('فيه حقل واحد محتاج تصحيح'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('field-name')));
      await tester.enterText(find.byKey(const ValueKey('field-name')), 'أبونا يوحنا');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-error-summary')), findsNothing);
    });

    testWidgets('P2-27b: FeaturesEditor shows englishEnabled switch for owner only and saves only when changed',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FeatureSettings? saved;
      await tester.pumpWidget(_app(
        Scaffold(
          body: FeaturesEditor(
            key: const ValueKey('feat-editor-role'),
            initial: FeatureSettings.defaults,
            isOwner: false,
            onSave: (f) async => saved = f,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('features-englishEnabled')), findsNothing);

      await tester.pumpWidget(_app(
        Scaffold(
          body: FeaturesEditor(
            key: const ValueKey('feat-owner-role'),
            initial: FeatureSettings.defaults,
            isOwner: true,
            onSave: (f) async => saved = f,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      final swFinder = find.byKey(const ValueKey('features-englishEnabled'));
      expect(swFinder, findsOneWidget);
      expect(tester.widget<AdminStateSwitch>(swFinder).value, isTrue);

      await tester.ensureVisible(swFinder);
      await tester.tap(swFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<AdminStateSwitch>(swFinder).value, isFalse);

      // English text fields in FeaturesEditor disappear when englishEnabled is toggled off.
      expect(find.text('عنوان الصفحة الرئيسية (إنجليزي)'), findsNothing);

      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved?.englishEnabled, isFalse);

      // featuresSaveWrites omits englishEnabled when unchanged from stored doc (safe for editors).
      final editorWrites = featuresSaveWrites(
        FeatureSettings.defaults.copyWith(theme: 'navy'),
        FeatureSettings.defaults.toMap(),
      );
      expect(editorWrites.first.containsKey('englishEnabled'), isFalse);

      final ownerWrites = featuresSaveWrites(
        FeatureSettings.defaults.copyWith(englishEnabled: false),
        FeatureSettings.defaults.toMap(),
      );
      expect(ownerWrites.first['englishEnabled'], isFalse);
    });

    testWidgets('P2-27b: DocEditor(englishEnabled: false) hides EN fields, saves Arabic-only, & preserves stored EN',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      final existingChurch = <String, dynamic>{
        'nameAr': 'كنيسة القديسين',
        'nameEn': 'St. Maximus Church',
        'addressAr': 'شارع ٤٥، العصافرة',
        'verseAr': 'الرب نوري',
        'verseEn': 'The Lord is my light',
        'verseRefAr': 'مز ٢٧: ١',
        'verseRef': 'Ps 27:1',
        'phones': [
          {'labelAr': 'المكتب', 'labelEn': 'Office', 'number': '035368888'},
        ],
        'altars': [
          {'nameAr': 'مذبح العذراء', 'nameEn': 'St. Mary Altar'},
        ],
      };

      // 1. Arabic-only new church info doc saves even though nameEn is marked required in schema.
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('church-ar-only'),
          title: churchInfoDoc.labelAr,
          fields: churchInfoDoc.fields,
          popOnSave: false,
          englishEnabled: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-nameEn')), findsNothing);
      expect(find.byKey(const ValueKey('field-verseEn')), findsNothing);
      expect(find.byKey(const ValueKey('field-verseRef')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'كنيسة العصافرة');
      await tester.enterText(find.byKey(const ValueKey('field-addressAr')), 'شارع ٤٥، العصافرة');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['nameAr'], 'كنيسة العصافرة');

      // 2. Editing an existing doc while englishEnabled is false preserves stored EN fields & subfields untouched.
      saved = null;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('church-preserve-en'),
          title: churchInfoDoc.labelAr,
          fields: churchInfoDoc.fields,
          data: existingChurch,
          popOnSave: false,
          englishEnabled: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-nameEn')), findsNothing);
      expect(find.text('Office'), findsNothing);
      expect(find.text('St. Mary Altar'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('field-nameAr')).first, 'كنيسة القديسين الجديدة');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, {'nameAr': 'كنيسة القديسين الجديدة'});

      // 3. Reopening with englishEnabled: true restores stored English values.
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('church-restored-en'),
          title: churchInfoDoc.labelAr,
          fields: churchInfoDoc.fields,
          data: {...existingChurch, ...?saved},
          popOnSave: false,
          englishEnabled: true,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      for (final gKey in const ['group-contacts', 'group-hero', 'group-history']) {
        final tile = find.byKey(ValueKey(gKey));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('field-nameEn')), findsNWidgets(2));
      expect(find.text('St. Maximus Church'), findsOneWidget);
      expect(find.text('The Lord is my light'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('St. Mary Altar'), findsOneWidget);
    });

    testWidgets('P2-27b: _groupCard excludes EN fields so invalid stored EN does not block Arabic save',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      final meetingsDef = collectionById('meetings')!;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('meeting-ar-only-groups'),
          title: meetingsDef.labelAr,
          fields: meetingsDef.fields,
          def: meetingsDef,
          data: {
            'stage': 'youth',
            'nameAr': 'اجتماع الشباب',
            'speakerEn': 'S' * 250, // > 200 max when English enabled
            'detailsEn': 'D' * 10050, // > 10000 max when English enabled
            'contactNoteEn': 'N' * 600, // > 500 max when English enabled
          },
          popOnSave: false,
          englishEnabled: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Grouped English fields must not be mounted inside group cards (even after expanding them).
      for (final gKey in const ['group-program', 'group-details', 'group-contacts']) {
        final tile = find.byKey(ValueKey(gKey));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('field-speakerEn')), findsNothing);
      expect(find.byKey(const ValueKey('field-detailsEn')), findsNothing);
      expect(find.byKey(const ValueKey('field-contactNoteEn')), findsNothing);

      final nameAr = find.byKey(const ValueKey('field-nameAr'));
      await tester.ensureVisible(nameAr);
      await tester.enterText(nameAr, 'اجتماع الشباب الجديد');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-error-summary')), findsNothing);
      expect(saved, {'nameAr': 'اجتماع الشباب الجديد'});
    });

    testWidgets('P2-27b: DocEditor.collect excludes hidden EN drafts when englishEnabled flips false',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      Widget buildEditor(bool en) => _app(
            DocEditor(
              key: const ValueKey('church-en-flip'),
              title: churchInfoDoc.labelAr,
              fields: churchInfoDoc.fields,
              data: const {
                'nameAr': 'كنيسة',
                'nameEn': 'St. Maximus',
                'addressAr': 'شارع ٤٥',
                'phones': [
                  {'number': '01223344556', 'labelAr': 'المكتب', 'labelEn': 'Office'},
                ],
              },
              popOnSave: false,
              englishEnabled: en,
              onSave: (d) async => saved = d,
            ),
            locale: const Locale('ar'),
          );

      await tester.pumpWidget(buildEditor(true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('field-nameEn')), 'X' * 350);
      await tester.tap(find.byKey(const ValueKey('group-contacts')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-labelEn')).first, 'Draft Office');
      await tester.pumpAndSettle();

      await tester.pumpWidget(buildEditor(false));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('field-nameEn')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'كنيسة محدثة');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(saved, {'nameAr': 'كنيسة محدثة'});
    });

    testWidgets('P2-27a: pending error focus clears after expansion/edit so subsequent typing keeps focus',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final meetingsDef = collectionById('meetings')!;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('meeting-focus-clear'),
          title: meetingsDef.labelAr,
          fields: meetingsDef.fields,
          def: meetingsDef,
          data: const {'stage': 'youth', 'nameAr': 'اجتماع', 'contactPhone': 'bad'},
          popOnSave: false,
          englishEnabled: false,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('editor-save'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      final errEntry = find.byKey(const ValueKey('error-summary-contactPhone'));
      expect(errEntry, findsOneWidget);

      await tester.ensureVisible(errEntry);
      await tester.tap(errEntry);
      await tester.pumpAndSettle();

      // Now focus nameAr and type multiline/long text; focus must stay on nameAr.
      final nameField = find.byKey(const ValueKey('field-nameAr'));
      await tester.ensureVisible(nameField);
      await tester.tap(nameField);
      await tester.pump();
      await tester.enterText(nameField, 'اجتماع محدث');
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(of: nameField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('P2-27b: FeaturesEditor preserves stored EN fields and pageReset clears only AR when englishEnabled is false',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FeatureSettings? saved;
      final initial = FeatureSettings.defaults.copyWith(
        heroTitleAr: 'كنيستنا',
        heroTitleEn: 'Our Church',
        bannerAr: 'أهلا',
        bannerEn: 'Welcome',
        footer: const FooterConfig(noteAr: 'ملحوظة', noteEn: 'Footer note'),
        dailyVerse: const DailyVerseConfig(
          mode: DailyVerseConfig.fixed,
          textAr: 'آية',
          refAr: 'مرجع',
          textEn: 'Verse EN',
          refEn: 'Ref EN',
        ),
        pageHeaders: const {
          'about': PageCustom(titleAr: 'عن الكنيسة', titleEn: 'About Church'),
        },
      );

      await tester.pumpWidget(_app(
        Scaffold(
          body: FeaturesEditor(
            key: const ValueKey('feat-preserve-en'),
            initial: initial,
            isOwner: true,
            onSave: (v) async => saved = v,
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // User edits EN hero title draft, then turns English off and resets the 'about' page header.
      await tester.enterText(find.byKey(const ValueKey('features-heroTitleEn')), 'Changed Draft');
      final swFinder = find.byKey(const ValueKey('features-englishEnabled'));
      await tester.ensureVisible(swFinder);
      await tester.tap(swFinder);
      await tester.pumpAndSettle();

      final aboutTile = find.byKey(const ValueKey('page-about'));
      await tester.ensureVisible(aboutTile);
      await tester.tap(aboutTile);
      await tester.pumpAndSettle();
      final resetBtn = find.byKey(const ValueKey('pageReset-about'));
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('features-save'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.englishEnabled, isFalse);
      expect(saved!.heroTitleEn, 'Our Church');
      expect(saved!.bannerEn, 'Welcome');
      expect(saved!.footer.noteEn, 'Footer note');
      expect(saved!.dailyVerse.textEn, 'Verse EN');
      expect(saved!.pageHeader('about').titleAr, isEmpty);
      expect(saved!.pageHeader('about').titleEn, 'About Church');
    });

    testWidgets('P2-27b: OverviewScreen counts missing English only when englishEnabled is true', (tester) async {
      final opened = <String>[];
      final cols = <String, List<AdminDoc>>{
        'liturgies': [
          AdminDoc('l1', {'nameAr': 'قداس أول', 'nameEn': '', 'sample': false}),
        ],
      };

      final repoOn = _TestAdminBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'englishEnabled': true},
        },
        initialCollections: cols,
      );
      await tester.pumpWidget(_app(
        OverviewScreen(
          key: const ValueKey('ov-en-on'),
          repo: repoOn,
          role: AdminRoles.editor,
          onOpen: opened.add,
          now: () => DateTime.utc(2026, 11, 14, 12, 0),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('attention-missingEnglish'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      expect(opened, ['liturgies']);

      final repoOff = _TestAdminBackend(
        initialDocs: {
          'settings/features': {'liveEnabled': false, 'englishEnabled': false},
        },
        initialCollections: cols,
      );
      await tester.pumpWidget(_app(
        OverviewScreen(
          key: const ValueKey('ov-en-off'),
          repo: repoOff,
          role: AdminRoles.editor,
          onOpen: (_) {},
          now: () => DateTime.utc(2026, 11, 14, 12, 0),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attention-missingEnglish')), findsNothing);
      expect(find.byKey(const ValueKey('attention-all-clear')), findsOneWidget);
    });

    testWidgets('P2-27a/b: 320px at 200% RTL/LTR without overflow & Criterion S3 check for non-owner', (tester) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final priestDef = collectionById('priests')!;
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        await tester.pumpWidget(_app(
          DocEditor(
            key: ValueKey('err-320-${locale.languageCode}'),
            title: priestDef.labelAr,
            fields: priestDef.fields,
            def: priestDef,
            popOnSave: false,
            englishEnabled: false,
            data: const {'name': '', 'rank': 'priest', 'status': 'serving', 'order': 'bad'},
            onSave: (_) async {},
          ),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('editor-save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-error-summary')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'DocEditor summary locale=${locale.languageCode}');

        await tester.pumpWidget(_app(
          Scaffold(
            body: FeaturesEditor(
              key: ValueKey('feat-320-${locale.languageCode}'),
              initial: FeatureSettings.defaults,
              isOwner: true,
              onSave: (_) async {},
            ),
          ),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'FeaturesEditor locale=${locale.languageCode}');
      }

      // Criterion S3: no technical English terms in Arabic non-owner FeaturesEditor or DocEditor.
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(_app(
        Scaffold(
          body: FeaturesEditor(
            key: const ValueKey('feat-s3'),
            initial: FeatureSettings.defaults.copyWith(englishEnabled: false),
            isOwner: false,
            onSave: (_) async {},
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' ');
      for (final banned in ['Firebase', 'UID', 'App Check', 'Sentry', 'APK', 'HH:mm']) {
        expect(allText, isNot(contains(banned)));
      }
    });
  });

  group('PR 3H: P2-25 Inbox (MessagesScreen)', () {
    testWidgets('opens filtered on «محتاجة رد», shows WhatsApp only for usable phones, and «تمّت» removes from default view',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final ctrl = StreamController<List<AdminDoc>>.broadcast();
      addTearDown(ctrl.close);
      final repo = _ReactiveAdminBackend(
        controller: ctrl,
        initialCollections: {
          'contact_messages': [
            AdminDoc('m-mobile', {
              'name': 'بيشوي',
              'phone': '01012345678',
              'message': 'استفسار عن موعد',
              'status': 'new',
            }),
            AdminDoc('m-no-phone', {
              'name': 'مريم',
              'email': 'mary@example.org',
              'message': 'رسالة بالبريد فقط',
              'status': 'new',
            }),
            AdminDoc('m-bad-phone', {
              'name': 'كيرلس',
              'phone': 'abc-123',
              'message': 'رقم غير صالح',
              'status': 'new',
            }),
            AdminDoc('m-landline', {
              'name': 'يوحنا',
              'phone': '03 555 1234',
              'message': 'تليفون أرضي',
              'status': 'new',
            }),
            AdminDoc('m-handled', {
              'name': 'سارة',
              'phone': '01212345678',
              'message': 'رسالة منتهية',
              'status': 'handled',
            }),
          ],
        },
      );

      await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      // Default filter is «محتاجة رد» and only open messages are visible.
      final newChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('filter-new')));
      expect(newChip.selected, isTrue);
      expect(find.text('محتاجة رد'), findsOneWidget);
      expect(find.byKey(const ValueKey('m-mobile')), findsOneWidget);
      expect(find.byKey(const ValueKey('m-no-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('m-bad-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('m-landline')), findsOneWidget);
      expect(find.byKey(const ValueKey('m-handled')), findsNothing);

      // Call, WhatsApp and «تمّت» are visible in the same step for a valid mobile.
      expect(find.byKey(const ValueKey('msgCall-m-mobile')), findsOneWidget);
      expect(find.byKey(const ValueKey('msgWhatsApp-m-mobile')), findsOneWidget);
      expect(find.byKey(const ValueKey('msgToggleStatus-m-mobile')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('m-mobile')), matching: find.text('تمّت')), findsOneWidget);

      // Missing, malformed, and landline phones never get a WhatsApp chip.
      expect(find.byKey(const ValueKey('msgWhatsApp-m-no-phone')), findsNothing);
      expect(find.byKey(const ValueKey('msgWhatsApp-m-bad-phone')), findsNothing);
      expect(find.byKey(const ValueKey('msgWhatsApp-m-landline')), findsNothing);

      // One tap on «تمّت» marks handled and removes it from «محتاجة رد».
      await tester.tap(find.byKey(const ValueKey('msgToggleStatus-m-mobile')));
      await tester.pumpAndSettle();
      expect(repo.collections['contact_messages']!.firstWhere((d) => d.id == 'm-mobile').data['status'], 'handled');
      expect(find.byKey(const ValueKey('m-mobile')), findsNothing);

      // Switching to handled shows the completed message.
      await tester.tap(find.byKey(const ValueKey('filter-handled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('m-mobile')), findsOneWidget);
      expect(find.byKey(const ValueKey('m-handled')), findsOneWidget);
    });

    testWidgets('MessagesScreen renders cleanly at 320 px / 200% in RTL & LTR and respects S3', (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _TestAdminBackend(initialCollections: {
        'contact_messages': [
          AdminDoc('m1', {
            'name': 'زائر برقم طويل',
            'phone': '+20 101 234 5678',
            'email': 'visitor@example.org',
            'message': 'أحتاج التواصل مع المكتب الكنسي',
            'status': 'new',
            'createdAt': DateTime.utc(2026, 11, 14, 10, 30),
          }),
        ],
      });

      for (final locale in [const Locale('ar'), const Locale('en')]) {
        await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: locale));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('msgWhatsApp-m1')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'MessagesScreen 320px locale=${locale.languageCode}');
        if (locale.languageCode == 'en') {
          expect(find.text('Needs reply'), findsOneWidget);
          expect(find.text('Done'), findsOneWidget);
        } else {
          final allText = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
              .join(' ');
          for (final banned in ['Firebase', 'UID', 'App Check', 'Sentry', 'APK', 'HH:mm']) {
            expect(allText, isNot(contains(banned)));
          }
        }
      }
    });
  });

  group('PR 3J: P3-30 & P3-31 — church info split, hints & inbox mark-new overflow', () {
    test('P3-30: churchInfoDoc splits fields across basic/location/contacts/hero/history and adds coordinate & priority hints',
        () {
      const expectedKeys = {
        'nameAr',
        'nameEn',
        'bishopAr',
        'bishopEn',
        'addressAr',
        'addressEn',
        'sample',
        'transportAr',
        'transportEn',
        'lat',
        'lng',
        'mapsQuery',
        'mapsUrl',
        'phones',
        'whatsapp',
        'whatsappChannel',
        'facebook',
        'youtube',
        'instagram',
        'verseAr',
        'verseEn',
        'verseRefAr',
        'verseRef',
        'heroImageUrl',
        'historyAr',
        'historyEn',
        'altars',
      };
      final actualKeys = churchInfoDoc.fields.map((f) => f.key).toList();
      expect(actualKeys.toSet(), expectedKeys);
      expect(actualKeys.length, expectedKeys.length);

      expect(
        churchInfoDoc.fields.where((f) => f.group == FieldGroup.basic).map((f) => f.key).toSet(),
        {'nameAr', 'nameEn', 'bishopAr', 'bishopEn', 'addressAr', 'addressEn', 'sample'},
      );
      expect(
        churchInfoDoc.fields.where((f) => f.group == FieldGroup.location).map((f) => f.key).toSet(),
        {'transportAr', 'transportEn', 'lat', 'lng', 'mapsQuery', 'mapsUrl'},
      );
      expect(
        churchInfoDoc.fields.where((f) => f.group == FieldGroup.contacts).map((f) => f.key).toSet(),
        {'phones', 'whatsapp', 'whatsappChannel', 'facebook', 'youtube', 'instagram'},
      );
      expect(
        churchInfoDoc.fields.where((f) => f.group == FieldGroup.hero).map((f) => f.key).toSet(),
        {'verseAr', 'verseEn', 'verseRefAr', 'verseRef', 'heroImageUrl'},
      );
      expect(
        churchInfoDoc.fields.where((f) => f.group == FieldGroup.history).map((f) => f.key).toSet(),
        {'historyAr', 'historyEn', 'altars'},
      );

      for (final key in ['lat', 'lng', 'mapsQuery']) {
        final f = churchInfoDoc.fields.firstWhere((field) => field.key == key);
        expect(f.hintAr.trim(), isNotEmpty, reason: 'churchInfoDoc.$key.hintAr');
        expect(f.hintEn.trim(), isNotEmpty, reason: 'churchInfoDoc.$key.hintEn');
      }

      final alertsDef = collectionById('alerts')!;
      final priorityField = alertsDef.fields.firstWhere((f) => f.key == 'priority');
      expect(priorityField.hintAr, contains('الأكبر'));
      expect(priorityField.hintEn.toLowerCase(), contains('before'));
    });

    testWidgets('P3-30: split church info saves identical flat keys and displays coordinate & priority hints',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      await tester.pumpWidget(_app(
        DocEditor(
          title: churchInfoDoc.labelAr,
          fields: churchInfoDoc.fields,
          popOnSave: false,
          onSave: (d) async => saved = d,
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Basic identity fields remain open at top; grouped sections sit in collapsed cards.
      expect(find.byKey(const ValueKey('field-nameAr')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-addressAr')), findsOneWidget);
      expect(find.byKey(const ValueKey('groupCard-location')), findsOneWidget);
      expect(find.byKey(const ValueKey('groupCard-contacts')), findsOneWidget);
      expect(find.byKey(const ValueKey('groupCard-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('groupCard-history')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'كنيسة مكسيموس ودوماديوس');
      await tester.enterText(find.byKey(const ValueKey('field-nameEn')), 'St. Maximus Church');
      await tester.enterText(find.byKey(const ValueKey('field-addressAr')), 'شارع ٤٥، العصافرة قبلي');

      await tester.tap(find.byKey(const ValueKey('group-location')));
      await tester.pumpAndSettle();
      final latHint = churchInfoDoc.fields.firstWhere((f) => f.key == 'lat').hintAr;
      expect(find.textContaining(latHint), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-lat')), '31.265');
      await tester.enterText(find.byKey(const ValueKey('field-lng')), '30.012');

      await tester.tap(find.byKey(const ValueKey('group-contacts')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-whatsapp')), '01012345678');

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['nameAr'], 'كنيسة مكسيموس ودوماديوس');
      expect(saved!['nameEn'], 'St. Maximus Church');
      expect(saved!['addressAr'], 'شارع ٤٥، العصافرة قبلي');
      expect(saved!['lat'], 31.265);
      expect(saved!['lng'], 30.012);
      expect(saved!['whatsapp'], '01012345678');

      // Alert priority hint appears cleanly in Arabic when advanced options open.
      final alertsDef = collectionById('alerts')!;
      await tester.pumpWidget(_app(
        DocEditor(
          key: const ValueKey('alerts-editor'),
          title: alertsDef.labelAr,
          fields: alertsDef.fields,
          def: alertsDef,
          popOnSave: false,
          onSave: (_) async {},
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      final priorityHint = alertsDef.fields.firstWhere((f) => f.key == 'priority').hintAr;
      expect(find.textContaining(priorityHint), findsOneWidget);
    });

    testWidgets('P3-30: ChurchInfoScreen renders cleanly at 320 px / 200% in RTL & LTR without S3 jargon',
        (tester) async {
      tester.view.physicalSize = const Size(320, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _TestAdminBackend(initialDocs: {
        'settings/church': {
          'nameAr': 'كنيسة القديسين',
          'nameEn': 'Saints Church',
          'addressAr': 'شارع ٤٥',
          'phones': [
            {'labelAr': 'المكتب', 'labelEn': 'Office', 'number': '035368888'},
          ],
          'altars': [
            {'nameAr': 'مذبح العذراء', 'nameEn': 'St. Mary Altar', 'kind': 'main'},
          ],
        },
      });

      for (final locale in [const Locale('ar'), const Locale('en')]) {
        await tester.pumpWidget(_app(ChurchInfoScreen(repo: repo), locale: locale));
        await tester.pumpAndSettle();
        for (final g in ['group-location', 'group-contacts', 'group-hero', 'group-history']) {
          final tile = find.byKey(ValueKey(g));
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: 'ChurchInfoScreen 320px locale=${locale.languageCode}');
        if (locale.languageCode == 'ar') {
          final allText = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
              .join(' ');
          for (final banned in ['Firebase', 'UID', 'App Check', 'Sentry', 'APK', 'HH:mm']) {
            expect(allText, isNot(contains(banned)));
          }
        }
      }
    });

    testWidgets(
        'P3-31: handled message puts markNew in overflow menu away from Done, keeps Delete tooltip, renders at 320px/200%',
        (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repo = _TestAdminBackend(initialCollections: {
        'contact_messages': [
          AdminDoc('m-open', {
            'name': 'زائر جديد',
            'message': 'استفسار',
            'status': 'new',
            'createdAt': DateTime.utc(2026, 11, 14, 9),
          }),
          AdminDoc('m-done', {
            'name': 'زائر تمت متابعته',
            'message': 'رسالة منتهية',
            'status': 'handled',
            'createdAt': DateTime.utc(2026, 11, 13, 9),
          }),
        ],
      });

      await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('msgToggleStatus-m-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('msgMore-m-open')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('filter-handled')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('msgToggleStatus-m-done')), findsNothing);
      expect(find.byKey(const ValueKey('msgMarkNew-m-done')), findsNothing);
      expect(find.byKey(const ValueKey('msgMore-m-done')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('msgMore-m-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('msgMarkNew-m-done')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('msgMarkNew-m-done')));
      await tester.pumpAndSettle();

      expect(repo.updates.last.id, 'm-done');
      expect(repo.updates.last.data, {'status': 'new'});
      expect(tester.takeException(), isNull);

      // Verify English mode as well and Delete tooltip invariant.
      final enRepo = _TestAdminBackend(initialCollections: {
        'contact_messages': [
          AdminDoc('m-done', {
            'name': 'Handled Visitor',
            'message': 'Finished note',
            'status': 'handled',
            'createdAt': DateTime.utc(2026, 11, 13, 9),
          }),
        ],
      });
      await tester.pumpWidget(_app(MessagesScreen(repo: enRepo), locale: const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-handled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('msgMore-m-done')), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('Phase 3J Remaining Implementer Tests', () {
      testWidgets('DocEditor displays persistent Key(editor-save-error) banner on save failure and clears on edit or dismiss',
          (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final alertsDef = adminCollections.firstWhere((c) => c.name == 'alerts');
        var shouldFail = true;
        await tester.pumpWidget(MaterialApp(
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          locale: const Locale('ar'),
          home: Scaffold(
            body: DocEditor(
              key: const ValueKey('alerts-editor'),
              title: alertsDef.labelAr,
              fields: alertsDef.fields,
              def: alertsDef,
              popOnSave: true,
              onSave: (_) async {
                if (shouldFail) throw StateError('Firestore write error');
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Enter required title so form is valid but save will call onSave and fail
        await tester.enterText(find.byType(TextFormField).first, 'Notice Title');
        await tester.pumpAndSettle();

        // Tap top save button
        await tester.tap(find.byKey(const Key('editor-save-top')));
        await tester.pumpAndSettle();

        // Persistent error banner is shown
        expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('editor-save-error')),
            matching: find.textContaining('Firestore write error'),
          ),
          findsOneWidget,
        );

        // Editing a field clears the error banner
        await tester.enterText(find.byType(TextFormField).first, 'Notice Title Updated');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-save-error')), findsNothing);

        // Save again to trigger failure again
        await tester.tap(find.byKey(const Key('editor-save-top')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-save-error')), findsOneWidget);

        // Tapping close icon on the banner dismisses it
        await tester.tap(find.descendant(of: find.byKey(const Key('editor-save-error')), matching: find.byIcon(Icons.close)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-save-error')), findsNothing);
      });

      testWidgets('UnsavedGuard intercepts browser back via debugSimulatePopState when dirty', (tester) async {
        var discarded = false;
        await tester.pumpWidget(MaterialApp(
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          locale: const Locale('ar'),
          home: Scaffold(
            body: UnsavedGuard(
              dirty: true,
              handlePop: false,
              onBrowserBackDiscard: () => discarded = true,
              child: const Text('Dirty Form Content'),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Simulate popstate
        final future = debugSimulatePopState();
        await tester.pumpAndSettle();

        // Dialog is visible with keepEditing and discard
        expect(find.byKey(const ValueKey('discard-keep')), findsOneWidget);
        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);

        // Tap keep editing
        await tester.tap(find.byKey(const ValueKey('discard-keep')));
        await tester.pumpAndSettle();
        final keepResult = await future;
        expect(keepResult, isFalse);
        expect(discarded, isFalse);

        // Simulate popstate again and confirm discard
        final futureDiscard = debugSimulatePopState();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pumpAndSettle();
        final discardResult = await futureDiscard;
        expect(discardResult, isTrue);
        expect(discarded, isTrue);
      });

      testWidgets('FeaturesEditor resets dirty state on browser back discard via onBrowserBackDiscard', (tester) async {
        final doc = AdminDoc('features', {
          'sections': {'meetings': true},
        });
        final repo = _TestAdminBackend(initialDocs: {
          'settings/features': doc.data,
        });

        await tester.pumpWidget(_app(
          FeaturesScreen(repo: repo),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Mutate a switch to make form dirty
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

        // Simulate browser back (popstate)
        final futureDiscard = debugSimulatePopState();
        await tester.pumpAndSettle();

        // Discard dialog is displayed -> tap discard
        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pumpAndSettle();

        final result = await futureDiscard;
        expect(result, isTrue);

        // Form was cleanly reset and dirty flag cleared
        expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
      });

      testWidgets('ContactCategoriesScreen resets dirty state on browser back discard via onBrowserBackDiscard', (tester) async {
        final doc = AdminDoc('contact', {
          'categories': [
            {'slot': 'c1', 'nameAr': 'استفسار عام', 'nameEn': 'General Inquiry', 'order': 10},
          ],
        });
        final repo = _TestAdminBackend(initialDocs: {
          'settings/contact': doc.data,
        });

        await tester.pumpWidget(_app(
          ContactCategoriesScreen(repo: repo),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Edit category name to make dirty
        await tester.enterText(find.byType(TextField).first, 'تعديل الاستفسار');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

        // Simulate browser back (popstate)
        final futureDiscard = debugSimulatePopState();
        await tester.pumpAndSettle();

        // Discard dialog is displayed -> tap discard
        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pumpAndSettle();

        final result = await futureDiscard;
        expect(result, isTrue);

        // Form reset and dirty flag cleared
        expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
        expect(find.text('استفسار عام'), findsWidgets);
      });

      testWidgets('MessagesScreen.dispose() closes undo snackbar via controller without removing unrelated snackbars', (tester) async {
        final doc = AdminDoc('msg-dispose', {
          'name': 'Sender Dispose',
          'message': 'Message to delete',
          'createdAt': DateTime.utc(2026, 11, 15, 12),
          'status': 'new',
        });
        final repo = _TestAdminBackend(initialCollections: {
          'contact_messages': [doc],
        });

        await tester.pumpWidget(_app(
          MessagesScreen(repo: repo),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Delete message -> undo snackbar appears
        await tester.tap(find.byTooltip('حذف'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pumpAndSettle();

        expect(find.text('تراجع'), findsOneWidget);

        // Replace MessagesScreen with another widget, triggering dispose()
        await tester.pumpWidget(_app(
          const Scaffold(body: Text('Different Screen')),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Different Screen'), findsOneWidget);
      });

      testWidgets('MessagesScreen clears undo controller reference when snackbar closes', (tester) async {
        final doc = AdminDoc('msg-closed', {
          'name': 'Sender Closed',
          'message': 'Message to delete',
          'createdAt': DateTime.utc(2026, 11, 15, 12),
          'status': 'new',
        });
        final repo = _TestAdminBackend(initialCollections: {
          'contact_messages': [doc],
        });

        await tester.pumpWidget(_app(
          MessagesScreen(repo: repo),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Delete message -> undo snackbar appears
        await tester.tap(find.byTooltip('حذف'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pumpAndSettle();

        expect(find.text('تراجع'), findsOneWidget);

        // Advance clock past the 10-second duration so the snackbar closes
        await tester.pump(const Duration(seconds: 10));
        await tester.pump(const Duration(milliseconds: 750));
        await tester.pumpAndSettle();
        expect(find.text('تراجع'), findsNothing);

        // Disposing MessagesScreen now does not throw or call close on closed controller
        await tester.pumpWidget(_app(
          const Scaffold(body: Text('Closed Screen')),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('FeaturesEditor defers browser back discard until active save completes', (tester) async {
        final completer = Completer<void>();
        final doc = AdminDoc('features', {
          'sections': {'meetings': true},
          'bannerAr': 'Initial Banner',
        });
        final repo = _DelayedSaveBackend(completer.future, initialDocs: {
          'settings/features': doc.data,
        });

        await tester.pumpWidget(_app(
          FeaturesScreen(repo: repo),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Toggle section switch to make form dirty
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

        // Trigger Save -> save is in flight
        await tester.tap(find.byKey(const Key('features-save')));
        await tester.pump();

        // Simulate browser back discard while save is in flight
        final futureDiscard = debugSimulatePopState();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pump(const Duration(milliseconds: 100));

        // Complete save
        completer.complete();
        await tester.pumpAndSettle();

        final result = await futureDiscard;
        expect(result, isTrue);

        // After delayed save finishes, deferred reset restores resulting baseline and clears dirty
        expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
      });

      testWidgets('DocEditor defers browser back discard until active save completes', (tester) async {
        final completer = Completer<void>();
        var savedTitle = '';
        await tester.pumpWidget(_app(
          DocEditor(
            title: 'Custom Item',
            fields: const [
              FieldDef('nameAr', 'الاسم', 'Name', FieldType.text, required: true),
            ],
            data: const {'nameAr': 'Item Initial'},
            popOnSave: false,
            onSave: (chunk) async {
              savedTitle = chunk['nameAr'] as String? ?? '';
              await completer.future;
            },
          ),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Edit text field
        await tester.enterText(find.byType(TextField).first, 'Item Edited');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);

        // Tap save -> in flight
        await tester.tap(find.byKey(const Key('editor-save')));
        await tester.pump();

        // Trigger popstate discard while save is in flight
        final futureDiscard = debugSimulatePopState();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pump(const Duration(milliseconds: 100));

        // Complete the save
        completer.complete();
        await tester.pumpAndSettle();

        final result = await futureDiscard;
        expect(result, isTrue);
        expect(savedTitle, 'Item Edited');
        expect(find.byKey(const ValueKey('unsaved-bar')), findsNothing);
      });

      testWidgets('NotificationsAdmin discards open draft and resets on browser back discard', (tester) async {
        final repo = _TestAdminBackend(initialDocs: {
          'settings/notifications': {'schedule': []},
        });

        await tester.pumpWidget(_app(
          NotificationsAdminSection(
            repo: repo,
          ),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Tap add announcement to open draft editor
        await tester.tap(find.byKey(const ValueKey('addScheduledPush')));
        await tester.pumpAndSettle();

        // Enter text in draft title to make draft dirty
        await tester.enterText(find.byKey(const ValueKey('draft-titleAr')), 'Draft Title');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('push-editor')), findsOneWidget);

        // Simulate browser back discard
        final futureDiscard = debugSimulatePopState();
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('discard-confirm')));
        await tester.pumpAndSettle();

        final result = await futureDiscard;
        expect(result, isTrue);

        // Draft was closed and dirty state cleared
        expect(find.byKey(const ValueKey('push-editor')), findsNothing);
      });

      testWidgets('MessagesScreen soft-deletes, hides, offers 10s undo and restores on undo', (tester) async {
        final doc = AdminDoc('msg-1', {
          'name': 'Test Sender',
          'message': 'Test message content',
          'createdAt': DateTime.utc(2026, 11, 15, 12),
          'status': 'new',
        });
        final repo = _TestAdminBackend(initialCollections: {
          'contact_messages': [doc],
        });

        await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
        await tester.pumpAndSettle();

        expect(find.text('Test Sender'), findsOneWidget);

        // Tap delete icon
        await tester.tap(find.byTooltip('حذف'));
        await tester.pumpAndSettle();

        // Confirm dialog
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pumpAndSettle();

        // Soft delete: deletedAt written in repo.updates, message hidden from view immediately
        expect(repo.updates.any((u) => u.id == 'msg-1' && u.data.containsKey('deletedAt')), isTrue);
        expect(find.text('Test Sender'), findsNothing);

        // Undo snackbar is visible
        expect(find.text('تراجع'), findsOneWidget);

        // Tap undo
        await tester.tap(find.text('تراجع'));
        await tester.pumpAndSettle();

        // Restoration: deletedAt: null written, message restored
        expect(repo.updates.any((u) => u.id == 'msg-1' && u.data['deletedAt'] == null), isTrue);
        expect(find.text('Test Sender'), findsOneWidget);
      });

      testWidgets('MessagesScreen commits hard delete after 10s grace window', (tester) async {
        final doc = AdminDoc('msg-2', {
          'name': 'Expiring Sender',
          'message': 'Expiring message content',
          'createdAt': DateTime.utc(2026, 11, 15, 12),
          'status': 'new',
        });
        final repo = _TestAdminBackend(initialCollections: {
          'contact_messages': [doc],
        });

        await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: const Locale('ar')));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('حذف'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pumpAndSettle();

        // Advance past 10-second timer
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();

        expect(repo.deletedIds, contains('contact_messages/msg-2'));
      });

      testWidgets('MessagesScreen rapid 2-message soft-delete shows batched Undo all and restores both with 0 hard deletes',
          (tester) async {
        for (final locale in const [Locale('ar'), Locale('en')]) {
          final isAr = locale.languageCode == 'ar';
          final m1 = AdminDoc('msg-b1', {
            'name': 'Sender One',
            'message': 'First inbox message',
            'createdAt': DateTime.utc(2026, 11, 15, 13),
            'status': 'new',
          });
          final m2 = AdminDoc('msg-b2', {
            'name': 'Sender Two',
            'message': 'Second inbox message',
            'createdAt': DateTime.utc(2026, 11, 15, 12),
            'status': 'new',
          });
          final repo = _TestAdminBackend(initialCollections: {
            'contact_messages': [m1, m2],
          });

          await tester.pumpWidget(_app(MessagesScreen(repo: repo), locale: locale));
          await tester.pumpAndSettle();

          // Confirm & soft-delete first message
          await tester.tap(find.byTooltip(isAr ? 'حذف' : 'Delete').first);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('confirm-ok')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Sender One'), findsNothing);
          expect(find.text(isAr ? 'تم مسح «Sender One»' : 'Deleted "Sender One"'), findsOneWidget);
          expect(find.text(isAr ? 'تراجع' : 'Undo'), findsOneWidget);

          // Confirm & soft-delete second message rapidly within 10s window
          await tester.tap(find.byTooltip(isAr ? 'حذف' : 'Delete').first);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('confirm-ok')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Sender Two'), findsNothing);
          expect(
            find.text(isAr ? 'تم مسح 2 عناصر (آخرهم «Sender Two»)' : 'Deleted 2 items (latest: "Sender Two")'),
            findsOneWidget,
          );
          expect(find.text(isAr ? 'تراجع عن الكل' : 'Undo all'), findsOneWidget);
          for (final id in ['msg-b1', 'msg-b2']) {
            final doc = repo.collections['contact_messages']!.firstWhere((d) => d.id == id);
            expect(isSoftDeleted(doc.data), isTrue, reason: '$id should have deletedAt tombstone before Undo all');
          }
          expect(repo.deletedIds, isEmpty);

          // Tap batched Undo all -> restores both messages with deletedAt: null and 0 hard deletes
          await tester.tap(find.text(isAr ? 'تراجع عن الكل' : 'Undo all'));
          await tester.pumpAndSettle();

          expect(find.text('Sender One'), findsOneWidget);
          expect(find.text('Sender Two'), findsOneWidget);
          for (final id in ['msg-b1', 'msg-b2']) {
            final doc = repo.collections['contact_messages']!.firstWhere((d) => d.id == id);
            expect(isSoftDeleted(doc.data), isFalse, reason: '$id deletedAt should be cleared');
          }
          expect(repo.deletedIds, isEmpty);

          // Wait past 10s grace window -> still 0 hard deletes
          await tester.pump(const Duration(seconds: 12));
          await tester.pumpAndSettle();
          expect(repo.deletedIds, isEmpty);
        }
      });

      testWidgets('MessagesScreen.dispose() keeps _barState alive through exit animation, preserves unrelated SnackBars, and skips media deletion (removeMedia: false)',
          (tester) async {
        final mediaRepo = _TestMediaRepo();
        final repo = _MediaTestAdminBackend(mediaRepo, initialCollections: {
          'contact_messages': [
            AdminDoc('msg-anim', {
              'name': 'Anim Sender',
              'message': 'Dispose exit animation safety',
              'createdAt': DateTime.utc(2026, 11, 15, 14),
              'status': 'new',
              'image': {'source': 'inline', 'mediaId': 'm1'},
            }),
            AdminDoc('msg-expired', {
              'name': 'Expired Sender',
              'message': 'Already expired soft delete',
              'createdAt': DateTime.utc(2026, 11, 15, 13),
              'deletedAt': DateTime.utc(2026, 11, 15, 13),
              'status': 'new',
              'image': {'source': 'inline', 'mediaId': 'm2'},
            }),
          ],
        });
        final messengerKey = GlobalKey<ScaffoldMessengerState>();
        Widget screen = MessagesScreen(repo: repo);

        await tester.pumpWidget(StatefulBuilder(
          builder: (context, setHost) => MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            scaffoldMessengerKey: messengerKey,
            home: screen,
          ),
        ));
        await tester.pumpAndSettle();

        // Lazy purge ran on msg-expired without deleting media (removeMedia: false)
        expect(repo.deletedIds, contains('contact_messages/msg-expired'));
        expect(mediaRepo.deleted, isEmpty);

        // Soft-delete msg-anim, let Undo SnackBar present, then unmount MessagesScreen
        await tester.tap(find.byTooltip('حذف').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pump();
        expect(find.text('تراجع'), findsOneWidget);

        // Unmount to a plain Container (no Scaffold), pump mid-exit (100ms), then mount a new Scaffold
        screen = const SizedBox.shrink();
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: messengerKey,
          home: screen,
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: Text('Next Scaffold')),
        ));
        messengerKey.currentState!.showSnackBar(const SnackBar(content: Text('Unrelated Note')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('تراجع'), findsNothing);
        expect(find.text('Unrelated Note'), findsOneWidget);

        // Verify commit path with removeMedia: false directly via fresh MessagesScreen
        final repoCommit = _MediaTestAdminBackend(mediaRepo, initialCollections: {
          'contact_messages': [
            AdminDoc('msg-media', {
              'name': 'Commit Sender',
              'message': 'Check removeMedia false on commit',
              'createdAt': DateTime.utc(2026, 11, 15, 15),
              'status': 'new',
              'image': {'source': 'inline', 'mediaId': 'm3'},
            }),
          ],
        });
        await tester.pumpWidget(_app(MessagesScreen(repo: repoCommit), locale: const Locale('ar')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('حذف').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-ok')));
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(repoCommit.deletedIds, contains('contact_messages/msg-media'));
        expect(mediaRepo.deleted, isEmpty);
      });

      testWidgets('MessagesScreen preserves queued non-undo SnackBars and stale lazy purge never deletes a restored message',
          (tester) async {
        final messengerKey = GlobalKey<ScaffoldMessengerState>();
        final undo = SoftDeleteUndo(
          isMounted: () => true,
          onChanged: () {},
          removeMedia: false,
        );
        addTearDown(undo.dispose);

        final repo = _ControlledUpdateBackend(initialCollections: {
          'contact_messages': [
            AdminDoc('msg-a', {
              'name': 'Expired A',
              'message': 'Old tombstone',
              'createdAt': DateTime.utc(2026, 11, 15, 10),
              'deletedAt': DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
              'status': 'new',
            }),
            AdminDoc('msg-b', {
              'name': 'Restored B',
              'message': 'Deleted then undone while purge runs',
              'createdAt': DateTime.utc(2026, 11, 15, 11),
              'status': 'new',
            }),
          ],
        });
        addTearDown(repo.dispose);

        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ));
        await tester.pumpAndSettle();

        // Delete msg-b cleanly first, while an external error bar is active & another queued.
        messengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Active Info'), duration: Duration(seconds: 1)),
        );
        messengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Queued Save Error'), duration: Duration(seconds: 1)),
        );
        await tester.pump();

        final docB = repo.collections['contact_messages']!.last;
        await undo.delete(
          repo: repo,
          collection: 'contact_messages',
          doc: docB,
          title: 'Restored B',
          messenger: messengerKey.currentState,
          failedMsg: 'Failed: {e}',
          undoLabel: 'تراجع',
          undoAllLabel: 'تراجع عن الكل',
        );
        // Queued Save Error survived removeCurrentSnackBar() and shows before Undo enters.
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Queued Save Error'), findsOneWidget);

        for (var i = 0; i < 8 && find.text('تراجع').evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle();
        expect(find.text('تراجع'), findsOneWidget);

        // Snapshot has expired msg-a AND stale expired tombstone for msg-b (as if B's
        // original 10s deadline elapsed while A's purge was awaiting).
        final staleSnapshot = [
          AdminDoc('msg-a', Map<String, dynamic>.from(repo.collections['contact_messages']!.first.data)),
          AdminDoc('msg-b', {
            ...Map<String, dynamic>.from(docB.data),
            'deletedAt': DateTime.now().toUtc().subtract(const Duration(seconds: 15)),
          }),
        ];
        final holdDeleteA = repo.holdDelete('contact_messages', 'msg-a');
        const msgDef = CollectionDef('contact_messages', '', '', [], []);
        undo.checkLazyPurge(repo, msgDef, staleSnapshot);
        await tester.pump(); // starts purging msg-a

        // Tap Undo on msg-b while msg-a delete is in flight -> msg-b is restored locally + backend.
        await tester.tap(find.text('تراجع'));
        await tester.pumpAndSettle();
        expect(isSoftDeleted(repo.collections['contact_messages']!.last.data), isFalse);

        // Complete msg-a purge -> stale loop reaches msg-b and MUST skip it!
        holdDeleteA.complete();
        await tester.pumpAndSettle();
        expect(repo.deletedIds, ['contact_messages/msg-a']);
        expect(repo.deletedIds, isNot(contains('contact_messages/msg-b')));
      });

      testWidgets('SoftDeleteUndo keeps undone cutoff if re-delete write fails so stale purge still skips doc',
          (tester) async {
        final messengerKey = GlobalKey<ScaffoldMessengerState>();
        final undo = SoftDeleteUndo(
          isMounted: () => true,
          onChanged: () {},
          removeMedia: false,
        );
        addTearDown(undo.dispose);

        final repo = _ControlledUpdateBackend(initialCollections: {
          'contact_messages': [
            AdminDoc('msg-a', {
              'name': 'Expired A',
              'message': 'Old tombstone',
              'createdAt': DateTime.utc(2026, 11, 15, 10),
              'deletedAt': DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
              'status': 'new',
            }),
            AdminDoc('msg-b', {
              'name': 'Restored B',
              'message': 'Undo then failed re-delete while purge in flight',
              'createdAt': DateTime.utc(2026, 11, 15, 11),
              'status': 'new',
            }),
          ],
        });
        addTearDown(repo.dispose);

        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ));
        await tester.pumpAndSettle();

        final docB = repo.collections['contact_messages']!.last;
        await undo.delete(
          repo: repo,
          collection: 'contact_messages',
          doc: docB,
          title: 'Restored B',
          messenger: messengerKey.currentState,
          failedMsg: 'Failed: {e}',
          undoLabel: 'تراجع',
          undoAllLabel: 'تراجع عن الكل',
        );
        await tester.pumpAndSettle();

        final staleSnapshot = [
          AdminDoc('msg-a', Map<String, dynamic>.from(repo.collections['contact_messages']!.first.data)),
          AdminDoc('msg-b', {
            ...Map<String, dynamic>.from(docB.data),
            'deletedAt': DateTime.now().toUtc().subtract(const Duration(seconds: 15)),
          }),
        ];
        final holdDeleteA = repo.holdDelete('contact_messages', 'msg-a');
        const msgDef = CollectionDef('contact_messages', '', '', [], []);
        undo.checkLazyPurge(repo, msgDef, staleSnapshot);
        await tester.pump();

        // Undo sets _undoneCutoffs['msg-b']
        await tester.tap(find.text('تراجع'));
        await tester.pumpAndSettle();
        expect(isSoftDeleted(repo.collections['contact_messages']!.last.data), isFalse);

        // Second delete attempt fails on Firestore write -> cutoff must remain intact!
        final failReDelete = repo.hold('contact_messages', 'msg-b');
        await undo.delete(
          repo: repo,
          collection: 'contact_messages',
          doc: repo.collections['contact_messages']!.last,
          title: 'Restored B',
          messenger: messengerKey.currentState,
          failedMsg: 'Failed: {e}',
          undoLabel: 'تراجع',
          undoAllLabel: 'تراجع عن الكل',
        );
        failReDelete.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Offline'));
        await tester.pumpAndSettle();

        // Stale purge resumes after msg-a -> msg-b is STILL protected by preserved cutoff!
        holdDeleteA.complete();
        await tester.pumpAndSettle();
        expect(repo.deletedIds, ['contact_messages/msg-a']);
        expect(repo.deletedIds, isNot(contains('contact_messages/msg-b')));
      });

      testWidgets('SoftDeleteUndo holds deletes and keeps full 10s Undo window behind a long unrelated SnackBar',
          (tester) async {
        final messengerKey = GlobalKey<ScaffoldMessengerState>();
        final undo = SoftDeleteUndo(
          isMounted: () => true,
          onChanged: () {},
          removeMedia: false,
        );
        addTearDown(undo.dispose);

        final m1 = AdminDoc('msg-q1', {
          'name': 'Queued One',
          'message': 'First',
          'createdAt': DateTime.utc(2026, 11, 15, 10),
          'status': 'new',
        });
        final m2 = AdminDoc('msg-q2', {
          'name': 'Queued Two',
          'message': 'Second',
          'createdAt': DateTime.utc(2026, 11, 15, 11),
          'status': 'new',
        });
        final repo = _TestAdminBackend(initialCollections: {
          'contact_messages': [m1, m2],
        });

        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ));
        await tester.pumpAndSettle();

        // Show an active transient bar plus a queued 15-second SnackBar (> 10s delete window).
        messengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Active Transient'), duration: Duration(seconds: 1)),
        );
        messengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Long Unrelated Notice'), duration: Duration(seconds: 15)),
        );
        await tester.pump();

        // Delete m1 at t=0 (dismisses transient, promotes Long Unrelated Notice), then m2 at t=2s while queued behind it.
        await undo.delete(
          repo: repo,
          collection: 'contact_messages',
          doc: m1,
          title: 'Queued One',
          messenger: messengerKey.currentState,
          failedMsg: 'Failed: {e}',
          undoLabel: 'تراجع',
          undoAllLabel: 'تراجع عن الكل',
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Long Unrelated Notice'), findsOneWidget);

        await undo.delete(
          repo: repo,
          collection: 'contact_messages',
          doc: m2,
          title: 'Queued Two',
          messenger: messengerKey.currentState,
          failedMsg: 'Failed: {e}',
          undoLabel: 'تراجع',
          undoAllLabel: 'تراجع عن الكل',
        );
        await tester.pump();
        expect(find.text('Long Unrelated Notice'), findsOneWidget);

        // Advance past 12s (still inside the 15s unrelated bar): neither doc commits before Undo shows!
        await tester.pump(const Duration(seconds: 12));
        expect(repo.deletedIds, isEmpty);
        expect(find.text('Long Unrelated Notice'), findsOneWidget);

        // Advance past 15s unrelated bar exit -> batched Undo all mounts directly (stale single Undo never appears)
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('تراجع عن الكل'), findsOneWidget);
        expect(find.text('تراجع'), findsNothing);
        expect(repo.deletedIds, isEmpty);

        // Undo stays available for the full 10s window while visible (check at +8s), then restores both cleanly!
        await tester.pump(const Duration(seconds: 8));
        expect(find.text('تراجع عن الكل'), findsOneWidget);
        expect(repo.deletedIds, isEmpty);

        await tester.tap(find.text('تراجع عن الكل'));
        await tester.pumpAndSettle();
        expect(repo.deletedIds, isEmpty);
        expect(isSoftDeleted(repo.collections['contact_messages']!.first.data), isFalse);
        expect(isSoftDeleted(repo.collections['contact_messages']!.last.data), isFalse);
      });

      testWidgets('FeaturesScreen never shows updatedElsewhere banner on failed save with rollback', (tester) async {
        final initialDoc = AdminDoc('features', {
          'updatedAt': DateTime.utc(2026, 11, 1, 10),
          'sections': {'meetings': true},
        });
        final backend = _FailingRollbackSaveBackend(initialDocs: {
          'settings/features': initialDoc.data,
        });

        await tester.pumpWidget(_app(
          FeaturesScreen(repo: backend),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Mark form dirty by changing a switch
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();

        // Save
        await tester.tap(find.byKey(const Key('features-save')));
        await tester.pumpAndSettle();

        // Verify updatedElsewhere banner is NEVER shown
        expect(find.text('تم تعديل هذه البيانات في مكان آخر'), findsNothing);
        expect(find.byType(MaterialBanner), findsNothing);
      });

      testWidgets('OverviewScreen shows breakdown subtitle when sample items span multiple collections',
          (tester) async {
        final backend = _TestAdminBackend(initialCollections: {
          'liturgies': [
            for (var i = 0; i < 45; i++)
              AdminDoc('lit-$i', {
                'type': 'liturgy',
                'sample': true,
                'nameAr': 'قداس تجريبي',
                'weekday': 1,
              }),
          ],
          'priests': [
            AdminDoc('pr-1', {
              'status': 'serving',
              'sample': true,
              'nameAr': 'أب كاهن',
            }),
          ],
        }, initialDocs: {
          'settings/features': {
            'sections': {'liturgies': true, 'priests': true},
          },
        });

        await tester.pumpWidget(_app(
          OverviewScreen(repo: backend, role: AdminRoles.owner, onOpen: (_) {}),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('attention-unconfirmedData')), findsOneWidget);
        expect(find.textContaining('منها 45 في القداسات'), findsOneWidget);
      });

      testWidgets('OverviewScreen shows breakdown subtitle in English when sample items span multiple collections',
          (tester) async {
        final backend = _TestAdminBackend(initialCollections: {
          'liturgies': [
            for (var i = 0; i < 10; i++)
              AdminDoc('lit-$i', {
                'type': 'liturgy',
                'sample': true,
                'nameAr': 'قداس تجريبي',
                'nameEn': 'Sample mass',
                'weekday': 1,
              }),
          ],
          'priests': [
            AdminDoc('pr-1', {
              'status': 'serving',
              'sample': true,
              'nameAr': 'أب كاهن',
              'nameEn': 'Sample priest',
            }),
          ],
        }, initialDocs: {
          'settings/features': {
            'sections': {'liturgies': true, 'priests': true},
          },
        });

        await tester.pumpWidget(_app(
          OverviewScreen(repo: backend, role: AdminRoles.owner, onOpen: (_) {}),
          locale: const Locale('en'),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('attention-unconfirmedData')), findsOneWidget);
        expect(find.textContaining('Includes 10 in Liturgies'), findsOneWidget);
      });

      testWidgets('DocEditor displays updated switch_sample label', (tester) async {
        final litDef = adminCollections.firstWhere((c) => c.name == 'liturgies');
        await tester.pumpWidget(MaterialApp(
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          locale: const Locale('ar'),
          home: Scaffold(
            body: DocEditor(
              key: const ValueKey('liturgies-editor'),
              title: litDef.labelAr,
              fields: litDef.fields,
              def: litDef,
              popOnSave: true,
              data: const {'sample': true},
              onSave: (_) async {},
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('غير مؤكد (تجريبي)'), findsWidgets);
      });
    });
  });

  group('PR #83 follow-up fixes and regressions', () {
    testWidgets('CollectionListScreen(categories) creates a new category from scratch (englishEnabled: false and true)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final englishEnabled in [false, true]) {
        final repo = _TestAdminBackend(
          initialCollections: {
            'categories': [],
            'entries': [],
            'pages': [],
          },
          initialDocs: {
            'settings/features': {'englishEnabled': englishEnabled},
          },
        );

        await tester.pumpWidget(_app(
          CollectionListScreen(repo: repo, def: collectionById('categories')!),
          locale: const Locale('ar'),
        ));
        await tester.pumpAndSettle();

        // Tap Add
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        // Fill Arabic name
        await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'رحلات الشباب');
        await tester.pumpAndSettle();

        // Tap Save
        await tester.tap(find.byKey(const Key('editor-save-top')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(repo.savedDocs, isNotEmpty);
        final saved = repo.savedDocs.last.data;

        expect(saved['nameAr'], 'رحلات الشباب');
        expect(saved['slug'], 'rhlat-alshbab');
        expect(saved['icon'], 'star');
        expect(saved['showInNav'], isTrue);
        expect(saved['visible'], isTrue);
        expect(saved['order'], isNull);
        expect(saved['nameEn'], '');
        expect(saved['introEn'], '');
        expect(saved['introAr'], '');
        expect(saved.containsKey('imageStyle'), isFalse);
      }
    });

    testWidgets('DocEditor surfaces Firebase error code when repo.save throws FirebaseException', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _PermissionDeniedBackend();
      final catDef = collectionById('categories')!;

      await tester.pumpWidget(_app(
        Scaffold(
          body: DocEditor(
            title: 'إضافة فسم',
            fields: catDef.fields,
            def: catDef,
            popOnSave: true,
            onSave: (data) => repo.save('categories', null, data),
            newDefaults: const {
              'nameAr': 'قسم ممنوع',
            },
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();

      final errorBanner = find.byKey(const Key('editor-save-error'));
      expect(errorBanner, findsOneWidget);
      expect(find.descendant(of: errorBanner, matching: find.textContaining('permission-denied')), findsOneWidget);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.textContaining('permission-denied')), findsOneWidget);
    });

    testWidgets('CollectionListScreen Undo SnackBar auto-dismisses after 10 seconds cleanly', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _TestAdminBackend(initialCollections: {
        'liturgies': [
          AdminDoc('lit-1', {
            'titleAr': 'قداس الأحد',
            'weekday': 7,
            'start': '06:30',
            'end': '08:30',
            'visible': true,
          }),
        ],
      });

      await tester.pumpWidget(_app(
        CollectionListScreen(repo: repo, def: collectionById('liturgies')!),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(const ValueKey('delete-lit-1'));
      expect(deleteBtn, findsOneWidget);
      await _confirmDeleteTap(tester, deleteBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'تراجع'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'تراجع'), findsNothing);
      expect(find.text('تراجع'), findsNothing);
    });

    testWidgets('Empty heading block validation fails, summary expands collapsed block on tap, filling text allows save to succeed', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      final pagesDef = collectionById('pages')!;
      await tester.pumpWidget(_app(
        Scaffold(
          body: DocEditor(
            title: 'صفحة جد،دة',
            fields: pagesDef.fields,
            def: pagesDef,
            popOnSave: true,
            onSave: (d) async => saved = d,
            newDefaults: const {
              'titleAr': 'صفحة تجريبية',
              'blocks': [
                'heading',
                'paragraphفقرة نصية',
              ],
            },
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      // Tap Save -> fails because heading textAr is empty
      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      final errorSummary = find.byKey(const Key('editor-error-summary'));
      expect(errorSummary, findsOneWidget);

      // Tap the error entry in summary
      final errorEntry = find.descendant(of: errorSummary, matching: find.byType(InkWell)).first;
      await tester.tap(errorEntry);
      await tester.pumpAndSettle();

      // Heading block (row 0) should now be expanded!
      final textArFields = find.byKey(const ValueKey('field-textAr'));
      expect(textArFields, findsWidgets);
      await tester.enterText(textArFields.first, 'عنوان رئيسي');
      await tester.pumpAndSettle();

      // Tap Save again -> should succeed!
      await tester.tap(find.byKey(const Key('editor-save-top')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final savedBlocks = saved!['blocks'] as List;
      expect(savedBlocks.first, contains('عنوان رئيسي'));
    });
  });

  group('Phase 4 PR4B: details block validator & snippet summary', () {
    test('validateDetailsBlock enforces required AR summary/body and length bounds', () {
      expect(
        validateDetailsBlock(summaryAr: 'ملخص', bodyAr: 'نص التفاصيل'),
        isEmpty,
      );
      expect(
        validateDetailsBlock(
          summaryAr: 'أ' * detailsSummaryMax,
          bodyAr: 'ب' * detailsBodyMax,
          summaryEn: 'S' * detailsSummaryMax,
          bodyEn: 'E' * detailsBodyMax,
        ),
        isEmpty,
      );

      final missingBoth = validateDetailsBlock(summaryAr: '  \u001f ', bodyAr: '\u001e  ');
      expect(missingBoth.map((e) => (e.field, e.isEn, e.code)).toList(), [
        ('summary', false, 'blockDetailsSummaryRequired'),
        ('body', false, 'blockDetailsBodyRequired'),
      ]);

      final tooLongAll = validateDetailsBlock(
        summaryAr: 'أ' * (detailsSummaryMax + 1),
        bodyAr: 'ب' * (detailsBodyMax + 1),
        summaryEn: 'S' * (detailsSummaryMax + 1),
        bodyEn: 'E' * (detailsBodyMax + 1),
      );
      expect(tooLongAll.map((e) => (e.field, e.isEn, e.code)).toList(), [
        ('summary', false, 'blockDetailsSummaryTooLong'),
        ('body', false, 'blockDetailsBodyTooLong'),
        ('summary', true, 'blockDetailsSummaryTooLong'),
        ('body', true, 'blockDetailsBodyTooLong'),
      ]);

      // Partial EN is allowed by validator (public UI performs block-level AR fallback).
      expect(
        validateDetailsBlock(summaryAr: 'ملخص', bodyAr: 'نص', summaryEn: 'Only summary'),
        isEmpty,
      );
      expect(
        validateDetailsBlock(summaryAr: 'ملخص', bodyAr: 'نص', bodyEn: 'Only body'),
        isEmpty,
      );
    });

    test('validateDocument checks BlockTypes.details blocks on pages', () {
      final pagesDef = adminCollections.firstWhere((c) => c.name == 'pages');
      Map<String, dynamic> pageWith(PageBlock b) => {
            'slug': 'details-check',
            'titleAr': 'عنوان',
            'blocks': [b.toMap()],
          };

      expect(
        validateDocument(
          pagesDef,
          pageWith(PageBlock.details(
            summaryAr: 'سؤال',
            bodyAr: 'إجابة',
            summaryEn: 'Question',
            bodyEn: 'Answer',
          )),
        ),
        isNull,
      );
      expect(
        validateDocument(pagesDef, pageWith(PageBlock.details(summaryAr: '', bodyAr: 'إجابة'))),
        'blockDetailsSummaryRequired',
      );
      expect(
        validateDocument(pagesDef, pageWith(PageBlock.details(summaryAr: 'سؤال', bodyAr: '   '))),
        'blockDetailsBodyRequired',
      );
      expect(
        validateDocument(
          pagesDef,
          pageWith(PageBlock.details(
            summaryAr: 'سؤال',
            bodyAr: 'إجابة',
            bodyEn: 'E' * (detailsBodyMax + 1),
          )),
        ),
        'blockDetailsBodyTooLong',
      );
    });

    test('blockSnippetSummary handles BlockTypes.details fallback order and clipping', () {
      expect(blockSnippetSummary(type: BlockTypes.details), '');
      expect(blockSnippetSummary(type: BlockTypes.details, textAr: '  \u001e  ', textEn: '\u001e'), '');
      expect(
        blockSnippetSummary(
          type: BlockTypes.details,
          textAr: 'ملخص عربي\u001eتفاصيل عربية',
          textEn: 'English summary\u001eEnglish body',
        ),
        'ملخص عربي',
      );
      expect(
        blockSnippetSummary(
          type: BlockTypes.details,
          textAr: '\u001eتفاصيل عربية',
          textEn: 'English summary\u001eEnglish body',
        ),
        'English summary',
      );
      expect(
        blockSnippetSummary(
          type: BlockTypes.details,
          textAr: '\u001eتفاصيل عربية',
          textEn: '\u001eEnglish body',
        ),
        'تفاصيل عربية',
      );
      expect(
        blockSnippetSummary(
          type: BlockTypes.details,
          textAr: '',
          textEn: '\u001eEnglish body only',
        ),
        'English body only',
      );
      final clipped = blockSnippetSummary(
        type: BlockTypes.details,
        textAr: 'تجربة ملخص طويل جداً يتجاوز أربعين حرفاً في المعاينة\u001eنص',
      );
      expect(clipped, isNotNull);
      expect(clipped!.endsWith('…'), isTrue);
      expect(clipped.length, 41);
    });
  });

  group('appInstallDoc schema & DocEditor', () {
    test('schema defines all 13 app install & APK fields', () {
      expect(appInstallDoc.fields.length, 13);
      final keys = appInstallDoc.fields.map((f) => f.key).toSet();
      expect(
        keys,
        containsAll([
          'installPrompt',
          'installTitleAr',
          'installTitleEn',
          'installBodyAr',
          'installBodyEn',
          'installAndroidUrl',
          'installAndroidUrl32',
          'installApkVersion',
          'installApkBuild',
          'installApkSizeMb',
          'installApkSize32Mb',
          'installReshowDays',
          'installRemindDays',
        ]),
      );
    });

    testWidgets('DocEditor renders appInstallDoc with initial values and saves only changed fields', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? saved;
      final initialData = <String, dynamic>{
        'installPrompt': true,
        'installTitleAr': 'تطبيق الكنيسة',
        'installTitleEn': 'Church App',
        'installBodyAr': 'نص الشريط',
        'installBodyEn': 'Banner text',
        'installAndroidUrl': 'https://example.com/app.apk',
        'installApkVersion': '1.1.0',
        'installApkBuild': 12,
        'installApkSizeMb': 18.4,
        'installReshowDays': 14,
        'installRemindDays': 3,
      };

      await tester.pumpWidget(_app(DocEditor(
        title: appInstallDoc.labelAr,
        fields: appInstallDoc.fields,
        data: initialData,
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-save')), findsOneWidget);
      for (final f in appInstallDoc.fields) {
        expect(find.byKey(ValueKey('field-${f.key}')), findsOneWidget, reason: 'Field ${f.key} must be rendered');
      }

      await tester.enterText(find.byKey(const ValueKey('field-installApkVersion')), '1.2.0');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['installApkVersion'], '1.2.0');
      expect(saved!.containsKey('installApkBuild'), isFalse);
      expect(saved!.containsKey('installApkSizeMb'), isFalse);
      expect(saved!.containsKey('installPrompt'), isFalse);
    });
  });
}

class _MediaTestAdminBackend extends _TestAdminBackend {
  final _TestMediaRepo _media;
  _MediaTestAdminBackend(this._media, {super.initialCollections});

  @override
  MediaRepository? get media => _media;
}

class _SilentOverviewBackend extends _TestAdminBackend {
  final Stream<List<AdminDoc>>? Function(String collection)? onWatchCollection;
  final Stream<AdminDoc?>? Function(String path)? onWatchDoc;

  _SilentOverviewBackend({
    super.initialCollections,
    super.initialDocs,
    this.onWatchCollection,
    this.onWatchDoc,
  });

  @override
  Stream<List<AdminDoc>> watch(String collection) =>
      onWatchCollection?.call(collection) ?? super.watch(collection);

  @override
  Stream<AdminDoc?> watchDoc(String path) => onWatchDoc?.call(path) ?? super.watchDoc(path);
}

class _TestAdminBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> collections = {};
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> deletedIds = [];
  final List<String> savedPaths = [];
  final List<({String collection, String? id, Map<String, dynamic> data})> savedDocs = [];
  final List<({String collection, List<String> ids, int base})> reorderCalls = [];
  final List<({String collection, String id, Map<String, dynamic> data})> updates = [];
  final List<({String uid, String email, String role})> setAdminCalls = [];
  bool failDelete = false;

  _TestAdminBackend({
    Map<String, List<AdminDoc>>? initialCollections,
    Map<String, Map<String, dynamic>>? initialDocs,
  }) {
    if (initialCollections != null) collections.addAll(initialCollections);
    if (initialDocs != null) docs.addAll(initialDocs);
  }

  @override
  String get actor => 'admin@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    return Stream.value(collections[collection] ?? const []);
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final d = docs[path];
    return Stream.value(d == null ? null : AdminDoc(path.split('/').last, d));
  }

  @override
  Future<void> delete(String collection, String id) async {
    if (failDelete) throw StateError('delete blocked');
    deletedIds.add('$collection/$id');
    collections[collection]?.removeWhere((doc) => doc.id == id);
  }

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    savedDocs.add((collection: collection, id: id, data: Map<String, dynamic>.from(data)));
    return id ?? 'new';
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    updates.add((collection: collection, id: id, data: Map<String, dynamic>.from(data)));
    final list = collections[collection];
    if (list != null) {
      for (final doc in list) {
        if (doc.id == id) {
          doc.data.addAll(data);
          if (data.containsKey('deletedAt') && data['deletedAt'] == null) {
            doc.data.remove('deletedAt');
          }
          if (data.containsKey('expiresAt') && data['expiresAt'] == null) {
            doc.data.remove('expiresAt');
          }
        }
      }
    }
  }

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {
    reorderCalls.add((collection: collection, ids: List<String>.from(ids), base: base));
  }

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {
    setAdminCalls.add((uid: uid, email: email, role: role));
    final list = collections['admins'];
    if (list != null) {
      for (final doc in list) {
        if (doc.id == uid) {
          doc.data['email'] = email;
          doc.data['role'] = role;
        }
      }
    }
  }

  @override
  Future<void> removeAdmin(String uid) async {}

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    savedPaths.add(path);
    docs[path] = data;
  }
}

class _ReactiveAdminBackend extends _TestAdminBackend {
  final StreamController<List<AdminDoc>> controller;

  _ReactiveAdminBackend({
    required this.controller,
    super.initialCollections,
  });

  @override
  Stream<List<AdminDoc>> watch(String collection) async* {
    yield [for (final d in collections[collection] ?? const <AdminDoc>[]) AdminDoc(d.id, Map<String, dynamic>.from(d.data))];
    yield* controller.stream;
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    await super.update(collection, id, data);
    if (!controller.isClosed) {
      controller.add([
        for (final d in collections[collection] ?? const <AdminDoc>[]) AdminDoc(d.id, Map<String, dynamic>.from(d.data)),
      ]);
    }
  }

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {
    await super.setAdmin(uid, email: email, role: role);
    if (!controller.isClosed) {
      controller.add([
        for (final d in collections['admins'] ?? const <AdminDoc>[]) AdminDoc(d.id, Map<String, dynamic>.from(d.data)),
      ]);
    }
  }
}

class _StreamingDocBackend extends _TestAdminBackend {
  final Map<String, StreamController<AdminDoc?>> _controllers = {};

  _StreamingDocBackend({super.initialDocs});

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _controllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        final d = docs[path];
        c.add(d == null ? null : AdminDoc(path.split('/').last, d));
      }
    });
    return c.stream;
  }

  void emitDoc(String path, Map<String, dynamic>? data) {
    if (data == null) {
      docs.remove(path);
      _controllers[path]?.add(null);
      return;
    }
    docs[path] = data;
    _controllers[path]?.add(AdminDoc(path.split('/').last, data));
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
  }
}

class _TestMediaRepo implements MediaRepository {
  final List<String> deleted = [];

  @override
  String get source => 'firestore';

  @override
  Future<Uint8List?> load(String mediaId) async => null;

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) async =>
      MediaImage(source: MediaSource.inline, mediaId: 'm1');

  @override
  Future<void> delete(String mediaId) async {
    deleted.add(mediaId);
  }
}

class _SlowSaveBackend extends _TestAdminBackend {
  Completer<void>? _pending;
  final Map<String, StreamController<AdminDoc?>> _docControllers = {};

  _SlowSaveBackend({super.initialDocs});

  void holdNextSave() {
    _pending = Completer<void>();
  }

  void releaseNextSave() {
    _pending?.complete();
    _pending = null;
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _docControllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        final d = docs[path];
        c.add(d == null ? null : AdminDoc(path.split('/').last, Map<String, dynamic>.from(d)));
      }
    });
    return c.stream;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    final pending = _pending;
    if (pending != null) {
      await pending.future;
    }
    savedPaths.add(path);
    docs[path] = {...?docs[path], ...data};
    final c = _docControllers[path];
    if (c != null && !c.isClosed) {
      c.add(AdminDoc(path.split('/').last, Map<String, dynamic>.from(docs[path]!)));
    }
  }
}

class _ControllableOverviewBackend extends _TestAdminBackend {
  final Stream<List<AdminDoc>> Function() alertsStream;
  bool useEmptyAlerts = false;

  _ControllableOverviewBackend({
    required this.alertsStream,
    super.initialDocs,
  });

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    if (collection == 'alerts' && !useEmptyAlerts) {
      return alertsStream();
    }
    return super.watch(collection);
  }
}

class _FailingRollbackSaveBackend extends _TestAdminBackend {
  final Map<String, StreamController<AdminDoc?>> _docControllers = {};
  bool failSave = true;

  _FailingRollbackSaveBackend({super.initialDocs});

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _docControllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        final d = docs[path];
        c.add(d == null ? null : AdminDoc(path.split('/').last, Map<String, dynamic>.from(d)));
      }
    });
    return c.stream;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    savedPaths.add(path);
    final c = _docControllers[path];
    if (failSave) {
      final original = docs[path];
      if (c != null && !c.isClosed) {
        c.add(AdminDoc(path.split('/').last, {...?original, ...data, 'updatedAt': null}));
      }
      if (c != null && !c.isClosed) {
        c.add(original == null ? null : AdminDoc(path.split('/').last, Map<String, dynamic>.from(original)));
      }
      throw StateError('Firestore save failed');
    }
  }
}


class _DelayedSaveBackend extends _TestAdminBackend {
  final Future<void> delay;
  final Map<String, StreamController<AdminDoc?>> _docControllers = {};

  _DelayedSaveBackend(this.delay, {super.initialDocs});

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    final c = _docControllers.putIfAbsent(path, () => StreamController<AdminDoc?>.broadcast());
    scheduleMicrotask(() {
      if (!c.isClosed) {
        final d = docs[path];
        c.add(d == null ? null : AdminDoc(path.split('/').last, Map<String, dynamic>.from(d)));
      }
    });
    return c.stream;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    await delay;
    savedPaths.add(path);
    docs[path] = {...?docs[path], ...data};
    final c = _docControllers[path];
    if (c != null && !c.isClosed) {
      c.add(AdminDoc(path.split('/').last, Map<String, dynamic>.from(docs[path]!)));
    }
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    await delay;
    final path = '$collection/$id';
    savedPaths.add(path);
    docs[path] = {...?docs[path], ...data};
    final c = _docControllers[path];
    if (c != null && !c.isClosed) {
      c.add(AdminDoc(id, Map<String, dynamic>.from(docs[path]!)));
    }
  }
}

class _PermissionDeniedBackend extends _TestAdminBackend {

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}

class _ControlledUpdateBackend extends _TestAdminBackend {
  final Map<String, StreamController<List<AdminDoc>>> _controllers = {};
  final Map<String, Completer<void>> _holds = {};
  final Map<String, Completer<void>> _deleteHolds = {};
  bool emitOnUpdate = true;

  _ControlledUpdateBackend({super.initialCollections});

  Completer<void> hold(String collection, String id) {
    final c = Completer<void>();
    _holds['$collection:$id'] = c;
    return c;
  }

  Completer<void> holdDelete(String collection, String id) {
    final c = Completer<void>();
    _deleteHolds['$collection:$id'] = c;
    return c;
  }

  @override
  Future<void> delete(String collection, String id) async {
    final hold = _deleteHolds.remove('$collection:$id');
    if (hold != null) {
      await hold.future;
    }
    await super.delete(collection, id);
  }

  void emitSnapshot(String collection) {
    final c = _controllers[collection];
    if (c != null && !c.isClosed) {
      c.add([
        for (final d in collections[collection] ?? const <AdminDoc>[])
          AdminDoc(d.id, Map<String, dynamic>.from(d.data)),
      ]);
    }
  }

  @override
  Stream<List<AdminDoc>> watch(String collection) async* {
    yield [
      for (final d in collections[collection] ?? const <AdminDoc>[])
        AdminDoc(d.id, Map<String, dynamic>.from(d.data)),
    ];
    final c = _controllers.putIfAbsent(collection, () => StreamController<List<AdminDoc>>.broadcast());
    yield* c.stream;
  }

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
    final hold = _holds.remove('$collection:$id');
    updates.add((collection: collection, id: id, data: Map<String, dynamic>.from(data)));
    if (hold != null) {
      await hold.future;
    }
    final list = collections[collection];
    if (list != null) {
      for (final doc in list) {
        if (doc.id == id) {
          doc.data.addAll(data);
        }
      }
    }
    if (emitOnUpdate) {
      emitSnapshot(collection);
    }
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
  }
}
