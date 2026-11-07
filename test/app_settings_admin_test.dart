import 'package:church_portal/core/theme.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {Locale locale = const Locale('ar')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('appSettingsDoc schema & DocEditor', () {
    test('schema defines all 18 app & push notification fields', () {
      expect(appSettingsDoc.fields.length, 18);
      final keys = appSettingsDoc.fields.map((f) => f.key).toSet();
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
          'push',
          'pushVapidKey',
          'pushTypes',
          'reminderLeads',
          'reminderDefaultLead',
        ]),
      );
    });

    testWidgets('DocEditor renders appSettingsDoc with initial values and saves edits', (tester) async {
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
        'push': true,
        'pushVapidKey': 'test_vapid_key_01234567890123456789012345678901234567890123456789012345678901234567890123456789',
        'pushTypes': ['announcements', 'seasons', 'reminders'],
        'reminderLeads': [0, 15, 60, 1440],
        'reminderDefaultLead': 60,
      };

      await tester.pumpWidget(_app(DocEditor(
        title: 'التطبيق والإشعارات',
        fields: appSettingsDoc.fields,
        data: initialData,
        popOnSave: false,
        onSave: (d) async => saved = d,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-save')), findsOneWidget);

      // Verify that every field key has an editor entry
      for (final f in appSettingsDoc.fields) {
        expect(find.byKey(ValueKey('field-${f.key}')), findsOneWidget, reason: 'Field ${f.key} must be rendered');
      }

      // Modify version and trigger save
      await tester.enterText(find.byKey(const ValueKey('field-installApkVersion')), '1.2.0');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['installApkVersion'], '1.2.0');
      expect(saved!.containsKey('installApkBuild'), isFalse, reason: 'Unchanged key installApkBuild must not be rewritten');
      expect(saved!.containsKey('installApkSizeMb'), isFalse, reason: 'Unchanged key installApkSizeMb must not be rewritten');
      expect(saved!.containsKey('push'), isFalse, reason: 'Unchanged key push must not be rewritten');
      expect(saved!.containsKey('reminderLeads'), isFalse, reason: 'Unchanged key reminderLeads must not be rewritten');
    });
  });
}
