import 'package:flutter/material.dart';

class RoomColors {
  static const paper = Color(0xFFF7F3EB);
  static const surface = Color(0xFFFFFCF6);
  static const ink = Color(0xFF242B28);
  static const muted = Color(0xFF5E655F);
  static const forest = Color(0xFF28564B);
  static const line = Color(0xFFDDD9CF);
  static const terra = Color(0xFFB66750);
  // Bookcase: warm wood and a slightly deeper paper for the back panel.
  static const shelfBack = Color(0xFFEADFCB);
  static const shelfBackDeep = Color(0xFFD9CBB1);
  static const woodLight = Color(0xFFCDA97C);
  static const wood = Color(0xFFB08659);
  static const woodDark = Color(0xFF86623F);
}

ThemeData roomTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'DM Sans',
    colorScheme: ColorScheme.fromSeed(
      seedColor: RoomColors.forest,
      primary: RoomColors.forest,
      surface: RoomColors.surface,
      onSurface: RoomColors.ink,
      secondary: RoomColors.terra,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: RoomColors.paper,
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(
        fontFamily: 'Literata',
        fontSize: 34,
        height: 1.2,
        color: RoomColors.ink,
        letterSpacing: -1.3,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Literata',
        fontSize: 28,
        height: 1.25,
        color: RoomColors.ink,
        letterSpacing: -.7,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'Literata',
        fontSize: 22,
        color: RoomColors.ink,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'DM Sans',
        fontSize: 16,
        height: 1.5,
        color: RoomColors.ink,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RoomColors.paper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    dividerColor: RoomColors.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RoomColors.surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: RoomColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: RoomColors.surface,
      indicatorColor: Color(0xFFE5EBE3),
      height: 76,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: RoomColors.paper,
      showDragHandle: false,
    ),
  );
}
