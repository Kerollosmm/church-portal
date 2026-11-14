import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/ui/admin/admin_access.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/admin/pending_delete.dart';
import 'package:church_portal/ui/admin/session_policy.dart';
import 'package:church_portal/ui/admin/state_switch.dart';
import 'package:church_portal/ui/admin/unsaved_bar.dart';
import 'package:church_portal/ui/admin/unsaved_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/admin_pickers.dart';

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

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('field validation', () {
    test('required and length', () {
      expect(validateFieldValue(_f(FieldType.text, required: true), '  '), 'required');
      expect(validateFieldValue(_f(FieldType.text), ''), isNull);
      expect(validateFieldValue(_f(FieldType.text, maxLength: 3), 'abcd'), 'tooLong');
      expect(validateFieldValue(_f(FieldType.multiline), 'x' * 5000), isNull);
      expect(validateFieldValue(_f(FieldType.multiline), 'x' * 5001), 'tooLong');
    });

    test('time, dates and loose dates', () {
      expect(validateFieldValue(_f(FieldType.time), '06:30'), isNull);
      expect(validateFieldValue(_f(FieldType.time), '6:30'), 'invalidTime');
      expect(validateFieldValue(_f(FieldType.time), '24:00'), 'invalidTime');
      expect(validateFieldValue(_f(FieldType.date), '2027-02-30'), 'invalidDate');
      expect(validateFieldValue(_f(FieldType.date), '2027-01-06'), isNull);
      expect(validateFieldValue(_f(FieldType.dateTime), '2027-01-06 20:00'), isNull);
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
      expect(validateFieldValue(_f(FieldType.url), '/clinics'), 'invalidUrl');
      expect(validateFieldValue(_f(FieldType.url, allowPath: true), '/clinics'), isNull);
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
      final clinic = collectionById('clinics')!;
      expect(validateDocument(clinic, {'start': '20:00', 'end': '16:00'}), 'endBeforeStart');
      expect(validateDocument(clinic, {'start': '16:00', 'end': '20:00'}), isNull);
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
      expect(names, containsAll(['alerts', 'seasons', 'liturgies', 'meetings', 'activities', 'clinics', 'facilities', //
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

    test('departed-fathers screen filters priests by status (missing = serving)', () {
      final departed = collectionById('departedPriests')!;
      final serving = collectionById('priests')!;
      expect(departed.matches({'status': 'departed'}), isTrue);
      expect(departed.matches({'status': 'serving'}), isFalse);
      expect(serving.matches(const {}), isTrue);
      expect(departed.newDefaults['status'], 'departed');
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
        'activities': 'validActivity', 'clinics': 'validClinic', 'facilities': 'validFacility',
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
    const detailCols = ['meetings', 'activities', 'clinics', 'facilities', 'priests', 'milestones', 'saints'];
    FieldDef fd(CollectionDef c, String k) => c.fields.firstWhere((f) => f.key == k, orElse: () => throw k);

    test('imageList type, field groups and the image collections', () {
      expect(FieldType.values, contains(FieldType.imageList));
      expect(FieldGroup.values,
          [FieldGroup.basic, FieldGroup.program, FieldGroup.details, FieldGroup.media, FieldGroup.contacts]);
      expect(const FieldDef('x', 'x', 'x', FieldType.text).group, FieldGroup.basic);
      expect(imageCollections,
          ['alerts', 'seasons', 'meetings', 'activities', 'clinics', 'facilities', 'priests', 'milestones', 'saints',
            'entries', 'pages']);
      for (final c in adminCollections) {
        expect(c.fields.any((f) => f.key == 'image'), imageCollections.contains(c.name), reason: c.id);
      }
    });

    test('the 7 detail collections carry grouped details, media and contacts fields', () {
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

        expect(fd(c, 'image').group, FieldGroup.media, reason: c.id);
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
        final phone = switch (c.name) { 'clinics' => 'bookingPhone', 'facilities' => 'phone', _ => 'contactPhone' };
        final link = c.name == 'activities' ? 'link' : 'externalUrl';
        for (final k in [phone, 'whatsapp', 'whatsappUrl', 'facebookUrl', 'youtubeUrl', 'instagramUrl', link,
          'externalLabelAr', 'externalLabelEn', 'contactNoteAr', 'contactNoteEn']) {
          expect(fd(c, k).group, FieldGroup.contacts, reason: '${c.id}.$k');
        }
        if (['clinics', 'facilities'].contains(c.name)) expect(keys, isNot(contains('contactPhone')));
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
      expect(path('c1', 'clinics', on, english: true), '/clinics/c1?lang=en');
      expect(path('f1', 'facilities', on), '/public-services/f1');
      expect(path('p1', 'priests', on), '/about/priests/p1');
      expect(path('p2', 'departedPriests', on), '/about/priests/p2');
      expect(path('s1', 'saints', on), '/about/saints/s1');
      expect(path('h1', 'milestones', on), '/about/milestones/h1');
      // Untouched items (no field) have a page since PR #14.
      expect(path('c1', 'clinics', const {}), '/clinics/c1');
      // No detail page (switched off, hidden, or a collection without one): no link.
      expect(path('c1', 'clinics', const {'detailsEnabled': false}), isNull);
      // Inactive clinics are not listed publicly, so their page is unavailable (CodeRabbit review).
      expect(path('c1', 'clinics', const {'active': false}), isNull);
      expect(path('c1', 'clinics', const {'active': true}), '/clinics/c1');
      expect(path('c1', 'clinics', const {'detailsEnabled': true, 'visible': false}), isNull);
      expect(path('l1', 'liturgies', on), isNull);
      expect(path('x/y', 'clinics', on), '/clinics/x%2Fy');
    });
  });

  group('admin list helpers', () {
    final def = collectionById('clinics')!;
    final docs = [
      const AdminDoc('a', {'doctorName': 'Dr Mina', 'specialtyAr': 'الأسنان', 'order': 20, 'visible': false}),
      const AdminDoc('b', {'doctorName': 'Dr Bishoy', 'specialtyAr': 'الأطفال', 'order': 10, 'sample': true}),
      const AdminDoc('c', {'doctorName': 'Dr Kero', 'specialtyAr': 'الباطنة'}),
    ];

    test('sorts orderable collections by order, unordered last', () {
      expect(sortAdminDocs(def, docs).map((d) => d.id), ['b', 'a', 'c']);
    });

    test('search and filters', () {
      expect(filterAdminDocs(def, docs, query: 'mina').map((d) => d.id), ['a']);
      expect(filterAdminDocs(def, docs, query: 'الأطفال').map((d) => d.id), ['b']);
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
      final def = collectionById('clinics')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Add clinic',
        fields: def.fields,
        def: def,
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Required'), findsWidgets);

      await tester.enterText(find.byKey(const ValueKey('field-specialty')), 'dental');
      await tester.enterText(find.byKey(const ValueKey('field-specialtyAr')), 'الأسنان');
      await tester.enterText(find.byKey(const ValueKey('field-doctorName')), 'د. مينا');
      // The booking phone sits in the collapsible "Contacts & links" group (PR #12).
      await tester.tap(find.byKey(const ValueKey('group-contacts')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-bookingPhone')), '010 1234 5678');
      await tester.enterText(find.byKey(const ValueKey('field-order')), 'abc'); // invalid
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      // Times come from the 12-hour picker since ADR-049 (read-only fields; stored 24h).
      await pickTime(tester, 'start', 16, 0);
      await pickTime(tester, 'end', 20, 0);
      await tester.enterText(find.byKey(const ValueKey('field-order')), '30');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['doctorName'], 'د. مينا');
      // New doc: every field, except an unset image style (ADR-023: missing =
      // section default, so a new doc does not write it).
      expect(saved!.keys, containsAll(def.fields.map((f) => f.key).where((k) => k != 'imageStyle')));
      expect(saved!.containsKey('imageStyle'), isFalse);
      expect(saved!['bookingPhone'], '01012345678');
      expect(saved!['order'], 30);
      expect(saved!['visible'], isTrue); // new items start visible
      expect(saved!['sample'], isFalse);
      expect(saved!['active'], isTrue);
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
      final clinicsSwitch = find.descendant(
          of: find.byKey(const ValueKey('section-clinics')), matching: find.byType(Switch));
      await tester.tap(clinicsSwitch);
      await tester.tap(find.byKey(const ValueKey('theme-navy')));
      await tester.enterText(find.byKey(const ValueKey('features-bannerEn')), 'Christmas times are out');
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.enabled(Sections.clinics), isFalse);
      expect(saved!.enabled(Sections.schedule), isTrue);
      expect(saved!.theme, 'navy');
      expect(saved!.bannerEn, 'Christmas times are out');
      expect(saved!.toMap()['sections'], containsPair('clinics', false));
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
      expect(find.byKey(const ValueKey('pageCustomized-clinics')), findsNothing);
      expect(find.text('Customized'), findsNWidgets(2));
      // Collapsed rows keep their fields mounted.
      expect(page('clinics', 'titleEn'), findsNothing);
      expect(page('clinics', 'titleEn').hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-clinics')));
      await tester.pumpAndSettle();
      await tester.enterText(page('clinics', 'titleEn'), 'Our clinics');
      await tester.enterText(page('clinics', 'introAr'), 'الكشف بالحجز المسبق');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageCustomized-clinics')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pageReset-ask')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pageCustomized-ask')), findsNothing);
      expect(find.byKey(const ValueKey('pageReset-ask')), findsNothing, reason: 'nothing left to reset');
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.pageHeaders.keys, ['about', 'clinics']);
      expect(saved!.pageHeader('clinics'), const PageCustom(titleEn: 'Our clinics', introAr: 'الكشف بالحجز المسبق'));
      expect(saved!.pageHeader('about'), const PageCustom(subtitleAr: 'تاريخنا'));
      expect(saved!.toMap()['pageHeaders'], {
        'about': const PageCustom(subtitleAr: 'تاريخنا').toMap(),
        'clinics': const PageCustom(titleEn: 'Our clinics', introAr: 'الكشف بالحجز المسبق').toMap(),
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
    testWidgets('selected theme ChoiceChip and clinic weekday FilterChip use a white label', (tester) async {
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

      final def = collectionById('clinics')!;
      await tester.pumpWidget(_app(DocEditor(
        title: 'Clinic',
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
      await tester.pumpWidget(_app(AdminDashboard(
        repo: repo,
        uid: 'u1',
        email: 'test@church.org',
        role: AdminRoles.owner,
        onSignOut: () {},
        initial: 'church',
      )));
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
    test('schedule, undo within window, expiry, flush and dispose', () async {
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

      // Flush commits immediately
      pd.schedule('item3', () async => commits++);
      expect(pd.hasPending, isTrue);
      await pd.flush();
      expect(commits, 2);
      expect(pd.hasPending, isFalse);

      // Dispose cancels local timers without committing
      pd.schedule('item4', () async => commits++);
      expect(pd.hasPending, isTrue);
      pd.dispose();
      expect(pd.hasPending, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(commits, 2);
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
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Immediately hidden and soft-deleted
      expect(find.text('مارمرقس'), findsNothing);
      expect(repo.deletedIds, isEmpty);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's1').data), isTrue);
      expect(find.text('اتمسح «مارمرقس»'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      // Tap Undo -> restores row and clears deletedAt
      await tester.tap(find.byType(SnackBarAction));
      await tester.pump();
      expect(find.text('مارمرقس'), findsOneWidget);
      expect(isSoftDeleted(repo.collections['saints']!.firstWhere((d) => d.id == 's1').data), isFalse);
      expect(repo.deletedIds, isEmpty);

      // Delete s1 again and wait 10s -> commits hard delete
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('مارمرقس'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, contains('saints/s1'));

      // Delete s2 and unmount/dispose -> cancels local timers, doc remains soft-deleted, lazy purge purges it
      await tester.tap(find.byIcon(Icons.delete_outline).first);
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
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('عن الكنيسة'), findsNothing);

      // Open editor for a new page
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(DocEditor), findsOneWidget);

      // Enter the slug of the pending-deleted page
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
      await tester.tap(find.byIcon(Icons.delete_outline).first);
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
        await tester.pumpWidget(_app(
          Scaffold(
            bottomNavigationBar: UnsavedBar(
              dirty: true,
              onSave: () {},
              onCancel: () {},
            ),
          ),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('unsaved-bar')), findsOneWidget);
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
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
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
      await tester.tap(find.byIcon(Icons.delete_outline).first);
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
          matching: find.textContaining('٠٧:٠٠ ص'),
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

      // Self switches and expiry picker are disabled (own comes after ed1)
      await tester.scrollUntilVisible(find.byKey(const ValueKey('admin-active-own')), 200, scrollable: outerScroll);
      await tester.pumpAndSettle();
      final ownSwitch = tester.widget<AdminStateSwitch>(find.byKey(const ValueKey('admin-active-own')));
      expect(ownSwitch.onChanged, isNull);
      final ownExpiry = tester.widget<ActionChip>(find.byKey(const ValueKey('admin-expiry-own')));
      expect(ownExpiry.onPressed, isNull);

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

      // Clearing ed1 expiry removes expiresAt
      await tester.ensureVisible(find.byKey(const ValueKey('admin-clear-expiry-ed1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-clear-expiry-ed1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-clear-expiry-ed1')), findsNothing);
    });

    testWidgets('AdminCheckGate blocks stopped/expired admins, revokes live, and locks when expiresAt passes', (tester) async {
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

      // 3. Live revocation via accessChanges while dashboard is open
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

      // 4. Expiry timer locks open dashboard once expiresAt elapses
      final soon = DateTime.now().toUtc().add(const Duration(seconds: 5));
      await tester.pumpWidget(ProviderScope(
        child: _app(
          AdminCheckGate(
            repo: repo,
            uid: 'u4',
            email: 'timer@church.org',
            loadAccess: () async => AdminAccess(role: 'editor', status: AdminAccountStatus.active, expiresAt: soon),
            accessChanges: const Stream.empty(),
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
    });
  });

  group('PR 3C: P1-13 session idle policy & remember me', () {
    test('SessionPolicy boundaries match 30-minute idle limit and 60-second warning', () {
      const policy = SessionPolicy();
      expect(policy.idleLimit, const Duration(minutes: 30));
      expect(policy.warnBefore, const Duration(seconds: 60));
      expect(policy.warnAt, const Duration(minutes: 29));

      expect(policy.shouldWarn(const Duration(minutes: 28, seconds: 59)), isFalse);
      expect(policy.shouldSignOut(const Duration(minutes: 28, seconds: 59)), isFalse);

      expect(policy.shouldWarn(const Duration(minutes: 29)), isTrue);
      expect(policy.shouldSignOut(const Duration(minutes: 29)), isFalse);

      expect(policy.shouldWarn(const Duration(minutes: 29, seconds: 59)), isTrue);
      expect(policy.shouldSignOut(const Duration(minutes: 29, seconds: 59)), isFalse);

      expect(policy.shouldWarn(const Duration(minutes: 30)), isFalse);
      expect(policy.shouldSignOut(const Duration(minutes: 30)), isTrue);

      expect(policy.shouldSignOut(const Duration(minutes: 31)), isTrue);
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

    testWidgets('AdminSessionGuard warns at warnAt, signs out at limit, resets on pointer/key/button, skips when disabled', (tester) async {
      final unsaved = UnsavedGuardRegistry();
      var signedOut = 0;

      Widget buildGuard({required bool enabled, Locale locale = const Locale('ar')}) => _app(
            Scaffold(
              body: AdminSessionGuard(
                enabled: enabled,
                unsaved: unsaved,
                onSignOut: () => signedOut++,
                child: const Center(child: Text('Dashboard Content')),
              ),
            ),
            locale: locale,
          );

      // 1. Enabled -> warns at 29m, pointer move/down resets timer and dismisses warning
      await tester.pumpWidget(buildGuard(enabled: true));
      await tester.pump(const Duration(minutes: 28, seconds: 59));
      expect(find.byKey(const ValueKey('session-idle-warning')), findsNothing);
      expect(signedOut, 0);

      await tester.pump(const Duration(seconds: 2)); // 29:01 idle
      expect(find.byKey(const ValueKey('session-idle-warning')), findsOneWidget);

      // Pointer event cancels warning & resets clock
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
}

class _TestAdminBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> collections = {};
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> deletedIds = [];
  final List<String> savedPaths = [];
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
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {
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
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}

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
}

class _TestMediaRepo implements MediaRepository {
  @override
  String get source => 'firestore';

  @override
  Future<Uint8List?> load(String mediaId) async => null;

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) async =>
      const MediaImage(source: 'firestore', mediaId: 'm1');

  @override
  Future<void> delete(String mediaId) async {}
}
