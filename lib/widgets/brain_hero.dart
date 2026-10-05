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
  static const _idleDeg = 360.0 / _turnSecs; // idle turning, degrees/s
  static const _degPerPx = 1.25; // drag: degrees turned per pixel

  // 2026-10-05: user - "keep spinning with the momentum the user drags", on a
  // perfect axis. The brain now has a real 3D orientation (_m, 3x3) that turns
  // around the axis the drag sets (_w, degrees/s) - forever, like a real
  // object. Each frame the orientation is split into the nearest rendered
  // view (tilt row + turn) plus an on-screen roll of that picture: render
  // views are Rx(tilt) * Rz(turn) (render_brain.py, BRAIN_GRID 96x9) seen by
  // a camera at 75 deg, so any orientation = roll about the camera's view
  // axis * a view. Checked in Python: 99.4% of orientations exact, the rest
  // (top pointing into the screen) within 10 deg, no jumps on a long
  // diagonal spin. Replaces the yaw/pitch + upside-down flip, which tumbled
  // off-axis and seemed to reverse.
  static final _camF = [0.0, math.sin(75 * math.pi / 180), -math.cos(75 * math.pi / 180)];
  static final _camUp = [0.0, math.cos(75 * math.pi / 180), math.sin(75 * math.pi / 180)];
  static const _camRight = [1.0, 0.0, 0.0];

  static List<double> _axisAngle(List<double> axis, double rad) {
    final n = math.sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    if (n == 0) return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    final x = axis[0] / n, y = axis[1] / n, z = axis[2] / n;
    final c = math.cos(rad), s = math.sin(rad), t = 1 - c;
    return [t * x * x + c, t * x * y - s * z, t * x * z + s * y,
        t * x * y + s * z, t * y * y + c, t * y * z - s * x,
        t * x * z - s * y, t * y * z + s * x, t * z * z + c];
  }
  static List<double> _mul(List<double> a, List<double> b) => [
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++)
            a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
      ];
  static List<double> _rx(double a) => [1, 0, 0, 0, math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a)];
  static double _wrap(double a) => (a + math.pi) % (2 * math.pi) - math.pi;
  // Keep _m a clean rotation (rounding drifts over thousands of frames).
  static List<double> _orthonormal(List<double> m) {
    var x = [m[0], m[3], m[6]], y = [m[1], m[4], m[7]];
    double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    List<double> norm(List<double> v) { final n = math.sqrt(dot(v, v)); return [v[0] / n, v[1] / n, v[2] / n]; }
    x = norm(x);
    final d = dot(x, y);
    y = norm([y[0] - d * x[0], y[1] - d * x[1], y[2] - d * x[2]]);
    final z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]];
    return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
  }

  // Orientation -> (roll, tilt row 0..8, turn 0..96).
  void _decompose() {
    final u = [_m[2], _m[5], _m[8]];
    final qr = u[0] * _camRight[0] + u[1] * _camRight[1] + u[2] * _camRight[2];
    final qu = u[0] * _camUp[0] + u[1] * _camUp[1] + u[2] * _camUp[2];
    final now = math.atan2(qu, qr);
    (double, double, double, double)? best, fallback;
    for (final target in [math.pi / 2, -math.pi / 2]) {
      final th = _wrap(target - now);
      final w = _mul(_axisAngle(_camF, -th), _m);
      var a = math.atan2(-w[5], w[8]);
      final ok = w[8] >= -1e-9 && a.abs() <= math.pi / 2 + 1e-6;
      if (!ok) a = w[8] >= 0 ? a.clamp(-math.pi / 2, math.pi / 2) : (a > 0 ? math.pi / 2 : -math.pi / 2);
      final k = _mul(_rx(-a), w);
      final b = math.atan2(k[3], k[0]);
      final cand = (_wrap(th - _roll).abs(), th, a, b);
      if (ok) { if (best == null || cand.$1 < best.$1) best = cand; }
      else if (fallback == null || w[8] > fallback.$1) { fallback = (w[8], th, a, b); }
    }
    final (_, th, a, b) = best ?? fallback!;
    _roll = th;
    _rowF = ((a * 180 / math.pi + 90) / (180 / (_pitches - 1))).clamp(0.0, _pitches - 1.0);
    _yawF = ((b * 180 / math.pi + 35) / (360 / _yaws)) % _yaws;
  }

  // Turn the orientation by a screen-space amount: right = around the
  // camera's up axis, down = around its right axis (the brain follows the finger).
  void _turnBy(double degRight, double degDown) {
    final axis = [for (var i = 0; i < 3; i++) degRight * _camUp[i] + degDown * _camRight[i]];
    final deg = math.sqrt(degRight * degRight + degDown * degDown);
    if (deg == 0) return;
    _m = _mul(_axisAngle(axis, deg * math.pi / 180), _m);
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
  List<double> _m = _axisAngle(const [0, 0, 1], -35 * math.pi / 180); // straight-on view 1
  int _frames = 0;
  double _roll = 0, _rowF = _level * 1.0, _yawF = 0;
  // Spin: axis * speed in degrees/s, world frame. Idle = the brain's own up axis.
  List<double> _w = const [0, 0, _idleDeg];
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
          final speed = math.sqrt(_w[0] * _w[0] + _w[1] * _w[1] + _w[2] * _w[2]);
          _m = _mul(_axisAngle(_w, speed * dt * math.pi / 180), _m);
          if (++_frames % 120 == 0) _m = _orthonormal(_m);
          // Friction: a fast flick slows to idle speed on the SAME axis -
          // the momentum's direction is kept for good, never below idle.
          final k = (dt * 0.6).clamp(0.0, 1.0);
          final next = speed > _idleDeg ? speed + (_idleDeg - speed) * k : _idleDeg;
          if (speed > 0) _w = [for (final c in _w) c * next / speed];
          _decompose();
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
    final r0 = _rowF.floor(), y0 = _yawF.floor();
    final key = '$_set/${_nextSet ?? ''}/$r0/$y0';
    if (key == _warmKey) return;
    _warmKey = key;
    for (final set in [_set, if (_nextSet != null) _nextSet!]) {
      for (var r = math.max(0, r0 - 1); r <= math.min(_pitches - 1, r0 + 2); r++) {
        for (var y = y0 - 1; y <= y0 + 2; y++) {
          precacheImage(AssetImage(_frame(set, y, r)), context);
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
    final y0 = _yawF.floor(), r0 = _rowF.floor();
    final r1 = math.min(r0 + 1, _pitches - 1);
    final fy = _yawF - y0, fp = _rowF - r0;
    Widget img(int y, int p, double o) => Opacity(
        opacity: o.clamp(0.0, 1.0),
        child: Image.asset(_frame(set, y, p),
            gaplessPlayback: true, fit: BoxFit.contain));
    // Nearest views blended by distance, then the whole picture rolled
    // round the spin centre (the pivot, 11.85% below the middle).
    Widget row(int r) => Stack(fit: StackFit.expand,
        children: [img(y0, r, 1), img(y0 + 1, r, fy)]);
    return Transform.rotate(
        angle: _roll,
        alignment: const Alignment(0, _pivotY),
        child: Stack(fit: StackFit.expand,
            children: [row(r0), Opacity(opacity: fp, child: row(r1))]));
  }

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
        final px = d.delta;
        if (px.distance > 0.5) _dragVec = _dragVec * 0.6 + px * 0.4;
        _turnBy(px.dx * _degPerPx, px.dy * _degPerPx);
        _decompose();
      }),
      onPanEnd: (d) {
        // The flick sets the spin axis and speed for good (see _w).
        final v = d.velocity.pixelsPerSecond * _degPerPx;
        var s = v.distance > _idleDeg ? v : (_dragVec.distance > 0 ? _dragVec * (_idleDeg / _dragVec.distance) : Offset.zero);
        if (s.distance > _idleDeg * 6) s = s * (_idleDeg * 6 / s.distance);
        if (s != Offset.zero) {
          _w = [for (var i = 0; i < 3; i++) s.dx * _camUp[i] + s.dy * _camRight[i]];
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
