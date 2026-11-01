import 'dart:convert';
import 'dart:io';

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

FieldDef _f(FieldType t, {bool required = false, num? min, num? max, bool allowPath = false, int maxLength = 0}) =>
    FieldDef('k', 'ك', 'k', t, required: required, min: min, max: max, allowPath: allowPath, maxLength: maxLength);

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
        final list = RegExp(r"keysAllowed\(\[([^\]]*)\]").firstMatch(body)!.group(1)!;
        final keys = RegExp(r"'([A-Za-z]+)'").allMatches(list).map((m) => m.group(1)!).toSet();
        if (body.contains('concat(meta())')) keys.addAll(['visible', 'sample', 'order', 'updatedAt', 'updatedBy']);
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
      await tester.enterText(find.byKey(const ValueKey('field-start')), '9:00'); // invalid
      await tester.enterText(find.byKey(const ValueKey('field-bookingPhone')), '010 1234 5678');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Use HH:mm, e.g. 06:30'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field-start')), '16:00');
      await tester.enterText(find.byKey(const ValueKey('field-end')), '20:00');
      await tester.enterText(find.byKey(const ValueKey('field-order')), '30');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['doctorName'], 'د. مينا');
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
}
