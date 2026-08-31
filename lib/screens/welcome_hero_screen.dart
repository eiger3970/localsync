// screens/welcome_hero_screen.dart
//
// 2026-08-31: new first screen, replacing SyncChoiceScreen per direct
// design work - "just show me a simple drag drop from phone to desktop
// done... I want to see the benefit to me, saving the headache of lost
// file, data conflict, backup complexities." A plain two-choice list
// describes the app; this demonstrates it - drag the dog (carrying a
// file) from the phone to the desktop and watch it dock. Real
// Draggable/DragTarget, not decoration.
//
// Deliberately pastel/light, matching the real dog sprite's own colors
// (#2dd4bf teal, #0e4a44 dark teal) rather than the app's dark kVoid
// theme - confirmed directly: the dark neon-green UI is "the technical
// tool," this is the one-time warm welcome moment before it. Palette
// constants are local to this file (and its sibling preview screens),
// not added to theme.dart's skin system - this isn't a selectable skin.
//
// Same navigation contract as the SyncChoiceScreen it replaces: set
// LinkingController.preferredMode, then proceed - via the new preview
// screens first, which is the only routing change; the real pairing
// flow (LinkingScreen) is untouched.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart' show kGreen;
import '../models/repository.dart';
import '../features/linking/linking_controller.dart';
import 'sync_files_preview_screen.dart';
import 'sync_obsidian_preview_screen.dart';

const wBg1 = Color(0xFFF3FBFA);
const wBg2 = Color(0xFFE1F5F0);
const wInk = Color(0xFF0C2B26);
const wInkDim = Color(0xFF5E827B);
const wTeal = Color(0xFF2DD4BF);
const wTealDark = Color(0xFF0E4A44);
const wCream = Color(0xFFEAFFFB);
const wTealBg = Color(0xFFD9F5EF);
const wViolet = Color(0xFFB39DDB);
const wVioletDark = Color(0xFF6B4FA0);
const wVioletBg = Color(0xFFF1ECFA);
const wGold = Color(0xFFFFD166);

class WelcomeHeroScreen extends StatefulWidget {
  const WelcomeHeroScreen({super.key});

  @override
  State<WelcomeHeroScreen> createState() => _WelcomeHeroScreenState();
}

class _WelcomeHeroScreenState extends State<WelcomeHeroScreen> {
  bool _delivered = false;

  void _choose(BuildContext context, SyncMode mode) {
    context.read<LinkingController>().preferredMode = mode;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => mode == SyncMode.obsidianVault
            ? const SyncObsidianPreviewScreen()
            : const SyncFilesPreviewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [wBg1, wBg2],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: wTeal, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('LocalSync',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: wInkDim,
                            letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 12),
                const _HeadlinePoint(
                    icon: Icons.insert_drive_file_outlined,
                    text: 'No more lost files.'),
                const _HeadlinePoint(
                    icon: Icons.backup_outlined,
                    text: 'No more backup worries.'),
                const _HeadlinePoint(
                    assetIcon: 'assets/logos/git-branches-only.svg',
                    text: 'No more conflicts.'),
                const SizedBox(height: 6),
                Text('Try it - drag your file across.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: wInkDim)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 172,
                  child: _PhoneToDesktopDemo(
                    delivered: _delivered,
                    onDelivered: () => setState(() => _delivered = true),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      _PathCard(
                        iconBg: wTealBg,
                        iconFg: wTealDark,
                        title: 'Sync my files',
                        tag: 'FREE',
                        tagBg: wTealBg,
                        tagFg: wTealDark,
                        subtitle: 'Notes, documents, photos',
                        onTap: () => _choose(context, SyncMode.genericFolder),
                      ),
                      const SizedBox(height: 14),
                      _PathCard(
                        iconBg: wVioletBg,
                        iconFg: wVioletDark,
                        title: 'Sync my Obsidian notes',
                        tag: 'PRO',
                        tagBg: wVioletBg,
                        tagFg: wVioletDark,
                        subtitle: 'Real conflict protection',
                        onTap: () => _choose(context, SyncMode.obsidianVault),
                      ),
                    ],
                  ),
                ),
                Text('No cloud. No account. Just you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: wInkDim)),
                const SizedBox(height: 4),
                Text('iPhone only. Works with a Linux or Mac desktop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: wInkDim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadlinePoint extends StatelessWidget {
  final IconData? icon;
  // git-branches-only.svg for the conflicts line - the real app's own
  // git mark (stroke only, no diamond, per direct request), not a
  // generic Material icon.
  final String? assetIcon;
  final String text;
  const _HeadlinePoint({this.icon, this.assetIcon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (assetIcon != null)
            SvgPicture.asset(assetIcon!,
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(wTealDark, BlendMode.srcIn))
          else
            Icon(icon, color: wTealDark, size: 18),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 20, color: wInk)),
        ],
      ),
    );
  }
}

