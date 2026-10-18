import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// KALA AI BRAND COLORS
// =============================================================================
// Primary gradient: Purple (#7B5EFF) → Cyan (#00D4FF)
// Accent: Magenta/Pink (#FF66B2)
// Surface dark: Deep navy (#1A1A2E)

class KalaColors {
  KalaColors._();
  
  // Core brand colors
  static const Color purple = Color(0xFF7B5EFF);      // Primary purple
  static const Color cyan = Color(0xFF00D4FF);        // Secondary cyan
  static const Color magenta = Color(0xFFFF66B2);     // Accent pink/magenta
  static const Color gold = Color(0xFFFFAA33);        // Accent gold (brush tip)
  
  // Surface colors
  static const Color surfaceDark = Color(0xFF1A1A2E);    // Deep navy background
  static const Color surfaceDarkAlt = Color(0xFF12121C); // Deeper variant
  static const Color surfaceLight = Color(0xFFF8F9FC);   // Light mode surface
  
  // Gradient presets
  static const List<Color> brandGradient = [purple, cyan];
  static const List<Color> accentGradient = [purple, magenta];
  static const List<Color> fullGradient = [purple, magenta, cyan];
}

/// Optional helper — can be reused by custom widgets (like GradientButton)
LinearGradient appButtonGradient(BuildContext context) {
  return const LinearGradient(
    colors: KalaColors.brandGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Brand gradient for text/icons
LinearGradient kalaBrandGradient({
  Alignment begin = Alignment.topLeft,
  Alignment end = Alignment.bottomRight,
}) {
  return LinearGradient(
    colors: KalaColors.brandGradient,
    begin: begin,
    end: end,
  );
}

// =============================================================================
// KALA AI LOGO WIDGET
// =============================================================================
/// A reusable widget that displays the Kala AI logo with gradient text.
/// Matches the brand styling: "Kala" in purple transitioning to "AI" in cyan.
class KalaLogo extends StatelessWidget {
  final double fontSize;
  final bool showTagline;
  final String? tagline;
  
  const KalaLogo({
    super.key,
    this.fontSize = 24,
    this.showTagline = false,
    this.tagline,
  });
  
  /// Small variant for app bars
  factory KalaLogo.small() => const KalaLogo(fontSize: 20);
  
  /// Medium variant for headers
  factory KalaLogo.medium() => const KalaLogo(fontSize: 28);
  
  /// Large variant for splash/hero sections
  factory KalaLogo.large({String? tagline}) => KalaLogo(
    fontSize: 36,
    showTagline: tagline != null,
    tagline: tagline,
  );
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              KalaColors.purple,
              KalaColors.purple,
              KalaColors.cyan,
            ],
            stops: [0.0, 0.5, 1.0],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            'Kala AI',
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
        ),
        if (showTagline && tagline != null) ...[
          const SizedBox(height: 4),
          Text(
            tagline!,
            style: GoogleFonts.inter(
              fontSize: fontSize * 0.4,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }
}

/// A compact logo with icon + text for headers
class KalaLogoWithIcon extends StatelessWidget {
  final double logoHeight;
  final double fontSize;
  
  const KalaLogoWithIcon({
    super.key,
    this.logoHeight = 28,
    this.fontSize = 22,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo icon
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/kala_ai_logo.png',
            height: logoHeight,
            width: logoHeight,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        // Gradient text
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              KalaColors.purple,
              KalaColors.purple,
              KalaColors.cyan,
            ],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            'Kala AI',
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class AppTheme {
  // ---------------------------------------------------------------------------
  //  BASE COLORS (Kala AI Brand Palette)
  // ---------------------------------------------------------------------------

  static const Color seedPrimary = KalaColors.purple;   // Brand purple
  static const Color seedSecondary = KalaColors.cyan;   // Brand cyan

  // Creates harmonized color scheme
  static ColorScheme _harmonize(ColorScheme scheme) {
    return ColorScheme.fromSeed(
      seedColor: scheme.primary,
      brightness: scheme.brightness,
      primary: scheme.primary,
      secondary: scheme.secondary,
    );
  }

  // ---------------------------------------------------------------------------
  //  DARK THEME
  // ---------------------------------------------------------------------------

  static ThemeData get modernDark {
    final scheme = _harmonize(const ColorScheme(
      brightness: Brightness.dark,
      primary: seedPrimary,
      onPrimary: Colors.white,
      secondary: seedSecondary,
      onSecondary: Colors.black,
      tertiary: KalaColors.magenta,
      onTertiary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: KalaColors.surfaceDark,
      onSurface: Colors.white,
    ));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,

      // Background
      scaffoldBackgroundColor: scheme.surface,

      // Typography
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: Colors.white.withValues(alpha: 0.95),
        displayColor: Colors.white.withValues(alpha: 0.95),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // Buttons (we’ll override visuals with GradientButton widget)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          foregroundColor: Colors.white,
          backgroundColor: seedPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
              side: const BorderSide(
                width: 2,
                color: Colors.white30,
              ),
            ),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
          ),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? Colors.white.withValues(alpha: 0.05)
                : null,
          ),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1F1F2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      ),

      // Cards
      cardTheme: const CardThemeData(
        color: Color(0x1AFFFFFF), // 10% white glass
        elevation: 0,
        margin: EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),

      // ListTiles
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        tileColor: const Color(0xFF1B1B24),
        iconColor: Colors.white70,
        textColor: Colors.white.withValues(alpha: 0.95),
      ),

      // Switches / Checkbox
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(seedPrimary),
        trackColor: WidgetStateProperty.all(seedPrimary.withValues(alpha: 0.4)),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1A1A22),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 16,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  LIGHT THEME (Harmonized + matching aesthetic)
  // ---------------------------------------------------------------------------

  static ThemeData get modernLight {
    final scheme = _harmonize(const ColorScheme(
      brightness: Brightness.light,
      primary: seedPrimary,
      onPrimary: Colors.white,
      secondary: seedSecondary,
      onSecondary: Colors.black,
      tertiary: KalaColors.magenta,
      onTertiary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: KalaColors.surfaceLight,
      onSurface: Colors.black,
    ));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: Colors.black87,
        displayColor: Colors.black87,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          foregroundColor: Colors.white,
          backgroundColor: seedPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: const BorderSide(width: 2, color: Colors.black26),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade200,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: Colors.grey.shade600),
        labelStyle: TextStyle(color: Colors.grey.shade800),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.white,
        iconColor: Colors.black87,
        textColor: Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(seedPrimary),
        trackColor: WidgetStateProperty.all(seedPrimary.withValues(alpha: 0.4)),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.black87,
          fontSize: 16,
        ),
      ),
    );
  }
}
