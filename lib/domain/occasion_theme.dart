// Occasion themes (ADR-025): colour palettes for the church year — the
// "Golden hour" default, a dark and sombre Holy Week, a festive
// Resurrection, the Nativity, Epiphany, the fasts and the Marian feasts —
// plus the plain accent-colour presets kept from before. Pure Dart (colours
// are ARGB ints) so the contrast maths, the auto-correction, the Coptic
// (Orthodox) Easter computus and the Cairo-date schedule are unit-tested.

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// WCAG 2.x colour maths on ARGB ints.
// ---------------------------------------------------------------------------

double _linear(int c8) {
  final c = c8 / 255.0;
  // Same constant as Flutter's Color.computeLuminance.
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance of an opaque ARGB colour.
double relativeLuminance(int argb) =>
    0.2126 * _linear((argb >> 16) & 0xFF) + 0.7152 * _linear((argb >> 8) & 0xFF) + 0.0722 * _linear(argb & 0xFF);

/// WCAG contrast ratio (1–21) between two opaque colours.
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a), lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] at [alpha] (0–1) composited over the opaque [bg] (sRGB, like
/// Flutter's `Color.alphaBlend`).
int blendOver(int fg, double alpha, int bg) {
  int ch(int s) {
    final f = (fg >> s) & 0xFF, b = (bg >> s) & 0xFF;
    return (f * alpha + b * (1 - alpha)).round().clamp(0, 255);
  }

  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// Linear mix of two opaque colours: [t] = 0 gives [a], 1 gives [b].
int mixColor(int a, int b, double t) => blendOver(b, t, a);

/// HSL hue (0–360) and saturation (0–1) of an opaque colour.
(double, double) hueSat(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  if (d == 0) return (0, 0);
  final l = (mx + mn) / 2;
  final sat = d / (1 - (2 * l - 1).abs());
  double h;
  if (mx == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (mx == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  return (h < 0 ? h + 360 : h, sat);
}

/// A violet / purple hue (ADR-043): hue 260–320° with saturation > 0.25.
/// No built-in palette or scene accent may be one (the owner rejected the
/// violet look as "AI slop"); greys and near-greys are never violet.
bool isVioletPurple(int argb) {
  final (h, sat) = hueSat(argb);
  return h >= 260 && h <= 320 && sat > 0.25;
}

const int kBlack = 0xFF000000;
const int kWhite = 0xFFFFFFFF;

/// `#RRGGBB` (upper case) for an ARGB colour.
String colorToHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

final _hexRe = RegExp(r'^#?([0-9a-fA-F]{6})$');

/// Opaque ARGB from `#RRGGBB` / `RRGGBB`, or null.
int? parseHexColor(String? s) {
  final m = _hexRe.firstMatch((s ?? '').trim());
  if (m == null) return null;
  return 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

/// Minimum contrast for body text (WCAG 1.4.3 AA).
const double kBodyContrast = 4.5;

/// WCAG 2.1 non-text contrast (1.4.11) of controls: switch tracks, thumbs.
const double kNonTextContrast = 3.0;

/// Minimum contrast for large text (≥ 24 px, or ≥ 18.66 px bold).
const double kLargeContrast = 3.0;

// ---------------------------------------------------------------------------
// Palette.
// ---------------------------------------------------------------------------

/// One theme's colours. Every public widget reads these (through
/// `OccasionColors` in `lib/core/theme.dart`), never fixed tokens, so an
/// occasion changes the whole site: scene, panels, text and accents.
class ThemePalette {
  /// Buttons, tabs, the next-mass bar, titles and links.
  final int primary;

  /// Text and icons on [primary].
  final int onPrimary;

  /// Accent (halo gold) on [primary]: the clock icon, "Full schedule".
  final int onPrimaryAccent;

  /// Page / scene wash behind everything.
  final int background;

  /// Panels, cards, app bar, inputs.
  final int surface;

  /// Chips, icon tiles, skeletons.
  final int surfaceAlt;

  /// Body text.
  final int ink;

  /// Secondary text.
  final int muted;

  /// Gold labels / references on surfaces.
  final int goldText;

  /// Calligraphic accent word above titles.
  final int script;

  const ThemePalette({
    required this.primary,
    required this.onPrimary,
    required this.onPrimaryAccent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.goldText,
    required this.script,
  });

  /// Editable colour keys (admin), in display order.
  static const keys = [
    'primary', 'onPrimary', 'onPrimaryAccent', 'background', 'surface', 'surfaceAlt', //
    'ink', 'muted', 'goldText', 'script',
  ];

  /// [ar, en] labels of [keys] for the admin.
  static const keyLabels = <String, List<String>>{
    'primary': ['اللون الأساسي (الأزرار والعناوين والتبويبات)', 'Primary (buttons, titles, tabs)'],
    'onPrimary': ['النص فوق اللون الأساسي', 'Text on primary'],
    'onPrimaryAccent': ['اللمسة الذهبية فوق اللون الأساسي (الساعة)', 'Accent on primary (clock)'],
    'background': ['خلفية الصفحة', 'Page background'],
    'surface': ['الألواح والبطاقات', 'Panels & cards'],
    'surfaceAlt': ['الشرائح والأيقونات', 'Chips & icon tiles'],
    'ink': ['النص الأساسي', 'Body text'],
    'muted': ['النص الثانوي', 'Secondary text'],
    'goldText': ['النص الذهبي', 'Gold text'],
    'script': ['كلمة الخط العربي فوق العناوين', 'Calligraphic accent word'],
  };

  int operator [](String key) => switch (key) {
        'primary' => primary,
        'onPrimary' => onPrimary,
        'onPrimaryAccent' => onPrimaryAccent,
        'background' => background,
        'surface' => surface,
        'surfaceAlt' => surfaceAlt,
        'ink' => ink,
        'muted' => muted,
        'goldText' => goldText,
        'script' => script,
        _ => throw ArgumentError.value(key, 'key'),
      };

  ThemePalette withColor(String key, int c) {
    final m = {for (final k in keys) k: this[k]}..[key] = 0xFF000000 | (c & 0xFFFFFF);
    return ThemePalette._fromMap(m);
  }

  factory ThemePalette._fromMap(Map<String, int> m) => ThemePalette(
        primary: m['primary']!,
        onPrimary: m['onPrimary']!,
        onPrimaryAccent: m['onPrimaryAccent']!,
        background: m['background']!,
        surface: m['surface']!,
        surfaceAlt: m['surfaceAlt']!,
        ink: m['ink']!,
        muted: m['muted']!,
        goldText: m['goldText']!,
        script: m['script']!,
      );

  /// [base] with the valid `#RRGGBB` entries of [overrides] applied.
  factory ThemePalette.withOverrides(ThemePalette base, Map<String, String> overrides) {
    var p = base;
    overrides.forEach((k, v) {
      final c = parseHexColor(v);
      if (c != null && keys.contains(k)) p = p.withColor(k, c);
    });
    return p;
  }

  /// `#RRGGBB` of the keys that differ from [base].
  Map<String, String> diff(ThemePalette base) => {
        for (final k in keys)
          if (this[k] != base[k]) k: colorToHex(this[k]),
      };

  /// A dark scene (Holy Week): the art is dimmed, scrims go dark.
  bool get dark => relativeLuminance(background) < 0.18;

  // Ground model: the alphas the widgets actually paint with.
  static const double panelAlpha = 0.92;
  static const double cardAlpha = 0.95;
  static const double heroScrimAlpha = 0.80; // the lightest TextScrim used (patrons band)
  static const double verseScrimAlpha = 0.88; // the hero verse's TextScrim (no panel behind it)
  static const double textureAlphaLight = 0.28;
  static const double textureAlphaDark = 0.12;

  /// Darkest and lightest pixel of the cloud texture (assets/art/clouds.webp).
  static const int textureDarkest = 0xFFA36452;
  static const int textureLightest = 0xFFFEE8A2;

  double get textureAlpha => dark ? textureAlphaDark : textureAlphaLight;

  /// The deeper end of [primary] gradients (tabs, next-mass bar): darker for
  /// a dark primary, lighter for a light one, so [onPrimary] keeps contrast.
  int get primaryDeep => mixColor(primary, relativeLuminance(primary) < 0.18 ? kBlack : kWhite, 0.30);

  /// Decorative hairline (borders): never text.
  int get hairline => mixColor(background, goldText, 0.35);

  /// Grounds of text on a translucent panel / card (over any art: black and
  /// white are the extremes) and on the opaque surfaces.
  List<int> get panelGrounds => [
        surface,
        surfaceAlt,
        blendOver(surface, panelAlpha, kBlack),
        blendOver(surface, panelAlpha, kWhite),
      ];

  /// Grounds of text straight on the page backdrop (the wash over the cloud
  /// texture at [textureAlpha]).
  List<int> get sceneGrounds => [
        background,
        blendOver(textureDarkest, textureAlpha, background),
        blendOver(textureLightest, textureAlpha, background),
      ];

  /// Grounds of hero / page-header headings: the text scrim (the background
  /// at [heroScrimAlpha]) over any picture or video frame.
  List<int> get heroGrounds => [
        blendOver(background, heroScrimAlpha, kBlack),
        blendOver(background, heroScrimAlpha, kWhite),
      ];

  /// Grounds of the hero verse (body-size Ruqaa verse and its reference set
  /// straight on the hero, no panel): its text scrim (the background at
  /// [verseScrimAlpha]) over any picture or video frame.
  List<int> get verseGrounds => [
        blendOver(background, verseScrimAlpha, kBlack),
        blendOver(background, verseScrimAlpha, kWhite),
      ];

  /// Grounds of text on the primary bars.
  List<int> get barGrounds => [primary, primaryDeep];

  /// Every text-colour requirement of the palette: role, colour, ground and
  /// minimum ratio. Tests assert all of them for every preset; [normalized]
  /// corrects a palette until all hold.
  List<ContrastCheck> get checks {
    final out = <ContrastCheck>[];
    void add(String role, List<int> grounds, double min, String where) {
      for (var i = 0; i < grounds.length; i++) {
        out.add(ContrastCheck(role, this[role], grounds[i], min, '$where#$i'));
      }
    }

    for (final r in ['ink', 'muted', 'goldText', 'primary', 'script']) {
      add(r, panelGrounds, kBodyContrast, 'panel');
      add(r, sceneGrounds, kBodyContrast, 'scene');
    }
    // Headings are large, but a text button ("About the church") also sits on the scrim.
    add('primary', heroGrounds, kBodyContrast, 'hero');
    add('script', heroGrounds, kLargeContrast, 'hero');
    // The hero verse: verse in ink, reference in gold, on the verse scrim.
    add('ink', verseGrounds, kBodyContrast, 'verse');
    add('goldText', verseGrounds, kBodyContrast, 'verse');
    add('onPrimary', barGrounds, kBodyContrast, 'bar');
    add('onPrimaryAccent', barGrounds, kBodyContrast, 'bar');
    return out;
  }

  List<ContrastCheck> get failures => [for (final c in checks) if (!c.passes) c];

  bool get readable => failures.isEmpty;

  /// The palette with every text colour (and, when needed, a surface)
  /// nudged just far enough to pass [checks]. A palette that already passes
  /// is returned unchanged. Used for admin edits and again at render time,
  /// so even a hand-edited document can never make text unreadable.
  ThemePalette normalized() {
    if (readable) return this;
    final darkScene = dark;
    // 1. Surfaces on the background's side, and out of the mid-grey band
    //    where neither dark nor light text reaches 4.5:1 on every ground.
    int side(int c) {
      if ((relativeLuminance(c) < 0.18) != darkScene) c = mixColor(background, darkScene ? kWhite : kBlack, 0.06);
      return _pushOut(c, darkScene);
    }

    var p = ThemePalette._fromMap({for (final k in keys) k: this[k]});
    p = p.withColor('background', _pushOut(background, darkScene));
    p = p.withColor('surface', side(surface)).withColor('surfaceAlt', side(surfaceAlt));
    // 2. Primary, then the colours on it (the deep end follows primary).
    p = p.withColor('primary', _fix(p.primary, [
      for (final g in [...p.panelGrounds, ...p.sceneGrounds, ...p.heroGrounds]) (g, kBodyContrast),
    ]));
    for (final k in ['onPrimary', 'onPrimaryAccent']) {
      p = p.withColor(k, _fix(p[k], [for (final g in p.barGrounds) (g, kBodyContrast)]));
    }
    // 3. Text on panels and on the scene.
    for (final k in ['ink', 'muted', 'goldText', 'script']) {
      p = p.withColor(k, _fix(p[k], [
        for (final g in [...p.panelGrounds, ...p.sceneGrounds]) (g, kBodyContrast),
        if (k == 'script') for (final g in p.heroGrounds) (g, kLargeContrast),
        if (k == 'ink' || k == 'goldText') for (final g in p.verseGrounds) (g, kBodyContrast),
      ]));
    }
    return p;
  }

  static int _pushOut(int c, bool dark) {
    for (var t = 0.0; t <= 1.0001; t += 0.02) {
      final x = mixColor(c, dark ? kBlack : kWhite, t);
      final l = relativeLuminance(x);
      if (dark ? l <= 0.05 : l >= 0.5) return x;
    }
    return dark ? kBlack : kWhite;
  }

  /// [fg] moved toward black or white (whichever needs the smaller step)
  /// until it meets every (ground, minimum) pair.
  static int _fix(int fg, List<(int, double)> reqs) {
    bool ok(int c) => reqs.every((r) => contrastRatio(c, r.$1) >= r.$2);
    if (ok(fg)) return fg;
    int? best;
    var bestT = 2.0;
    for (final target in const [kBlack, kWhite]) {
      for (var t = 0.02; t <= 1.0001; t += 0.02) {
        final c = mixColor(fg, target, t);
        if (ok(c)) {
          if (t < bestT) {
            bestT = t;
            best = c;
          }
          break;
        }
      }
    }
    if (best != null) return best;
    double worst(int c) => reqs.map((r) => contrastRatio(c, r.$1) / r.$2).reduce(math.min);
    return worst(kBlack) >= worst(kWhite) ? kBlack : kWhite;
  }

  @override
  bool operator ==(Object other) => other is ThemePalette && keys.every((k) => this[k] == other[k]);

  @override
  int get hashCode => Object.hashAll([for (final k in keys) this[k]]);
}

/// [fg] nudged toward black or white just enough to reach [min] on every
/// one of [grounds] (unchanged when it already does).
int ensureContrast(int fg, List<int> grounds, [double min = kBodyContrast]) =>
    ThemePalette._fix(fg, [for (final g in grounds) (g, min)]);

/// One contrast requirement of a palette.
class ContrastCheck {
  final String role;
  final int fg, bg;
  final double min;
  final String ground;
  const ContrastCheck(this.role, this.fg, this.bg, this.min, this.ground);
  double get ratio => contrastRatio(fg, bg);
  bool get passes => ratio >= min;
  @override
  String toString() =>
      '$role ${colorToHex(fg)} on $ground ${colorToHex(bg)}: ${ratio.toStringAsFixed(2)} (min $min)';
}

// ---------------------------------------------------------------------------
// Scene accents (ADR-043): the sub-theme every decorative surface reads.
// ---------------------------------------------------------------------------

/// The colours a theme gives the site's decorative surfaces beyond the ten
/// editable [ThemePalette] roles: title bands (next-service header, seal tab,
/// selected chips and tabs), ribbons, story panels, halos, notices, the live
/// banner, status colours, shadows. Widgets never hard-code a colour (a test
/// greps `lib/ui`); they read these through `context.pal`.
///
/// Golden hour and Holy Week are hand-tuned; every other palette (and any
/// palette with admin colour edits) derives its accents from its roles, so an
/// edit flows through to every surface. Text-bearing pairs are listed in
/// [checks] and asserted for every preset.
class SceneAccents {
  /// Decorative metal: halo rings, rules, borders (gold on light scenes, ash
  /// on Holy Week). Never text.
  final int ornament;

  /// Title bands: the next-service header, the seal tab, selected chips and
  /// tabs, filled buttons. [bar] → [barDeep] gradient.
  final int bar, barDeep;

  /// Text / icons on the bands, and their accent (the clock, «الجدول الكامل»).
  final int onBar, onBarAccent;

  /// A thin line under / around the bands (Holy Week's deep crimson); null =
  /// none.
  final int? barEdge;

  /// The posters' sub-title ribbon and its text.
  final int ribbon, ribbonText;

  /// The story box (sepia panel) gradient and its edge.
  final int sepiaTop, sepiaBottom, sepiaEdge;

  /// Glow behind poster headings.
  final int glow;

  /// Portrait halo (inner, middle, outer).
  final int haloInner, haloMid, haloOuter;

  /// Tint of panel shadows (RGB; the widgets set the alpha).
  final int shadow;

  /// "Sample data" / "pending" notice box: ground, edge, text.
  final int notice, noticeEdge, noticeInk;

  /// Alert notice ground, alert text, success text.
  final int alertGround, alert, success;

  /// Live-stream banner ground and its text.
  final int live, onLive;

  /// The drawn Coptic cross when no colour is given.
  final int cross;

  const SceneAccents({
    required this.ornament,
    required this.bar,
    required this.barDeep,
    required this.onBar,
    required this.onBarAccent,
    this.barEdge,
    required this.ribbon,
    required this.ribbonText,
    required this.sepiaTop,
    required this.sepiaBottom,
    required this.sepiaEdge,
    required this.glow,
    required this.haloInner,
    required this.haloMid,
    required this.haloOuter,
    required this.shadow,
    required this.notice,
    required this.noticeEdge,
    required this.noticeInk,
    required this.alertGround,
    required this.alert,
    required this.success,
    required this.live,
    required this.onLive,
    required this.cross,
  });

  /// Deep crimson of Holy Week (decorative: band edges, the live banner).
  static const crimson = 0xFF8E1B1B;

  /// Status hues before they are made readable on a palette.
  static const _alertBase = 0xFFB3261E;
  static const _successBase = 0xFF2E6B45;

  /// Golden hour, exactly as before ADR-043 (the owner-approved look).
  static SceneAccents _golden(ThemePalette p) => SceneAccents(
        ornament: 0xFFC9963F,
        bar: p.primary,
        barDeep: p.primaryDeep,
        onBar: p.onPrimary,
        onBarAccent: p.onPrimaryAccent,
        ribbon: 0xFF7A4530,
        ribbonText: 0xFFFFF3DC,
        sepiaTop: 0xFFE6CFA9,
        sepiaBottom: 0xFFDDC197,
        sepiaEdge: 0xFFA06E3C,
        glow: 0xFFFFF0D2,
        haloInner: 0xFFFFEAB0,
        haloMid: 0xFFE8B65C,
        haloOuter: 0xFFC08A35,
        shadow: 0xFF603208,
        notice: 0xFFFFF3CD,
        noticeEdge: 0xFFE0C36A,
        noticeInk: p.ink,
        alertGround: 0xFFFFF4E0,
        alert: _alertBase,
        success: _successBase,
        live: _alertBase,
        onLive: kWhite,
        cross: 0xFFB8862B,
      );

  /// Accents derived from any palette's roles (light or dark scene).
  factory SceneAccents.derive(ThemePalette p) {
    final dark = p.dark;
    final panel = p.panelGrounds;
    if (dark) {
      // Black cloth: charcoal bands with ink text and a silver accent, a
      // crimson edge, ash ornaments, greyed halos. No gold, no violet.
      final ornament = mixColor(p.muted, p.background, 0.3);
      final alertGround = mixColor(p.surface, crimson, 0.18);
      return SceneAccents(
        ornament: ornament,
        bar: p.surfaceAlt,
        barDeep: mixColor(p.surfaceAlt, kBlack, 0.45),
        onBar: ensureContrast(p.ink, [p.surfaceAlt, mixColor(p.surfaceAlt, kBlack, 0.45)]),
        onBarAccent: ensureContrast(p.primary, [p.surfaceAlt, mixColor(p.surfaceAlt, kBlack, 0.45)]),
        barEdge: crimson,
        ribbon: p.surfaceAlt,
        ribbonText: ensureContrast(p.ink, [p.surfaceAlt]),
        sepiaTop: p.surfaceAlt,
        sepiaBottom: p.surface,
        sepiaEdge: ornament,
        glow: p.background,
        haloInner: mixColor(p.ink, p.background, 0.25),
        haloMid: mixColor(p.muted, p.background, 0.35),
        haloOuter: mixColor(p.muted, p.background, 0.6),
        shadow: kBlack,
        notice: mixColor(p.surfaceAlt, p.goldText, 0.08),
        noticeEdge: mixColor(p.goldText, p.background, 0.5),
        noticeInk: ensureContrast(p.ink, [mixColor(p.surfaceAlt, p.goldText, 0.08)]),
        alertGround: alertGround,
        alert: ensureContrast(_alertBase, [...panel, alertGround]),
        success: ensureContrast(_successBase, panel),
        live: crimson,
        onLive: ensureContrast(p.ink, [crimson]),
        cross: ornament,
      );
    }
    final ornament = mixColor(p.onPrimaryAccent, p.goldText, 0.3);
    final ribbon = mixColor(p.muted, p.primary, 0.35);
    final notice = mixColor(p.surface, p.onPrimaryAccent, 0.25);
    final alertGround = mixColor(p.surface, _alertBase, 0.06);
    return SceneAccents(
      ornament: ornament,
      bar: p.primary,
      barDeep: p.primaryDeep,
      onBar: p.onPrimary,
      onBarAccent: p.onPrimaryAccent,
      ribbon: ribbon,
      ribbonText: ensureContrast(p.surface, [ribbon]),
      sepiaTop: _tint(p.surfaceAlt, ornament, 0.22, p.ink),
      sepiaBottom: _tint(p.surfaceAlt, ornament, 0.34, p.ink),
      sepiaEdge: mixColor(ornament, p.muted, 0.4),
      glow: mixColor(p.background, p.onPrimaryAccent, 0.2),
      haloInner: mixColor(p.onPrimaryAccent, kWhite, 0.45),
      haloMid: p.onPrimaryAccent,
      haloOuter: mixColor(p.onPrimaryAccent, p.goldText, 0.45),
      shadow: mixColor(p.ink, p.primary, 0.3),
      notice: notice,
      noticeEdge: mixColor(p.onPrimaryAccent, p.goldText, 0.2),
      noticeInk: ensureContrast(p.ink, [notice]),
      alertGround: alertGround,
      alert: ensureContrast(_alertBase, [...panel, alertGround]),
      success: ensureContrast(_successBase, panel),
      live: _alertBase,
      onLive: kWhite,
      cross: mixColor(ornament, p.goldText, 0.25),
    );
  }

  /// [base] tinted toward [tint] by up to [t], less when [text] would drop
  /// under 4.5:1 on it (an admin-edited ornament can be any colour).
  static int _tint(int base, int tint, double t, int text) {
    for (var x = t; x > 0; x -= 0.02) {
      final c = mixColor(base, tint, x);
      if (contrastRatio(text, c) >= kBodyContrast) return c;
    }
    return base;
  }

  /// The accents of preset [key] showing [palette]: the tuned Golden hour
  /// set when the palette is the untouched default, else derived.
  factory SceneAccents.of(String key, ThemePalette palette) {
    if (key == ThemePresets.goldenHour && palette == ThemePresets.goldenHourPalette) return _golden(palette);
    return SceneAccents.derive(palette);
  }

  /// Every colour (for the no-violet test).
  List<int> get all => [
        ornament, bar, barDeep, onBar, onBarAccent, ?barEdge, ribbon, ribbonText, //
        sepiaTop, sepiaBottom, sepiaEdge, glow, haloInner, haloMid, haloOuter, shadow, notice, noticeEdge,
        noticeInk, alertGround, alert, success, live, onLive, cross,
      ];

  /// Text-bearing pairs (≥ 4.5:1) on [p].
  List<ContrastCheck> checks(ThemePalette p) => [
        for (final g in [bar, barDeep]) ...[
          ContrastCheck('onBar', onBar, g, kBodyContrast, 'bar'),
          ContrastCheck('onBarAccent', onBarAccent, g, kBodyContrast, 'bar'),
        ],
        ContrastCheck('ribbonText', ribbonText, ribbon, kBodyContrast, 'ribbon'),
        for (final g in [sepiaTop, sepiaBottom]) ContrastCheck('ink', p.ink, g, kBodyContrast, 'sepia'),
        ContrastCheck('noticeInk', noticeInk, notice, kBodyContrast, 'notice'),
        for (final g in [...p.panelGrounds, alertGround]) ContrastCheck('alert', alert, g, kBodyContrast, 'alert'),
        ContrastCheck('ink', p.ink, alertGround, kBodyContrast, 'alert'),
        for (final g in p.panelGrounds) ContrastCheck('success', success, g, kBodyContrast, 'panel'),
        ContrastCheck('onLive', onLive, live, kBodyContrast, 'live'),
      ];
}

// ---------------------------------------------------------------------------
// Presets.
// ---------------------------------------------------------------------------

/// Built-in theme presets (`settings/features.theme`). The first one is the
/// default. Occasion presets change the whole scene; the colour presets
/// (navy … purple, kept from before) only change the accent on the Golden
/// hour scene.
class ThemePresets {
  ThemePresets._();

  static const goldenHour = 'goldenHour';
  static const holyWeek = 'holyWeek';
  static const resurrection = 'resurrection';
  static const nativity = 'nativity';
  static const epiphany = 'epiphany';
  static const fasting = 'fasting';
  static const marian = 'marian';

  /// The default before ADR-025 (oxblood, then maroon): stored documents and
  /// the seed may still say `burgundy`; it reads as [goldenHour].
  static const legacyBurgundy = 'burgundy';

  /// The old violet accent preset (ADR-043): still a valid stored key, read
  /// as a sober oxblood accent, hidden from the admin picker.
  static const legacyPurple = 'purple';

  /// Kept for older call sites: the default preset key.
  static const burgundy = goldenHour;

  /// The default palette (Golden hour).
  static const goldenHourPalette = _golden;

  static const _golden = ThemePalette(
    primary: 0xFF6E1C1C, // poster maroon
    onPrimary: 0xFFFFFFFF,
    onPrimaryAccent: 0xFFE7C27A, // halo gold
    background: 0xFFFBF3E4, // cream haze
    surface: 0xFFFFF9EE, // vellum
    surfaceAlt: 0xFFF4E6CC, // parchment
    ink: 0xFF3A2416,
    muted: 0xFF6A4A2E,
    goldText: 0xFF6F4C0E, // a shade deeper than the old #7A5410: 4.5:1 on the darkest texture
    script: 0xFF9A2A1E,
  );

  static ThemePalette _accent(int primary) => ThemePalette(
        primary: primary,
        onPrimary: _golden.onPrimary,
        onPrimaryAccent: _golden.onPrimaryAccent,
        background: _golden.background,
        surface: _golden.surface,
        surfaceAlt: _golden.surfaceAlt,
        ink: _golden.ink,
        muted: _golden.muted,
        goldText: _golden.goldText,
        script: _golden.script,
      );

  static final palettes = <String, ThemePalette>{
    goldenHour: _golden,
    // Black cloth of Pascha week (ADR-043): charcoal and black, ashen-silver
    // titles and accents, deep crimson for the accent word and the bars'
    // edge, the golden art dimmed to grey. No gold, no violet.
    holyWeek: const ThemePalette(
      primary: 0xFFC8C2BA, // ashen silver
      onPrimary: 0xFF141211,
      onPrimaryAccent: 0xFF7A1016, // deep crimson on silver
      background: 0xFF0C0B0A, // black cloth
      surface: 0xFF1A1817, // charcoal
      surfaceAlt: 0xFF26231F,
      ink: 0xFFECE7E0, // ash white
      muted: 0xFFB8B1A8, // ash
      goldText: 0xFFC9BCA6, // the gold dimmed to ashen parchment
      script: 0xFFE07468, // crimson, lifted just enough to read on black
    ),
    // Festive Easter red and bright gold on a luminous ivory.
    resurrection: const ThemePalette(
      primary: 0xFFA3121A,
      onPrimary: 0xFFFFFFFF,
      onPrimaryAccent: 0xFFFFD877,
      background: 0xFFFFFAEC,
      surface: 0xFFFFFDF7,
      surfaceAlt: 0xFFFBEDCB,
      ink: 0xFF2E1A0E,
      muted: 0xFF5E4326,
      goldText: 0xFF755000,
      script: 0xFFB0151E,
    ),
    // Night blue and star gold on snow white.
    nativity: const ThemePalette(
      primary: 0xFF1C3566,
      onPrimary: 0xFFFFFFFF,
      onPrimaryAccent: 0xFFF2D27A,
      background: 0xFFF7F5EE,
      surface: 0xFFFFFEF9,
      surfaceAlt: 0xFFEDE7D6,
      ink: 0xFF1E2433,
      muted: 0xFF4A5064,
      goldText: 0xFF6E5012,
      script: 0xFF8C1C13,
    ),
    // Jordan water: deep teal on a pale aqua white.
    epiphany: const ThemePalette(
      primary: 0xFF0F5566,
      onPrimary: 0xFFFFFFFF,
      onPrimaryAccent: 0xFFF0D58C,
      background: 0xFFF1F6F5,
      surface: 0xFFFBFEFD,
      surfaceAlt: 0xFFDFECEA,
      ink: 0xFF15302F,
      muted: 0xFF3E5958,
      goldText: 0xFF6B5310,
      script: 0xFF7A2E1E,
    ),
    // Fasts (Great Lent, the Nativity fast…; ADR-043): sober ash and stone
    // with a deep oxblood / dark umber accent. Penitential without violet.
    fasting: const ThemePalette(
      primary: 0xFF4F2420, // deep oxblood umber
      onPrimary: 0xFFFFFFFF,
      onPrimaryAccent: 0xFFDCC797, // muted candle gold
      background: 0xFFF0EEEA, // ash
      surface: 0xFFFAF9F6,
      surfaceAlt: 0xFFE4E0D8, // stone
      ink: 0xFF25211D,
      muted: 0xFF534C44,
      goldText: 0xFF66501F,
      script: 0xFF7A2621, // oxblood
    ),
    // Feasts of the Theotokos: Marian blue on sky white.
    marian: const ThemePalette(
      primary: 0xFF1F4E8C,
      onPrimary: 0xFFFFFFFF,
      onPrimaryAccent: 0xFFF3D58A,
      background: 0xFFF2F6FB,
      surface: 0xFFFCFDFF,
      surfaceAlt: 0xFFE2EAF4,
      ink: 0xFF1C2738,
      muted: 0xFF46536A,
      goldText: 0xFF6F5212,
      script: 0xFF8A2232,
    ),
    'navy': _accent(0xFF1F3A5F),
    'green': _accent(0xFF1E5631),
    'brown': _accent(0xFF5D3A1A),
    // Legacy key (ADR-043): stored documents may still say `purple`; it now
    // reads as the sober oxblood accent of the fasts, never violet, and is
    // no longer offered in the admin picker ([pickable]).
    legacyPurple: _accent(0xFF4F2420),
  };

  /// Preset keys in admin order (every key a stored document may hold).
  static List<String> get keys => palettes.keys.toList();

  /// Keys offered in the admin's theme picker: [keys] without the legacy
  /// `purple` (still selectable when a document already holds it).
  static List<String> get pickable => [for (final k in keys) if (k != legacyPurple) k];

  /// Occasion presets (they change the whole scene).
  static const occasions = [goldenHour, holyWeek, resurrection, nativity, epiphany, fasting, marian];

  /// Primary ARGB of each preset (swatches; kept for older call sites).
  static Map<String, int> get all => {for (final e in palettes.entries) e.key: e.value.primary};

  static const labels = <String, List<String>>{
    goldenHour: ['الساعة الذهبية (الافتراضي)', 'Golden hour (default)'],
    holyWeek: ['أسبوع الآلام (داكن)', 'Holy Week (dark)'],
    resurrection: ['عيد القيامة (احتفالي)', 'Resurrection (festive)'],
    nativity: ['عيد الميلاد', 'Nativity'],
    epiphany: ['عيد الغطاس', 'Epiphany'],
    fasting: ['الأصوام', 'Fasts'],
    marian: ['أعياد السيدة العذراء', 'Marian feasts'],
    'navy': ['كحلي', 'Navy'],
    'green': ['أخضر', 'Green'],
    'brown': ['بني', 'Brown'],
    legacyPurple: ['عنابي داكن (كان «بنفسجي»)', 'Dark oxblood (was “Purple”)'],
  };

  /// A stored key as a known preset: `burgundy` (and anything unknown) is the
  /// default.
  static String normalize(String key) => palettes.containsKey(key) ? key : goldenHour;
}

// ---------------------------------------------------------------------------
// Coptic (Orthodox) Easter and the Cairo-date schedule.
// ---------------------------------------------------------------------------

/// Coptic / Eastern Orthodox Easter Sunday (Gregorian date) for [year]:
/// Meeus' Julian computus, shifted by the Julian–Gregorian gap of that year
/// (13 days in 1900–2099).
DateTime orthodoxEaster(int year) {
  final a = year % 4, b = year % 7, c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = (d + e + 114) % 31 + 1;
  final gap = year ~/ 100 - year ~/ 400 - 2;
  return DateTime.utc(year, month, day + gap);
}

/// A date-only value (UTC midnight) for y/m/d arithmetic without DST.
DateTime dateOnly(int y, int m, int d) => DateTime.utc(y, m, d);

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `YYYY-MM-DD` as a date-only value, or null when malformed / impossible.
DateTime? parseDate(String? s) {
  final m = _dateRe.firstMatch((s ?? '').trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}

/// One scheduled range: [theme] from [start] to [end] (inclusive Cairo dates).
class ThemeRange {
  final String theme;
  final String start, end;
  const ThemeRange({required this.theme, required this.start, required this.end});

  DateTime? get startDate => parseDate(start);
  DateTime? get endDate => parseDate(end);

  bool get valid =>
      ThemePresets.palettes.containsKey(theme) &&
      startDate != null &&
      endDate != null &&
      !endDate!.isBefore(startDate!);

  bool covers(DateTime day) => valid && !day.isBefore(startDate!) && !day.isAfter(endDate!);

  /// Stored as one string, `theme|YYYY-MM-DD|YYYY-MM-DD` (one regex in the
  /// rules keeps twelve slots within Firestore's expression budget).
  static ThemeRange? parse(Object? v) {
    if (v is! String) return null;
    final parts = v.split('|');
    if (parts.length != 3) return null;
    final r = ThemeRange(theme: parts[0], start: parts[1], end: parts[2]);
    return r.valid ? r : null;
  }

  String encode() => '$theme|$start|$end';

  @override
  bool operator ==(Object other) => other is ThemeRange && other.theme == theme && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(theme, start, end);
}

/// Which occasion theme each church-season key brings (ADR-043). The
/// default map; an admin can change or switch off any entry
/// (`settings/features.occasions.seasonThemes`, value [none]).
class SeasonThemes {
  SeasonThemes._();

  /// No theme for this season key (the next rule decides).
  static const none = 'none';

  /// Every season key (mirrors `firestore.rules` and the admin's season
  /// form), in priority order: when two seasons are active at once, the
  /// first mapped one wins (Holy Week over a fast, a feast over a revival).
  static const seasonKeys = [
    'holy_week', 'pascha', 'nativity', 'epiphany', 'marian', 'fast', //
    'revival_maximus', 'revival_moses', 'summer',
  ];

  static const defaults = <String, String>{
    'holy_week': ThemePresets.holyWeek,
    'pascha': ThemePresets.resurrection,
    'nativity': ThemePresets.nativity,
    'epiphany': ThemePresets.epiphany,
    'marian': ThemePresets.marian,
    'fast': ThemePresets.fasting,
    'revival_maximus': none,
    'revival_moses': none,
    'summer': none,
  };
}

/// Occasion-theme settings (`settings/features.occasions`). Missing = manual
/// (the selected `theme` applies), no schedule, no colour edits, and the
/// theme follows the active church season (ADR-043).
///
/// Precedence ([resolve]), first match wins:
/// 1. with [auto]: an admin date range covering the day;
/// 2. with [followSeason]: the active season's theme ([seasonThemes]);
/// 3. with [auto] and [easter]: Holy Week / the Resurrection by the computed
///    Coptic Easter;
/// 4. the selected theme (`settings/features.theme`).
class OccasionConfig {
  /// Switch themes on their own by date. Off = the selected theme always
  /// applies (the manual override).
  final bool auto;

  /// With [auto]: Holy Week and the Resurrection follow the computed Coptic
  /// Easter every year.
  final bool easter;

  /// Days the Resurrection theme lasts from Easter Sunday (1–50; 50 = the
  /// whole Holy Fifty Days).
  final int resurrectionDays;

  /// Admin date ranges (first match wins; they win over the Easter dates).
  final List<ThemeRange> schedule;

  /// Admin colour edits per preset: key → `#RRGGBB` (stored apart, as
  /// `settings/features.themeColors`).
  final Map<String, Map<String, String>> custom;

  /// The theme follows the active church season (`seasons/{id}` with an
  /// active window now). Default on; off = the season never changes the
  /// theme (ADR-043).
  final bool followSeason;

  /// Admin changes to [SeasonThemes.defaults]: season key → preset key or
  /// [SeasonThemes.none]. Only the keys that differ are stored.
  final Map<String, String> seasonThemes;

  const OccasionConfig({
    this.auto = false,
    this.easter = true,
    this.resurrectionDays = 7,
    this.schedule = const [],
    this.custom = const {},
    this.followSeason = true,
    this.seasonThemes = const {},
  });

  /// The theme season [seasonKey] brings, or null (none / unknown key).
  String? themeForSeason(String seasonKey) {
    final t = seasonThemes[seasonKey] ?? SeasonThemes.defaults[seasonKey];
    return t == null || t == SeasonThemes.none || !ThemePresets.palettes.containsKey(t) ? null : t;
  }

  static const defaults = OccasionConfig();
  static const maxRanges = 12;
  static const maxResurrectionDays = 50;

  bool get isDefault => this == defaults;

  /// [v] = `settings/features.occasions`, [colors] = `settings/features.themeColors`.
  factory OccasionConfig.fromMap(Object? v, [Object? colors]) {
    if (v is! Map) v = const {};
    final rawSchedule = v['schedule'];
    final ranges = <ThemeRange>[];
    if (rawSchedule is Map) {
      // Slots r1…r12 (rules can validate a fixed set of keys, not a list).
      for (var i = 1; i <= maxRanges; i++) {
        final r = ThemeRange.parse(rawSchedule['r$i']);
        if (r != null) ranges.add(r);
      }
    }
    final rawCustom = colors;
    final custom = <String, Map<String, String>>{};
    if (rawCustom is Map) {
      // One string per preset: the [ThemePalette.keys] colours in order,
      // `|`-separated, empty = the preset's own (one regex in the rules).
      for (final k in ThemePresets.keys) {
        final m = rawCustom[k];
        if (m is! String) continue;
        final parts = m.split('|');
        if (parts.length != ThemePalette.keys.length) continue;
        final entry = <String, String>{
          for (var i = 0; i < parts.length; i++)
            if (parseHexColor(parts[i]) case final c?) ThemePalette.keys[i]: colorToHex(c),
        };
        if (entry.isNotEmpty) custom[k] = entry;
      }
    }
    final days = v['resurrectionDays'];
    final rawSeasons = v['seasonThemes'];
    return OccasionConfig(
      auto: v['auto'] is bool ? v['auto'] as bool : false,
      easter: v['easter'] is bool ? v['easter'] as bool : true,
      resurrectionDays: days is int ? days.clamp(1, maxResurrectionDays) : 7,
      schedule: ranges,
      custom: custom,
      followSeason: v['followSeason'] is bool ? v['followSeason'] as bool : true,
      seasonThemes: rawSeasons is Map
          ? {
              for (final e in rawSeasons.entries)
                if (SeasonThemes.seasonKeys.contains(e.key) &&
                    (e.value == SeasonThemes.none || ThemePresets.palettes.containsKey(e.value)) &&
                    e.value != SeasonThemes.defaults[e.key])
                  e.key as String: e.value as String,
            }
          : const {},
    );
  }

  Map<String, dynamic> toMap() => {
        'auto': auto,
        'easter': easter,
        'resurrectionDays': resurrectionDays,
        'schedule': {for (var i = 0; i < schedule.length && i < maxRanges; i++) 'r${i + 1}': schedule[i].encode()},
        'followSeason': followSeason,
        'seasonThemes': {
          for (final e in seasonThemes.entries)
            if (e.value != SeasonThemes.defaults[e.key]) e.key: e.value,
        },
      };

  /// `settings/features.themeColors` (its own field: its own write and
  /// rules budget).
  Map<String, dynamic> colorsToMap() => {
        for (final e in custom.entries)
          if (e.value.isNotEmpty) e.key: [for (final k in ThemePalette.keys) e.value[k] ?? ''].join('|'),
      };

  OccasionConfig copyWith({
    bool? auto,
    bool? easter,
    int? resurrectionDays,
    List<ThemeRange>? schedule,
    Map<String, Map<String, String>>? custom,
    bool? followSeason,
    Map<String, String>? seasonThemes,
  }) =>
      OccasionConfig(
        auto: auto ?? this.auto,
        easter: easter ?? this.easter,
        resurrectionDays: resurrectionDays ?? this.resurrectionDays,
        schedule: schedule ?? this.schedule,
        custom: custom ?? this.custom,
        followSeason: followSeason ?? this.followSeason,
        seasonThemes: seasonThemes ?? this.seasonThemes,
      );

  /// The config with each preset's colour edits replaced by the corrected
  /// (readable) colours that differ from the preset — what is saved.
  OccasionConfig withReadableCustom() => copyWith(custom: {
        for (final k in custom.keys)
          if (paletteFor(k).diff(ThemePresets.palettes[k]!) case final d when d.isNotEmpty) k: d,
      });

  /// The preset's palette with the admin's colour edits, auto-corrected for
  /// contrast.
  ThemePalette paletteFor(String key) {
    final k = ThemePresets.normalize(key);
    final base = ThemePresets.palettes[k]!;
    final edits = custom[k];
    return (edits == null || edits.isEmpty ? base : ThemePalette.withOverrides(base, edits)).normalized();
  }

  /// Holy Week (Palm Sunday → Holy Saturday) and the Resurrection (Easter
  /// Sunday + [resurrectionDays] − 1) of the Coptic Easter of [year].
  List<ThemeRange> easterRanges(int year) {
    final e = orthodoxEaster(year);
    return [
      ThemeRange(
        theme: ThemePresets.holyWeek,
        start: formatDate(e.subtract(const Duration(days: 7))),
        end: formatDate(e.subtract(const Duration(days: 1))),
      ),
      ThemeRange(
        theme: ThemePresets.resurrection,
        start: formatDate(e),
        end: formatDate(e.add(Duration(days: resurrectionDays - 1))),
      ),
    ];
  }

  /// The theme in force on the Cairo calendar day [cairoDay] (y/m/d only)
  /// while the seasons [activeSeasonKeys] are active (see the precedence on
  /// the class): an admin range (with [auto]), else the active season's
  /// theme (with [followSeason]), else the Coptic Easter dates (with [auto]
  /// and [easter]), else [selected].
  ThemeResolution resolve(String selected, DateTime cairoDay, {Iterable<String> activeSeasonKeys = const []}) {
    final sel = ThemePresets.normalize(selected);
    final day = DateTime.utc(cairoDay.year, cairoDay.month, cairoDay.day);
    if (auto) {
      for (final r in schedule) {
        if (r.covers(day)) return ThemeResolution(r.theme, ThemeSource.schedule, r);
      }
    }
    if (followSeason) {
      final active = activeSeasonKeys.toSet();
      for (final k in SeasonThemes.seasonKeys) {
        if (!active.contains(k)) continue;
        final t = themeForSeason(k);
        if (t != null) return ThemeResolution(t, ThemeSource.season, null, k);
      }
    }
    if (!auto) return ThemeResolution(sel, ThemeSource.manual);
    if (easter) {
      // The Fifty Days can spill into the next year's calendar only in
      // theory (Easter is in April / May), so this year's Easter is enough.
      for (final r in easterRanges(day.year)) {
        if (r.covers(day)) return ThemeResolution(r.theme, ThemeSource.easter, r);
      }
    }
    return ThemeResolution(sel, ThemeSource.fallback);
  }

  @override
  bool operator ==(Object other) =>
      other is OccasionConfig &&
      other.auto == auto &&
      other.easter == easter &&
      other.resurrectionDays == resurrectionDays &&
      other.followSeason == followSeason &&
      _listEq(other.schedule, schedule) &&
      _customEq(other.custom, custom) &&
      _customEq({'s': other.seasonThemes}, {'s': seasonThemes});

  @override
  int get hashCode =>
      Object.hash(auto, easter, resurrectionDays, followSeason, Object.hashAll(schedule), custom.length, seasonThemes.length);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _customEq(Map<String, Map<String, String>> a, Map<String, Map<String, String>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final o = b[e.key];
    if (o == null || o.length != e.value.length) return false;
    for (final c in e.value.entries) {
      if (o[c.key] != c.value) return false;
    }
  }
  return true;
}

enum ThemeSource { manual, schedule, season, easter, fallback }

/// Which theme applies and why.
class ThemeResolution {
  final String theme;
  final ThemeSource source;
  final ThemeRange? range;

  /// The season key that brought the theme ([ThemeSource.season]).
  final String? seasonKey;
  const ThemeResolution(this.theme, this.source, [this.range, this.seasonKey]);
}
