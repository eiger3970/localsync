// screens/pairing_screen.dart
//
// One-time pairing: enter the desktop's login password to install this
// phone's SSH key. Password is never stored - only held in this screen's
// local state for the duration of the request.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_state.dart';
import '../features/linking/linking_controller.dart';
import '../features/pairing/pairing_controller.dart';
import '../widgets/content_above_drag_canvas.dart';
import '../widgets/controllable_gif.dart';
import '../widgets/diag_card.dart';
import '../widgets/key_pairing_trigger.dart';
import '../widgets/shredding_password_field.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import '../services/repository_provider.dart';
import 'linking_screen.dart';

class PairingScreen extends StatefulWidget {
  final String desktopUser;
  final String desktopIp;
  const PairingScreen({
    super.key,
    required this.desktopUser,
    required this.desktopIp,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final PairingController _ctrl;
  final _passwordCtrl = TextEditingController();
  final _shredKey = GlobalKey<ShreddingPasswordFieldState>();

  @override
  void initState() {
    super.initState();
    _ctrl = PairingController(
      desktopUser: widget.desktopUser,
      desktopIp:   widget.desktopIp,
    );
    _ctrl.addListener(_onChange);
    _passwordCtrl.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _ctrl.result;

    if (result is StepSuccess) {
      // 2026-08-16: "what if a vault is already setup?" - this screen is
      // also reached from the home screen's own "Pair with desktop" menu
      // ("New phone, or lost connection" - i.e. re-pairing an existing
      // setup), not just first-time setup. Unconditionally shoving the
      // user into a fresh vault-setup run after a successful re-pair
      // made no sense once a repo already exists.
      final hasExistingVault = context.read<RepositoryProvider>().repos.isNotEmpty;
      return Scaffold(
        appBar: AppBar(title: const Text('PAIR WITH DESKTOP')),
        body: _PairedSuccessView(
          hasExistingVault: hasExistingVault,
          onContinue: () => _continueToVaultSetup(context, hasExistingVault),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('PAIR WITH DESKTOP')),
      // 2026-08-16: "drag only in bottom left corner" (x3), then "messed
      // up with images now over the top area with text", then "images
      // are way down the bottom of the page... keyboard appears and now
      // I can't see the phonekey image... unable to progress" - the real
      // bug in this last round: `content` was wrapped in a
      // SingleChildScrollView, which does NOT shrink-wrap to its child's
      // natural height - it fills whatever height it's given. That made
      // ContentAboveDragCanvas measure almost the *entire available
      // screen* as "content height" rather than the real (short) text
      // height, and that available height itself shrinks when the
      // keyboard opens - which is exactly why the canvas tracked
      // keyboard state instead of actual content size. Plain Column,
      // no ScrollView - the measurement is real now.
      body: SafeArea(
        child: ContentAboveDragCanvas(
          // 2026-08-16: "missing the number 2 on the left" (restored -
          // dropping it two rounds ago was a real regression, not
          // requested) then "moving phonekey to the right will allow
          // badge 2 to be on the left of the 2 images" - the badge now
          // lives inside KeyPairingTrigger itself via leadingBadge, so it
          // can be pixel-aligned to the key/lock's actual rest row
          // instead of positioned externally by guesswork.
          canvas: KeyPairingTrigger(
            enabled: !_ctrl.isRunning && _passwordCtrl.text.isNotEmpty,
            onConfirm: _pair,
            leadingBadge: const _StepBadge(2),
          ),
          content: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect to ${widget.desktopUser}@${widget.desktopIp}',
                  style: const TextStyle(
                      color: kStar, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                // 2026-08-16: "this is verbose and needs to be
                // simplified. Can you design an infographic for
                // this workflow process?" - replaced the
                // type-once/never-stored paragraph with a 3-step
                // icon strip. No new asset pipeline needed (reuses
                // Material icons in the app's existing palette) -
                // glanceable in one look instead of a sentence to
                // parse.
                const _PasswordWorkflowStrip(),
                const SizedBox(height: 24),
                // 2026-08-16: "1 is not on same line as text" - badge
                // was top-aligned against a field whose label sits
                // vertically centered when empty, not flush with the
                // top. Center alignment instead.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _StepBadge(1),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ShreddingPasswordField(
                        key: _shredKey,
                        controller: _passwordCtrl,
                        enabled: !_ctrl.isRunning,
                      ),
                    ),
                  ],
                ),
                // 2026-08-16: wrapped as one single Keyed block
                // (rather than loose conditional children) after
                // finding a real bug elsewhere this session where
                // an unkeyed conditional sibling shifting list
                // position confused Flutter's element
                // reconciliation mid-gesture - defensive fix for
                // the reported "vertical red line" artifact left
                // behind after this box disappears on retry.
                if (result is StepFailure)
                  Column(
                    key: const ValueKey('failureBox'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      // 2026-08-16: was a bespoke Container using
                      // kTextDim at 14px for the resolution text -
                      // direct feedback that it was "too small and
                      // dark to read." Switched to the same DiagCard
                      // used everywhere else in the app (kStar, 15px,
                      // 1.7 line height) instead of inventing a
                      // dimmer, harder-to-read variant just for this
                      // screen.
                      DiagCard(
                        label: 'WHAT HAPPENED',
                        text: result.diagnosis,
                        accent: Colors.redAccent,
                      ),
                      const SizedBox(height: 12),
                      DiagCard(
                        label: 'HOW TO FIX IT',
                        text: result.resolution,
                        accent: kGreen,
                      ),
                      // 2026-08-16: guards against both null AND an
                      // empty/whitespace-only debugDetail - real device
                      // feedback showed the "Raw error" label with
                      // nothing underneath it, which a bare null-check
                      // wouldn't have caught if the underlying
                      // exception's toString() ever comes back blank.
                      if (result.debugDetail != null &&
                          result.debugDetail!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DiagCard(
                          label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
                          text: result.debugDetail!,
                          accent: Colors.redAccent,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pair() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;
    final shredding = _shredKey.currentState?.shred();
    if (shredding != null) unawaited(shredding);
    await _ctrl.pairWithPassword(password);
  }

  void _continueToVaultSetup(BuildContext context, bool hasExistingVault) {
    if (hasExistingVault) {
      // Re-pairing an already-set-up phone - just return to the vault,
      // nothing left to set up.
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    final linkingCtrl = context.read<LinkingController>();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LinkingScreen()),
    );
    // Kicks off immediately rather than landing on another idle screen
    // with its own START button - user just finished one setup step,
    // don't make them find and tap a second one.
    linkingCtrl.startLinking();
  }
}

// ── Password workflow, as a glance not a paragraph ──────────────────────────
//
// 2026-08-16: replaces "Enter your desktop login password once, just to
// install this phone's key. The desktop login password is never stored -
// only used for this one connection." Three icons read left to right:
// type it -> it installs a key -> it's never kept.
//
// 2026-08-16, revised: "NEVER STORED implies the INSTALLS KEY is never
// stored, but you need to refer to the password" - correct read: the KEY
// is the thing that persists (stays installed on the desktop), the
// PASSWORD is the thing that doesn't. Bookending both end labels with
// "PASSWORD" makes the subject of "never stored" unambiguous regardless
// of which icon it's sitting next to.
class _PasswordWorkflowStrip extends StatelessWidget {
  const _PasswordWorkflowStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _step(const Icon(Icons.password_rounded, color: kGreen, size: 26),
            'TYPE PASSWORD'),
        _arrow(),
        // 2026-08-16: "change image to pairing_phone_key.svg" - the
        // actual key asset used in the drag gesture, not a generic
        // Material key glyph.
        _step(
          SvgPicture.asset('assets/pairing/pairing_phone_key.svg',
              width: 30, colorFilter: const ColorFilter.mode(kGreen, BlendMode.srcIn)),
          'INSTALLS KEY',
        ),
        _arrow(),
        _step(const Icon(Icons.block_rounded, color: kGreen, size: 26),
            'PASSWORD NEVER STORED'),
      ],
    );
  }

  Widget _step(Widget icon, String label) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(height: 26, child: Center(child: icon)),
          const SizedBox(height: 8),
          // 2026-08-16: "text is too small and dark" - 9px kTextDim was
          // genuinely hard to read; bumped to 11px kTextMid, same
          // readability bar as the DiagCard fix earlier this session.
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kTextMid, fontSize: 11, letterSpacing: 0.6, height: 1.3)),
        ],
      ),
    );
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Icon(Icons.arrow_forward_rounded, color: kTextDim, size: 16),
      );
}

