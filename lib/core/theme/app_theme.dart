import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void toggle(bool isCurrentlyDark) {
    state = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
  }
}
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
class AppTheme {
  static const Color pdfAccent = Color(0xFFE5322D);
  static const Color imageAccent = Color(0xFF2563EB);
  static const Color docAccent = Color(0xFF059669);
  static const Color mediaAccent = Color(0xFF7C3AED);
  static const Color youtubeAccent = Color(0xFFDC2626);
  static const Color privacyBadge = Color(0xFF0D9488);
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: pdfAccent,
      brightness: Brightness.light,
      primary: pdfAccent,
      surface: const Color(0xFFF8FAFC),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: pdfAccent,
      brightness: Brightness.dark,
      primary: const Color(0xFFFF5A54),
      surface: const Color(0xFF0F172A),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF090D16),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Color(0xFFF8FAFC),
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}



