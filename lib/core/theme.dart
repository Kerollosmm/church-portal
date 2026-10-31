import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Coptic-church visual identity: deep burgundy, liturgical gold, warm cream.
class AppColors {
  static const burgundy = Color(0xFF6B1426);
  static const burgundyDark = Color(0xFF4A0D1A);
  static const burgundyLight = Color(0xFF8E2A3E);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE8D28A);
  static const cream = Color(0xFFFBF6EC);
  static const parchment = Color(0xFFF3E9D2);
  static const ink = Color(0xFF2B1A12);
  static const muted = Color(0xFF7A6658);
  static const success = Color(0xFF2E7D4F);
  static const alert = Color(0xFFB3261E);
}

ThemeData buildTheme(Locale locale) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.burgundy,
    primary: AppColors.burgundy,
    onPrimary: Colors.white,
    secondary: AppColors.gold,
    onSecondary: AppColors.ink,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
    error: AppColors.alert,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: AppColors.cream);
  final text = GoogleFonts.cairoTextTheme(base.textTheme).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.burgundy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.burgundy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.burgundy,
        side: const BorderSide(color: AppColors.burgundy),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: AppColors.burgundy,
      backgroundColor: Colors.white,
      labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
      side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.burgundy, width: 1.6),
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.gold.withValues(alpha: 0.3)),
  );
}
