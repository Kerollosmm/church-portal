import 'package:material_ui/material_ui.dart';

import '../domain/occasion_theme.dart';

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

/// Viewport height threshold below which compact landscape mode applies (ADR-061).
/// Suppresses top utility bar and install banner to preserve vertical reading space.
const double kLandscapeShortHeight = 420.0;

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

/// Deeper end of the active primary (tab gradients, pressed states): darker
/// for a dark primary, lighter for a light one (Holy Week's ashen silver), so
/// the text on it keeps its contrast. Follows every theme.
Color primaryDarkOf(BuildContext context) => context.pal.primaryDeep;

/// The active occasion theme's colours (ADR-025), carried by [ThemeData] so
/// every public widget follows the theme in force. Without one (a bare
/// MaterialApp in a test) the Golden hour palette applies.
@immutable
class OccasionColors extends ThemeExtension<OccasionColors> {
  final String key;
  final ThemePalette palette;
  const OccasionColors(this.palette, {this.key = ThemePresets.goldenHour});

  static const golden = OccasionColors(ThemePresets.goldenHourPalette);

  Color get primary => Color(palette.primary);
  Color get primaryDeep => Color(palette.primaryDeep);
  Color get onPrimary => Color(palette.onPrimary);
  Color get onPrimaryAccent => Color(palette.onPrimaryAccent);
  Color get background => Color(palette.background);
  Color get surface => Color(palette.surface);
  Color get surfaceAlt => Color(palette.surfaceAlt);
  Color get ink => Color(palette.ink);
  Color get muted => Color(palette.muted);
  Color get goldText => Color(palette.goldText);
  Color get script => Color(palette.script);
  Color get hairline => Color(palette.hairline);
  bool get dark => palette.dark;

  /// The theme's scene accents (ADR-043): every decorative surface reads
  /// these, never a fixed colour.
  SceneAccents get accents => _accentCache.putIfAbsent((key, palette), () => SceneAccents.of(key, palette));
  static final _accentCache = <(String, ThemePalette), SceneAccents>{};

  /// Decorative metal (gold; ash on Holy Week): rings, rules. Never text.
  Color get ornament => Color(accents.ornament);

  /// Hairline border of panels and cards (the ornament at 38 %).
  Color get ornamentLine => ornament.withValues(alpha: 0.38);

  /// Title bands (next-service header, seal tab, selected chips / tabs,
  /// filled buttons): gradient [bar] → [barDeep], text [onBar], accent
  /// [onBarAccent], optional [barEdge] line.
  Color get bar => Color(accents.bar);
  Color get barDeep => Color(accents.barDeep);
  Color get onBar => Color(accents.onBar);
  Color get onBarAccent => Color(accents.onBarAccent);
  Color? get barEdge => accents.barEdge == null ? null : Color(accents.barEdge!);
  LinearGradient barGradient({AlignmentGeometry begin = AlignmentDirectional.centerStart, AlignmentGeometry end = AlignmentDirectional.centerEnd}) =>
      LinearGradient(begin: begin, end: end, colors: [bar, barDeep]);

  Color get ribbon => Color(accents.ribbon);
  Color get ribbonText => Color(accents.ribbonText);
  Color get sepiaTop => Color(accents.sepiaTop);
  Color get sepiaBottom => Color(accents.sepiaBottom);
  Color get sepiaEdge => Color(accents.sepiaEdge);
  Color get glow => Color(accents.glow);
  List<Color> get halo => [Color(accents.haloInner), Color(accents.haloMid), Color(accents.haloOuter)];

  /// Shadow tint at [alpha] (0–1).
  Color shadow(double alpha) => Color(accents.shadow).withValues(alpha: alpha);
  Color get notice => Color(accents.notice);
  Color get noticeEdge => Color(accents.noticeEdge);
  Color get noticeInk => Color(accents.noticeInk);
  Color get alertGround => Color(accents.alertGround);
  Color get alert => Color(accents.alert);
  Color get success => Color(accents.success);
  Color get live => Color(accents.live);
  Color get onLive => Color(accents.onLive);
  Color get cross => Color(accents.cross);

  /// Soft shadow under floating panels, in the theme's tint.
  List<BoxShadow> get panelShadow => [
        BoxShadow(color: shadow(0.25), blurRadius: 28, offset: const Offset(0, 10), spreadRadius: -12),
        BoxShadow(color: shadow(0.08), blurRadius: 6, offset: const Offset(0, 2)),
      ];

  /// Grounds a control on a card sits on: the opaque surface and the card
  /// ([ThemePalette.cardAlpha]) over the darkest and lightest backdrop.
  List<int> get _cardGrounds => [
        palette.surface,
        blendOver(palette.surface, ThemePalette.cardAlpha, kBlack),
        blendOver(palette.surface, ThemePalette.cardAlpha, kWhite),
      ];

