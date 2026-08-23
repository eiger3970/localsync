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
import '../services/database_service.dart';
import '../services/discovery_service.dart';
import '../services/repository_provider.dart';
import 'linking_screen.dart';

class PairingScreen extends StatefulWidget {
  final String desktopUser;
  final String desktopIp;
  // 2026-08-23: real feedback, live - "why not just take the user to
  // the pair page, then back to the setup?" User had already done the
  // drag-to-set-up gesture once (that's what triggered the "not paired
  // yet" failure in the first place) - landing back on the idle view
  // after pairing meant repeating an action already taken, not seeing
  // it for the first time. True only when reached via LinkingScreen's
  // "PAIR NOW" button (a setup attempt that failed specifically because
  // pairing wasn't done yet); false for the kebab menu's standalone
  // "Pair with desktop" entry, where there's no interrupted setup to
  // resume and the 2026-08-17 idle-view reasoning below still applies.
  final bool autoResumeSetup;
  const PairingScreen({
    super.key,
    required this.desktopUser,
    required this.desktopIp,
    this.autoResumeSetup = false,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  // 2026-08-23: not `final` anymore - _findAndRetry() below needs to
  // rebuild this against a freshly-discovered IP.
  late PairingController _ctrl;
  final _passwordCtrl = TextEditingController();
  final _shredKey = GlobalKey<ShreddingPasswordFieldState>();
  final _discovery = DiscoveryService();
  bool _discovering = false;

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
      // 2026-08-16: "the WHAT HAPPENED and HOW TO FIX IT text is below,
      // then the keyboard is below, so there's no hope of me progressing
      // as I can't drag the phonekey" - once a failure box lengthens the
      // content AND the keyboard is open at the same time, the canvas can
      // shrink to a genuinely tiny sliver. KeyPairingTrigger already
      // dismisses the keyboard once a drag *starts*, but a drag needs
      // real finger movement to register at all - a plain tap on a
      // barely-visible sliver does nothing. A tap-anywhere-to-dismiss
      // GestureDetector (a plain tap, not a pan, so it doesn't compete
      // with the drag gesture) gives an always-available way to reclaim
      // the screen before the canvas is even reachable.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
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
                  // 2026-08-23: reads the live controller's IP, not
                  // widget.desktopIp - the latter stays frozen at
                  // whatever was passed in originally, so it would
                  // keep showing the stale address even after
                  // _findAndRetry() corrects it.
                  'Connect to ${widget.desktopUser}@${_ctrl.desktopIp}',
                  style: TextStyle(
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
                      // 2026-08-21: same fix as every other HOW TO FIX
                      // IT card in the app - "check all text which is
                      // verbose, change to point form."
                      DiagCard(
                        label: 'HOW TO FIX IT',
                        text: result.resolution,
                        accent: kGreen,
                        icon: Icons.lightbulb_outline,
                        bulleted: true,
                      ),
                      // 2026-08-23: real feedback, live - same auto-
                      // discovery gap as LinkingScreen's failure view,
                      // but this is the screen where connectionRefused
                      // actually happens first for most users (the
                      // very first line of pairWithPassword is a raw
                      // socket connect, before password is ever used).
                      if (result.error == LinkingError.connectionRefused) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _discovering ? null : _findAndRetry,
                            icon: _discovering
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kGreen),
                                  )
                                : Icon(Icons.wifi_find, color: kGreen, size: 18),
                            label: Text(
                                _discovering
                                    ? 'LOOKING FOR DESKTOP…'
                                    : 'FIND DESKTOP AUTOMATICALLY',
                                style: TextStyle(
                                    color: kGreen, fontSize: 13, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: kGreen),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
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
                          maxLength: 300,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
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

  // 2026-08-23: real feedback, live - same gap as LinkingScreen's
  // failure view, but this is the screen where connectionRefused
  // actually surfaces first (the very first line of pairWithPassword
  // is a raw socket connect, before any password is used - see
  // pairing_controller.dart). Discovers + persists the real IP, then
  // rebuilds _ctrl against it - does NOT auto-retry pairing itself,
  // since the password field is shredded (cleared) after every attempt
  // by design (never cached) - the user still re-enters it themselves,
  // now against the corrected address.
  Future<void> _findAndRetry() async {
    setState(() => _discovering = true);
    final ip = await _discovery.findDesktopIp();
    if (!mounted) return;
    setState(() => _discovering = false);
    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurface,
          content: Text(
            'No desktop found - check your phone\'s hotspot is on, or a '
            'USB cable is plugged in between phone and desktop, then '
            'try again',
            style: TextStyle(color: kStar, fontSize: 14),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    await DatabaseService().setDesktopIp(ip);
    if (!mounted) return;
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    setState(() {
      _ctrl = PairingController(desktopUser: widget.desktopUser, desktopIp: ip);
      _ctrl.addListener(_onChange);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSurface,
        content: Text('Found desktop at $ip - re-enter your password to retry',
            style: TextStyle(color: kStar, fontSize: 14)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _continueToVaultSetup(BuildContext context, bool hasExistingVault) {
    if (hasExistingVault) {
      // Re-pairing an already-set-up phone - just return to the vault,
      // nothing left to set up.
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    // 2026-08-17: no longer auto-calls startLinking() here by default.
    // That was meant to save a second tap, but it skipped straight past
    // LinkingScreen's idle view - the drag-and-drop-the-desktop-onto-
    // the-vault gesture that's the actual, expected first step of
    // setup, for a user who has never attempted it. If checkingPairing
    // then failed fast (a network blip, or an iOS permission prompt
    // getting dismissed), the user landed straight on the failure
    // screen having never seen that step at all.
    //
    // 2026-08-17 (second pass): real device bug - LinkingController is a
    // singleton provided at app root (main.dart), not re-created per
    // screen. If an earlier drag attempt (before this pairing) already
    // failed with "not paired yet", that failure state was still sitting
    // in the controller - landing back on a fresh LinkingScreen showed
    // that STALE failure immediately, before the user ever saw the idle
    // view. reset() clears it so idle view is what actually shows.
    final ctrl = context.read<LinkingController>();
    ctrl.reset();
    // 2026-08-23: real feedback, live - "why not just take the user to
    // the pair page, then back to the setup?" autoResumeSetup is true
    // specifically when the user already did the idle-view drag once
    // (that's what surfaced the pairing failure) - resuming the same
    // attempt here means they never have to repeat that gesture. The
    // 2026-08-17 concern above (skipping the idle view for someone who
    // has never seen it) doesn't apply in this path, since they have.
    if (widget.autoResumeSetup) {
      unawaited(ctrl.startLinking());
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LinkingScreen()),
    );
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
    // 2026-08-23: real feedback, live - "TYPE PASSWORD" was an
    // imperative command while the other two labels describe the
    // process ("INSTALLS KEY" read as bad English either way - a
    // command missing its final S, or a description missing its
    // article). Only the first step is a real user action; all three
    // now consistently describe what happens, past-tense, not commands.
    return Row(
      children: [
        _step(Icon(Icons.password_rounded, color: kGreen, size: 26),
            'PASSWORD TYPED'),
        _arrow(),
        // 2026-08-16: "change image to pairing_phone_key.svg" - the
        // actual key asset used in the drag gesture, not a generic
        // Material key glyph.
        _step(
          SvgPicture.asset('assets/pairing/pairing_phone_key.svg',
              width: 30, colorFilter: ColorFilter.mode(kGreen, BlendMode.srcIn)),
          'KEY INSTALLED',
        ),
        _arrow(),
        _step(Icon(Icons.block_rounded, color: kGreen, size: 26),
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
              style: TextStyle(
                  color: kTextMid, fontSize: 11, letterSpacing: 0.6, height: 1.3)),
        ],
      ),
    );
  }

  Widget _arrow() => Padding(
        padding: const EdgeInsets.only(bottom: 20),
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
          style: TextStyle(
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
              style: TextStyle(
                  color: kStar, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            hasExistingVault
                ? 'Your phone is trusted by your desktop again. Your vault is already set up - nothing else to do.'
                : 'Your phone is now trusted by your desktop.',
            style: TextStyle(color: kTextMid, fontSize: 15, height: 1.6),
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
