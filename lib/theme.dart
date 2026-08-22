import 'package:flutter/material.dart';

// 2026-08-22: which CustomPainter treatment flag_frame.dart uses for a
// palette's border. `stripes` covers every flag that's genuinely a set
// of parallel colour bands (with correct axis/weights per flag) - that
// also covers flags that couldn't be made to look real any other way
// (Brazil, Albania: a single-colour "stripe list" of length 1 paints
// a plain accent border, no fake pattern pretended). `none` is the 3
// non-flag base themes only - never used to mean "gave up," see above.
enum FlagKind {
  none,
  stripes,
  nordicCross,
  stGeorgesCross,
  unionJack,
  southernCross,
  starsAndStripes,
}

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
  // the ordered band colours for FlagKind.stripes palettes (Germany's
  // black/red/gold, France's blue/white/red, etc., plus single-colour
  // lists used as a plain accent border where a real flag pattern
  // isn't achievable - see FlagKind doc above). Null for every other
  // FlagKind and for the 3 non-flag base skins.
  final List<Color>? flagStripes;
  // Band axis for flagStripes: false = horizontal bands stacked top to
  // bottom (Germany, Spain, Netherlands...), true = vertical bands
  // left to right (France, Italy, Ireland, Canada). Matters: the old
  // painter tiled every stripe list as repeating squares round the
  // frame regardless of the flag's real orientation - looked like
  // bunting, not a flag. Now the full flag is drawn at screen scale
  // and only the 8px edge band is left visible (see flag_frame.dart),
  // so getting the axis right makes each edge show the actual slice
  // of the real flag that would be there.
  final bool stripesVertical;
  // Proportional band widths matching flagStripes order, e.g. Spain's
  // red/yellow/red is 1:2:1, not equal thirds. Null = equal weights.
  final List<double>? stripeWeights;
  // 2026-08-22: repurposed from "border star-dot count" (2026-08-21,
  // real feedback: dots looked cheap) to "number of Southern Cross
  // constellation stars" for FlagKind.southernCross (Australia 5, NZ
  // 4) - drawn as real 5-point star polygons clustered along the
  // visible right/bottom border, not positioned at their true 2D
  // flag coordinates (those fall in the middle of the flag, which a
  // thin edge frame can never reveal - see flag_frame.dart's header
  // comment for why).
  final int? starCount;
  // NZ's Southern Cross stars are red with a white edge, not white
  // like Australia's.
  final bool southernCrossRedStars;
  // Australia only: adds the separate 7-point Commonwealth Star near
  // the canton.
  final bool southernCrossCommonwealthStar;
  final FlagKind flagKind;
  // 2026-08-22: path to a real flag SVG (assets/flags/), user-sourced
  // per country, for FULL display where nothing is clipped - the skin
  // picker's swatch in settings_screen.dart. NOT used by
  // flag_frame.dart's border: that frame only ever reveals an 8px
  // edge slice regardless of source, so a real SVG there would buy no
  // extra fidelity over the hand-coded painter while reintroducing
  // the asset-breaking-invisibly risk this app has real prior history
  // with. Null until a real SVG has actually been sourced for that
  // country - the swatch falls back to its plain accent-dot preview
  // rather than guessing at a flag it hasn't been given.
  final String? flagAsset;
  // 2026-08-22: "2nd option for crazy patriotic with flags all over
  // the place where the black space is." The border frame
  // (flag_frame.dart) only ever decorates the outer 8px edge - this
  // is a second, separate treatment (widgets/flag_backdrop.dart) that
  // tiles small complete flag icons across the app's void/background
  // areas everywhere real content isn't already sitting on an opaque
  // surface. False for every existing skin (including plain
  // "Australia") - it's an explicit second, louder option, not the
  // new default for a country once one variant exists.
  final bool boldBackdrop;
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
    this.stripesVertical = false,
    this.stripeWeights,
    this.starCount,
    this.southernCrossRedStars = false,
    this.southernCrossCommonwealthStar = false,
    this.flagKind = FlagKind.none,
    this.flagAsset,
    this.boldBackdrop = false,
  });
}