  /// On / off switch colours from the palette (ADR-049): ON is a filled
  /// [primary] track with the [onPrimaryAccent] thumb (gold on the maroon
  /// posters, crimson on Holy Week's ash), OFF the card's [surfaceAlt] track
  /// with a [muted] outline and thumb, so the two states never read alike
  /// on a dark theme. Each part keeps ≥ 3:1 (WCAG non-text) against the card
  /// and the thumb against its track, whatever the admin edits.
  Color get switchOnTrack => Color(ensureContrast(palette.primary, _cardGrounds, kNonTextContrast));
  Color get switchOnThumb => Color(ensureContrast(
      palette.onPrimaryAccent, [switchOnTrack.toARGB32() | 0xFF000000], kNonTextContrast));
  Color get switchOffTrack => surfaceAlt;
  Color get switchOffThumb => Color(ensureContrast(palette.muted, [..._cardGrounds, palette.surfaceAlt], kNonTextContrast));

  /// Translucent panel over imagery ([ThemePalette.panelAlpha]).
  Color get panel => surface.withValues(alpha: ThemePalette.panelAlpha);

  /// Cards ([ThemePalette.cardAlpha]).
  Color get card => surface.withValues(alpha: ThemePalette.cardAlpha);

  /// Opacity of the cloud texture on the page backdrop.
  double get textureOpacity => palette.textureAlpha;

  /// Dark scenes dim the golden art to a sombre grey (null = unchanged).
  ColorFilter? get artFilter => dark ? kSombreArtFilter : null;

  /// Season wash over the hero painting (ADR-050, issue 19): top-down from
  /// the theme's [primary] to its [background], fading out before the
  /// bottom, so a Marian-blue / ash / festive theme reaches the golden art.
  /// Null on the Golden-hour scene (and its accent-only colour presets) and
  /// on dark themes, which already dim the art ([artFilter]). Palette roles
  /// only, never a fixed colour.
  List<Color>? get heroTint {
    if (dark || key == ThemePresets.goldenHour || !ThemePresets.occasions.contains(key)) return null;
    return [primary.withValues(alpha: heroTintTop), background.withValues(alpha: heroTintMid), background.withValues(alpha: 0)];
  }

  /// Alphas of [heroTint] at the top and the middle of the stage.
  static const double heroTintTop = 0.22, heroTintMid = 0.14;

  /// Stops of [heroTint].
  List<double> get heroTintStops => const [0, 0.5, 0.92];

  /// The same for platform views (the web hero video).
  String get artCssFilter => dark ? 'grayscale(1) brightness(0.42)' : 'none';

  @override
  OccasionColors copyWith({String? key, ThemePalette? palette}) =>
      OccasionColors(palette ?? this.palette, key: key ?? this.key);

  @override
  OccasionColors lerp(ThemeExtension<OccasionColors>? other, double t) =>
      other is OccasionColors && t >= 0.5 ? other : this;

  @override
  bool operator ==(Object other) => other is OccasionColors && other.key == key && other.palette == palette;

  @override
  int get hashCode => Object.hash(key, palette);
}

/// Greyscale at 42 % brightness (Holy Week art).
const kSombreArtFilter = ColorFilter.matrix(<double>[
  0.0893, 0.3007, 0.0302, 0, 0, //
  0.0893, 0.3007, 0.0302, 0, 0,
  0.0893, 0.3007, 0.0302, 0, 0,
  0, 0, 0, 1, 0,
]);

extension OccasionColorsContext on BuildContext {
  /// The active theme's colours.
  OccasionColors get pal => Theme.of(this).extension<OccasionColors>() ?? OccasionColors.golden;
}

/// [fg] made readable (≥ 4.5:1) on the opaque [grounds]: status colours
/// (success green, alert red) on a dark theme's panels.
Color readableOn(Color fg, List<Color> grounds) =>
    Color(ensureContrast(fg.toARGB32() | 0xFF000000, [for (final g in grounds) g.toARGB32() | 0xFF000000]));

/// [child] through the active theme's art filter (dark scenes only).
Widget sceneArt(BuildContext context, Widget child) {
  final f = context.pal.artFilter;
  return f == null ? child : ColorFiltered(colorFilter: f, child: child);
}

/// Heading style in the poster display face.
TextStyle displayStyle(BuildContext context, {double? size, Color? color, double? height}) =>
    AppFonts.heading(size: size, color: color, height: height);

/// Soft warm shadow under floating panels.
const List<BoxShadow> kPanelShadow = [
  BoxShadow(color: Color(0x40603208), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -12),
  BoxShadow(color: Color(0x14603208), blurRadius: 6, offset: Offset(0, 2)),
];

