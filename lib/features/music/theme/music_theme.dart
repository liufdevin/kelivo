import 'package:flutter/material.dart';

class MusicColors {
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF667085);
  static const faint = Color(0xFF98A2B3);
  static const paper = Color(0xFFF6F8F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFCFDFB);
  static const surfaceSoft = Color(0xFFE9F0EC);
  static const accentSoft = Color(0xFFE0F3EC);
  static const accentWash = Color(0xFFF0FAF6);
  static const line = Color(0xFFD9E2DD);
  static const accent = Color(0xFF0E7C66);
  static const accentDark = Color(0xFF07594A);
  static const coral = Color(0xFFE0523F);
  static const shadow = Color(0x180F172A);
}

ThemeData buildMusicTheme(ThemeData base) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: MusicColors.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: MusicColors.accent,
        secondary: MusicColors.coral,
        surface: MusicColors.surface,
      );
  return base.copyWith(
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: MusicColors.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: MusicColors.accentWash,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: MusicColors.paper,
      foregroundColor: MusicColors.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MusicColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MusicColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MusicColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MusicColors.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(color: MusicColors.muted),
      hintStyle: const TextStyle(color: MusicColors.faint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: MusicColors.accentDark,
        side: const BorderSide(color: MusicColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: MusicColors.accentWash,
      selectedColor: MusicColors.accentSoft,
      side: const BorderSide(color: MusicColors.line),
      labelStyle: const TextStyle(color: MusicColors.accentDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MusicColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
