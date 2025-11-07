// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';

// class AppTheme {
//   static ThemeData darkTheme = ThemeData(
//     useMaterial3: true,
//     brightness: Brightness.dark,
//     colorScheme: ColorScheme.fromSeed(
//       seedColor: Colors.indigo,
//       brightness: Brightness.dark,
//     ),
//     scaffoldBackgroundColor: const Color(0xFF0E0E12),
//     textTheme: GoogleFonts.poppinsTextTheme(
//       const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
//     ),
//     appBarTheme: const AppBarTheme(
//       backgroundColor: Colors.transparent,
//       elevation: 0,
//     ),
//   );
// }

//////==============================================================

// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';

// class AppTheme {
//   static ThemeData modernDark = ThemeData(
//     useMaterial3: true,
//     brightness: Brightness.dark,

//     // ---------- Core Color Scheme ----------
//     colorScheme: ColorScheme(
//       brightness: Brightness.dark,
//       primary: const Color(0xFF8F7BFF), // Soft neon purple
//       onPrimary: Colors.white,
//       secondary: const Color(0xFF5CE1E6), // Aqua accent
//       onSecondary: Colors.black,
//       error: Colors.redAccent,
//       onError: Colors.white,
//       background: const Color(0xFF0C0C12),
//       onBackground: Colors.white.withOpacity(0.9),
//       surface: const Color(0xFF1A1A24),
//       onSurface: Colors.white.withOpacity(0.9),
//     ),

//     // ---------- Background ----------
//     scaffoldBackgroundColor: const Color(0xFF0C0C12),

//     // ---------- Typography ----------
//     textTheme: GoogleFonts.interTextTheme().apply(
//       bodyColor: Colors.white.withOpacity(0.95),
//       displayColor: Colors.white.withOpacity(0.95),
//     ),

//     // ---------- AppBar ----------
//     appBarTheme: AppBarTheme(
//       backgroundColor: Colors.transparent,
//       elevation: 0,
//       centerTitle: false,
//       titleTextStyle: GoogleFonts.inter(
//         fontSize: 20,
//         fontWeight: FontWeight.w600,
//         color: Colors.white,
//       ),
//       iconTheme: const IconThemeData(color: Colors.white),
//     ),

//     // ---------- Buttons ----------
//     elevatedButtonTheme: ElevatedButtonThemeData(
//       style: ElevatedButton.styleFrom(
//         elevation: 0,
//         foregroundColor: Colors.white,
//         backgroundColor: const Color(0xFF8F7BFF),
//         padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(14),
//         ),
//         textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
//       ),
//     ),

//     filledButtonTheme: FilledButtonThemeData(
//       style: FilledButton.styleFrom(
//         backgroundColor: const Color(0xFF5CE1E6),
//         foregroundColor: Colors.black,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(14),
//         ),
//       ),
//     ),

//     // ---------- Input Fields ----------
//     inputDecorationTheme: InputDecorationTheme(
//       filled: true,
//       fillColor: const Color(0xFF1F1F2A),
//       border: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(14),
//         borderSide: BorderSide.none,
//       ),
//       hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
//       labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
//     ),

//     // ---------- Cards (glass effect) ----------
//     cardTheme: CardThemeData(
//       color: const Color(0x1AFFFFFF), // subtle glass
//       elevation: 0,
//       margin: const EdgeInsets.all(12),
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(20),
//       ),
//     ),

//     // ---------- ListTile ----------
//     listTileTheme: ListTileThemeData(
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(14),
//       ),
//       tileColor: const Color(0xFF1B1B24),
//       iconColor: Colors.white.withOpacity(0.9),
//       textColor: Colors.white.withOpacity(0.9),
//     ),

//     // ---------- Switch, Radio, Checkbox ----------
//     switchTheme: SwitchThemeData(
//       thumbColor: MaterialStateProperty.all(const Color(0xFF8F7BFF)),
//       trackColor:
//           MaterialStateProperty.all(const Color(0xFF8F7BFF).withOpacity(0.4)),
//     ),

//     // ---------- Divider ----------
//     dividerTheme: DividerThemeData(
//       color: Colors.white.withOpacity(0.08),
//       thickness: 1,
//     ),

//     // ---------- Dialogs ----------
//     dialogTheme: DialogThemeData(
//       backgroundColor: const Color(0xFF1A1A22),
//       elevation: 10,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(20),
//       ),
//       titleTextStyle: GoogleFonts.inter(
//         color: Colors.white,
//         fontSize: 20,
//         fontWeight: FontWeight.bold,
//       ),
//       contentTextStyle: GoogleFonts.inter(
//         color: Colors.white.withOpacity(0.9),
//         fontSize: 16,
//       ),
//     ),
//   );
// }
//
//===================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ---------------------------------------------------------------------------
  //  BASE COLORS (Modern Professional Palette)
  // ---------------------------------------------------------------------------

  static const Color seedPrimary = Color(0xFF3A8FFF); // Electric Blue
  static const Color seedSecondary = Color(0xFF00D1B2); // Mint / Teal accent

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
      error: Colors.redAccent,
      onError: Colors.white,
      background: Color(0xFF0C0C12),
      onBackground: Colors.white,
      surface: Color(0xFF1A1A24),
      onSurface: Colors.white,
    ));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,

      // Background
      scaffoldBackgroundColor: scheme.background,

      // Typography
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: Colors.white.withOpacity(0.95),
        displayColor: Colors.white.withOpacity(0.95),
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

      // Buttons
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
          backgroundColor: seedSecondary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
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
        textColor: Colors.white.withOpacity(0.95),
      ),

      // Switches / Checkbox
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.all(seedPrimary),
        trackColor: MaterialStateProperty.all(seedPrimary.withOpacity(0.4)),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.08),
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
          color: Colors.white.withOpacity(0.9),
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
      error: Colors.red,
      onError: Colors.white,
      background: Color(0xFFF7F8FB),
      onBackground: Colors.black,
      surface: Color(0xFFFFFFFF),
      onSurface: Colors.black,
    ));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
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
          backgroundColor: seedSecondary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
        thumbColor: MaterialStateProperty.all(seedPrimary),
        trackColor: MaterialStateProperty.all(seedPrimary.withOpacity(0.4)),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withOpacity(0.06),
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
