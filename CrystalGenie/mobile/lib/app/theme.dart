import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. Oct 2026: the client switched the whole app to the orange + white style of the new
/// Home page. The token names are kept from the original teal Figma guide (teal = primary accent,
/// mint = light accent, navy = dark text) so every screen picks up the orange theme from here.
/// Original Figma teal values: mint #98CBCC, navy #003249, sky #4FB2C9, teal #34A0A3, deepTeal #123839.
abstract final class AppColors {
  // Base colours (orange theme)
  static const mint = Color(0xFFF6C29B); // light orange: borders, active states
  static const navy = Color(0xFF2B1A12); // dark brown text
  static const sky = Color(0xFFEF7D10); // bright orange
  static const teal = Color(0xFFD2401A); // primary orange-red accent (titles, icons)
  static const deepTeal = Color(0xFF4A1D0B); // dark surfaces (snackbars)
  /// Darker orange for small text links; ≥5.5:1 on the light backgrounds.
  static const linkTeal = Color(0xFFB3360F);

  // Neutrals
  static const ink = Color(0xFF1A181B);
  static const black = Color(0xFF0C0C0C);
  static const offWhite = Color(0xFFFBF6F3);
  static const grey = Color(0xFF7E7A79);
  static const darkGrey = Color(0xFF575654);
  static const slate = Color(0xFFA0928A); // warm grey for hints and secondary icons
  static const sand = Color(0xFFE4DFDC);

  // Alerts
  static const error = Color(0xFF952016);
  static const success = Color(0xFF1B7C11);
  static const warning = Color(0xFFEFAD4F);
  static const info = Color(0xFF075293);

  // Surfaces used by the frosted-glass screens
  static const bgTop = Color(0xFFFFF1E6);
  static const bgBottom = Color(0xFFF6F6F6);
  static const glassFill = Color(0x99FFFFFF);
  static const glassBorder = Color(0x80F6C29B);

  static const buttonGradient = LinearGradient(colors: [Color(0xFFE2601A), Color(0xFFD2401A)]);

  /// Continuous animations (the rotating diamond on Home). Widget/integration tests turn this off so
  /// pumpAndSettle can finish; the app always animates.
  static bool animatedImages = true;

  // Home page (orange style requested by the client, Oct 2026).
  static const orange = Color(0xFFEF7D10); // bright end of the gradient (large text only)
  static const orangeDeep = Color(0xFFD2401A); // white text ≥4.5:1
  static const homeBg = Color(0xFFF6F6F6);
  static const orangeGradient =
      LinearGradient(colors: [orange, orangeDeep], begin: Alignment.centerLeft, end: Alignment.centerRight);
}

/// Typography: Playfair Display (display / gem names) + Montserrat (UI text).
///
/// Tests set [useGoogleFonts] to false so no font download is attempted.
abstract final class AppText {
  static bool useGoogleFonts = true;

  static TextStyle playfair({double size = 24, FontWeight weight = FontWeight.w400, Color color = AppColors.ink, double? height}) {
    final base = TextStyle(fontSize: size, fontWeight: weight, color: color, height: height);
    return useGoogleFonts ? GoogleFonts.playfairDisplay(textStyle: base) : base.copyWith(fontFamily: 'serif');
  }

  static TextStyle montserrat({double size = 14, FontWeight weight = FontWeight.w400, Color color = AppColors.ink, double? height,
      FontStyle? style, double? letterSpacing}) {
    final base = TextStyle(
        fontSize: size, fontWeight: weight, color: color, height: height, fontStyle: style, letterSpacing: letterSpacing);
    return useGoogleFonts ? GoogleFonts.montserrat(textStyle: base) : base;
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    primary: AppColors.teal,
    secondary: AppColors.sky,
    surface: AppColors.offWhite,
    error: AppColors.error,
    onPrimary: Colors.white,
    onSurface: AppColors.ink,
  );
  final textTheme = TextTheme(
    displayLarge: AppText.montserrat(size: 36, weight: FontWeight.w500, color: AppColors.teal),
    headlineMedium: AppText.playfair(size: 28, weight: FontWeight.w700),
    headlineSmall: AppText.montserrat(size: 22, weight: FontWeight.w600),
    titleLarge: AppText.playfair(size: 24),
    titleMedium: AppText.montserrat(size: 16, weight: FontWeight.w600),
    bodyLarge: AppText.montserrat(size: 15, height: 1.35),
    bodyMedium: AppText.montserrat(size: 13.5, height: 1.35),
    bodySmall: AppText.montserrat(size: 11, color: AppColors.grey),
    labelLarge: AppText.montserrat(size: 16, weight: FontWeight.w500, color: AppColors.navy),
  );
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgBottom,
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.offWhite.withValues(alpha: 0.9),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: AppText.montserrat(size: 14, color: AppColors.slate),
      labelStyle: AppText.montserrat(size: 14, color: AppColors.navy),
      floatingLabelStyle: AppText.montserrat(size: 14, color: AppColors.teal),
      errorStyle: AppText.montserrat(size: 12, color: AppColors.error),
      border: border(AppColors.mint),
      enabledBorder: border(AppColors.mint),
      focusedBorder: border(AppColors.teal, 1.6),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.6),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.deepTeal,
      contentTextStyle: AppText.montserrat(size: 14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.offWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: AppText.montserrat(size: 18, weight: FontWeight.w600),
      contentTextStyle: AppText.montserrat(size: 14, color: AppColors.darkGrey),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.offWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.teal),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.slate),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.teal : AppColors.sand),
    ),
  );
}
