// screens/linking_screen.dart
//
// UI for the vault setup sequence (see linking_controller.dart).
// One park point — opening Obsidian's vault picker — shows plain
// instructions, no tech language. Error screen shows plain diagnosis +
// exact fix steps.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_state.dart';
import '../features/linking/linking_controller.dart';
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
                    LinkingStep.complete => const _CompleteView(),
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
          const Text(
            'synclocal will download your notes and connect them '
            'to your desktop.\n\n'
            'You will need Obsidian installed.\n\n'
            'At the end you will point Obsidian at the downloaded '
            'folder — instructions will be clear.',
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _PrimaryButton(
            label: 'START',
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
      LinkingStep.awaitingObsidianVaultOpen => 'Open your vault',
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
                  fontSize: 14,
                  height: 2.0),
            ),
          ),
          const SizedBox(height: 14),

          // Reassurance line
          const Text(
            'synclocal is waiting — iOS needs a moment between steps.',
            style: TextStyle(
                color: kTextDim,
                fontSize: 10,
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 32),

          _PrimaryButton(
            label: 'DONE — CONTINUE',
            onPressed: ctrl.confirmParkedActionComplete,
          ),
        ],
      ),
    );
  }
}

// ── Complete ───────────────────────────────────────────────────────────────────

class _CompleteView extends StatelessWidget {
  const _CompleteView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, color: kTeal, size: 64),
          const SizedBox(height: 24),
          const Text('You\'re connected',
              style: TextStyle(
                  color: kStar,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          const Text(
            'Your phone vault is linked to your desktop.\n\n'
            'synclocal will keep them in sync automatically.',
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _PrimaryButton(
            label: 'DONE',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
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
          const SizedBox(height: 32),

          if (failure.error == LinkingError.pairingNotComplete) ...[
            _PrimaryButton(
              label: 'PAIR NOW',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PairingScreen(
                    desktopUser: 'rapi5',
                    desktopIp:   '172.20.10.6',
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
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  color: kStar,
                  fontSize: 12,
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