// 2026-08-22: derives a "— Bold" companion from any existing palette -
// same identity/colours/flag data, boldBackdrop: true. One helper
// instead of hand-duplicating every colour field per country: adding
// the bold variant for a country that already has a subtle one is one
// line (`final xBoldPalette = bold(xPalette);`), whether that palette
// was hand-built (const AppPalette(...)) or generated via _flagSkin -
// both are just AppPalette values, this doesn't care which.
AppPalette bold(AppPalette base) => AppPalette(
      id: '${base.id}_bold',
      label: '${base.label} — Bold',
      void_: base.void_,
      surface: base.surface,
      border: base.border,
      purple: base.purple,
      blue: base.blue,
      star: base.star,
      textDim: base.textDim,
      textMid: base.textMid,
      accent: base.accent,
      free: base.free,
      flagStripes: base.flagStripes,
      stripesVertical: base.stripesVertical,
      stripeWeights: base.stripeWeights,
      starCount: base.starCount,
      southernCrossRedStars: base.southernCrossRedStars,
      southernCrossCommonwealthStar: base.southernCrossCommonwealthStar,
      flagKind: base.flagKind,
      flagAsset: base.flagAsset,
      boldBackdrop: true,
    );

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
  // Horizontal celeste/white/celeste. The Sol de Mayo sun sits dead
  // centre of the white band - centre of the flag is exactly what an
  // 8px edge frame can never show (see flag_frame.dart), so it's
  // dropped rather than drawn somewhere it'd never render. The three
  // correctly-ordered horizontal bands in the right shade of celeste
  // still read as Argentina on their own.
  flagStripes: [Color(0xFF75AADB), Color(0xFFFFFFFF), Color(0xFF75AADB)],
  flagKind: FlagKind.stripes,
);
final argentinaBoldPalette = bold(argentinaPalette);

// 2026-08-22: Brazil's identity is the yellow diamond and blue circle
// on the green field - centred, touching none of the flag's own
// edges. A thin edge frame can only ever show what's drawn at the
// screen's own outer edge (see flag_frame.dart), so that diamond and
// circle would render nowhere, ever - not "simplified," genuinely
// invisible. Scrapping the real-flag ambition here per the fallback
// rule: a plain green accent border (single-colour flagStripes list),
// no fake pattern pretending to be more than it is.
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
  flagStripes: [Color(0xFF009739)],
  flagKind: FlagKind.stripes,
);
final brazilBoldPalette = bold(brazilPalette);

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
  stripesVertical: true,
  flagKind: FlagKind.stripes,
);
final italyBoldPalette = bold(italyPalette);

// 2026-08-22: had zero border decoration before this pass - St
// George's Cross is a centred, full-height/full-width red cross on
// white, which is exactly the shape an edge frame CAN show (the bars
// run edge to edge, unlike a centred emblem) - drawn for real via
// FlagKind.stGeorgesCross in flag_frame.dart.
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
  flagKind: FlagKind.stGeorgesCross,
);
final englandBoldPalette = bold(englandPalette);

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
  bool stripesVertical = false,
  List<double>? stripeWeights,
  int? stars,
  FlagKind flagKind = FlagKind.none,
  bool southernCrossRedStars = false,
  bool southernCrossCommonwealthStar = false,
  String? flagAsset,
  bool boldBackdrop = false,
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
    stripesVertical: stripesVertical,
    stripeWeights: stripeWeights,
    starCount: stars,
    southernCrossRedStars: southernCrossRedStars,
    southernCrossCommonwealthStar: southernCrossCommonwealthStar,
    flagAsset: flagAsset,
    boldBackdrop: boldBackdrop,
    // A stripe list implies FlagKind.stripes automatically (covers the
    // plain tricolours below, and doubles as the "scrap the real-flag
    // ambition, plain accent border" fallback for a length-1 list) -
    // unless an explicit special kind was passed (US passes both: its
    // 13-colour list drives the striping, starsAndStripes adds the
    // canton on top).
    flagKind: flagKind != FlagKind.none
        ? flagKind
        : (stripes != null ? FlagKind.stripes : FlagKind.none),
  );
}

