// screens/linking_screen.dart
//
// UI for the vault setup sequence (see linking_controller.dart).
// One park point — opening Obsidian's vault picker — shows plain
// instructions, no tech language. Error screen shows plain diagnosis +
// exact fix steps.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_state.dart';
import '../features/linking/linking_controller.dart';
import '../models/repository.dart';
import '../services/repository_provider.dart';
import 'pairing_screen.dart';

class LinkingScreen extends StatelessWidget {
  const LinkingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAULT SETUP'),
        leading: Consumer<LinkingController>(
          builder: (_, ctrl, __) {
            // Prevent back-nav while machine is running between park points
            final canLeave = !ctrl.isRunning ||
                ctrl.currentInstruction != null ||
                ctrl.step == LinkingStep.complete ||
                ctrl.step == LinkingStep.failed;
            return IconButton(
              icon: const Icon(Icons.close),
              onPressed: canLeave ? () => Navigator.pop(context) : null,
            );
          },
        ),
      ),
      body: Consumer<LinkingController>(
        builder: (_, ctrl, __) {
          return Column(
            children: [
              _ProgressBar(progress: ctrl.progress),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: switch (ctrl.step) {
                    LinkingStep.idle     => _IdleView(ctrl: ctrl),
                    LinkingStep.complete => _CompleteView(ctrl: ctrl),
                    LinkingStep.failed   => _FailedView(ctrl: ctrl),
                    _ when ctrl.currentInstruction != null =>
                      _ParkedView(ctrl: ctrl),
                    _ => _RunningView(ctrl: ctrl),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Progress bar ───────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, v, __) => LinearProgressIndicator(
        value: v,
        minHeight: 2,
        backgroundColor: kBorder,
        valueColor: const AlwaysStoppedAnimation<Color>(kTeal),
      ),
    );
  }
}

// ── Idle ───────────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final LinkingController ctrl;
  const _IdleView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⇄',
              style: TextStyle(fontSize: 56, color: kTextDim)),
          const SizedBox(height: 24),
          const Text('Connect your vault',
              style: TextStyle(
                  color: kStar,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          // Fixed 2026-08-09, twice same day: first for vagueness (a
          // real user proceeded without understanding this downloads
          // their actual, active desktop vault, not placeholder data).
          // Then again for order, once the flow was corrected to match
          // how Obsidian actually works on iOS - real user documentation
          // of years of working Working Copy usage showed Obsidian must
          // create its own vault folder FIRST; Synclocal downloads into
          // it SECOND, not the reverse.
          Text(
            'You will first create a new vault in Obsidian.\n\n'
            'Then this will download your notes from your desktop\n'
            '(${ctrl.desktopUser}@${ctrl.desktopIp}) into that vault.\n\n'
            'Nothing already on this phone is touched.\n\n'
            'You will need Obsidian installed - instructions will\n'
            'be clear at each step.',
            style: const TextStyle(color: kTextMid, fontSize: 15, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _PrimaryButton(
            label: 'START DOWNLOAD',
            onPressed: ctrl.startLinking,
          ),
        ],
      ),
    );
  }
}

// ── Running: autonomous step ───────────────────────────────────────────────────

