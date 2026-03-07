import 'package:flutter/material.dart';

// ── Colours ──────────────────────────────────────────────────────────────────
const kVoid        = Color(0xFF03020A);
const kSurface     = Color(0xFF0D0B1A);
const kBorder      = Color(0xFF1E1A35);
const kTeal        = Color(0xFF00D4C8);
const kPurple      = Color(0xFF6B21D6);
const kBlue        = Color(0xFF4488FF);
const kStar        = Color(0xFFF0EEFF);
const kTextDim     = Color(0xFF5A5175);
const kTextMid     = Color(0xFF9B90BB);

// ── App theme ─────────────────────────────────────────────────────────────────
final appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kVoid,
  colorScheme: const ColorScheme.dark(
    primary:   kTeal,
    secondary: kPurple,
    surface:   kSurface,
    onPrimary: kVoid,
    onSurface: kStar,
  ),
  fontFamily: 'monospace',
  appBarTheme: const AppBarTheme(
    backgroundColor: kVoid,
    foregroundColor: kStar,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: kTeal,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
    ),
  ),
  textTheme: const TextTheme(
    bodyLarge:  TextStyle(color: kStar,    fontSize: 14),
    bodyMedium: TextStyle(color: kTextMid, fontSize: 12),
    bodySmall:  TextStyle(color: kTextDim, fontSize: 11),
    labelSmall: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 1.5),
  ),
  dividerColor: kBorder,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: const BorderSide(color: kTeal),
    ),
    hintStyle: const TextStyle(color: kTextDim, fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kTeal,
      foregroundColor: kVoid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
  ),
);