// 2026-08-22: every one of these 15 now gets SOME real border
// decoration - either the flag's genuine pattern drawn at screen
// scale (see flag_frame.dart's header for why that's the only way an
// 8px edge frame can show a real flag shape), or, where the flag's
// identity lives in the centre and could never appear in an edge
// frame (Albania's double-headed eagle - no edge-spanning shape to
// derive from it at all), a single-colour flagStripes list as a
// plain accent border instead of a fake pattern.
// 2026-08-22: user-sourced real Wikimedia SVG (assets/flags/us.svg,
// viewBox 0 0 7410 3900) confirmed the canton is exactly 0.4 width x
// 7/13 height (2964/7410, 2100/3900) - already correct below - but
// caught two real colour errors: the red was 0xFFB22234 (a plain
// wrong value, not the official "Old Glory Red") and usCantonBlue in
// flag_paint.dart was 0xFF3C3B6E, nowhere close to the real 0x0A3161.
// Both fixed to the SVG's literal fill values.
final usPalette = _flagSkin(
    id: 'us',
    label: 'United States',
    accent: const Color(0xFFB31942),
    // 13 horizontal stripes span the full width, so top/bottom edges
    // show the right stripe colour and left/right edges show the
    // whole alternating sequence stacked - all genuinely visible. The
    // canton corner (blue field) touches the top and left edges too,
    // so it's real and visible; a few star polygons are drawn
    // directly onto that corner's visible border strip (their true
    // grid positions inside the canton are mostly interior and would
    // be invisible - same reasoning as Southern Cross, see
    // flag_frame.dart's _drawStarsAndStripes).
    flagKind: FlagKind.starsAndStripes,
    stripes: const [
      Color(0xFFB31942), Color(0xFFFFFFFF), Color(0xFFB31942), Color(0xFFFFFFFF),
      Color(0xFFB31942), Color(0xFFFFFFFF), Color(0xFFB31942), Color(0xFFFFFFFF),
      Color(0xFFB31942), Color(0xFFFFFFFF), Color(0xFFB31942), Color(0xFFFFFFFF),
      Color(0xFFB31942),
    ],
    flagAsset: 'assets/flags/us.svg');
final usBoldPalette = bold(usPalette);
final canadaPalette = _flagSkin(
    id: 'canada',
    label: 'Canada',
    accent: const Color(0xFFFF0000),
    // Vertical red/white/red, correct 1:2:1 pale proportions. The
    // maple leaf sits dead centre of the white band, so - like
    // Argentina's sun - it's dropped rather than drawn somewhere an
    // edge frame can never reveal it.
    stripes: const [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFFFF0000)],
    stripesVertical: true,
    stripeWeights: const [1, 2, 1]);
final canadaBoldPalette = bold(canadaPalette);
final australiaPalette = _flagSkin(
    id: 'australia',
    label: 'Australia',
    accent: const Color(0xFF00247D),
    flagKind: FlagKind.southernCross,
    stars: 5,
    southernCrossCommonwealthStar: true,
    // 2026-08-22: user-sourced real Wikimedia SVG, used for the full,
    // unclipped skin-picker thumbnail only (see flagAsset's doc
    // comment above) - the border frame's canton/star fractions in
    // flag_frame.dart were also corrected against this file's exact
    // coordinates.
    flagAsset: 'assets/flags/australia.svg');
// 2026-08-22: "2nd option for crazy patriotic with flags all over the
// place where the black space is" - same identity/colours as plain
// Australia above (same accent, same border), plus boldBackdrop:
// true, which turns on widgets/flag_backdrop.dart's tiled mini-flags
// across every screen's void background. A separate selectable skin,
// not a toggle on the existing one - so "subtle" stays available
// exactly as it already was.
final australiaBoldPalette = bold(australiaPalette);
final nzPalette = _flagSkin(
    id: 'nz',
    label: 'New Zealand',
    accent: const Color(0xFF1C39BB),
    flagKind: FlagKind.southernCross,
    stars: 4,
    southernCrossRedStars: true);
final nzBoldPalette = bold(nzPalette);
final ukPalette = _flagSkin(
    id: 'uk',
    label: 'United Kingdom',
    accent: const Color(0xFF012169),
    flagKind: FlagKind.unionJack);
final ukBoldPalette = bold(ukPalette);
final irelandPalette = _flagSkin(
    id: 'ireland',
    label: 'Ireland',
    accent: const Color(0xFF169B62),
    stripes: const [Color(0xFF169B62), Color(0xFFFFFFFF), Color(0xFFFF883E)],
    stripesVertical: true);
final irelandBoldPalette = bold(irelandPalette);
final germanyPalette = _flagSkin(
    id: 'germany',
    label: 'Germany',
    accent: const Color(0xFFFFCE00),
    stripes: const [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)]);
final germanyBoldPalette = bold(germanyPalette);
final francePalette = _flagSkin(
    id: 'france',
    label: 'France',
    accent: const Color(0xFF002654),
    stripes: const [Color(0xFF0055A4), Color(0xFFFFFFFF), Color(0xFFEF4135)],
    stripesVertical: true);
final franceBoldPalette = bold(francePalette);
final spainPalette = _flagSkin(
    id: 'spain',
    label: 'Spain',
    accent: const Color(0xFFC60B1E),
    // Real proportions are 1:2:1, not equal thirds.
    stripes: const [Color(0xFFAA151B), Color(0xFFF1BF00), Color(0xFFAA151B)],
    stripeWeights: const [1, 2, 1]);