// ── Step number, no sentence needed ─────────────────────────────────────────
//
// 2026-08-16: replaces a full instruction sentence per direct feedback
// ("text is too verbose, users prefer images... perhaps 1 of 2 left of
// password and 2 of 2 left of the images"). Just a plain numbered marker -
// the password field and the key/lock graphic explain themselves.
class _StepBadge extends StatelessWidget {
  final int number;
  const _StepBadge(this.number);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kGreen, width: 1.4),
      ),
      child: Text('$number',
          style: const TextStyle(
              color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Big, unmissable pairing success ─────────────────────────────────────────
//
// 2026-08-09: the previous success state was a single small teal line
// ("Paired", 14px) easy to miss entirely when scanning a stressed,
// error-fatigued screen - the user reported overlooking it outright and
// being left not knowing what to do next. Full-screen, high-contrast,
// with one obvious next action.
class _PairedSuccessView extends StatelessWidget {
  final VoidCallback onContinue;
  // 2026-08-16: "what if a vault is already setup?" - this screen is
  // also reached by re-pairing an existing setup (home screen's "Pair
  // with desktop" menu, "New phone, or lost connection"), not just
  // first-time setup - copy and the next action both need to reflect
  // that instead of always assuming a fresh vault is about to be built.
  final bool hasExistingVault;
  const _PairedSuccessView(
      {required this.onContinue, required this.hasExistingVault});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 2026-08-16: replaced the generic checkmark with the same
          // success-dog gif already used for the "Your notes have
          // arrived!" moment in linking_screen.dart - one consistent
          // mascot for "this step is done," not a plain Material icon.
          const ControllableGif(
            assetPath: 'assets/gifs/dog_success_stand.gif',
            playing: true,
            height: 88,
            frameDurationOverrides: {
              4: Duration(milliseconds: 700),
              5: Duration(milliseconds: 50),
            },
          ),
          const SizedBox(height: 24),
          Text(hasExistingVault ? 'Reconnected!' : 'Paired!',
              style: const TextStyle(
                  color: kStar, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            hasExistingVault
                ? 'Your phone is trusted by your desktop again. Your vault is already set up - nothing else to do.'
                : 'Your phone is now trusted by your desktop.',
            style: const TextStyle(color: kTextMid, fontSize: 15, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // 2026-08-16: plain tap ElevatedButton replaced with the same
          // dog-on-a-leash swipe-to-confirm control used for the other
          // "confirm and move on" moments in the app (vault creation,
          // leaving setup) - one consistent confirm gesture instead of
          // this screen being the only one still using a tap button.
          // Kept a label (unlike those two) since this is a standalone
          // screen with no preceding checklist step already implying
          // "now swipe."
          SwapGifSwipeConfirm(
            animatedAssetPath: 'assets/gifs/progress_running.gif',
            label: hasExistingVault ? 'SWIPE TO CONTINUE' : 'SWIPE TO SET UP VAULT',
            onConfirm: onContinue,
          ),
        ],
      ),
    );
  }
}
