import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/document_lang.dart';
import 'core/theme.dart';
import 'domain/features.dart';
import 'router.dart';
import 'state/providers.dart';

class ChurchPortalApp extends ConsumerWidget {
  const ChurchPortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    final themeKey = ref.watch(featuresProvider.select((f) => f.theme));
    final primary = Color(ThemePresets.all[themeKey] ?? ThemePresets.all[ThemePresets.burgundy]!);
    setDocumentLanguage(locale.languageCode);
    return MaterialApp.router(
      title: locale.languageCode == 'ar'
          ? 'كنيسة القديسين مكسيموس ودوماديوس والقوي الأنبا موسى الأسود'
          : 'St. Maximus & Domadius and St. Moses the Black Church',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale, primary: primary),
      routerConfig: router,
    );
  }
}
