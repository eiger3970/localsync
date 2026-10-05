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
// Idle, success and distracted are each a grid of still views (see
// _BrainHeroState), turnable in any direction. 2026-09-29: user - "the
// brain in all states of standard, error or success, to continue in
// whatever the last momentum is set by the user." Success/distracted no
// longer play a fixed pre-rendered clip (always a sideways turn, then a
// jump to front/back); the brain cross-fades into the result at the
// angle it's already at and keeps turning the way it was going. Only a
// tap stops it.
// Render: ~/Documents/Blender/brain_render/render_grid.sh.
import 'dart:math' as math;
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
  // 2026-09-27: user - "Turn brain any direction, not just horizontal
  // axis." Each turntable is now a grid of Blender views: 24 around
  // (15 deg) x 9 up/down (-90..+90 deg, 22.5 deg), frame =
  // pitch * 24 + yaw + 1 (render_brain.py BRAIN_GRID=24x9). Neighbouring
  // views are cross-faded so 15 deg steps still turn smoothly.
  // 2026-09-28: user - "Moving brain is jittery, add more quality." 48
  // around (7.5 deg) instead of 24 - half the jump between views.
  static const _yaws = 96;
  static const _pitches = 9;
  static const _level = 4; // pitch row facing straight on
  static const _turnSecs = 4.0; // one full idle turn
  static const _yawStep = 360.0 / _yaws; // degrees between views
  static const _pitchStep = 180.0 / (_pitches - 1);
  static const _idleDeg = 360.0 / _turnSecs; // idle turning, degrees/s
  static const _degPerPx = 1.25; // drag: degrees turned per pixel
  static const _pitchSign = 1.0; // flip if dragging down tilts the wrong way
  // 2026-10-04: user - "stops turning upside down and won't spin 360".
  // Tilt now wraps all the way round: 16 steps of 22.5 deg. Past the top
  // or bottom view, the brain is the view from the other side (row
  // 16 - i, half a turn round) shown upside down - no new renders.
  static const _tilts = 2 * (_pitches - 1);
  // Upside down, turning the brain's own axis the same way moves it the
  // other way on screen - so sideways drag and spin flip sign there, and
  // the brain keeps following the finger (user: "doesn't follow my drag").
  // 2026-10-05: user - "after a while the brain starts spinning the opposite
  // direction". The sign flipped as soon as the tilt passed row 8.0, but the
  // upside-down picture only takes over at 8.5 (rows cross-fade), so for half
  // a step at every pass over the top/bottom the spin ran backwards on screen.
  // Flip with the picture that's actually showing (nearest row).
  double get _yawSign => _pitch.round() % _tilts > _pitches - 1 ? -1.0 : 1.0;

  static (int, int, bool) _rowOf(int tilt) {
    final i = tilt % _tilts;
    return i <= _pitches - 1 ? (i, 0, false) : (_tilts - i, _yaws ~/ 2, true);
  }
  static String _frame(String set, int yaw, int pitch) {
    final i = pitch * _yaws + (yaw % _yaws) + 1;
    return 'assets/brain/grid_$set/${i.toString().padLeft(4, '0')}.webp';
  }

  static String _setFor(BrainMode m) => switch (m) {
        BrainMode.idle => 'idle',
        BrainMode.success => 'success_hold',
        BrainMode.distracted => 'distracted_hold',
      };
  static const _fadeSecs = 1.2; // idle -> result cross-fade
  static const _pivotY = 0.1185; // spin pivot, below picture centre (see row())

  // Turntable showing, and the one fading in over it (null = no fade).
  String _set = 'idle';
  String? _nextSet;
  double _fade = 0; // 0.._fadeSecs

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  // 2026-09-29: user - "Brain needs more success activity ... a pulsating
  // glow." Picked option D of the previews: white light breathing
  // inside the circle, around the brain, every 1.6 s while success shows.
  double _pulseT = 0; // seconds
  static const _pulseSecs = 1.6;
  double _yaw = 0; // 0.._yaws
  double _pitch = _level * 1.0; // 0.._tilts, wraps (see _rowOf)
  bool _paused = false;
  bool _dragging = false;
  // 2026-09-28: user - "User drags and lets go, that sets the speed,
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
      if (widget.mode == BrainMode.success) {
        setState(() => _pulseT = (_pulseT + dt) % _pulseSecs);
      }
      if (_nextSet != null) {
        setState(() {
          _fade += dt;
          if (_fade >= _fadeSecs) {
            _set = _nextSet!;
            _nextSet = null;
            _fade = 0;
          }
        });
      }
      if (!_paused && !_dragging) {
        setState(() {
          _yaw = (_yaw + _yawSign * dt * _vel.dx / _yawStep) % _yaws;
          _pitch = (_pitch + dt * _vel.dy / _pitchStep) % _tilts;
          // Friction: a fast flick slows down to idle speed, same
          // direction; never below idle, never back to a sideways spin.
          final m = _vel.distance;
          final k = (dt * 0.6).clamp(0.0, 1.0);
          final next = m > _idleDeg ? m + (_idleDeg - m) * k : _idleDeg;
          _vel = m > 0 ? _vel * (next / m) : const Offset(_idleDeg, 0);
        });
      }
      _preloadRows();
    })
      ..start();
  }

  // One row of 48 views is ~25 MB decoded; all 432 would be ~224 MB per
  // set - iOS already killed LocalSync once for memory (2026-09-25).
  // 2026-09-29: user - "Brain has a little jitter." Only the level row was
  // ever preloaded, so a tilted brain decoded each view on first use - and
  // the 100 MB image cache couldn't hold them, so it kept re-decoding.
  // Now the (at most two) rows the brain is between are preloaded as it
  // tilts, for the set showing and the one fading in.
  // 2026-10-04: user - "locks up when upside down". Whole rows (96 views,
  // ~50 MB decoded each) didn't fit the 100 MB image cache two at a time,
  // and queueing views ahead made the views on screen wait behind them -
  // the old view stayed (frozen) or nothing showed (blank). Tested on the
  // desktop build with a scripted drag: only the (up to 4) views on screen
  // are requested now, and a full vertical turn shows every step.
  String _warmKey = '';
  void _preloadRows() {
    if (!mounted) return;
    final t0 = _pitch.floor(), y0 = _yaw.floor();
    final key = '$_set/${_nextSet ?? ''}/$t0/$y0';
    if (key == _warmKey) return;
    _warmKey = key;
    // 2026-10-05: user - "jumpy on vertical turn" (96x17 and 96x9 both).
    // Only the views on screen were requested, so tilting into the next
    // row showed a view not decoded yet. Now one more row and view on
    // every side too (16 views per set; 240 px views, ~0.2 MB decoded).
    for (final set in [_set, if (_nextSet != null) _nextSet!]) {
      for (var t = t0 - 1; t <= t0 + 2; t++) {
        final (r, off, _) = _rowOf(t + _tilts);
        for (var y = y0 - 1; y <= y0 + 2; y++) {
          precacheImage(AssetImage(_frame(set, y + off, r)), context);
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloadRows();
  }

  @override
  void didUpdateWidget(BrainHero old) {
    super.didUpdateWidget(old);
    if (widget.mode != old.mode || widget.playId != old.playId) {
      // Same result again (a second miss): fade in from idle so it still
      // shows. Angle and momentum are left exactly as they are.
      final target = _setFor(widget.mode);
      final showing = _nextSet ?? _set;
      _set = showing == target && target != 'idle' ? 'idle' : showing;
      _nextSet = target == _set ? null : target;
      _fade = 0;
      _preloadRows();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Nearest views around (_yaw, _pitch), blended by distance.
  Widget _gridView(String set) {
    final y0 = _yaw.floor(), t0 = _pitch.floor();
    final fy = _yaw - y0, fp = _pitch - t0;
    Widget img(int y, int p, double o) => Opacity(
        opacity: o.clamp(0.0, 1.0),
        child: Image.asset(_frame(set, y, p),
            gaplessPlayback: true, fit: BoxFit.contain));
    // Bottom layer fully opaque, the next views fade in on top of it.
    // Same widget tree at every angle (both rows, always rotated - by 0 or
    // half a turn), so no Image is rebuilt from scratch and none blanks.
    Widget row(int tilt) {
      final (r, off, flip) = _rowOf(tilt);
      // 2026-10-05: user - "like an imperfect gif loop, not spinning on a
      // central axis". The flip turned the picture round its middle, but the
      // render camera looks down 15 deg, so the brain's real centre (the spin
      // pivot) sits 11.85% of the half-height below the middle (camera at
      // (0,-5.2,1.6), 75 deg, 58 mm lens - render_brain.py). Flip round that.
      return Transform.rotate(
          angle: flip ? math.pi : 0,
          alignment: const Alignment(0, _pivotY),
          child: Stack(fit: StackFit.expand,
              children: [img(y0 + off, r, 1), img(y0 + 1 + off, r, fy)]));
    }
    return Stack(fit: StackFit.expand,
        children: [row(t0), Opacity(opacity: fp, child: row(t0 + 1))]);
  }

  // Soft white light inside the circle, behind the brain: 0.35 -> 1
  // opacity and 0.9 -> 1.08 size, and back, every [_pulseSecs]. White
  // outside the circle would vanish on the light welcome screen.
  Widget _successGlow() {
    final k = 0.5 - 0.5 * math.cos(2 * math.pi * _pulseT / _pulseSecs);
    return IgnorePointer(
      child: Opacity(
        opacity: 0.35 + 0.65 * k,
        child: Transform.scale(
          scale: 0.9 + 0.18 * k,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xBFFFFFFF),
                  Color(0x40FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0.2, 0.45, 0.68],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = _nextSet == null
        ? _gridView(_set)
        : Stack(fit: StackFit.expand, children: [
            _gridView(_set),
            Opacity(
                opacity: (_fade / _fadeSecs).clamp(0.0, 1.0),
                child: _gridView(_nextSet!)),
          ]);
    return GestureDetector(
      // Tap is the only way to stop it (and to start it again).
      onTap: () => setState(() => _paused = !_paused),
      // Any direction: sideways turns, up/down tilts, diagonal does both.
      onPanStart: (_) => _dragging = true,
      onPanUpdate: (d) => setState(() {
        final px = Offset(d.delta.dx, _pitchSign * d.delta.dy);
        if (px.distance > 0.5) _dragVec = _dragVec * 0.6 + px * 0.4;
        _yaw = (_yaw + _yawSign * px.dx * _degPerPx / _yawStep) % _yaws;
        _pitch = (_pitch + px.dy * _degPerPx / _pitchStep) % _tilts;
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
        _paused = false; // a flick means "turn", even if tapped still
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [Color(0xFF1A1640), Color(0xFF03020A)]),
        ),
        child: widget.mode == BrainMode.success
            ? Stack(fit: StackFit.expand, children: [_successGlow(), image])
            : image,
      ),
    );
  }
}
