import 'package:flutter/material.dart';

class MeerColors {
  MeerColors._();
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF5D76E);
  static const goldDark = Color(0xFFA8862A);
  static const black = Color(0xFF0E0E0E);
  static const charcoal = Color(0xFF1C1C1C);
  static const graphite = Color(0xFF2A2A2A);
  static const surface = Color(0xFFF6F4EF);
  static const card = Colors.white;
  static const border = Color(0xFFE6E1D6);
  static const muted = Color(0xFF6E6A62);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFB26A00);
  static const danger = Color(0xFFC62828);
}

ThemeData buildMeerTheme() {
  const scheme = ColorScheme.light(
    primary: MeerColors.black,
    onPrimary: Colors.white,
    secondary: MeerColors.gold,
    onSecondary: MeerColors.black,
    surface: MeerColors.card,
    onSurface: MeerColors.black,
    error: MeerColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Segoe UI');
  final radius = BorderRadius.circular(12);
  return base.copyWith(
    scaffoldBackgroundColor: MeerColors.surface,
    textTheme: base.textTheme.apply(bodyColor: MeerColors.black, displayColor: MeerColors.black),
    cardTheme: CardThemeData(
      color: MeerColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: MeerColors.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MeerColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MeerColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MeerColors.gold, width: 2)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MeerColors.gold,
        foregroundColor: MeerColors.black,
        disabledBackgroundColor: const Color(0xFFE9E3D2),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MeerColors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MeerColors.black,
        side: const BorderSide(color: MeerColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return MeerColors.gold;
        if (s.contains(WidgetState.disabled)) return const Color(0xFFF1EEE6);
        return Colors.white;
      }),
      side: const BorderSide(color: MeerColors.border),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: MeerColors.black),
      secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w700, color: MeerColors.black),
      checkmarkColor: MeerColors.black,
      iconTheme: const IconThemeData(color: MeerColors.black, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: MeerColors.charcoal),
    dividerTheme: const DividerThemeData(color: MeerColors.border, space: 1),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(const Color(0xFFFBF8F0)),
      headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: MeerColors.black),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? MeerColors.black : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? MeerColors.gold : null),
    ),
  );
}