class _PhoneToDesktopDemo extends StatelessWidget {
  final bool delivered;
  final VoidCallback onDelivered;
  const _PhoneToDesktopDemo(
      {required this.delivered, required this.onDelivered});

  @override
  Widget build(BuildContext context) {
    final dog = _DogWithFile(delivered: delivered);
    return Stack(
      children: [
        // phone
        Positioned(
          left: 8,
          top: 46,
          child: Container(
            width: 42,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: wTealDark, width: 2.5),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    decoration: BoxDecoration(
                        color: wTealBg, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: wTealDark, width: 2)),
                  ),
                ),
              ],
            ),
          ),
        ),
        // dashed path
        const Positioned(
          left: 58,
          right: 92,
          top: 97,
          child: _DashedLine(),
        ),
        // desktop = the drop target
        Positioned(
          right: 6,
          top: 52,
          child: DragTarget<bool>(
            onAcceptWithDetails: (_) => onDelivered(),
            builder: (context, candidate, rejected) {
              final hover = candidate.isNotEmpty;
              return SizedBox(
                width: 78,
                height: 60,
                child: Stack(
                  children: [
                    Positioned(
                      left: 8,
                      top: 0,
                      child: Container(
                        width: 62,
                        height: 48,
                        decoration: BoxDecoration(
                          color: hover ? wTealBg : Colors.white,
                          border: Border.all(color: wTealDark, width: 2.5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 48,
                      child: ClipPath(
                        clipper: _TrapClipper(),
                        child: Container(
                            width: 78, height: 9, color: wTealDark),
                      ),
                    ),
                    // upper-left area of the SCREEN box (which starts
                    // at x=8, not the container edge) - centered used
                    // to sit right where the dog docks and got hidden
                    // behind its face once delivered; flush-left was
                    // too tight against the screen's own border.
                    Positioned(
                      left: 14,
                      top: 6,
                      child: AnimatedOpacity(
                        opacity: delivered ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: wTeal, shape: BoxShape.circle),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // the draggable dog+file, resting near the phone
        Positioned(
          top: 70,
          left: delivered ? null : 44,
          right: delivered ? 6 : null,
          child: delivered
              ? dog
              : Draggable<bool>(
                  data: true,
                  feedback: Material(color: Colors.transparent, child: dog),
                  childWhenDragging: Opacity(opacity: 0.3, child: dog),
                  child: dog,
                ),
        ),
        // twinkling stars hinting the dog is the actionable/draggable
        // thing - gone once delivered, same "gentle hint, not a wall of
        // text" affordance idea used elsewhere in the welcome flow.
        if (!delivered) ...[
          const Positioned(
              top: 50, left: 82, child: _TwinkleStar(size: 18, delayMs: 0)),
          const Positioned(
              top: 104, left: 32, child: _TwinkleStar(size: 14, delayMs: 400)),
          const Positioned(
              top: 118, left: 96, child: _TwinkleStar(size: 12, delayMs: 800)),
          const Positioned(
              top: 78, left: 34, child: _TwinkleStar(size: 10, delayMs: 200)),
          const Positioned(
              top: 62, left: 108, child: _TwinkleStar(size: 11, delayMs: 650)),
        ],
        // above the dashed line, not at the very bottom - that's
        // already where the user's eyes are, they shouldn't have to
        // search the screen for what just happened.
        if (delivered)
          Positioned(
            left: 0,
            right: 0,
            top: 76,
            child: Text('Synced! Just like that.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: wTealDark)),
          ),
      ],
    );
  }
}

class _TwinkleStar extends StatefulWidget {
  final double size;
  final int delayMs;
  const _TwinkleStar({required this.size, required this.delayMs});

  @override
  State<_TwinkleStar> createState() => _TwinkleStarState();
}

class _TwinkleStarState extends State<_TwinkleStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "not sparkling" - a plain opacity fade doesn't read as a twinkle.
    // Real sparkle needs a size pulse alongside the brightness pulse,
    // plus a slow spin - that combination is what actually reads as
    // "sparkling" rather than "fading."
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(curved),
      child: ScaleTransition(
        scale: Tween(begin: 0.6, end: 1.15).animate(curved),
        child: RotationTransition(
          turns: Tween(begin: -0.05, end: 0.05).animate(curved),
          // the real app's own accent green (kGreen, respects the
          // active skin) - not the welcome flow's own dark teal, which
          // is a different colour despite being in the same family.
          child: Icon(Icons.auto_awesome, color: kGreen, size: widget.size),
        ),
      ),
    );
  }
}

class _DogWithFile extends StatelessWidget {
  final bool delivered;
  const _DogWithFile({required this.delivered});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: wTealDark.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: CustomPaint(size: const Size(52, 52), painter: _DogFacePainter()),
          ),
          if (!delivered)
            Positioned(
              right: -8,
              bottom: -6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: wTealDark.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                // an actual file glyph (folded-corner page), not a plain
                // rectangle - matches the traveler icon used on the
                // preview screens for the same "this is a file" idea.
                child: Icon(Icons.insert_drive_file_outlined,
                    color: wTealDark, size: 14),
              ),
            ),
        ],
      ),
    );
  }
}