class _RunningView extends StatelessWidget {
  final LinkingController ctrl;
  const _RunningView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _PulsingDots(),
          const SizedBox(height: 32),
          Text(
            ctrl.stepLabel,
            key: ValueKey(ctrl.step),
            style: const TextStyle(
                color: kStar,
                fontSize: 16,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            ctrl.stepSubtitle,
            style: const TextStyle(
                color: kTextDim,
                fontSize: 11,
                letterSpacing: 0.3,
                height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Parked: user action required ───────────────────────────────────────────────

class _ParkedView extends StatelessWidget {
  final LinkingController ctrl;
  const _ParkedView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Derive a plain heading from the current park point
    final heading = switch (ctrl.step) {
      LinkingStep.awaitingVaultCreation => 'Create your vault',
      LinkingStep.pickingVaultFolder    => 'Select your vault',
      _ => 'Your turn',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Heading
          Text(
            heading,
            style: const TextStyle(
                color: kStar,
                fontSize: 20,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Instruction card — plain language, no tech
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ctrl.currentInstruction!,
              style: const TextStyle(
                  color: kStar,
                  fontSize: 16,
                  height: 2.0),
            ),
          ),
          const SizedBox(height: 14),

          // Reassurance line
          const Text(
            'synclocal is waiting — iOS needs a moment between steps.',
            style: TextStyle(
                color: kTextDim,
                fontSize: 12,
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 32),

          if (ctrl.step == LinkingStep.awaitingVaultCreation) ...[
            _PrimaryButton(
              label: 'OPEN OBSIDIAN',
              onPressed: ctrl.openObsidianNow,
            ),
            const SizedBox(height: 12),
            _PrimaryButton(
              label: 'I\'VE CREATED IT — CONTINUE',
              onPressed: ctrl.confirmVaultCreated,
            ),
          ] else if (ctrl.step == LinkingStep.pickingVaultFolder) ...[
            _PrimaryButton(
              label: 'SELECT VAULT FOLDER',
              onPressed: ctrl.pickVaultFolder,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Complete ───────────────────────────────────────────────────────────────────
//
// Fixed 2026-08-09: reaching LinkingStep.complete never actually created a
// Repository record - RepositoryProvider.addRepository() already existed
// but nothing called it, so a fully successful link still left the home
// screen showing "No repositories". Inserted here, on arrival at this
// screen (not deferred to the DONE tap, so it happens even if the user
// backgrounds the app before tapping DONE), guarded against duplicates
// for re-runs of setup against the same desktop repo.
class _CompleteView extends StatefulWidget {
  final LinkingController ctrl;
  const _CompleteView({required this.ctrl});

  @override
  State<_CompleteView> createState() => _CompleteViewState();
}

class _CompleteViewState extends State<_CompleteView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burstCtrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveRepository());

    // 2026-08-09: first-run completion was a quiet 64px outline icon and
    // a 20px heading - user's own words, "not a very clear win... a
    // successful setup is THE major milestone." This is the one moment
    // in the whole app that deserves to feel unmistakably like an
    // achievement, not just another status screen. No new package added
    // for this (particle burst is a plain CustomPainter) - every native
    // dependency this session has cost real build-pipeline days, not
    // worth the risk for a one-off animation.
    HapticFeedback.heavyImpact();
    final rand = math.Random();
    _particles = List.generate(16, (_) {
      final angle = rand.nextDouble() * 2 * math.pi;
      final distance = 60 + rand.nextDouble() * 50;
      return _Particle(
        angle: angle,
        distance: distance,
        color: [kTeal, kStar, Colors.amber][rand.nextInt(3)],
        size: 4 + rand.nextDouble() * 5,
      );
    });
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveRepository() async {
    final provider = context.read<RepositoryProvider>();
    final ctrl     = widget.ctrl;
    final alreadySaved = provider.repos.any(
      (r) => r.remoteHost == ctrl.desktopIp && r.remotePath == ctrl.bareRepoPath,
    );
    if (alreadySaved) return;

    final vaultPath     = ctrl.pickedVaultPath;
    final vaultBookmark = ctrl.pickedVaultBookmark;
    if (vaultPath == null || vaultBookmark == null) return; // web target

    await provider.addRepository(Repository(
      name:              'Obsidian_vault',
      remoteHost:        ctrl.desktopIp,
      remoteUser:        ctrl.desktopUser,
      remotePath:        ctrl.bareRepoPath,
      remotePort:        ctrl.sshPort,
      localPath:         vaultPath,
      vaultBookmark:     vaultBookmark,
      obsidianVaultPath: 'On My iPhone/Obsidian/Synclocal',
      autoSync:          true,
      status:            SyncStatus.ok,
      lastSync:          DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: AnimatedBuilder(
              animation: _burstCtrl,
              builder: (_, __) => CustomPaint(
                painter: _BurstPainter(
                  particles: _particles,
                  progress: _burstCtrl.value,
                ),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: const Icon(Icons.check_circle,
                        color: kTeal, size: 88),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Your notes have arrived! 🎉',
              style: TextStyle(
                  color: kStar,
                  fontSize: 28,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          // Fixed 2026-08-09: this used to say "Your phone vault is
          // linked to your desktop" - overclaiming. Synclocal can only
          // verify that files were downloaded onto the phone (checked
          // in _verifySync()); it has no way to confirm Obsidian was
          // ever actually pointed at that folder - no cross-app
          // introspection on iOS. Real device feedback: a user reached
          // this screen without ever having opened the folder as a
          // vault in Obsidian ("Synclocal" never appeared in Obsidian's
          // own vault list), and the old wording had already told them
          // they were fully linked. Now honest about what's actually
          // still required, with a direct way to do it from here.
          // Rewritten 2026-08-09 alongside the vault-folder-picker
          // rework: the old copy told the user to go select the vault
          // in Obsidian "if you haven't already" - stale as of this
          // rewrite, since selecting the vault folder is now a
          // precondition of reaching this screen at all (it happens
          // before the clone, not after). This screen is reached only
          // once Synclocal already has real access to that same folder
          // Obsidian is showing.
          const Text(
            'Your notes have been downloaded into your\n'
            '"Synclocal" vault in Obsidian.',
            style: TextStyle(color: kTextMid, fontSize: 15, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _PrimaryButton(
            label: 'OPEN OBSIDIAN',
            onPressed: widget.ctrl.openObsidianNow,
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'CONTINUE TO SYNCLOCAL',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final Color  color;
  final double size;
  const _Particle({
    required this.angle,
    required this.distance,
    required this.color,
    required this.size,
  });
}

class _BurstPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1
  const _BurstPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Ease-out so particles decelerate outward, and fade in the back half.
    final travel = Curves.easeOut.transform(progress);
    final opacity = (1 - progress).clamp(0.0, 1.0);
    for (final p in particles) {
      final offset = Offset(
        center.dx + math.cos(p.angle) * p.distance * travel,
        center.dy + math.sin(p.angle) * p.distance * travel,
      );
      final paint = Paint()..color = p.color.withOpacity(opacity);
      canvas.drawCircle(offset, p.size * (1 - progress * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Failed ─────────────────────────────────────────────────────────────────────

class _FailedView extends StatelessWidget {
  final LinkingController ctrl;
  const _FailedView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final failure = ctrl.lastFailure!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Something stopped',
              style: TextStyle(
                  color: kStar,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),

          // What happened
          _DiagCard(
            label: 'WHAT HAPPENED',
            text: failure.diagnosis,
            accent: Colors.redAccent,
          ),
          const SizedBox(height: 12),

          // How to fix it
          _DiagCard(
            label: 'HOW TO FIX IT',
            text: failure.resolution,
            accent: kTeal,
          ),

          if (failure.debugDetail != null) ...[
            const SizedBox(height: 12),
            _DiagCard(
              label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
              text: failure.debugDetail!,
              accent: Colors.redAccent,
            ),
          ],
          const SizedBox(height: 32),

          if (failure.error == LinkingError.pairingNotComplete ||
              failure.error == LinkingError.sshAuthFailed) ...[
            _PrimaryButton(
              label: 'PAIR NOW',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PairingScreen(
                    desktopUser: 'rapi5',
                    desktopIp:   '172.20.10.11',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          _PrimaryButton(
            label: 'TRY AGAIN',
            onPressed: ctrl.startLinking,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL',
                  style: TextStyle(
                      color: kTextDim,
                      fontSize: 11,
                      letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagCard extends StatelessWidget {
  final String label;
  final String text;
  final Color  accent;
  const _DiagCard({
    required this.label,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  color: kStar,
                  fontSize: 15,
                  height: 1.7)),
        ],
      ),
    );
  }
}

// ── Pulsing dots ───────────────────────────────────────────────────────────────

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
          final scale = 0.4 + 0.6 * math.sin(phase * math.pi);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: kTeal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Primary button ─────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String       label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kTeal,
          foregroundColor: kVoid,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2),
        ),
        child: Text(label),
      ),
    );
  }
}