final spainBoldPalette = bold(spainPalette);
final netherlandsPalette = _flagSkin(
    id: 'netherlands',
    label: 'Netherlands',
    accent: const Color(0xFFFF9B00),
    stripes: const [Color(0xFFAE1C28), Color(0xFFFFFFFF), Color(0xFF21468B)]);
final netherlandsBoldPalette = bold(netherlandsPalette);
// 2026-08-22: "top" tier ends here (Argentina/Brazil/Italy/England
// hand-built above, US through Netherlands generated here - all "top
// earning countries" per the original 2026-08-21 batch). Finland
// through Albania below are the secondary tier, added to allPalettes
// after the top tier's Bold companions, per explicit ordering.
final finlandPalette = _flagSkin(
    id: 'finland',
    label: 'Finland',
    accent: const Color(0xFF003580),
    // Nordic cross bars run edge to edge, so - unlike a centred
    // emblem - this one genuinely shows in full.
    flagKind: FlagKind.nordicCross);
final finlandBoldPalette = bold(finlandPalette);
final slovakiaPalette = _flagSkin(
    id: 'slovakia',
    label: 'Slovakia',
    accent: const Color(0xFF0B4EA2),
    stripes: const [Color(0xFFFFFFFF), Color(0xFF0B4EA2), Color(0xFFEE1C25)]);
final slovakiaBoldPalette = bold(slovakiaPalette);
final sloveniaPalette = _flagSkin(
    id: 'slovenia',
    label: 'Slovenia',
    accent: const Color(0xFFE9424D),
    stripes: const [Color(0xFFFFFFFF), Color(0xFF0000FF), Color(0xFFED1C24)]);
final sloveniaBoldPalette = bold(sloveniaPalette);
final estoniaPalette = _flagSkin(
    id: 'estonia',
    label: 'Estonia',
    accent: const Color(0xFF0072CE),
    stripes: const [Color(0xFF0072CE), Color(0xFF000000), Color(0xFFFFFFFF)]);
final estoniaBoldPalette = bold(estoniaPalette);
// 2026-08-22: Albania's flag is a black double-headed eagle on red -
// no stripe/cross/canton shape to derive at all, and an eagle
// silhouette is exactly the kind of centred emblem an edge frame can
// never show. Scrapping the real-flag ambition here per the fallback
// rule: plain red accent border, no fake pattern.
final albaniaPalette = _flagSkin(
    id: 'albania',
    label: 'Albania',
    accent: const Color(0xFFE41E20),
    stripes: const [Color(0xFFE41E20)]);
final albaniaBoldPalette = bold(albaniaPalette);

// 2026-08-22: every country now has a "— Bold" companion (see the
// `bold()` helper above), each listed right next to its subtle
// original. Order: the 3 non-flag base themes, then the top-earning
// tier (Argentina through Netherlands, matching the original
// prioritised list), then the secondary tier (Finland through
// Albania) - same top-then-secondary grouping the palettes were
// already declared in above.
final allPalettes = [
  terminalGreenPalette,
  amberTerminalPalette,
  monochromePalette,
  // ── Top tier ──────────────────────────────────────────────────────
  argentinaPalette,
  argentinaBoldPalette,
  brazilPalette,
  brazilBoldPalette,
  italyPalette,
  italyBoldPalette,
  englandPalette,
  englandBoldPalette,
  usPalette,
  usBoldPalette,
  canadaPalette,
  canadaBoldPalette,
  australiaPalette,
  australiaBoldPalette,
  nzPalette,
  nzBoldPalette,
  ukPalette,
  ukBoldPalette,
  irelandPalette,
  irelandBoldPalette,
  germanyPalette,
  germanyBoldPalette,
  francePalette,
  franceBoldPalette,
  spainPalette,
  spainBoldPalette,
  netherlandsPalette,
  netherlandsBoldPalette,
  // ── Secondary tier ────────────────────────────────────────────────
  finlandPalette,
  finlandBoldPalette,
  slovakiaPalette,
  slovakiaBoldPalette,
  sloveniaPalette,
  sloveniaBoldPalette,
  estoniaPalette,
  estoniaBoldPalette,
  albaniaPalette,
  albaniaBoldPalette,
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
      // 2026-08-22: transparent, not kVoid - main.dart's
      // MaterialApp.builder now paints the void fill (and, for bold
      // skins, tiled mini-flags) via FlagBackdrop, underneath every
      // Scaffold everywhere in the app. A solid scaffoldBackgroundColor
      // here would just paint over that on every single screen.
      scaffoldBackgroundColor: Colors.transparent,
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
