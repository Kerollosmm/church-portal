import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/document_lang.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'router.dart';
import 'state/providers.dart';

class ChurchPortalApp extends ConsumerWidget {
  const ChurchPortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    // The occasion theme in force (manual pick, schedule or Coptic Easter);
    // `select` keeps the 30 s clock from rebuilding the theme for nothing.
    final active = ref.watch(activeThemeProvider.select((t) => (t.key, t.palette)));
    setDocumentLanguage(locale.languageCode);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.tr('appName'),
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale, palette: active.$2, key: active.$1),
      routerConfig: router,
    );
  }
}
