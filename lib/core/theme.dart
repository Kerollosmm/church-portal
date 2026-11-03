import 'package:material_ui/material_ui.dart';

/// "Iconostasis" visual identity (docs/design/direction.md): the earth pigments
/// of the parish's own icons (Sts Maximus & Domadius, St Moses the Black) on
/// parchment, gold leaf for ornament, a candle-lit umber "night" for the footer.
///
/// Older token names are kept so every widget moves to the new palette:
/// `cream` is the page ground (parchment), `parchment` is the deeper plaster
/// band, `gold` is gold leaf, `goldLight` is the halo gold used on dark grounds.
class AppColors {
  /// Icon oxblood: default primary (the `burgundy` preset).
  static const burgundy = Color(0xFF7B2216);
  static const burgundyDark = Color(0xFF561409);
  static const burgundyLight = Color(0xFF9A3524);

  /// Gold leaf. Decorative only (rules, arch frames, ornaments): 2.8:1 on
  /// parchment, so never use it for text or icons on light surfaces.
  static const gold = Color(0xFFB8862B);

  /// Gold for text and icons on light surfaces (WCAG AA: 6.6:1 on vellum,
  /// 5.9:1 on parchment).
  static const goldText = Color(0xFF7A5400);

  /// Halo gold for text on dark grounds (10.8:1 on [night]).
  static const goldLight = Color(0xFFE3C578);

  /// Page ground (parchment).
  static const cream = Color(0xFFF5EEDF);

  /// Deeper plaster band (page headers, icon tiles, chips).
  static const parchment = Color(0xFFECE2CC);

  /// Card / app-bar surface.
  static const vellum = Color(0xFFFFFCF5);

  /// Hairline borders (decorative, 1.6:1: never the only cue).
  static const hairline = Color(0xFFD9C8A4);

  /// Umber black body text (15.4:1 on parchment).
  static const ink = Color(0xFF1F1611);

  /// Umber secondary text (7.2:1 on parchment, 8.1:1 on vellum).
  static const muted = Color(0xFF5E4A3A);

  /// Candle-lit nave: footer ground.
  static const night = Color(0xFF1C140E);

  /// Cinnabar (St Moses' robe): "today / now" accents (5.0:1 on parchment).
  static const cinnabar = Color(0xFFB0402A);

  /// Lapis: rare second accent (9.5:1 on parchment).
  static const lapis = Color(0xFF1F3B6E);

  static const success = Color(0xFF2E6B45);
  static const alert = Color(0xFFB3261E);
}

/// Bundled font families (pubspec `fonts:`; SIL OFL 1.1).
class AppFonts {
  static const body = 'Plex'; // IBM Plex Sans Arabic
  static const naskh = 'Naskh'; // Noto Naskh Arabic
  static const latinDisplay = 'Marcellus';

  /// Heading face for [locale]: Naskh for Arabic, Marcellus (with Naskh for
  /// any Arabic inside English pages) for English.
  static TextStyle display(Locale locale, {double? size, Color? color, double? height}) => locale.languageCode == 'ar'
      ? TextStyle(fontFamily: naskh, fontWeight: FontWeight.w700, fontSize: size, color: color, height: height ?? 1.45)
      : TextStyle(
          fontFamily: latinDisplay,
          fontFamilyFallback: const [naskh],
          fontWeight: FontWeight.w400,
          fontSize: size,
          color: color,
          height: height ?? 1.3,
          letterSpacing: 0.2);
}

/// Darker shade of the active theme colour (admin-selected preset), used for
/// pressed states and the page-header watermark so they follow every preset.
Color primaryDarkOf(BuildContext context) => Color.lerp(Theme.of(context).colorScheme.primary, Colors.black, 0.30)!;

/// Heading style in the current language's display face.
TextStyle displayStyle(BuildContext context, {double? size, Color? color, double? height}) =>
    AppFonts.display(Localizations.localeOf(context), size: size, color: color, height: height);

/// [primary] is the admin-selected accent preset (settings/features.theme).
ThemeData buildTheme(Locale locale, {Color primary = AppColors.burgundy}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    onPrimary: Colors.white,
    secondary: AppColors.gold,
    onSecondary: AppColors.ink,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
    error: AppColors.alert,
  ).copyWith(
    surfaceContainerLowest: AppColors.vellum,
    surfaceContainerLow: AppColors.vellum,
    surfaceContainer: AppColors.vellum,
    surfaceContainerHigh: AppColors.parchment,
    outline: AppColors.muted,
    outlineVariant: AppColors.hairline,
  );
  const radius = BorderRadius.all(Radius.circular(4));
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.cream,
  );
  TextStyle? head(TextStyle? s) => s?.merge(AppFonts.display(locale, color: AppColors.ink));
  final t = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final text = t.copyWith(
    displayLarge: head(t.displayLarge),
    displayMedium: head(t.displayMedium),
    displaySmall: head(t.displaySmall),
    headlineLarge: head(t.headlineLarge),
    headlineMedium: head(t.headlineMedium),
    headlineSmall: head(t.headlineSmall),
    titleLarge: head(t.titleLarge),
    bodyLarge: t.bodyLarge?.copyWith(height: 1.7),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.65),
  );
  const buttonText = TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 15);
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.vellum,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.vellum,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.hairline)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: buttonText,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.muted),
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: buttonText,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: radius)),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: primary,
      backgroundColor: AppColors.parchment,
      labelStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: AppColors.ink),
      checkmarkColor: Colors.white,
      secondaryLabelStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: Colors.white),
      side: const BorderSide(color: AppColors.hairline),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.vellum,
      border: const OutlineInputBorder(borderRadius: radius),
      enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: primary, width: 1.6)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(),
      endShape: RoundedRectangleBorder(),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.vellum,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.hairline)),
    ),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: radius)),
  );
}
