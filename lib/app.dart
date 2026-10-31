import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme.dart';
import 'router.dart';
import 'state/providers.dart';

class ChurchPortalApp extends ConsumerWidget {
  const ChurchPortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: locale.languageCode == 'ar' ? 'كنيسة القديسين مكسيموس ودوماديوس — العصافرة' : 'Asafra Church Portal',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      routerConfig: router,
    );
  }
}
