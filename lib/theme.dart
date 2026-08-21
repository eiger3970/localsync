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
  // 2026-08-21: "make the paid skins now" - the free/paid split
  // exists for real now, not just as a plan. terminalGreenPalette is
  // the only free one; unrestricted selection in Settings still
  // applies (no purchase gate wired in yet), this only drives the
  // "PRO" badge so the eventual gate isn't a surprise.
  final bool free;
  // 2026-08-21: "add real flags around... like a Fortnite skin around
  // the edges, but so you can still see and operate the functions" -
  // the actual stripe sequence for flags that are genuinely
  // stripe-based (Germany's horizontal black/red/gold, France's
  // vertical blue/white/red, etc.) - drawn as a thin repeating-band
  // frame around the screen edge by widgets/flag_frame.dart. Null for
  // palettes with no accurate stripe representation (complex flags
  // like the UK's Union Jack or the US's stars-and-stripes, or the 3
  // non-flag skins) - those get no frame at all rather than a
  // misleading simplified pattern.
  final List<Color>? flagStripes;
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
    this.free = false,
    this.flagStripes,
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
  free: true,
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

// 2026-08-21: "national colours of countries for football teams or
// popular stuff that sells" - flag/team colors only, no crest, no
// club name. Colors alone aren't trademarked; a specific football
// CLUB's branding (crest, name) would be - deliberately stayed at the
// national-team level, not "Real Madrid" etc. Void/surface/border
// kept close to the same dark-neutral baseline as the other skins
// (this app has no light theme at all - buildAppTheme() is hardcoded
// Brightness.dark) - each flag's own color is the accent, not a full
// palette redesign.
const argentinaPalette = AppPalette(
  id: 'argentina',
  label: 'Argentina',
  void_: Color(0xFF050810),
  surface: Color(0xFF0D1420),
  border: Color(0xFF1B2A40),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFF0F4FF),
  textDim: Color(0xFF4A5875),
  textMid: Color(0xFF8DA3C4),
  accent: Color(0xFF75AADB),
  flagStripes: [Color(0xFF75AADB), Color(0xFFFFFFFF), Color(0xFF75AADB)],
);

const brazilPalette = AppPalette(
  id: 'brazil',
  label: 'Brazil',
  void_: Color(0xFF060A03),
  surface: Color(0xFF0E1607),
  border: Color(0xFF223815),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFF5F9E8),
  textDim: Color(0xFF4E6B2E),
  textMid: Color(0xFF8FAE5C),
  accent: Color(0xFFFFDF00),
);

const italyPalette = AppPalette(
  id: 'italy',
  label: 'Italy (Azzurri)',
  void_: Color(0xFF03060C),
  surface: Color(0xFF091121),
  border: Color(0xFF162645),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFEAF2FF),
  textDim: Color(0xFF3A5480),
  textMid: Color(0xFF7098C8),
  accent: Color(0xFF0066CC),
  flagStripes: [Color(0xFF009246), Color(0xFFFFFFFF), Color(0xFFCE2B37)],
);

const englandPalette = AppPalette(
  id: 'england',
  label: 'England',
  void_: Color(0xFF0A0304),
  surface: Color(0xFF160709),
  border: Color(0xFF3A1418),
  purple: Color(0xFF6B21D6),
  blue: Color(0xFF4488FF),
  star: Color(0xFFFFF0F0),
  textDim: Color(0xFF7A3E42),
  textMid: Color(0xFFC47D82),
  accent: Color(0xFFCE1124),
);

// 2026-08-21: "top earning countries" batch - 15 more (Italy already
// exists above, skipped here rather than duplicated). Hand-writing 15
// more full literal palettes the way the first 4 were built would be
// a lot of repetition for what's really one real decision per country
// (which color represents it) - this derives the rest of each
// palette from that one accent choice instead, same dark-neutral-
// tinted-toward-the-accent look as the hand-built ones, just
// generated. Not `const` (Color.lerp isn't a compile-time constant),
// so allPalettes below is `final`, not `const` - fine, nothing reads
// it in a const context.
AppPalette _flagSkin({
  required String id,
  required String label,
  required Color accent,
  List<Color>? stripes,
}) {
  const baseVoid = Color(0xFF030307);
  const baseSurface = Color(0xFF0B0B12);
  const baseBorder = Color(0xFF1E1E2A);
  const baseStar = Color(0xFFF0F0F5);
  const baseTextDim = Color(0xFF555560);
  const baseTextMid = Color(0xFF9B9BB0);
  return AppPalette(
    id: id,
    label: label,
    void_: Color.lerp(baseVoid, accent, 0.06)!,
    surface: Color.lerp(baseSurface, accent, 0.10)!,
    border: Color.lerp(baseBorder, accent, 0.18)!,
    purple: const Color(0xFF6B21D6),
    blue: const Color(0xFF4488FF),
    star: Color.lerp(baseStar, accent, 0.05)!,
    textDim: Color.lerp(baseTextDim, accent, 0.25)!,
    textMid: Color.lerp(baseTextMid, accent, 0.30)!,
    accent: accent,
    flagStripes: stripes,
  );
}

