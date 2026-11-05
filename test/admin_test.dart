import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
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
      // Times come from the 24-hour picker since ADR-048 (read-only fields).
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
      tester.view.physicalSize = const Size(1200, 5000);
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
}