// Small round dog face - angular pointed ears (not round) so it reads
// as a dog, not a bear; a real, verified-live fix from earlier feedback.
class _DogFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    Offset p(double x, double y) => Offset(x * s, y * s);

    final earPaint = Paint()..color = wTealDark;
    canvas.drawPath(
        Path()
          ..moveTo(p(2, 16).dx, p(2, 16).dy)
          ..lineTo(p(12, 1).dx, p(12, 1).dy)
          ..lineTo(p(17, 17).dx, p(17, 17).dy)
          ..close(),
        earPaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(38, 16).dx, p(38, 16).dy)
          ..lineTo(p(28, 1).dx, p(28, 1).dy)
          ..lineTo(p(23, 17).dx, p(23, 17).dy)
          ..close(),
        earPaint);

    canvas.drawCircle(p(20, 19), 16 * s, Paint()..color = wTeal);
    canvas.drawOval(
        Rect.fromCenter(center: p(20, 28), width: 20 * s, height: 16 * s),
        Paint()..color = wCream);

    final darkDot = Paint()..color = wInk;
    canvas.drawCircle(p(14, 17), 2.2 * s, darkDot);
    canvas.drawCircle(p(26, 17), 2.2 * s, darkDot);
    canvas.drawOval(
        Rect.fromCenter(center: p(20, 26), width: 6 * s, height: 4.8 * s),
        darkDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(double.infinity, 2), painter: _DashPainter());
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = wTealDark.withValues(alpha: 0.3)
      ..strokeWidth = 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + 5, 1), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrapClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.1, 0)
      ..lineTo(size.width * 0.9, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _PathCard extends StatelessWidget {
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String tag;
  final Color tagBg;
  final Color tagFg;
  final String subtitle;
  final VoidCallback onTap;
  const _PathCard({
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.tag,
    required this.tagBg,
    required this.tagFg,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(
                    title.contains('Obsidian')
                        ? Icons.auto_stories_rounded
                        : Icons.folder_outlined,
                    color: iconFg,
                    size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: wInk)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                              color: tagBg, borderRadius: BorderRadius.circular(4)),
                          child: Text(tag,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: tagFg)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: wInkDim)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: wInkDim),
            ],
          ),
        ),
      ),
    );
  }
}