// 2026-08-21: flagStripes only set for genuinely stripe-based flags
// (see the AppPalette field comment) - US (stars+stripes), Australia/
// NZ/UK (Southern Cross/Union Jack), and Finland/Albania (Nordic
// cross / eagle) all left without a stripe pattern rather than a
// misleading simplified one.
final usPalette = _flagSkin(
    id: 'us', label: 'United States', accent: const Color(0xFFB22234));
final canadaPalette = _flagSkin(
    id: 'canada',
    label: 'Canada',
    accent: const Color(0xFFFF0000),
    stripes: const [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFFFF0000)]);
final australiaPalette = _flagSkin(
    id: 'australia', label: 'Australia', accent: const Color(0xFF00247D));
final nzPalette = _flagSkin(
    id: 'nz', label: 'New Zealand', accent: const Color(0xFF1C39BB));
final ukPalette =
    _flagSkin(id: 'uk', label: 'United Kingdom', accent: const Color(0xFF012169));
final irelandPalette = _flagSkin(
    id: 'ireland',
    label: 'Ireland',
    accent: const Color(0xFF169B62),
    stripes: const [Color(0xFF169B62), Color(0xFFFFFFFF), Color(0xFFFF883E)]);
final germanyPalette = _flagSkin(
    id: 'germany',
    label: 'Germany',
    accent: const Color(0xFFFFCE00),
    stripes: const [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)]);
final francePalette = _flagSkin(
    id: 'france',
    label: 'France',
    accent: const Color(0xFF002654),
    stripes: const [Color(0xFF0055A4), Color(0xFFFFFFFF), Color(0xFFEF4135)]);
final spainPalette = _flagSkin(
    id: 'spain',
    label: 'Spain',
    accent: const Color(0xFFC60B1E),
    stripes: const [Color(0xFFAA151B), Color(0xFFF1BF00), Color(0xFFAA151B)]);
final netherlandsPalette = _flagSkin(
    id: 'netherlands',
    label: 'Netherlands',
    accent: const Color(0xFFFF9B00),
    stripes: const [Color(0xFFAE1C28), Color(0xFFFFFFFF), Color(0xFF21468B)]);
final finlandPalette = _flagSkin(
    id: 'finland', label: 'Finland', accent: const Color(0xFF003580));
final slovakiaPalette = _flagSkin(
    id: 'slovakia',
    label: 'Slovakia',
    accent: const Color(0xFF0B4EA2),
    stripes: const [Color(0xFFFFFFFF), Color(0xFF0B4EA2), Color(0xFFEE1C25)]);
final sloveniaPalette = _flagSkin(
    id: 'slovenia',
    label: 'Slovenia',
    accent: const Color(0xFFE9424D),
    stripes: const [Color(0xFFFFFFFF), Color(0xFF0000FF), Color(0xFFED1C24)]);
final estoniaPalette = _flagSkin(
    id: 'estonia',
    label: 'Estonia',
    accent: const Color(0xFF0072CE),
    stripes: const [Color(0xFF0072CE), Color(0xFF000000), Color(0xFFFFFFFF)]);
final albaniaPalette = _flagSkin(
    id: 'albania', label: 'Albania', accent: const Color(0xFFE41E20));

final allPalettes = [
  terminalGreenPalette,
  amberTerminalPalette,
  monochromePalette,
  argentinaPalette,
  brazilPalette,
  italyPalette,
  englandPalette,
  usPalette,
  canadaPalette,
  australiaPalette,
  nzPalette,
  ukPalette,
  irelandPalette,
  germanyPalette,
  francePalette,
  spainPalette,
  netherlandsPalette,
  finlandPalette,
  slovakiaPalette,
  sloveniaPalette,
  estoniaPalette,
  albaniaPalette,
];

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
