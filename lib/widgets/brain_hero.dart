// widgets/brain_hero.dart
//
// 2026-09-26: welcome-screen hero - a glowing see-through brain (Blender
// render of a Royalty Free BlenderKit model, coloured by brain area).
//   idle        turns by itself; drag any direction to turn it, tap to
//               stop/start
//   success     plays once when the dog lands on the desktop: rainbow
//               stars climb the stem, the frontal lobe lights up with
//               more, brighter connections (no growing - 2026-09-27)
//   distracted  plays once when the drag misses: the frontal lobe fades
//               (fewer connections, not gone or shrunk - 2026-09-27)
// Success/distracted are animated WebP loops, then HOLD their result
// until the next swipe. Idle and both held results are grids of still
// views (see _BrainHeroState), turnable in any direction.
// Render: ~/Documents/Blender/brain_render/render_grid.sh.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum BrainMode { idle, success, distracted }

class BrainHero extends StatefulWidget {
  final BrainMode mode;
  final int playId; // bump to replay success/distracted
  final VoidCallback onDone; // called when success/distracted finishes
  final double size;
  const BrainHero(
      {super.key,
      required this.mode,
      required this.playId,
      required this.onDone,
      this.size = 130});

  @override
  State<BrainHero> createState() => _BrainHeroState();
}

