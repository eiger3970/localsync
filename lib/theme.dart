import 'package:flutter/material.dart';

// ── Palettes ─────────────────────────────────────────────────────────────────
//
// 2026-08-21: "skins" IAP - every color in the app used to be a
// top-level `const`, fixed at compile time. Real runtime switching
// needs a value that can actually change, so each palette is now a
// plain data object, and every `k*` name below became a getter that
// reads whichever palette is currently selected (see AppTheme below) -
// same call-site names everywhere else in the app, nothing renamed.

class AppPalette {
  final String id;
  final String label;
  final Color void_;
  final Color surface;
  final Color border;
  final Color purple;
  final Color blue;
  final Color star;
  final Color textDim;
  final Color textMid;
  final Color accent;
  const AppPalette({
    required this.id,
    required this.label,
    required this.void_,
    required this.surface,
    required this.border,
    required this.purple,
    required this.blue,
    required this.star,
    required this.textDim,
    required this.textMid,
    required this.accent,
  });
}

// 2026-08-11: "colour theme, possible like kworld.space with the retro
// terminal green?" - matched the exact --nebula-teal value from the
// website's own src/index.css (misnamed there too - it's real terminal
// green, #00ff41). The original, default, free palette.
const terminalGreenPalette = AppPalette(
  id: 'terminal_green',
  label: 'Terminal green',
  void_: Color(0xFF03020A),
  surface: Color(0xFF0D0B1A),
  border: Color(0xFF1E1A35),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFF0EEFF),
  textDim: Color(0xFF5A5175),
  textMid: Color(0xFF9B90BB),
  accent: Color(0xFF00FF41),
);

// Warm amber CRT terminal - same "retro terminal" identity, different
// phosphor color. Void/surface/border warmed slightly to match, not
// just the accent swapped in isolation.
const amberTerminalPalette = AppPalette(
  id: 'amber_terminal',
  label: 'Amber terminal',
  void_: Color(0xFF0A0602),
  surface: Color(0xFF140D05),
  border: Color(0xFF2E1F0D),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFFFF3D9),
  textDim: Color(0xFF5C4A2E),
  textMid: Color(0xFF8F7548),
  accent: Color(0xFFFFB000),
);

// Pure grayscale, no hue anywhere - deliberately the most minimal
// option, not just a desaturated copy of the others.
const monochromePalette = AppPalette(
  id: 'monochrome',
  label: 'Monochrome',
  void_: Color(0xFF050505),
  surface: Color(0xFF0F0F0F),
  border: Color(0xFF232323),
  purple: Color(0xFF888888),
  blue: Color(0xFFAAAAAA),
  star: Color(0xFFF5F5F5),
  textDim: Color(0xFF555555),
  textMid: Color(0xFF999999),
  accent: Color(0xFFE0E0E0),
);

const allPalettes = [terminalGreenPalette, amberTerminalPalette, monochromePalette];

AppPalette paletteById(String id) =>
    allPalettes.firstWhere((p) => p.id == id, orElse: () => terminalGreenPalette);

// ── Live selection ───────────────────────────────────────────────────────────
//
// Plain static holder, not routed through Provider/context - most of
// the 299 existing `kGreen`/`kVoid`/etc. call sites have no
// BuildContext in scope (static helpers, top-level widgets built deep
// in a tree). ThemeService (services/theme_service.dart) is the real
// ChangeNotifier that persists the choice and triggers a rebuild; this
// is just where the current value actually lives.
class AppTheme {
  static AppPalette _current = terminalGreenPalette;
  static AppPalette get current => _current;
  static void set(AppPalette palette) => _current = palette;
}

Color get kVoid => AppTheme.current.void_;
Color get kSurface => AppTheme.current.surface;
Color get kBorder => AppTheme.current.border;
Color get kPurple => AppTheme.current.purple;
Color get kBlue => AppTheme.current.blue;
Color get kStar => AppTheme.current.star;
Color get kTextDim => AppTheme.current.textDim;
Color get kTextMid => AppTheme.current.textMid;
Color get kGreen => AppTheme.current.accent;

// ── App theme ─────────────────────────────────────────────────────────────────
//
// 2026-08-21: was `final appTheme = ThemeData(...)`, built once at
// file load. Now a function, rebuilt fresh whenever the selected
// palette changes (see main.dart's Consumer<ThemeService> wrapping
// MaterialApp) - a `final` value computed once could never reflect a
// later skin change.
ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kVoid,
      colorScheme: ColorScheme.dark(
        primary: kGreen,
        secondary: kPurple,
        surface: kSurface,
        onPrimary: kVoid,
        onSurface: kStar,
      ),
      fontFamily: 'monospace',
      appBarTheme: AppBarTheme(
        backgroundColor: kVoid,
        foregroundColor: kStar,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: kGreen,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: kStar, fontSize: 14),
        bodyMedium: TextStyle(color: kTextMid, fontSize: 12),
        bodySmall: TextStyle(color: kTextDim, fontSize: 11),
        labelSmall: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 1.5),
      ),
      dividerColor: kBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: kGreen),
        ),
        hintStyle: TextStyle(color: kTextDim, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
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
