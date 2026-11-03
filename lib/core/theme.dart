import 'package:material_ui/material_ui.dart';

/// "Golden hour" visual identity (docs/design/direction.md, ADR-022): the
/// soul of the parish's own Facebook / WhatsApp posters — luminous
/// golden-hour painting (clouds, sun rays, the church, the Nile), warm amber /
/// gold / cream / sepia haze, heavy maroon Arabic display titles with a red
/// calligraphic accent word, content on translucent warm panels with soft
/// rounded corners, pill title ribbons and maroon "tabs" holding the seal.
///
/// Token names from earlier identities are kept so every widget moves to the
/// new palette: `cream` is the page wash, `parchment` the sand band, `vellum`
/// the panel surface, `gold` is decorative gold, `goldLight` the halo gold
/// used on maroon / dark grounds.
class AppColors {
  /// Poster maroon: default primary (the `burgundy` preset), sampled from the
  /// posters' heavy titles and seal tabs (#4F0201–#7A1F1F range).
  static const burgundy = Color(0xFF6E1C1C);
  static const burgundyDark = Color(0xFF4F1010);
  static const burgundyLight = Color(0xFF8E2A24);

  /// Red of the calligraphic accent word above titles («سلسلة»): 7.0:1 on cream.
  static const script = Color(0xFF9A2A1E);

  /// Decorative gold (halo rings, rules, glows). 2.3:1 on cream: never text.
  static const gold = Color(0xFFC9963F);

  /// Gold for text and icons on light surfaces (6.1:1 on cream).
  static const goldText = Color(0xFF7A5410);

  /// Halo gold for text on maroon / dark grounds (6.7:1 on [burgundy]).
  static const goldLight = Color(0xFFE7C27A);

  /// Amber glow of the sun disc and light rays (decorative).
  static const amber = Color(0xFFE8B65C);

  /// Page wash (cream haze over the gold-cloud texture).
  static const cream = Color(0xFFFBF3E4);

  /// Sand band (chips, icon tiles, skeletons).
  static const parchment = Color(0xFFF4E6CC);

  /// Opaque panel surface (inputs, popup menus, app bar).
  static const vellum = Color(0xFFFFF9EE);

  /// Translucent warm panel over imagery. Its worst case (over the darkest
  /// sepia of the art, #4B2E17) is [panelOverDark]; every text token is
  /// checked against that in the contrast test.
  static const panel = Color(0xE0FBF3E4);
  static const panelOverDark = Color(0xFFE2D7C7);

  /// Sepia panel (the posters' story box) — 55 % sand-brown over cream.
  static const sepia = Color(0x8CC8A069);

  /// Hairline borders (decorative only).
  static const hairline = Color(0xFFE2C99A);

  /// Sepia ink body text (13.2:1 on cream).
  static const ink = Color(0xFF3A2416);

  /// Sepia secondary text (7.2:1 on cream, 5.6:1 on [panelOverDark]).
  static const muted = Color(0xFF6A4A2E);

  /// Deep sepia night: video letterbox / dark scrims / footer legal strip.
  static const night = Color(0xFF2B1A10);

  /// "Today / now" accent (kept name; = [script]).
  static const cinnabar = script;

  /// Rare cool accent (kept for long-text links / info).
  static const lapis = Color(0xFF1F3B6E);

  static const success = Color(0xFF2E6B45);
  static const alert = Color(0xFFB3261E);
}

/// Bundled font families (pubspec `fonts:`; SIL OFL 1.1).
class AppFonts {
  static const body = 'Plex'; // IBM Plex Sans Arabic
  static const display = 'Lalezar'; // heavy rounded poster display (Arabic + Latin)
  static const accent = 'Ruqaa'; // Aref Ruqaa: calligraphic accent word, verses

  /// Heavy poster heading face (same family in both languages; Lalezar has a
  /// matching Latin).
  static TextStyle heading({double? size, Color? color, double? height}) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: const [body],
        fontWeight: FontWeight.w400,
        fontSize: size,
        color: color,
        height: height ?? 1.3,
      );

  /// Calligraphic accent (Ruqaa) — a word above a title, or a verse.
  static TextStyle script({double? size, Color? color, double? height}) => TextStyle(
        fontFamily: accent,
        fontFamilyFallback: const [body],
        fontWeight: FontWeight.w700,
        fontSize: size,
        color: color ?? AppColors.script,
        height: height ?? 1.25,
      );

}

/// Panel / card radius (soft rounded, like the posters' boxes).
const double kPanelRadius = 20;

/// Spacing scale (logical px). Use these instead of ad-hoc numbers so cards,
/// grids and sections share one rhythm.
class Space {
  Space._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Gap between cards in a grid (both directions).
  static const double grid = 16;

  /// Inner padding of a content card.
  static const double card = 16;
}

/// Darker shade of the active theme colour (admin-selected preset), used for
/// tab gradients and pressed states so they follow every preset.
Color primaryDarkOf(BuildContext context) => Color.lerp(Theme.of(context).colorScheme.primary, Colors.black, 0.30)!;

/// Heading style in the poster display face.
TextStyle displayStyle(BuildContext context, {double? size, Color? color, double? height}) =>
    AppFonts.heading(size: size, color: color, height: height);

/// Soft warm shadow under floating panels.
const List<BoxShadow> kPanelShadow = [
  BoxShadow(color: Color(0x40603208), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -12),
  BoxShadow(color: Color(0x14603208), blurRadius: 6, offset: Offset(0, 2)),
];

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
  const radius = BorderRadius.all(Radius.circular(kPanelRadius));
  const small = BorderRadius.all(Radius.circular(12));
  const stadium = StadiumBorder();
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.cream,
  );
  TextStyle? head(TextStyle? s) => s?.merge(AppFonts.heading(color: AppColors.ink));
  final t = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final text = t.copyWith(
    displayLarge: head(t.displayLarge),
    displayMedium: head(t.displayMedium),
    displaySmall: head(t.displaySmall),
    headlineLarge: head(t.headlineLarge),
    headlineMedium: head(t.headlineMedium),
    headlineSmall: head(t.headlineSmall),
    titleLarge: head(t.titleLarge),
    bodyLarge: t.bodyLarge?.copyWith(height: 1.75),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.7),
  );
  const buttonText = TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 15);
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xEBFBF3E4),
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: const CardThemeData(
      color: Color(0xF2FBF3E4),
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x66603208),
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: Color(0x66C9963F))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: buttonText,
        elevation: 2,
        shadowColor: const Color(0x99401010),
        shape: stadium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        backgroundColor: const Color(0xE6FBF3E4),
        side: BorderSide(color: primary.withValues(alpha: 0.55), width: 1.5),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: buttonText,
        shape: stadium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700),
        shape: stadium,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: primary,
      backgroundColor: const Color(0xEBFBF3E4),
      labelStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: AppColors.ink),
      checkmarkColor: Colors.white,
      secondaryLabelStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: Colors.white),
      side: const BorderSide(color: AppColors.hairline),
      shape: stadium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.vellum,
      border: const OutlineInputBorder(borderRadius: small),
      enabledBorder: const OutlineInputBorder(borderRadius: small, borderSide: BorderSide(color: AppColors.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: small, borderSide: BorderSide(color: primary, width: 1.6)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.vellum,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: small, side: BorderSide(color: AppColors.hairline)),
    ),
    listTileTheme: const ListTileThemeData(shape: stadium),
  );
}
