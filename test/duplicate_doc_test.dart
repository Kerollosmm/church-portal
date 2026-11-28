import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/media.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_strings.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeDuplicateBackend extends AdminBackend {
  final Map<String, List<AdminDoc>> _lists;
  final List<(String col, String? id, Map<String, dynamic> data)> saves = [];
  int _nextId = 1;

  _FakeDuplicateBackend(Map<String, List<AdminDoc>> lists)
      : _lists = {for (final e in lists.entries) e.key: List<AdminDoc>.of(e.value)};

  @override
  String get actor => 'admin@church.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(List<AdminDoc>.of(_lists[collection] ?? const []));

  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(null);

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    saves.add((collection, id, Map<String, dynamic>.from(data)));
    final list = _lists.putIfAbsent(collection, () => []);
    final docId = id ?? 'new-${_nextId++}';
    final idx = list.indexWhere((d) => d.id == docId);
    if (idx >= 0) {
      list[idx] = AdminDoc(docId, {...list[idx].data, ...data});
    } else {
      list.add(AdminDoc(docId, Map<String, dynamic>.from(data)));
    }
    return docId;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}

  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {}

  @override
  Future<void> delete(String collection, String id) async {}

  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}

  @override
  Future<void> removeAdmin(String uid) async {}
}

Widget _wrapAdmin(Widget child, {Locale locale = const Locale('ar')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(() {
    CairoTime.ensureInitialized();
    registerAdminStrings();
  });

  group('stripDocMeta & season date shift helpers', () {
    test('stripDocMeta removes identity/audit keys and deep-copies nested structures', () {
      final src = <String, dynamic>{
        'id': 'doc-1',
        'nameAr': 'قداس',
        'createdAt': DateTime.utc(2025, 1, 1),
        'updatedAt': DateTime.utc(2026, 1, 1),
        'updatedBy': 'a@b.c',
        'deletedAt': DateTime.utc(2026, 2, 1),
        'extraFields': [
          {'titleAr': 'ملاحظة', 'valueAr': 'قيمة'},
        ],
        'replaceDates': ['2026-04-10'],
      };
      final stripped = stripDocMeta(src);
      expect(stripped.containsKey('id'), isFalse);
      expect(stripped.containsKey('createdAt'), isFalse);
      expect(stripped.containsKey('updatedAt'), isFalse);
      expect(stripped.containsKey('updatedBy'), isFalse);
      expect(stripped.containsKey('deletedAt'), isFalse);
      expect(stripped['nameAr'], 'قداس');

      ((stripped['extraFields'] as List).first as Map)['titleAr'] = 'changed';
      (stripped['replaceDates'] as List).add('2026-04-11');
      expect(((src['extraFields'] as List).first as Map)['titleAr'], 'ملاحظة');
      expect(src['replaceDates'], ['2026-04-10']);
    });

    test('shiftCairoYear keeps Cairo wall time across DST changes and clamps Feb 29', () {
      // 2026-04-24 in Cairo is after DST spring-forward (UTC+3), so 18:00 Cairo = 15:00 UTC.
      // 2027-04-24 in Cairo is before DST spring-forward (Apr 30, 2027 -> UTC+2), so 18:00 Cairo = 16:00 UTC.
      final spring2026 = CairoTime.at(2026, 4, 24, 18 * 60).toUtc();
      final shifted2027 = shiftCairoYear(spring2026)!;
      final shiftedCairo = CairoTime.fromInstant(shifted2027);
      expect([shiftedCairo.year, shiftedCairo.month, shiftedCairo.day, shiftedCairo.hour, shiftedCairo.minute],
          [2027, 4, 24, 18, 0]);
      expect(shifted2027, CairoTime.at(2027, 4, 24, 18 * 60).toUtc());

      // Feb 29, 2024 14:30 Cairo -> Feb 28, 2025 14:30 Cairo.
      final leap = CairoTime.at(2024, 2, 29, 14 * 60 + 30).toUtc();
      final nonLeap = shiftCairoYear(leap)!;
      final nonLeapCairo = CairoTime.fromInstant(nonLeap);
      expect([nonLeapCairo.year, nonLeapCairo.month, nonLeapCairo.day, nonLeapCairo.hour, nonLeapCairo.minute],
          [2025, 2, 28, 14, 30]);

      expect(shiftCairoYear(null), isNull);
      expect(shiftCairoYear('not-a-date'), isNull);
    });

    test('shiftReplaceDatesYear shifts +1 year, handles Feb 29, and deduplicates/sorts', () {
      expect(
        shiftReplaceDatesYear(['2024-02-29', '2024-02-28', '2024-05-04', 'invalid']),
        ['2025-02-28', '2025-05-04'],
      );
      expect(shiftReplaceDatesYear(null), isEmpty);
    });
  });

  group('buildDuplicateDocDefaults', () {
    test('liturgies: appends (نسخة)/(copy), forces visible:false, strips meta and unexpected image', () {
      final res = buildDuplicateDocDefaults('liturgies', {
        'id': 'l1',
        'type': 'mass',
        'nameAr': 'قداس الجمعة',
        'nameEn': 'Friday Mass',
        'weekday': 5,
        'start': '08:00',
        'end': '10:00',
        'seasonKey': 'great_lent',
        'replacesDay': false,
        'visible': true,
        'sample': true,
        'order': 20,
        'speakerAr': 'أبونا',
        'image': {'source': MediaSource.url, 'url': 'https://example.com/a.jpg'},
        'updatedAt': DateTime.utc(2026, 1, 1),
        'updatedBy': 'a@b.c',
        'createdAt': DateTime.utc(2025, 1, 1),
        'deletedAt': DateTime.utc(2026, 1, 2),
      });
      final d = res.defaults;
      expect(res.droppedOwnedImage, isFalse);
      expect(d['nameAr'], 'قداس الجمعة (نسخة)');
      expect(d['nameEn'], 'Friday Mass (copy)');
      expect(d['visible'], isFalse);
      expect(d['type'], 'mass');
      expect(d['weekday'], 5);
      expect(d['start'], '08:00');
      expect(d['seasonKey'], 'great_lent');
      expect(d['speakerAr'], 'أبونا');
      expect(d.containsKey('image'), isFalse);
      expect(d.containsKey('id'), isFalse);
      expect(d.containsKey('updatedAt'), isFalse);
      expect(d.containsKey('updatedBy'), isFalse);
      expect(d.containsKey('createdAt'), isFalse);
      expect(d.containsKey('deletedAt'), isFalse);

      // Avoids double-suffixing and clamps to 300 chars.
      final already = buildDuplicateDocDefaults('liturgies', {
        'nameAr': 'قداس الجمعة (نسخة)',
        'nameEn': '',
      });
      expect(already.defaults['nameAr'], 'قداس الجمعة (نسخة)');
      expect(already.defaults['nameEn'], '');

      final long = buildDuplicateDocDefaults('liturgies', {
        'nameAr': 'أ' * 300,
        'nameEn': 'A' * 300,
      });
      expect((long.defaults['nameAr'] as String).length, 300);
      expect((long.defaults['nameAr'] as String).endsWith(' (نسخة)'), isTrue);
      expect((long.defaults['nameEn'] as String).length, 300);
      expect((long.defaults['nameEn'] as String).endsWith(' (copy)'), isTrue);
    });

    test('meetings: forces visible:false, copies url images, drops owned cover/gallery images', () {
      final res = buildDuplicateDocDefaults('meetings', {
        'stage': 'youth',
        'nameAr': 'اجتماع الشباب',
        'nameEn': 'Youth Meeting',
        'visible': true,
        'detailsEnabled': true,
        'image': {'source': MediaSource.inline, 'mediaId': 'm1'},
        'gallery': [
          {'source': MediaSource.url, 'url': 'https://example.com/g1.jpg'},
          {'source': MediaSource.storage, 'url': 'https://example.com/g2.jpg', 'mediaId': 'm2'},
        ],
        'extraFields': [
          {'titleAr': 'المشرف', 'titleEn': 'Lead', 'valueAr': 'أبونا', 'valueEn': 'Fr.'},
        ],
      });
      expect(res.droppedOwnedImage, isTrue);
      expect(res.defaults['nameAr'], 'اجتماع الشباب (نسخة)');
      expect(res.defaults['nameEn'], 'Youth Meeting (copy)');
      expect(res.defaults['visible'], isFalse);
      expect(res.defaults['image'], isNull);
      expect(res.defaults['gallery'], [
        {'source': MediaSource.url, 'url': 'https://example.com/g1.jpg'},
      ]);
      expect(res.defaults['extraFields'], hasLength(1));
    });

    test('alerts: forces visible:false and active:false, appends suffix to titleAr/titleEn', () {
      final res = buildDuplicateDocDefaults('alerts', {
        'titleAr': 'تنبيه مهم',
        'titleEn': 'Important Notice',
        'bodyAr': 'التفاصيل',
        'active': true,
        'visible': true,
        'priority': 10,
        'image': {'source': MediaSource.url, 'url': 'https://example.com/alert.jpg'},
      });
      expect(res.droppedOwnedImage, isFalse);
      expect(res.defaults['titleAr'], 'تنبيه مهم (نسخة)');
      expect(res.defaults['titleEn'], 'Important Notice (copy)');
      expect(res.defaults['visible'], isFalse);
      expect(res.defaults['active'], isFalse);
      expect(res.defaults['priority'], 10);
      expect(res.defaults['image'], {'source': MediaSource.url, 'url': 'https://example.com/alert.jpg'});
    });

    test('seasons: forces active:false, keeps key, shifts startsAt/endsAt/replaceDates by +1 year', () {
      final res = buildDuplicateDocDefaults('seasons', {
        'key': 'great_lent',
        'nameAr': 'الصوم الكبير',
        'nameEn': 'Great Lent',
        'startsAt': CairoTime.at(2024, 2, 29, 8 * 60).toUtc(),
        'endsAt': CairoTime.at(2024, 4, 20, 22 * 60).toUtc(),
        'active': true,
        'replacesRegular': false,
        'replaceDates': ['2024-02-29', '2024-04-19'],
      });
      final d = res.defaults;
      expect(d['key'], 'great_lent');
      expect(d['nameAr'], 'الصوم الكبير (نسخة)');
      expect(d['nameEn'], 'Great Lent (copy)');
      expect(d['active'], isFalse);
      expect(d.containsKey('visible'), isFalse);
      expect(d['replacesRegular'], isFalse);
      expect(d['startsAt'], CairoTime.at(2025, 2, 28, 8 * 60).toUtc());
      expect(d['endsAt'], CairoTime.at(2025, 4, 20, 22 * 60).toUtc());
      expect(d['replaceDates'], ['2025-02-28', '2025-04-19']);
    });

    test('entries: appends suffix to titleAr/titleEn, forces visible:false, keeps categoryId', () {
      final res = buildDuplicateDocDefaults('entries', {
        'categoryId': 'cat-1',
        'titleAr': 'رحلة الدير',
        'titleEn': 'Monastery Trip',
        'descAr': 'تفاصيل الرحلة',
        'visible': true,
        'order': 10,
      });
      expect(res.defaults['categoryId'], 'cat-1');
      expect(res.defaults['titleAr'], 'رحلة الدير (نسخة)');
      expect(res.defaults['titleEn'], 'Monastery Trip (copy)');
      expect(res.defaults['visible'], isFalse);
      expect(res.defaults['order'], 10);
    });
  });

  group('CollectionListScreen duplicate widget tests', () {
    testWidgets('Duplicate appears for liturgies and creates a hidden unsaved copy that saves cleanly', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final backend = _FakeDuplicateBackend({
        'liturgies': [
          AdminDoc('l1', {
            'type': 'mass',
            'nameAr': 'قداس الأحد',
            'nameEn': 'Sunday Mass',
            'weekday': 7,
            'start': '08:00',
            'end': '10:30',
            'placeAr': 'الكنيسة الكبيرة',
            'visible': true,
            'sample': false,
            'order': 10,
            'updatedAt': DateTime.utc(2026, 3, 1),
            'updatedBy': 'old@church.org',
          }),
        ],
        'seasons': const [],
      });

      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: backend, def: collectionById('liturgies')!)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('duplicate-l1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('duplicate-l1')));
      await tester.pumpAndSettle();

      expect(backend.saves, isEmpty);
      expect(find.byType(DocEditor), findsOneWidget);
      final editor = tester.widget<DocEditor>(find.byType(DocEditor));
      expect(editor.data, isNull);
      expect(editor.docId, isNull);

      final collected = tester.state<DocEditorState>(find.byType(DocEditor)).collect();
      expect(collected['nameAr'], 'قداس الأحد (نسخة)');
      expect(collected['nameEn'], 'Sunday Mass (copy)');
      expect(collected['visible'], isFalse);
      expect(collected['weekday'], 7);
      expect(collected['start'], '08:00');

      await tester.ensureVisible(find.byKey(const Key('editor-save')));
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(backend.saves, hasLength(1));
      expect(backend.saves.single.$1, 'liturgies');
      expect(backend.saves.single.$2, isNull);
      expect(backend.saves.single.$3['nameAr'], 'قداس الأحد (نسخة)');
      expect(backend.saves.single.$3['nameEn'], 'Sunday Mass (copy)');
      expect(backend.saves.single.$3['visible'], isFalse);
      expect(backend.saves.single.$3['type'], 'mass');
      expect(backend.saves.single.$3['start'], '08:00');
    });

    testWidgets('Duplicate appears for alerts, seasons, meetings, and entries (in categories)', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Seasons: shifts dates +1 year, forces active:false, keeps key.
      final seasonBackend = _FakeDuplicateBackend({
        'seasons': [
          AdminDoc('s1', {
            'key': 'kiahk',
            'nameAr': 'شهر كيهك',
            'nameEn': 'Kiahk',
            'startsAt': CairoTime.at(2026, 12, 10, 18 * 60).toUtc(),
            'endsAt': CairoTime.at(2027, 1, 7, 23 * 60).toUtc(),
            'active': true,
            'replacesRegular': false,
            'replaceDates': ['2027-01-06'],
          }),
        ],
      });
      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: seasonBackend, def: collectionById('seasons')!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duplicate-s1')));
      await tester.pumpAndSettle();
      final seasonData = tester.state<DocEditorState>(find.byType(DocEditor)).collect();
      expect(seasonData['key'], 'kiahk');
      expect(seasonData['nameAr'], 'شهر كيهك (نسخة)');
      expect(seasonData['active'], isFalse);
      expect(seasonData['startsAt'], CairoTime.at(2027, 12, 10, 18 * 60).toUtc());
      expect(seasonData['endsAt'], CairoTime.at(2028, 1, 7, 23 * 60).toUtc());
      expect(seasonData['replaceDates'], ['2028-01-06']);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // Alerts: forces visible:false & active:false.
      final alertBackend = _FakeDuplicateBackend({
        'alerts': [
          AdminDoc('a1', {'titleAr': 'إعلان', 'titleEn': 'Notice', 'active': true, 'visible': true}),
        ],
      });
      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: alertBackend, def: collectionById('alerts')!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duplicate-a1')));
      await tester.pumpAndSettle();
      final alertData = tester.state<DocEditorState>(find.byType(DocEditor)).collect();
      expect(alertData['titleAr'], 'إعلان (نسخة)');
      expect(alertData['visible'], isFalse);
      expect(alertData['active'], isFalse);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // Meetings: forces visible:false.
      final meetingBackend = _FakeDuplicateBackend({
        'meetings': [
          AdminDoc('m1', {'stage': 'youth', 'nameAr': 'اجتماع', 'visible': true}),
        ],
      });
      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: meetingBackend, def: collectionById('meetings')!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duplicate-m1')));
      await tester.pumpAndSettle();
      final meetingData = tester.state<DocEditorState>(find.byType(DocEditor)).collect();
      expect(meetingData['nameAr'], 'اجتماع (نسخة)');
      expect(meetingData['visible'], isFalse);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // Entries inside categories: duplicateEntry-e1 creates a hidden entry in 'entries'.
      final catBackend = _FakeDuplicateBackend({
        'categories': [
          AdminDoc('c1', {'nameAr': 'الرحلات', 'slug': 'trips', 'visible': true}),
        ],
        'entries': [
          AdminDoc('e1', {'categoryId': 'c1', 'titleAr': 'رحلة', 'titleEn': 'Trip', 'visible': true}),
        ],
        'pages': const [],
      });
      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: catBackend, def: collectionById('categories')!)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('duplicateEntry-e1')));
      await tester.tap(find.byKey(const ValueKey('duplicateEntry-e1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('editor-save')));
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(catBackend.saves, hasLength(1));
      expect(catBackend.saves.single.$1, 'entries');
      expect(catBackend.saves.single.$2, isNull);
      expect(catBackend.saves.single.$3['categoryId'], 'c1');
      expect(catBackend.saves.single.$3['titleAr'], 'رحلة (نسخة)');
      expect(catBackend.saves.single.$3['visible'], isFalse);

      // Non-duplicatable collections (e.g., saints) do not show Duplicate.
      final saintBackend = _FakeDuplicateBackend({
        'saints': [
          AdminDoc('sa1', {'nameAr': 'الأنبا موسى', 'visible': true}),
        ],
      });
      await tester.pumpWidget(_wrapAdmin(CollectionListScreen(repo: saintBackend, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('duplicate-sa1')), findsNothing);
    });
  });
}