/// The site theme for [palette] (the occasion theme in force, already
/// contrast-normalised); [primary] overrides its accent (tests, previews).
ThemeData buildTheme(Locale locale,
    {ThemePalette palette = ThemePresets.goldenHourPalette, Color? primary, String key = ThemePresets.goldenHour}) {
  if (primary != null) palette = palette.withColor('primary', primary.toARGB32()).normalized();
  final oc = OccasionColors(palette, key: key);
  final primaryColor = oc.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: oc.dark ? Brightness.dark : Brightness.light,
    primary: primaryColor,
    onPrimary: oc.onPrimary,
    secondary: oc.ornament,
    onSecondary: oc.dark ? oc.background : oc.ink,
    surface: oc.background,
    onSurface: oc.ink,
    onSurfaceVariant: oc.muted,
    error: oc.alert,
  ).copyWith(
    // Every scheme role from the palette (ADR-043): Material's seeded
    // tones (tertiary, containers…) can drift to violet on a blue seed.
    primaryContainer: oc.surfaceAlt,
    onPrimaryContainer: oc.ink,
    secondaryContainer: oc.surfaceAlt,
    onSecondaryContainer: oc.ink,
    tertiary: oc.goldText,
    onTertiary: oc.surface,
    tertiaryContainer: oc.surfaceAlt,
    onTertiaryContainer: oc.ink,
    errorContainer: oc.alertGround,
    onErrorContainer: oc.ink,
    inversePrimary: oc.onPrimaryAccent,
    inverseSurface: oc.ink,
    onInverseSurface: oc.background,
    surfaceTint: Colors.transparent,
    surfaceDim: oc.surfaceAlt,
    surfaceBright: oc.surface,
    surfaceContainerLowest: oc.surface,
    surfaceContainerLow: oc.surface,
    surfaceContainer: oc.surface,
    surfaceContainerHigh: oc.surfaceAlt,
    surfaceContainerHighest: oc.surfaceAlt,
    outline: oc.muted,
    outlineVariant: oc.hairline,
    shadow: oc.shadow(1),
    scrim: oc.shadow(1),
  );
  const radius = BorderRadius.all(Radius.circular(kPanelRadius));
  const small = BorderRadius.all(Radius.circular(12));
  const stadium = StadiumBorder();
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: oc.background,
    extensions: [oc],
  );
  TextStyle? head(TextStyle? s) => s?.merge(AppFonts.heading(color: oc.ink));
  final t = base.textTheme.apply(bodyColor: oc.ink, displayColor: oc.ink);
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
    appBarTheme: AppBarTheme(
      backgroundColor: oc.background.withValues(alpha: 0.92),
      foregroundColor: oc.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700, color: oc.ink),
    ),
    cardTheme: CardThemeData(
      color: oc.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: oc.shadow(0.4),
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: oc.ornament.withValues(alpha: 0.4))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // The title-band colours: the primary on light scenes, charcoal with
        // ash-white text on Holy Week (ADR-043).
        backgroundColor: oc.bar,
        foregroundColor: oc.onBar,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: buttonText,
        elevation: 2,
        shadowColor: oc.shadow(0.6),
        shape: oc.barEdge == null ? stadium : StadiumBorder(side: BorderSide(color: oc.barEdge!)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        backgroundColor: oc.surface.withValues(alpha: 0.9),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.55), width: 1.5),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: buttonText,
        shape: stadium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700),
        shape: stadium,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: oc.bar,
      backgroundColor: oc.surface.withValues(alpha: 0.92),
      labelStyle: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: oc.ink),
      checkmarkColor: oc.onBar,
      secondaryLabelStyle: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, color: oc.onBar),
      // Selected chips also get a stronger edge (Holy Week's crimson, else
      // the ornament): on dark scenes the band colour alone is close to the
      // unselected surface (Sentry review on PR #37).
      side: WidgetStateBorderSide.resolveWith((states) => states.contains(WidgetState.selected)
          ? BorderSide(color: oc.barEdge ?? oc.ornament, width: 1.6)
          : BorderSide(color: oc.hairline)),
      shape: stadium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: oc.surface,
      border: const OutlineInputBorder(borderRadius: small),
      enabledBorder: OutlineInputBorder(borderRadius: small, borderSide: BorderSide(color: oc.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: small, borderSide: BorderSide(color: primaryColor, width: 1.6)),
    ),
    dividerTheme: DividerThemeData(color: oc.hairline),
    drawerTheme: DrawerThemeData(
      backgroundColor: oc.background,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: oc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: small, side: BorderSide(color: oc.hairline)),
    ),
    listTileTheme: const ListTileThemeData(shape: stadium),
  );
}