class _BrainHeroState extends State<BrainHero>
    with SingleTickerProviderStateMixin {
  // 2026-09-27: Ken - "Turn brain any direction, not just horizontal
  // axis." Each turntable is now a grid of Blender views: 24 around
  // (15 deg) x 9 up/down (-90..+90 deg, 22.5 deg), frame =
  // pitch * 24 + yaw + 1 (render_brain.py BRAIN_GRID=24x9). Neighbouring
  // views are cross-faded so 15 deg steps still turn smoothly.
  // 2026-09-28: Ken - "Moving brain is jittery, add more quality." 48
  // around (7.5 deg) instead of 24 - half the jump between views.
  static const _yaws = 48;
  static const _pitches = 9;
  static const _level = 4; // pitch row facing straight on
  static const _turnSecs = 4.0; // one full idle turn
  static const _yawStep = 360.0 / _yaws; // degrees between views
  static const _pitchStep = 180.0 / (_pitches - 1);
  static const _idleDeg = 360.0 / _turnSecs; // idle turning, degrees/s
  static const _degPerPx = 1.25; // drag: degrees turned per pixel
  static const _pitchSign = 1.0; // flip if dragging down tilts the wrong way
  static String _frame(String set, int yaw, int pitch) {
    final i = pitch * _yaws + (yaw % _yaws) + 1;
    return 'assets/brain/grid_$set/${i.toString().padLeft(4, '0')}.webp';
  }

  // Which turntable is showing: idle, or the held result.
  String? get _holdSet => !_holding
      ? null
      : widget.mode == BrainMode.success
          ? 'success_hold'
          : widget.mode == BrainMode.distracted
              ? 'distracted_hold'
              : null;
  bool get _turning => widget.mode == BrainMode.idle || _holdSet != null;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _yaw = 0; // 0.._yaws
  double _pitch = _level * 1.0; // 0.._pitches-1
  bool _paused = false;
  bool _dragging = false;
  // 2026-09-28: Ken - "User drags and lets go, that sets the speed,
  // direction and motion of the brain, rather than always returning to
  // the horizontal spin." The flick sets these; the brain keeps turning
  // that way, slowing to the idle speed (never stopping), and stays at
  // the tilt it was left at. Up/down bounces off the top/bottom views.
  // Turning velocity in degrees/s: dx = around, dy = up/down. Its
  // direction is always the user's last movement - sideways, up/down or
  // diagonal - and it never slows below idle speed.
  Offset _vel = const Offset(_idleDeg, 0);
  // Recent drag direction - a mouse usually stops before the button is
  // let go, so the release speed alone often reads 0.
  Offset _dragVec = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      final dt = (t - _last).inMicroseconds / 1e6;
      _last = t;
      if (_turning && !_paused && !_dragging) {
        setState(() {
          _yaw = (_yaw + dt * _vel.dx / _yawStep) % _yaws;
          _pitch += dt * _vel.dy / _pitchStep;
          // Up/down bounces off the top and bottom views.
          if (_pitch <= 0 || _pitch >= _pitches - 1) {
            _pitch = _pitch.clamp(0.0, _pitches - 1.0);
            _vel = Offset(_vel.dx, -_vel.dy);
          }
          // Friction: a fast flick slows down to idle speed, same
          // direction; never below idle, never back to a sideways spin.
          final m = _vel.distance;
          final k = (dt * 0.6).clamp(0.0, 1.0);
          final next = m > _idleDeg ? m + (_idleDeg - m) * k : _idleDeg;
          _vel = m > 0 ? _vel * (next / m) : const Offset(_idleDeg, 0);
        });
      }
    })
      ..start();
  }

  // Level row only (24 views, ~12 MB decoded). All 216 would be ~110 MB
  // per set - iOS already killed LocalSync once for memory (2026-09-25).
  // Tilted views load on first use; gaplessPlayback holds the last one.
  void _precache(String set) {
    for (var y = 0; y < _yaws; y++) {
      precacheImage(AssetImage(_frame(set, y, _level)), context);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precache('idle');
    // 2026-09-28: Ken - "Brain success paused before success graphics
    // began." Both result animations are decoded up front, so a sync
    // result starts playing at once instead of freezing first.
    precacheImage(const AssetImage('assets/brain/success.webp'), context);
    precacheImage(const AssetImage('assets/brain/distracted.webp'), context);
  }

  @override
  void didUpdateWidget(BrainHero old) {
    super.didUpdateWidget(old);
    if (widget.mode != BrainMode.idle && widget.playId != old.playId) {
      // Each loop is 72 frames at 24 fps = 3 s. 2026-09-27: then HOLDS
      // the result (was: back to idle straight away) - "error or success
      // still needs to rotate 360 degrees" - as its own turntable, until
      // the next swipe replays (new playId).
      final id = widget.playId;
      _holding = false;
      final set =
          widget.mode == BrainMode.success ? 'success_hold' : 'distracted_hold';
      _precache(set);
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted && widget.playId == id) {
          setState(() {
            _holding = true;
            _yaw = 0; // the loops end facing front, as the grid's yaw 0 does
            _pitch = _level * 1.0;
            _vel = const Offset(_idleDeg, 0);
          });
        }
      });
    }
  }

  bool _holding = false;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Nearest views around (_yaw, _pitch), blended by distance.
  Widget _gridView(String set) {
    final y0 = _yaw.floor(), p0 = _pitch.floor();
    final fy = _yaw - y0, fp = _pitch - p0;
    final p1 = (p0 + 1).clamp(0, _pitches - 1);
    Widget img(int y, int p, double o) => Opacity(
        opacity: o.clamp(0.0, 1.0),
        child: Image.asset(_frame(set, y, p),
            gaplessPlayback: true, fit: BoxFit.contain));
    // Bottom layer fully opaque, the next views fade in on top of it.
    final row0 = Stack(fit: StackFit.expand,
        children: [img(y0, p0, 1), img(y0 + 1, p0, fy)]);
    if (fp < 0.01 || p1 == p0) return row0;
    final row1 = Stack(fit: StackFit.expand,
        children: [img(y0, p1, 1), img(y0 + 1, p1, fy)]);
    return Stack(fit: StackFit.expand,
        children: [row0, Opacity(opacity: fp, child: row1)]);
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = switch (widget.mode) {
      _ when _turning => _gridView(_holdSet ?? 'idle'),
      BrainMode.success => Image.asset('assets/brain/success.webp',
          key: ValueKey('s${widget.playId}'), fit: BoxFit.contain),
      BrainMode.distracted => Image.asset('assets/brain/distracted.webp',
          key: ValueKey('d${widget.playId}'), fit: BoxFit.contain),
      BrainMode.idle => const SizedBox.shrink(), // covered by _turning
    };
    return GestureDetector(
      onTap: () => setState(() => _paused = !_paused),
      // Any direction: sideways turns, up/down tilts, diagonal does both.
      onPanStart: (_) => _dragging = true,
      onPanUpdate: (d) => setState(() {
        final px = Offset(d.delta.dx, _pitchSign * d.delta.dy);
        if (px.distance > 0.5) _dragVec = _dragVec * 0.6 + px * 0.4;
        _yaw = (_yaw + px.dx * _degPerPx / _yawStep) % _yaws;
        _pitch = (_pitch + px.dy * _degPerPx / _pitchStep)
            .clamp(0.0, _pitches - 1.0);
      }),
      onPanEnd: (d) {
        final v = d.velocity.pixelsPerSecond;
        final flick = Offset(v.dx, _pitchSign * v.dy) * _degPerPx;
        if (flick.distance > _idleDeg) {
          // A real flick: its own speed and direction, capped.
          _vel = flick.distance > _idleDeg * 6
              ? flick * (_idleDeg * 6 / flick.distance)
              : flick;
        } else if (_dragVec.distance > 0) {
          // Slow let-go: idle speed, in the direction last dragged.
          _vel = _dragVec * (_idleDeg / _dragVec.distance);
        }
        _dragVec = Offset.zero;
        _dragging = false;
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [Color(0xFF1A1640), Color(0xFF03020A)]),
        ),
        child: image,
      ),
    );
  }
}