// Small phone/desktop device icons, shared by the preview screens so
// their illustrations echo this screen's own phone-to-desktop demo
// instead of standing alone - direct feedback: an illustration that
// "doesn't inform or remain consistent with the ease of the user
// syncing device1 to device2."
class MiniPhoneIcon extends StatelessWidget {
  final Color color;
  final Color screenColor;
  const MiniPhoneIcon({super.key, required this.color, required this.screenColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 2.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(5, 7, 5, 0),
              decoration: BoxDecoration(
                  color: screenColor, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

class MiniDesktopIcon extends StatelessWidget {
  final Color color;
  const MiniDesktopIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 58,
      child: Stack(
        children: [
          Positioned(
            left: 7,
            top: 0,
            child: Container(
              width: 62,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: color, width: 2.5),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 46,
            child: ClipPath(
              clipper: _MiniTrapClipper(),
              child: Container(width: 76, height: 9, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrapClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.1, 0)
      ..lineTo(size.width * 0.9, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Phone -> one traveling item -> desktop, looping automatically. Direct
// fix for real feedback: "I see 5 images in the middle of the screen,
// but it doesn't tell me a story" - one clear moving element on a
// visible path reads as "your stuff moves from phone to desktop" far
// better than several static icons with no motion cue. Same phone/
// desktop devices as the hero demo, so it's the same story continued,
// not a new one.
class PhoneToDesktopFlow extends StatefulWidget {
  final Color color;
  final Color screenColor;
  final IconData travelerIcon;
  const PhoneToDesktopFlow({
    super.key,
    required this.color,
    required this.screenColor,
    required this.travelerIcon,
  });

  @override
  State<PhoneToDesktopFlow> createState() => _PhoneToDesktopFlowState();
}

class _PhoneToDesktopFlowState extends State<PhoneToDesktopFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Real sync is bi-directional (SyncService has both pull() and
    // push()) - but a single item gliding back and forth read as
    // "ambiguous" (direct feedback). Now: the item travels to one
    // device and disappears INTO it, then a different item emerges
    // from that device and disappears into the other - two distinct
    // one-way trips, not one item bouncing.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pathWidth = 130.0;
    return SizedBox(
      width: 40 + 14 + pathWidth + 14 + 76,
      height: 90,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 0,
            top: 8,
            child: MiniPhoneIcon(color: widget.color, screenColor: widget.screenColor),
          ),
          Positioned(
            left: 40 + 14,
            top: 43,
            child: SizedBox(
              width: pathWidth,
              height: 2,
              child: CustomPaint(
                  painter: _ShortDashPainter(
                      color: widget.color.withValues(alpha: 0.35))),
            ),
          ),
          Positioned(
            right: 0,
            top: 16,
            child: MiniDesktopIcon(color: widget.color),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              const xStart = 54.0; // 40 + 14, item's left edge at rest
              const xEnd = 156.0; // 40 + 14 + pathWidth - 28
              final t = _ctrl.value;
              double local;
              double dir; // +1 outbound (phone->desktop), -1 return
              if (t < 0.4) {
                local = t / 0.4;
                dir = 1;
              } else if (t < 0.5) {
                return const SizedBox.shrink(); // gap between trips
              } else if (t < 0.9) {
                local = (t - 0.5) / 0.4;
                dir = -1;
              } else {
                return const SizedBox.shrink(); // gap between trips
              }
              local = Curves.easeInOut.transform(local);
              final x =
                  dir > 0 ? xStart + (xEnd - xStart) * local : xEnd + (xStart - xEnd) * local;
              // emerges (grows/fades in) leaving one device, shrinks/
              // fades out arriving at the other - reads as "disappears
              // into the device," not a static hover between them
              const edge = 0.18;
              final vis = local < edge
                  ? local / edge
                  : (local > 1 - edge ? (1 - local) / edge : 1.0);
              return Positioned(
                left: x,
                top: 25,
                child: Transform.scale(
                  scale: 0.4 + 0.6 * vis,
                  child: Opacity(
                    opacity: vis,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: widget.color.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2)),
                          ]),
                      child: Icon(widget.travelerIcon,
                          color: widget.color, size: 16),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// A real short-dash pattern - what was here before was one continuous
// solid bar (read as "a nasty long dash," direct feedback), not
// actually dashed at all.
class _ShortDashPainter extends CustomPainter {
  final Color color;
  const _ShortDashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(x + dash, size.height / 2), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
