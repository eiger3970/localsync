// screens/linking_screen.dart
//
// UI for the vault setup sequence (see linking_controller.dart).
// One park point — opening Obsidian's vault picker — shows plain
// instructions, no tech language. Error screen shows plain diagnosis +
// exact fix steps.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../features/linking/linking_state.dart';
import '../features/linking/linking_controller.dart';
import '../models/repository.dart';
import '../services/database_service.dart';
import '../services/discovery_service.dart';
import '../services/repository_provider.dart';
import '../features/pairing/pairing_controller.dart';
import '../widgets/content_above_drag_canvas.dart';
import '../widgets/pulsing_glow.dart';
import '../widgets/controllable_gif.dart';
import '../widgets/diag_card.dart';
import '../widgets/git_install_consent.dart';
import '../widgets/key_pairing_trigger.dart';
import '../widgets/shredding_password_field.dart';
import '../widgets/sparkle_background.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import 'home_screen.dart';
import 'pairing_screen.dart';
import 'settings_screen.dart';

// 2026-08-17: real device crash - "I tap X and app stays stuck in a
// black screen" / "I swiped right [LOCALSYNC HOME] and blackscreen".
// Root cause: home_screen.dart's empty-repos auto-redirect uses
// pushReplacement, so when LinkingScreen is reached that way it has
// nothing beneath it in the navigation stack. A bare Navigator.pop()
// (the X button, LOCALSYNC HOME's confirm, and the failed screen's
// CANCEL all did this) then pops into a void - a real dead end, not a
// recoverable state (matches "force closed the app, reopened" being
// the only way out). canPop() first, falling back to a fresh
// HomeScreen if there's nothing to pop to - which will show the real
// home screen once setup succeeded (repos is no longer empty) instead
// of bouncing back into this screen.
void _leaveSetup(BuildContext context) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }
}

class LinkingScreen extends StatelessWidget {
  const LinkingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 2026-08-27: mode-aware - a Tier 0 choice from SyncChoiceScreen
        // shouldn't still land on "PKM VAULT SETUP", the exact framing
        // that choice exists to avoid seeing at all.
        title: Consumer<LinkingController>(
          builder: (_, ctrl, __) => Text(
            ctrl.preferredMode == SyncMode.genericFolder
                ? 'FILE SYNC SETUP'
                : '${kGenericAppLabel.toUpperCase()} ${kContainerName.toUpperCase()} SETUP',
          ),
        ),
        leading: Consumer<LinkingController>(
          builder: (_, ctrl, __) {
            // Prevent back-nav while machine is running between park points
            final canLeave = !ctrl.isRunning ||
                ctrl.currentInstruction != null ||
                ctrl.step == LinkingStep.complete ||
                ctrl.step == LinkingStep.failed;
            return IconButton(
              icon: const Icon(Icons.close),
              onPressed: canLeave ? () => _leaveSetup(context) : null,
            );
          },
        ),
      ),
      body: Consumer<LinkingController>(
        builder: (_, ctrl, __) {
          return Column(
            children: [
              _ProgressBar(
                progress: ctrl.progress,
                // 2026-08-14: real device confirmed the freeze wasn't
                // in cloning at all - it was the ~30s between tapping
                // Open in the native picker and pickVaultFolder()'s
                // await actually returning, still on pickingVaultFolder
                // (fixed 55%) the whole time. ctrl.pickingFolder covers
                // exactly that gap.
                indeterminate: ctrl.step == LinkingStep.cloning ||
                    ctrl.step == LinkingStep.verifySync ||
                    ctrl.pickingFolder,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: switch (ctrl.step) {
                    LinkingStep.idle => _IdleView(ctrl: ctrl),
                    LinkingStep.complete => _CompleteView(ctrl: ctrl),
                    LinkingStep.failed => _FailedView(ctrl: ctrl),
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
  // 2026-08-14: real device feedback - the bar jumps to a fixed value
  // the instant cloning starts, then sits dead still for the ~30s a
  // real git pull takes (no incremental progress data from git2dart
  // wired up), reading as "the app is frozen" rather than "working".
  // An indeterminate (continuously animated) bar during the two
  // unbounded-duration steps is the standard, honest signal for
  // "actively working, duration unknown" instead of faking a fixed
  // percentage the app can't actually measure.
  final bool indeterminate;
  const _ProgressBar({required this.progress, this.indeterminate = false});

  @override
  Widget build(BuildContext context) {
    if (indeterminate) {
      return LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: kBorder,
        valueColor: AlwaysStoppedAnimation<Color>(kGreen),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, v, __) => LinearProgressIndicator(
        value: v,
        minHeight: 2,
        backgroundColor: kBorder,
        valueColor: AlwaysStoppedAnimation<Color>(kGreen),
      ),
    );
  }
}

// ── Idle ───────────────────────────────────────────────────────────────────────

class _IdleView extends StatefulWidget {
  final LinkingController ctrl;
  const _IdleView({required this.ctrl});

  @override
  State<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends State<_IdleView>
    with SingleTickerProviderStateMixin {
  // 2026-08-10: drag-to-connect, added alongside the COPY VAULT TO THIS
  // PHONE button. 2026-08-11: button removed per explicit user
  // direction ("just keep the drag drop theme") - drag is now the only
  // trigger, so a continuous pulse + hint text were added on the
  // draggable icon so the gesture is still discoverable without it.
  bool _dragHover = false;
  late final AnimationController _pulseCtrl;

  // 2026-08-23: real feedback, live - "why not have on the same
  // swipe/drag setup vault... enter password there too... then swipe
  // laptop to files?" First-time pairing (checkingPairing, guaranteed
  // to fail on any fresh install per the storyboard reviewed earlier)
  // is now collected and completed on this same screen, not a separate
  // PAIR WITH DESKTOP screen. Real PairingController instance is local
  // to this screen (real re-pairing via the kebab menu still uses the
  // standalone PairingScreen, untouched - this is additive, not a
  // replacement of that).
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _shredKey1 = GlobalKey<ShreddingPasswordFieldState>();
  final _shredKey2 = GlobalKey<ShreddingPasswordFieldState>();
  // 2026-08-28: real feedback, live - cursor should be ready to type the
  // moment Stage 2 unlocks, not require an extra manual tap. See
  // ShreddingPasswordField's own comment for why this has to be a
  // caller-controlled FocusNode rather than autofocus.
  final _passwordFocusNode = FocusNode();
  late final PairingController _pairingCtrl;
  bool _pairing = false;
  StepFailure? _pairingFailure;
  // 2026-08-25: _pairAttempts tried, reverted ("just use this same
  // solution"), then re-added with real different wording per attempt:
  // 1st wrong password - "Re-enter your desktop password - used once,
  // never stored." 2nd+ - "Re-enter your desktop password with care and
  // use the eye to read it" (a genuinely different, more specific
  // suggestion - check what you typed via the field's own reveal
  // toggle, not just retry blind). Scoped to connectionRefused only
  // (see the DiagCard call site below) - other error types keep
  // showing their own resolution text unconditionally, unaffected.
  int _pairAttempts = 0;

  bool get _passwordsMatch =>
      _passwordCtrl.text.isNotEmpty && _passwordCtrl.text == _confirmCtrl.text;

  // 2026-08-23: real feedback, live - "the user dragging the phonekey
  // to laptop lock is unnecessary, but it's a trust and value add for
  // the user to do it, thinking it's real perhaps. This explains the
  // pairing." Purely ceremonial - no backend call happens here, it
  // just unlocks stage 2. The real pairing work (installing the key)
  // still happens later, in _pairThenLink(), using the password.
  //
  // 2026-08-24: real feedback, live (round 4) - "Dragging the phonekey
  // into the laptoplock is impossible to position exactly... Stop
  // reinventing the wheel, just use the existing code for the pairing
  // page." Round 3's hand-rolled distance-to-target drag (own success
  // radius, own clamp bounds) was a second, subtly-different
  // reimplementation of exactly what KeyPairingTrigger already does,
  // and landed with a tighter/harder-to-hit radius in practice -
  // "unable to proceed to test password" confirms it was genuinely too
  // strict, not just a perception issue. All of round 3's custom
  // drag/snap state and methods are gone; the build() below now uses
  // KeyPairingTrigger directly, the same widget PairingScreen and this
  // file's own diagnostics-retry flow already use successfully.
  bool _paired = false;
  // 2026-08-28: real feedback, live - the consent check used to run
  // inside _pairThenLink() (Stage 3's drag), which meant it appeared
  // AFTER the password was already typed into Stage 2 - the opposite of
  // "before you type your password". Resolved here instead, the moment
  // Stage 1 settles and Stage 2 is about to unlock, then reused by
  // _pairThenLink() below rather than asked twice.
  bool? _allowAutoInstallGit;
  // 2026-08-28: real feedback, live - a "check Settings first" banner
  // lived on SyncChoiceScreen for one day, reverted same day ("this is
  // the welcome page, it needs warm fuzzy feelings, not technical mumbo
  // jumbo"). The underlying need was real - moved here instead, Stage
  // 1's own technical-setup context, where a Settings reminder actually
  // belongs.
  bool _needsSettings = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pairingCtrl = PairingController(
      desktopUser: widget.ctrl.desktopUser,
      desktopIp: widget.ctrl.desktopIp,
    );
    _passwordCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
    _skipStage1IfAlreadyPaired();
    _checkSettings();
  }

  Future<void> _checkSettings() async {
    final db = DatabaseService();
    final user = await db.getDesktopUser();
    final ip = await db.getDesktopIp();
    final path = await db.getBareRepoPath();
    if (!mounted) return;
    setState(() {
      _needsSettings = (user == null || user.trim().isEmpty) &&
          (ip == null || ip.trim().isEmpty) &&
          (path == null || path.trim().isEmpty);
    });
  }

  // 2026-08-28: real feedback, live - a returning user (Tier 0 buying
  // the Obsidian unlock, or "add another vault" from the kebab menu)
  // already has a working keypair from an earlier pairing - re-dragging
  // the key into the lock and retyping the desktop password was pure
  // repetition, not a real precondition. Same local keypair-file check
  // _checkPairing/_checkPairingGeneric already gate on, just run early
  // enough to skip Stage 1's gesture entirely instead of requiring it
  // and then re-verifying the same thing a moment later. Mirrors
  // _pairThenLink's own tail exactly (same mode branch, same start
  // calls) - just reached without the drag+password round trip.
  Future<void> _skipStage1IfAlreadyPaired() async {
    final already = await widget.ctrl.hasExistingKeypair();
    if (!mounted || !already) return;
    // 2026-08-28: real feedback, live - "I need informed users." This
    // skip is safe (no SSH/sudo runs on this path - startLinking() /
    // startLinkingGenericFolder() go straight through the existing
    // keypair, never touching PairingController), but it looked like
    // random skipping with zero explanation, including the consent
    // screen never showing up - confusing, even though nothing risky
    // happened. A brief note instead of silence.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Already paired with this desktop - skipping ahead',
            style: TextStyle(color: kVoid, fontWeight: FontWeight.w600)),
        backgroundColor: kGreen,
        duration: const Duration(seconds: 3),
      ),
    );
    setState(() => _paired = true);
    if (widget.ctrl.preferredMode == SyncMode.genericFolder) {
      widget.ctrl.startLinkingGenericFolder();
    } else {
      widget.ctrl.startLinking();
    }
  }

  // 2026-08-28: real feedback, live - "Password warning appears after
  // I've already entered the password, and only after completing step
  // 3. Introduce the warning when step 2 activates." Stage 1's own drag
  // is purely ceremonial (see pairing_controller.dart's own comment on
  // that) - the real moment to ask is right here, before Stage 2's
  // password fields unlock, not after Stage 3's drag when the password
  // is already sitting typed in the field. Resolved once here and
  // reused by _pairThenLink() below, rather than asked twice.
  //
  // 2026-08-28, follow-up: real feedback, live - the remembered-choice
  // behavior ("asked once, not every pairing") surfaced as confusing
  // twice in a row on a real device ("step 2 activates with no password
  // warning"), even though it was working as designed. Explicit
  // decision after being asked directly: ask every single time instead
  // - a security consent, not a convenience prompt, so the remembered
  // shortcut traded away more visibility than wanted. No longer reads
  // or writes DatabaseService's stored choice at all.
  Future<void> _onKeyPairingSettled() async {
    if (!mounted) return;
    final decided = await showGitInstallConsent(context);
    if (decided == null) return; // cancelled - Stage 2 stays locked
    if (!mounted) return;
    setState(() {
      _allowAutoInstallGit = decided;
      _paired = true;
    });
    // 2026-08-28: real feedback, live - "Step 2 activates but then I
    // have to tap the field, why doesn't the cursor activate ready to
    // type?" Scheduled for after this frame, not called inline here -
    // the password field is still behind IgnorePointer(ignoring: true)
    // until the setState above actually rebuilds, and requesting focus
    // before that rebuild lands would be racing it.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _passwordFocusNode.requestFocus());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _passwordFocusNode.dispose();
    _pairingCtrl.dispose();
    super.dispose();
  }

  // Pairs first (installs this device's key using the typed password),
  // then continues straight into vault linking on success - one drag,
  // two real actions, no intermediate screen. On failure, shows the
  // error inline on this same screen instead of navigating away.
  Future<void> _pairThenLink() async {
    // 2026-08-28: consent is now resolved earlier, in
    // _onKeyPairingSettled() above (Stage 1 -> 2, before any password is
    // typed) - _allowAutoInstallGit is always set by the time Stage 3's
    // drag can even fire, since Stage 3 stays locked until _paired is
    // true, which only happens after that consent step resolves.
    assert(_allowAutoInstallGit != null);

    setState(() {
      _pairing = true;
      _pairingFailure = null;
    });
    final password = _passwordCtrl.text;
    unawaited(_shredKey1.currentState?.shred());
    unawaited(_shredKey2.currentState?.shred());
    // 2026-08-28: real device bug, live - _pairingCtrl was built once in
    // initState() with whatever desktopUser/desktopIp LinkingController
    // had at that moment, usually both empty on a fresh install (Settings
    // hasn't been visited yet). Re-synced here, immediately before every
    // real attempt, so a Settings visit in between (the normal flow -
    // Stage 1's own reminder sends the user there) is actually picked up
    // instead of pairing against a stale, already-empty snapshot.
    _pairingCtrl.desktopUser = widget.ctrl.desktopUser;
    _pairingCtrl.desktopIp = widget.ctrl.desktopIp;
    await _pairingCtrl.pairWithPassword(password,
        allowAutoInstallGit: _allowAutoInstallGit!);
    if (!mounted) return;
    final result = _pairingCtrl.result;
    if (result is StepFailure) {
      setState(() {
        _pairing = false;
        _pairingFailure = result;
        _pairAttempts++;
      });
      return;
    }
    setState(() => _pairing = false);
    // 2026-08-27: honors a choice made on the chooser screen before
    // this one, if there was one - the drag gesture itself is identical
    // either way (SSH pairing doesn't care about sync mode), only which
    // flow it lands on afterward changes. Null (no chooser seen, e.g.
    // "Vault - add another" from the kebab menu) keeps the original
    // default.
    if (widget.ctrl.preferredMode == SyncMode.genericFolder) {
      widget.ctrl.startLinkingGenericFolder();
    } else {
      widget.ctrl.startLinking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    // 2026-08-11: "page 2 images are smaller than page 1, why?" - real
    // gap, not perception: page 1's icon size *is* the real content
    // width, but this formula computed glyphWidth (the container) and
    // then took 60% of it for the icon - an arbitrary shrink page 1
    // never applied. Rewritten to match page 1's approach exactly: size
    // the icon itself directly from the real screen width, then size
    // the glyph's box to just fit that icon (icon + its own 16px
    // padding/border) - label/caption wrap or ellipsis within it rather
    // than the icon being shrunk to fit a wider box.
    final screenWidth = MediaQuery.of(context).size.width;
    const rowPadding = 6.0;
    const arrowWidth = 26.0; // arrow's own icon, no horizontal padding
    const iconBoxOverhead = 16.0; // 6*2 padding + 2*2 border, per icon
    final glyphIcon =
        ((screenWidth - rowPadding * 2 - arrowWidth - iconBoxOverhead * 2) / 2)
            .clamp(70.0, 180.0);
    final glyphWidth = glyphIcon + iconBoxOverhead;
    // 2026-08-24, round 4: the exact key-bit-to-keyway sizing math that
    // used to live here (keyIconSize/keyTopOffset) was specific to the
    // hand-rolled Stage 1 drag rounds 1-3 built - no longer needed now
    // that Stage 1 uses KeyPairingTrigger directly (see below), which
    // owns its own icon sizing. Stage 3's vault-linking glyphs further
    // down don't use this math either (they're plain _DeviceGlyph calls
    // at glyphIcon size) - removed rather than left dead.
    // Arrow's own icon (26px) centred against the glyph's icon box
    // (iconSize + 6px padding + 2px border on each side), not the
    // glyph's full height (icon+label+caption) - a fixed 14px guess
    // here previously drifted out of alignment once sizes changed.
    final arrowTopOffset = ((glyphIcon + 16) - 26) / 2;

    // 2026-08-19: "magic stars only need to hint where a user is able
    // to action something... the user must action the desktop to swipe
    // right, therefore only have magic stars near the desktop" - the
    // 2026-08-18 whole-screen sparkle wrap hinted at the vault glyph,
    // arrow, and every line of body text too, none of which are
    // themselves draggable. Sparkles now scope to just the desktop
    // glyph (see the Draggable below), the one thing on this screen a
    // user actually acts on.
    // 2026-08-23: SingleChildScrollView added alongside the new password
    // fields below - two more text fields plus the keyboard genuinely
    // don't fit every screen size, same class of "keyboard covers the
    // content" bug this app has hit before on the standalone pairing
    // screen. This one shrink-wraps its own content height correctly
    // (no ContentAboveDragCanvas measuring involved here), so it
    // doesn't repeat that specific historical bug.
    // 2026-08-24, round 11: real feedback, live - "fix it," after round
    // 10's revert still didn't land ("no change" persisted through
    // rounds 6-9 despite each being a real, verified fix for the
    // specific symptom reported). Re-reading key_pairing_trigger.dart's
    // own 2026-08-16 history in round 10 surfaced the actual structural
    // cause rounds 6-9 were each patching around individually: its other
    // two working call sites (PairingScreen, this file's own
    // diagnostics-retry _FailedView further down) both give it a
    // genuinely bounded, non-scrolling, full-remaining-screen box via
    // ContentAboveDragCanvas - never a small fixed SizedBox inside a
    // SingleChildScrollView, which is what Stage 1 has always been
    // embedded in, every round, including round 10's revert.
    //
    // Fixed properly this round: while pairing hasn't happened yet
    // (!_paired), this view now returns ContentAboveDragCanvas directly
    // (same widget, same pattern _FailedView already uses successfully)
    // instead of the scrolling multi-stage Column - the welcome text
    // becomes the measured `content` above, KeyPairingTrigger becomes
    // the `canvas` below it, filling all real remaining screen space
    // exactly like it does at both its other call sites. This is a
    // structural fix, not another parameter tweak - no scroll ancestor
    // exists here at all anymore for the drag gesture to lose an arena
    // fight against.
    //
    // Once _paired flips true (via onSettled below), this method
    // returns the ORIGINAL scrolling Stage 2/3 content instead (further
    // down) - the welcome text and Stage 1's own header/canvas are
    // dropped from that branch since they're only relevant before
    // pairing, already shown once, in the ceremony view above.
    // 2026-08-25: real feedback, live - "2 and 3 are missing their
    // sections, they just show the headers... make another solution, it
    // worked before on previous code versions." Pre-round-11 showed
    // Steps 2/3's real content (fields, description text) dimmed
    // underneath Stage 1, all in one SingleChildScrollView - the exact
    // scroll-ancestor-around-the-drag-canvas combination round 11's
    // whole fix was about removing. The real risk isn't "more content
    // below the canvas" (that's just layout, checked locally below) -
    // it's specifically a Scrollable becoming an ANCESTOR of the drag
    // gesture. So: Stage 1 (content + bounded canvas) stays a sibling in
    // this outer, non-scrolling Column exactly as before; Stage 2/3's
    // real widgets (unchanged from the paired-only branch - same
    // IgnorePointer/AnimatedOpacity dimming they already had) move into
    // their OWN Expanded+SingleChildScrollView, a sibling of Stage 1,
    // never an ancestor of it. The canvas never gains a scroll ancestor;
    // Stage 2/3 keeps the scroll room its real TextFields need for the
    // keyboard. Verified via test/stage1_preview_test.dart (layout, no
    // overflow) and a simulated drag (tester.drag + onSettled firing)
    // before pushing - not just asserted safe by reasoning.
    //
    // 2026-08-25, follow-up - "it changes page to 2 and 3. I want the
    // user to simply flow down the same screen." Dropping stage1Widgets
    // entirely once _paired (round 11's original behavior, kept above)
    // is exactly what read as a page swap - Stage 1's content vanishing
    // the instant Steps 2/3 take over the full Expanded region. No
    // longer conditional: Stage 1 stays on screen permanently. The key
    // stays visually snapped in the lock once paired (resetAfterSettle:
    // false already does this), which reads as "step 1, done" rather
    // than empty space - Steps 2/3 just grow the page below it instead
    // of replacing it. The gesture layer becoming a no-op once _snapped
    // (key_pairing_trigger.dart's own _onStart guard) means leaving the
    // canvas mounted post-pairing doesn't let it be re-dragged.
    final stage1Widgets = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                widget.ctrl.preferredMode == SyncMode.genericFolder
                    ? 'Bring your desktop files to this phone'
                    : 'Bring your desktop $kGenericAppLabel $kContainerName to this phone',
                style: TextStyle(
                    color: kStar, fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const SizedBox(
              width: 220,
              child: Column(
                children: [
                  _ScopeRow(label: 'Notes'),
                  _ScopeRow(label: 'Folders'),
                  _ScopeRow(label: 'Attachments'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 2026-08-25: real feedback, live - "about 5 shades of grey,
            // too much. Kiss so the user experiences only a few shades
            // and colours." This row was kTextDim/12px/21px icon while
            // the row below was kTextMid/13px/15px icon - three
            // different greys and two different sizes across six lines
            // of intro text. Both rows now match each other exactly
            // (kTextMid, 13px, 16px icon); kTextDim dropped from this
            // block entirely. Only kStar (the one heading) and kTextMid
            // (everything else) remain.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, color: kTextMid, size: 16),
                const SizedBox(width: 6),
                Text('No other files on this phone are read or changed.',
                    style: TextStyle(color: kTextMid, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_outlined, color: kTextMid, size: 16),
                const SizedBox(width: 6),
                Text(
                  'This runs once. Larger vaults may take a few minutes.',
                  style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_needsSettings) ...[
              _SettingsReminder(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              const SizedBox(height: 20),
            ],
            Text('1. PAIR YOUR DEVICE',
                style: TextStyle(
                    color: kGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ],
        ),
      ),
      SizedBox(
        height: 222,
        width: double.infinity,
        child: KeyPairingTrigger(
          runningLabel: 'CONNECTING…',
          // 2026-08-24, round 12: real feedback, live - "same errors,
          // keep fixing." Re-adds round 6/9's captions, resetAfterSettle,
          // and zero minRun (widgets/key_pairing_trigger.dart) - dropped
          // in round 10's revert alongside the scroll-arena workarounds
          // they were never actually the cause of. Now built on round
          // 11's fixed foundation (a real full-screen canvas, no
          // competing ScrollView) instead of layered on top of the
          // broken one.
          resetAfterSettle: false,
          minRun: Duration.zero,
          // 2026-08-24, round 13: real feedback, live - "doesn't drag up
          // or over the whole screen. The previous version did until
          // you reverted back to its previous version." Round 9's
          // dragMargin, dropped in round 10's revert and not re-added in
          // round 12 - re-added now on top of round 11's real full-
          // screen-canvas fix instead of the broken small-box-in-
          // ScrollView it was layered on before. Still 200 here - the
          // 2026-08-25 fix above is about which widget the height cap
          // is applied to, not this value.
          dragMargin: 200,
          keyCaption: Text('Your phone\n(has a key)',
              style: TextStyle(
                  color: kTextMid, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          lockCaption: Text(
              'Your computer\n${ctrl.desktopUser}@${ctrl.desktopIp}',
              style: TextStyle(color: kTextMid, fontSize: 13),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
          onConfirm: () async {},
          onSettled: _onKeyPairingSettled,
        ),
      ),
    ];

    // 2026-08-24, round 14: real feedback, live - "2. DESKTOP PASSWORD
    // is way too far below." mainAxisAlignment.center was tuned for
    // this Column back when it also held the welcome text and Stage 1's
    // own header/canvas (removed in round 11) - with only Stage 2/3
    // left, centering the now-much-shorter content vertically within
    // this SingleChildScrollView's viewport pushed "2. DESKTOP
    // PASSWORD" well down from the top instead of starting there.
    // MainAxisAlignment.start, and top padding trimmed from 32 to 16 to
    // match - this is the first thing on screen now, it doesn't need as
    // much breathing room above it as it did when other content came
    // first.
    //
    // 2026-08-25: real feedback, live - still an unnecessary gap above
    // "2. DESKTOP PASSWORD" at 16. Trimmed to 0 - the AppBar and
    // progress bar above already give this enough separation from the
    // top of the screen.
    //
    // 2026-08-25: this SingleChildScrollView is now a sibling of Stage
    // 1's canvas (stage1Widgets, above) in the outer Column below,
    // wrapped in Expanded for its own bounded scroll region - never an
    // ancestor of the drag gesture, which is the property round 11
    // actually needed. Stage 2/3 content itself is untouched.
    //
    // 2026-08-25: real feedback, live - "add 1 more line space above the
    // header." Top trimmed to 0 earlier today when Stage 2/3 was the
    // first thing on screen; now that Stage 1 always precedes it, 0
    // reads as too tight again. One line's worth (24) back.
    final stage23Content = Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 2026-08-25: real feedback, live - "2. DESKTOP PASSWORD and
          // 3. SET UP VAULT not to be dimmed, to always show normal
          // text. The other features of sections 2 and 3 will activate
          // as the previous section is completed successfully." Heading
          // pulled out of the IgnorePointer/AnimatedOpacity wrapper -
          // always full color/opacity now, a fixed step marker rather
          // than something that itself looks locked. Everything below
          // it (description, fields) keeps the existing dim-until-
          // unlocked treatment unchanged.
          // 2026-08-24, round 6: "Desktop password too many stars, just
          // have on left of Desktop password... text, inside and
          // outside of text field 1." Moved the sparkle from inside
          // field 1 to the heading instead.
          // 2026-08-25, real feedback, live: reversed - "Magic stars
          // here, remove them. 2. DESKTOP PASSWORD... Magic stars needed
          // here: Desktop password..." Sparkle belongs on the field
          // itself, not the heading - back to a plain heading, sparkle
          // moved onto field 1 below.
          Text('2. DESKTOP PASSWORD',
              style: TextStyle(
                  color: kGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 14),
          // Stage 2 body - locked until stage 1 is done.
          // 2026-08-28: real feedback, live - a real device showed Stage 2
          // unlocking after cancelling the consent dialog once, then
          // completing Stage 1 again - the exact chain wasn't reproducible
          // off-device, so this is a structural fix rather than a traced
          // one: gating on _paired alone left a path where _paired could
          // end up true without _allowAutoInstallGit ever actually being
          // resolved. Now requires both - Stage 2 cannot unlock unless a
          // real consent choice exists, full stop, regardless of how
          // _paired got set.
          IgnorePointer(
            ignoring: !(_paired && _allowAutoInstallGit != null),
            child: AnimatedOpacity(
              opacity: (_paired && _allowAutoInstallGit != null) ? 1 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // 2026-08-25: real feedback, live - first pass ("the
                    // public key IS stored, on the desktop") was still
                    // incomplete - it's also stored on the phone itself
                    // (that's where it was generated, and it stays there
                    // for future use), not just the desktop. Also asked
                    // to be less verbose - two short lines instead of
                    // one long sentence.
                    child: Text(
                      'Your key is stored on both devices.\n'
                      'Your password never is.',
                      style:
                          TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // 2026-08-25: real feedback, live, several rounds -
                    // "Magic stars needed here" -> "not put here" (a real
                    // bug: painted behind the field's own opaque fill,
                    // see shredding_password_field.dart's 2026-08-25
                    // history) -> "should only be on the left of the
                    // text... left of the D." SparkleBackground (built
                    // for scattering across open backgrounds) was fought
                    // into a Stack+Positioned hack three different ways
                    // before landing on the actually-correct mechanism:
                    // ShreddingPasswordField's own prefixIcon, the real
                    // Flutter way to put an icon to the left of a field's
                    // text - no manual positioning needed.
                    //
                    // 2026-08-25, follow-up: "more stars ... inside and
                    // outside the password field" - the inside cluster
                    // lives in ShreddingPasswordField's own prefixIcon
                    // now (see its 2026-08-25 history); this outer Stack
                    // adds a second small star spilling past the field's
                    // own left border, field 1 only, same clipBehavior:
                    // Clip.none precedent as _SkinSwatch's badge overflow
                    // in settings_screen.dart.
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ShreddingPasswordField(
                          key: _shredKey1,
                          controller: _passwordCtrl,
                          enabled: !_pairing,
                          // 2026-08-28: real feedback, live - "can
                          // password field 1 stars twinkling disappear
                          // once populated... magic stars disappear
                          // once actioned, as they're no longer needed
                          // to attract the eye." Was hardcoded true
                          // regardless of content - field 2 already had
                          // this exact reactive pattern (showSparkle:
                          // _passwordCtrl.text.isNotEmpty, i.e. only
                          // once it's the active next step), just never
                          // applied symmetrically to field 1 once IT
                          // has been typed into.
                          showSparkle: _passwordCtrl.text.isEmpty,
                          focusNode: _passwordFocusNode,
                        ),
                        Positioned(
                          left: -10,
                          top: 14,
                          child: IgnorePointer(
                            child: Icon(Icons.auto_awesome,
                                color: kGreen, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 2026-08-25: copy-to-confirm button added then
                  // removed same day - defeats the actual purpose of a
                  // confirm field (catching typos via independent
                  // retyping). Each field's own reveal/eye icon already
                  // covers "let me double-check what I typed" without
                  // undermining that.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // 2026-08-24: sparkles are field 1 only, not the
                    // confirm field - reverted here per explicit
                    // clarification after briefly adding it to both.
                    // 2026-08-25, refined: "Can Desktop password... field
                    // 2 have stars once field1 has typing started."
                    // Conditional this time, not blanket - reactive to
                    // _passwordCtrl (already has a listener triggering
                    // rebuilds, see initState).
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _confirmCtrl.text.isEmpty
                              ? Colors.transparent
                              : (_passwordsMatch ? kGreen : Colors.redAccent),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ShreddingPasswordField(
                        key: _shredKey2,
                        controller: _confirmCtrl,
                        enabled: !_pairing,
                        showSparkle: _passwordCtrl.text.isNotEmpty,
                      ),
                    ),
                  ),
                  // 2026-08-24: real feedback, live (round 6) -
                  // "Passwords match/should match text is too jump
                  // scare, have the text smooth transition into
                  // appearance." This block used to only exist in the
                  // tree at all once the confirm field was non-empty (a
                  // hard insert, not a fade) - AnimatedSwitcher cross-
                  // fades between nothing and the real row instead of
                  // popping it in instantly.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _confirmCtrl.text.isEmpty
                        ? const SizedBox.shrink(key: ValueKey('matchEmpty'))
                        : Padding(
                            key: const ValueKey('matchRow'),
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    _passwordsMatch
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color:
                                        _passwordsMatch ? kGreen : Colors.amber,
                                    size: 16),
                                const SizedBox(width: 6),
                                Text(
                                    _passwordsMatch
                                        ? 'Passwords match'
                                        : 'Passwords should match',
                                    style: TextStyle(
                                        color: _passwordsMatch
                                            ? kGreen
                                            : Colors.amber,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                  if (_pairingFailure != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: DiagCard(
                        label: 'WHAT HAPPENED',
                        text: _pairingFailure!.diagnosis,
                        accent: Colors.redAccent,
                      ),
                    ),
                    // 2026-08-25: real bug, live - "I see no list, what
                    // list are you referring to?" This inline failure
                    // display (Stage 2's password entry, _pairThenLink())
                    // is a separate code path from _FailedView/
                    // PairingScreen's own failure screens - it only ever
                    // rendered WHAT HAPPENED, never HOW TO FIX IT, so the
                    // numbered resolution steps (leading with "re-enter
                    // your desktop password") genuinely never reached
                    // this screen. Added here to match the same pattern
                    // both other failure displays already use.
                    const SizedBox(height: 12),
                    // 2026-08-25, real feedback, live, full 10-attempt
                    // list provided directly (was 2 messages before this
                    // pass): each attempt gets its own distinct line, not
                    // a repeated/progressive reveal of the same text.
                    // Scoped to connectionRefused and pairingPasswordRejected
                    // (see isPasswordRetryError) - these are the ambiguous
                    // "could be a mistyped password, could be network/auth"
                    // errors this whole exchange has been about (see
                    // linking_state.dart's diagnosis text and history). Any
                    // other error type keeps showing its own resolution text
                    // unconditionally, unaffected - those already have their
                    // own specific, correct guidance and were never part of
                    // this complaint. Attempt 11+ repeats message 10 (list
                    // clamped) - there's nowhere further to escalate to.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Builder(builder: (context) {
                        if (!isPasswordRetryError(_pairingFailure!.error)) {
                          return DiagCard(
                            label: 'HOW TO FIX IT',
                            text: _pairingFailure!.resolution,
                            accent: kGreen,
                            icon: Icons.lightbulb_outline,
                            bulleted: true,
                          );
                        }
                        return DiagCard(
                          label: 'HOW TO FIX IT',
                          text: passwordRetryMessage(_pairAttempts),
                          accent: kGreen,
                          icon: Icons.lightbulb_outline,
                        );
                      }),
                    ),
                    // 2026-08-25: real feedback, live - "this is not
                    // showing what the real error is and needs to
                    // include the real error." Same RAW ERROR card
                    // _FailedView already shows when debugDetail is
                    // present - missing here for the same reason HOW TO
                    // FIX IT was: this inline display never got it.
                    // Matters concretely here: _diagnose() in
                    // pairing_controller.dart already has specific
                    // detection for SSHAuthFailError/SSHAuthAbortError/
                    // "authentication"/"password" that should map a
                    // wrong password to a distinct message, not this
                    // generic one - seeing the real exception text is
                    // what actually confirms whether that detection
                    // missed this specific error, or whether this really
                    // was a network failure coinciding with the
                    // mistyped password.
                    if (_pairingFailure!.debugDetail != null &&
                        _pairingFailure!.debugDetail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: DiagCard(
                          label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
                          text: _pairingFailure!.debugDetail!,
                          accent: Colors.redAccent,
                          maxLength: 300,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Heading always full color/opacity - same fix as Stage 2's
          // heading above.
          // 2026-08-28: real feedback, live - a Tier 0 user is linking a
          // plain folder, not a vault, and the glyph directly below this
          // heading already knew that (preferredMode ternary a few lines
          // down) - this heading was the one piece of Stage 3 still
          // hardcoded to vault language regardless of mode. Wording is
          // exact, given directly - "3. SET UP FOLDER SYNC", not a
          // paraphrase.
          Text(
              widget.ctrl.preferredMode == SyncMode.genericFolder
                  ? '3. SET UP FOLDER SYNC'
                  : '3. SET UP VAULT',
              style: TextStyle(
                  color: kGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 14),
          // Stage 3 body - locked until passwords match.
          // 2026-08-28: same structural fix as Stage 2 above - requires a
          // real consent choice to exist, not just _paired.
          IgnorePointer(
            ignoring: !(_paired && _allowAutoInstallGit != null && _passwordsMatch),
            child: AnimatedOpacity(
              opacity: (_paired && _allowAutoInstallGit != null && _passwordsMatch)
                  ? 1
                  : 0.3,
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: rowPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: glyphWidth,
                          child: Stack(
                            children: [
                              const Positioned.fill(child: SparkleBackground()),
                              Draggable<bool>(
                                data: true,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Opacity(
                                    opacity: 0.85,
                                    child: _DeviceGlyph(
                                      svgAsset:
                                          'assets/pairing/pairing_laptop_plain.svg',
                                      label: 'Your desktop',
                                      caption:
                                          '${ctrl.desktopUser}@${ctrl.desktopIp}',
                                      accent: true,
                                      width: glyphWidth,
                                      iconSize: glyphIcon,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: _DeviceGlyph(
                                    svgAsset:
                                        'assets/pairing/pairing_laptop_plain.svg',
                                    label: 'Your desktop',
                                    caption:
                                        '${ctrl.desktopUser}@${ctrl.desktopIp}',
                                    accent: true,
                                    width: glyphWidth,
                                    iconSize: glyphIcon,
                                  ),
                                ),
                                child: _DeviceGlyph(
                                  svgAsset:
                                      'assets/pairing/pairing_laptop_plain.svg',
                                  label: 'Your desktop',
                                  caption:
                                      '${ctrl.desktopUser}@${ctrl.desktopIp}',
                                  accent: true,
                                  width: glyphWidth,
                                  iconSize: glyphIcon,
                                  pulse: _pulseCtrl,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: arrowTopOffset),
                          child: Icon(Icons.arrow_forward_rounded,
                              color: kGreen, size: 26),
                        ),
                        DragTarget<bool>(
                          onWillAcceptWithDetails: (_) {
                            if (!(_paired &&
                                _allowAutoInstallGit != null &&
                                _passwordsMatch)) {
                              return false;
                            }
                            setState(() => _dragHover = true);
                            return true;
                          },
                          onLeave: (_) => setState(() => _dragHover = false),
                          onAcceptWithDetails: (_) {
                            setState(() => _dragHover = false);
                            _pairThenLink();
                          },
                          builder: (context, candidate, rejected) =>
                              _DeviceGlyph(
                            icon: widget.ctrl.preferredMode ==
                                    SyncMode.genericFolder
                                ? Icons.folder_outlined
                                : Icons.auto_stories_rounded,
                            // 2026-08-28: real feedback, live - exact
                            // wording given directly, "Folder sync", not
                            // "files" - matches the new "3. SET UP FOLDER
                            // SYNC" heading above rather than drifting
                            // from it.
                            label: widget.ctrl.preferredMode ==
                                    SyncMode.genericFolder
                                ? 'Folder sync'
                                : '$kGenericAppLabel $kContainerName',
                            caption: 'this phone',
                            width: glyphWidth,
                            iconSize: glyphIcon,
                            hovering: _dragHover,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_pairing) ...[
            const SizedBox(height: 16),
            Text('Pairing…',
                style: TextStyle(color: kTextMid, fontSize: 13),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: ctrl.startLinkingExistingVault,
            child: Text(
              'Already have a vault set up? Link it directly',
              style: TextStyle(
                color: kTextMid,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: kTextMid,
              ),
            ),
          ),
          // 2026-08-27: Tier 0 (docs/product-tiers.md) - free, generic
          // file sync, no PKM awareness at all. Names the app-agnostic
          // $kContainerName here, not $kNoteAppName - "no vault needed"
          // is real, generic-app-swap-safe copy (same reasoning as
          // constants.dart's own kContainerName/kGenericAppLabel split);
          // naming Obsidian specifically on this exact link would be
          // wrong the moment a second PKM is supported. Real UI polish
          // for this whole path is a real next step, not done here (see
          // the SyncMode.genericFolder header comment in
          // repository.dart), this is a working, reachable entry point.
          const SizedBox(height: 12),
          GestureDetector(
            onTap: ctrl.startLinkingGenericFolder,
            child: Text(
              "Just want to sync plain files, no $kContainerName needed? Sync a folder directly",
              style: TextStyle(
                color: kTextMid,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: kTextMid,
              ),
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      physics: _paired
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          ...stage1Widgets,
          stage23Content,
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
            style: TextStyle(
                color: kStar, fontSize: 16, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // 2026-08-20: real feedback, live - "too dark and too small",
          // same complaint hit repeatedly elsewhere today - kTextDim/
          // 11px was the dimmest+smallest text anywhere in this app.
          // kTextMid/13px matches the fix already applied to every
          // other instance of this same complaint.
          Text(
            ctrl.stepSubtitle,
            style: TextStyle(
                color: kTextMid, fontSize: 13, letterSpacing: 0.3, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Parked: user action required ───────────────────────────────────────────────

class _ParkedView extends StatefulWidget {
  final LinkingController ctrl;
  const _ParkedView({required this.ctrl});

  @override
  State<_ParkedView> createState() => _ParkedViewState();
}

class _ParkedViewState extends State<_ParkedView> {
  // 2026-08-16: "important steps that a user might try to skip and
  // have errors later on" - real device testing confirmed the folder
  // isn't created until force-close (step 1.10) actually happens, so
  // I'VE CREATED IT is now blocked until it's ticked. Tracked here
  // (lifted out of _StepChecklist's own private state) so the swipe
  // confirm below can check it.
  List<bool>? _vaultCreationChecked;

  // 2026-08-20: re-verified against the current vaultCreationSteps list
  // (linking_controller.dart) after 1.12/1.13 were removed - "force
  // close Obsidian" is now index 10 (1-indexed 1.11), the sole critical
  // step and the last one in the list. This index had drifted out of
  // sync with the actual list once before (found stale mid-session,
  // 2026-08-20) - if vaultCreationSteps changes length again, re-check
  // this against it directly rather than trusting the comment alone.
  static const _criticalIndices = [10]; // 1.11

  String? _validateVaultCreationDone() {
    final checked = _vaultCreationChecked;
    if (checked == null) return null;
    final allCriticalDone =
        _criticalIndices.every((i) => i < checked.length && checked[i]);
    if (allCriticalDone) return null;
    return 'Complete and tick 1.11';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    // Derive a plain heading from the current park point
    final heading = switch (ctrl.step) {
      LinkingStep.awaitingVaultCreation => 'Create your $kContainerName',
      // 2026-08-28: generic-folder mode never reaches
      // awaitingVaultCreation (skips straight here, see
      // startLinkingGenericFolder), so only this branch needed the
      // syncMode check - matches the convention already used for
      // obsidianVaultPath in _saveRepository below.
      LinkingStep.pickingVaultFolder => ctrl.syncMode == SyncMode.genericFolder
          ? 'Select your folder'
          : 'Select your $kContainerName',
      _ => 'Your turn',
    };

    // 2026-08-14: content used to sit pinned to the top of the
    // SingleChildScrollView regardless of screen height - fine on the
    // long vault-creation screen (12 steps usually exceeds the
    // viewport anyway) but left the shorter folder-picker screen
    // looking top-heavy with empty space below. ConstrainedBox with a
    // minHeight matching the viewport lets the Column center when
    // content is short, while still scrolling normally once content
    // (like the 12-step checklist) grows past the viewport.
    //
    // Real device feedback: centering within just the Expanded body
    // (below the AppBar + progress bar) still reads as "pushed down"
    // relative to the whole phone screen, since the header eats real
    // space at the top that this calculation never accounted for.
    // Appending an invisible trailing spacer equal to the header's own
    // height, rather than trying to precompute an offset, shifts the
    // *visible* content up by exactly half the header height - matches
    // where it would sit if centered against the full screen - without
    // any risk of clipping content on the long vault-creation screen
    // (there, content already exceeds the viewport, so the spacer just
    // adds harmless extra scroll space at the bottom).
    final headerHeight =
        (Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight) + 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),

                // Heading
                Text(
                  heading,
                  style: TextStyle(
                      color: kStar, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                // Instruction — numbered checklist on both user-action
                // screens (each background-switches into Obsidian or
                // iOS's native folder picker and back), plain text
                // fallback for anything else.
                //
                // 2026-08-14: real device confirmed page 4's checklist
                // opened with all 6 boxes already ticked. Both
                // checklists sit at the same position in this Column
                // and share the same widget type with no Key, so
                // Flutter's element diffing treated page 4's as an
                // update to page 3's existing State rather than a new
                // one - _checked (sized for 12 steps) carried over
                // positionally into the 6-step list instead of
                // resetting. A groupNumber-keyed instance per step
                // forces a fresh State (and fresh _checked) each time.
                if (ctrl.step == LinkingStep.awaitingVaultCreation)
                  _StepChecklist(
                    key: const ValueKey(1),
                    groupNumber: 1,
                    steps: ctrl.vaultCreationSteps,
                    // 2026-08-19: was also wired to fire on 1.11
                    // (reopen Obsidian) - that step is gone now, only
                    // 1.1 (create the vault) still needs the real
                    // swipe-to-open action.
                    swipeActions: {0: ctrl.openObsidianNow},
                    onChanged: (checked) =>
                        setState(() => _vaultCreationChecked = checked),
                  )
                else if (ctrl.step == LinkingStep.pickingVaultFolder)
                  _StepChecklist(
                    key: const ValueKey(2),
                    groupNumber: 2,
                    steps: ctrl.vaultFolderSteps,
                    // 2026-08-18: "2.1 to be swipe up" - was a tap.
                    // resilient: the native picker can be cancelled
                    // silently with no advance, unlike OPEN OBSIDIAN
                    // above - see _SwipeChecklistRow.resilient.
                    swipeActions: {0: ctrl.pickVaultFolder},
                    resilientSwipeIndices: const {0},
                  )
                else
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
                      style: TextStyle(color: kStar, fontSize: 16, height: 2.0),
                    ),
                  ),

                const SizedBox(height: 16),

                if (ctrl.step == LinkingStep.awaitingVaultCreation) ...[
                  // 2026-08-15: OPEN OBSIDIAN moved into checklist item
                  // 1.1 itself (see _StepChecklist's firstItemSwipeAction
                  // above) - the standalone swipe-up button that used to
                  // sit here is gone, per explicit direction.
                  // 2026-08-16: bottom-left instead of centered (no
                  // Center wrapper - the Column's own crossAxisAlignment
                  // is already .start), per explicit direction. Blocked
                  // by _validateVaultCreationDone() until 1.10 is
                  // ticked.
                  // 2026-08-19: final asset split - fixed person, a
                  // real draggable dog, a code-drawn leash that
                  // stretches with the drag, snapping to
                  // progress_running.gif once dragged past threshold
                  // (see widgets/leash_swipe_confirm.dart). Label
                  // dropped ("saves vertical space... user should be
                  // able to figure out to slide... once the gif is
                  // correctly showing the person holding the dog on
                  // the leash").
                  SwapGifSwipeConfirm(
                    animatedAssetPath: 'assets/gifs/progress_running.gif',
                    onConfirm: ctrl.confirmVaultCreated,
                    validate: _validateVaultCreationDone,
                  ),
                ] else if (ctrl.step == LinkingStep.pickingVaultFolder) ...[
                  // 2026-08-15: VAULT FOLDER moved into checklist item
                  // 2.1 itself (firstItemTapAction above) - the standalone
                  // button that used to sit here is gone. Only the busy
                  // indicator remains, shown once the tap in the
                  // checklist has fired.
                  if (ctrl.pickingFolder)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _PulsingDots(),
                        const SizedBox(width: 16),
                        // 2026-08-15: "picker" is developer jargon - the
                        // thing that opens is iOS's Files browser (the
                        // exact steps 2.2/2.3 already call "Browse" and
                        // "On My iPhone"), so name it that way. Lower-
                        // case + larger per explicit direction.
                        Text('Opening files…',
                            style: TextStyle(color: kTextMid, fontSize: 18)),
                      ],
                    ),
                ],

                SizedBox(height: headerHeight),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 2026-08-14: numbered, tickable checklist shared by both user-action
// screens (vault creation: group 1, folder picking: group 2). Checkbox
// state is local widget state, not controller state - it's just a
// progress marker for bouncing out to Obsidian or the native picker and
// back, not something that needs to survive navigating away from this
// screen.
class _StepChecklist extends StatefulWidget {
  final int groupNumber;
  final List<String> steps;
  // 2026-08-15: page 3/4 both start numbering at .1 (default); page 5's
  // checklist explicitly starts at .0, since its first item is the
  // swipe that opens Obsidian rather than the first action inside it.
  final int startIndex;
  // 2026-08-15: rows at these indices become a real swipe-up gesture
  // instead of a plain checkbox - folds the actual action into its
  // own checklist line instead of a separate control elsewhere on
  // screen, per explicit direction ("have the swipe up button here").
  // 2026-08-17: generalized from a single firstItemSwipeAction to a
  // map - "1.11 reopen Obsidian won't open, swiping 1.1 [now struck
  // through] doesn't work... add the swipe up function in 1.11 too" -
  // OPEN OBSIDIAN genuinely needs to fire twice in this flow (create
  // the vault, then reopen it), and once 1.1's row is done it can't
  // be swiped again to do the second one.
  final Map<int, Future<void> Function()> swipeActions;
  // 2026-08-18: "2.1 to be swipe up" - VAULT FOLDER moved from a tap
  // action to a swipe action for consistency ("the current image had
  // a few magic stars... to show the enduser clearly it's an action
  // to swipe" - every real action in this app is now a swipe). Which
  // indices in swipeActions need the resilient (cancel-safe) variant -
  // see _SwipeChecklistRow's resilient param for why this can't be a
  // blanket default. _TapChecklistRow removed entirely now that
  // nothing uses tap actions.
  final Set<int> resilientSwipeIndices;
  // 2026-08-16: reports the checkbox list back up on every toggle, so
  // a sibling control (I'VE CREATED IT) can validate specific steps
  // were actually ticked before allowing its own confirm to proceed.
  final void Function(List<bool>)? onChanged;
  const _StepChecklist({
    super.key,
    required this.groupNumber,
    required this.steps,
    this.startIndex = 1,
    this.swipeActions = const {},
    this.resilientSwipeIndices = const {},
    this.onChanged,
  });

  @override
  State<_StepChecklist> createState() => _StepChecklistState();
}

class _StepChecklistState extends State<_StepChecklist> {
  late final List<bool> _checked = List.filled(widget.steps.length, false);

  @override
  void initState() {
    super.initState();
    // Deferred to after this frame - calling widget.onChanged
    // synchronously here would trigger the parent's setState() while
    // this widget is still mid-build.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onChanged?.call(_checked));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.steps.length; i++)
            if (widget.swipeActions.containsKey(i))
              _SwipeChecklistRow(
                label:
                    '${widget.groupNumber}.${i + widget.startIndex}  ${widget.steps[i]}',
                onConfirm: widget.swipeActions[i]!,
                resilient: widget.resilientSwipeIndices.contains(i),
                onDone: () {
                  setState(() => _checked[i] = true);
                  widget.onChanged?.call(_checked);
                },
              )
            else
              CheckboxListTile(
                value: _checked[i],
                onChanged: (checked) {
                  setState(() => _checked[i] = checked ?? false);
                  widget.onChanged?.call(_checked);
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                activeColor: kGreen,
                checkColor: kVoid,
                title: Text(
                  '${widget.groupNumber}.${i + widget.startIndex}  ${widget.steps[i]}',
                  style: TextStyle(
                    color: _checked[i] ? kTextMid : kStar,
                    fontSize: 16,
                    height: 1.6,
                    decoration: _checked[i] ? TextDecoration.lineThrough : null,
                    decorationColor: kTextMid,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// 2026-08-15: a checklist row that IS the swipe-up gesture, instead of
// a checkbox describing a separate button elsewhere. Same drag-
// threshold shape as _SwipeToConfirm, just row-height instead of a big
// pill, and self-ticks (strikethrough, dimmed) once actually swiped -
// no separate manual checkbox once the row itself performed the action.
class _SwipeChecklistRow extends StatefulWidget {
  final String label;
  final Future<void> Function() onConfirm;
  // 2026-08-17: reports completion back to the parent checklist's
  // _checked list, same as a ticked checkbox - needed now that a
  // swipe row (1.11) can be one of the indices a sibling control
  // validates before letting its own confirm proceed.
  final VoidCallback? onDone;
  // 2026-08-18: "2.1 to be swipe up" - VAULT FOLDER's native picker
  // can be cancelled silently (no exception, ctrl.step doesn't
  // advance), unlike OPEN OBSIDIAN (1.1/1.11) where success *also*
  // never advances ctrl.step - so "reset if still mounted after" can't
  // tell the two apart universally. When true, awaits onConfirm and
  // re-enables itself if still mounted afterward (meaning nothing tore
  // this screen down, i.e. it didn't succeed) - same fix
  // _TapChecklistRow needed for the identical class of bug. When false
  // (the default, OPEN OBSIDIAN's case), stays permanently marked done
  // once swiped - there's no cancel-in-place scenario for it.
  final bool resilient;
  const _SwipeChecklistRow({
    required this.label,
    required this.onConfirm,
    this.onDone,
    this.resilient = false,
  });

  @override
  State<_SwipeChecklistRow> createState() => _SwipeChecklistRowState();
}

class _SwipeChecklistRowState extends State<_SwipeChecklistRow> {
  static const _threshold = 36.0;
  double _drag = 0;
  bool _done = false;

  void _onUpdate(double delta) {
    if (_done) return;
    // 2026-08-19: "swipe up text only physically moves up about 2
    // lines, make the text swipe up as far as the user swipes" - the
    // visible travel was capped at -_threshold*2 (72px) regardless of
    // how far the finger kept moving past that point. _threshold below
    // still gates how far it needs to travel to register as a
    // completed swipe (in _onEnd) - only the render-time cap is gone,
    // so the row now tracks the finger 1:1 with no ceiling.
    setState(() => _drag = (_drag + delta).clamp(double.negativeInfinity, 0.0));
  }

  void _onEnd() {
    if (_done) return;
    final reached = -_drag >= _threshold;
    setState(() => _drag = 0);
    if (!reached) return;

    setState(() => _done = true);
    if (widget.resilient) {
      _fireResilient();
    } else {
      widget.onDone?.call();
      widget.onConfirm();
    }
  }

  Future<void> _fireResilient() async {
    await widget.onConfirm();
    if (mounted) {
      setState(() => _done = false);
    } else {
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (-_drag / _threshold).clamp(0.0, 1.0);
    final color = _done ? kTextMid : Color.lerp(kStar, kGreen, progress)!;
    return GestureDetector(
      onVerticalDragUpdate: (d) => _onUpdate(d.delta.dy),
      onVerticalDragEnd: (_) => _onEnd(),
      child: Stack(
        children: [
          if (!_done) const Positioned.fill(child: SparkleBackground()),
          // 2026-08-19: "swipe up and Obsidian does open, but the line
          // of text doesn't move up, but the line of text must move up
          // as per normal swipe up actions" - _drag was already tracked
          // for the threshold/color logic above but never rendered, so
          // the row sat visually still through the whole drag. Now
          // follows the finger the same way _GifSwipeTrigger's pull/push
          // rows already do (home_screen.dart).
          Transform.translate(
            offset: Offset(0, _drag),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.keyboard_double_arrow_up_rounded,
                      color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                        decoration: _done ? TextDecoration.lineThrough : null,
                        decorationColor: kTextMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 2026-08-16: SwapGifSwipeConfirm (formerly private _SwapGifSwipeConfirm
// here) moved to widgets/swap_gif_swipe_confirm.dart so PairingScreen
// could reuse it for CONTINUE - SET UP VAULT.

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
        color: [kGreen, kStar, Colors.amber][rand.nextInt(3)],
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
    final ctrl = widget.ctrl;
    final alreadySaved = provider.repos.any(
      (r) =>
          r.remoteHost == ctrl.desktopIp && r.remotePath == ctrl.bareRepoPath,
    );
    if (alreadySaved) {
      // 2026-08-20: real gap, found while adding multi-repo support -
      // this used to silently no-op with zero feedback when the exact
      // same desktop+bare-repo combo was already linked (the download
      // above still ran in full either way, just the new DB record got
      // dropped) - confusing, looked like a successful new link that
      // quietly did nothing. Now says so explicitly. Real fix for the
      // underlying case (wanting a second vault to sync to a different
      // repo) is Settings -> Git bare repo path, set before linking.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: kSurface,
            content: Text(
              'A vault is already linked to this exact desktop + bare '
              'repo - nothing new was added. To link a genuinely '
              'different vault, set a different Git bare repo path in '
              'Settings first.',
              style: TextStyle(color: kStar, fontSize: 14),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    final vaultPath = ctrl.pickedVaultPath;
    final vaultBookmark = ctrl.pickedVaultBookmark;
    if (vaultPath == null || vaultBookmark == null) return; // web target

    await provider.addRepository(Repository(
      // 2026-08-14: was hardcoded to the literal generic string
      // "PKM_vault" regardless of which vault was linked - the
      // app-bar status widget (_AppBarRepoStatus) displays this as
      // the vault's name, so every repo looked identical and there
      // was no way to tell which vault was actually connected. Now
      // uses the real vault folder name, same pattern already used
      // correctly for obsidianVaultPath below.
      name: vaultPath.split('/').last,
      remoteHost: ctrl.desktopIp,
      remoteUser: ctrl.desktopUser,
      remotePath: ctrl.bareRepoPath,
      remotePort: ctrl.sshPort,
      localPath: vaultPath,
      vaultBookmark: vaultBookmark,
      // 2026-08-15: was hardcoded to literal "Localsync" - same stale
      // assumption fixed in the display text and deep link earlier,
      // just missed here. Display-only field (see repository.dart),
      // but still wrong for anyone who typed a different vault name.
      // 2026-08-27: a Tier 0 genericFolder repo has no $kNoteAppName
      // container at all - "On My iPhone/$kNoteAppName/..." would be an
      // actively wrong claim about where the folder lives, not just an
      // unused display string, so this branches on ctrl.syncMode.
      obsidianVaultPath: ctrl.syncMode == SyncMode.genericFolder
          ? vaultPath.split('/').last
          : 'On My iPhone/$kNoteAppName/${vaultPath.split('/').last}',
      autoSync: true,
      status: SyncStatus.ok,
      lastSync: DateTime.now(),
      syncMode: ctrl.syncMode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // 2026-08-15: this screen just grew a real checklist + swipe row on
    // top of the burst animation and text that were already here -
    // wrapped in scroll now (matches _ParkedView's pattern) so shorter
    // phones don't hit a layout overflow instead of just scrolling.
    // 2026-08-17: real device feedback - the final swipe control was
    // sitting below the fold, and the swipe gesture didn't register
    // until scrolled into view (a real usability bug, not just
    // cosmetic - the primary action was effectively unreachable at a
    // glance). Shrunk the checkmark/burst area and outer vertical
    // padding so the whole screen fits without scrolling on a normal
    // phone - this was the one area with real slack to give back.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            height: 100,
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
                    child: Icon(Icons.check_circle, color: kGreen, size: 50),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 2026-08-16: emoji replaced with the same success gif used
          // for the final swipe control below - decorative, always
          // playing (not gated behind a trigger like the swipe gifs,
          // there's no gesture here to wait for).
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 2026-08-28: real feedback, live - this heading was
              // hardcoded regardless of mode, even though the body text
              // right below it already correctly said "files" for Tier
              // 0 (see the syncMode ternary a few lines down) - same
              // class of bug already fixed there, just missed here.
              Text(
                  widget.ctrl.syncMode == SyncMode.genericFolder
                      ? 'Your files have arrived!'
                      : 'Your notes have arrived!',
                  style: TextStyle(
                      color: kStar, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              // 2026-08-20: "the timing leaves the standing dog jumping
              // in the air, the loop would be better if the standing
              // dog was pausing on the ground" - the file's own baked
              // timing (110ms per frame, except a 450ms hold on frame
              // 5) gives its longest pause to frame 5, a jump/lean pose
              // right before the loop wraps back to frame 0's stand.
              // Frames alternate stand (0,2,4) / jump (1,3,5) - moving
              // the long hold onto frame 4 (the last stand pose) and
              // shrinking frame 5 to a brief flash makes the loop read
              // as resting on the ground, not airborne, without
              // touching the actual artwork.
              const ControllableGif(
                assetPath: 'assets/gifs/dog_success_stand.gif',
                playing: true,
                height: 40,
                frameDurationOverrides: {
                  4: Duration(milliseconds: 700),
                  5: Duration(milliseconds: 50),
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Fixed 2026-08-09: this used to say "Your phone vault is
          // linked to your desktop" - overclaiming. Localsync can only
          // verify that files were downloaded onto the phone (checked
          // in _verifySync()); it has no way to confirm Obsidian was
          // ever actually pointed at that folder - no cross-app
          // introspection on iOS. Real device feedback: a user reached
          // this screen without ever having opened the folder as a
          // vault in Obsidian ("Localsync" never appeared in Obsidian's
          // own vault list), and the old wording had already told them
          // they were fully linked. Now honest about what's actually
          // still required, with a direct way to do it from here.
          // Rewritten 2026-08-09 alongside the vault-folder-picker
          // rework: the old copy told the user to go select the vault
          // in Obsidian "if you haven't already" - stale as of this
          // rewrite, since selecting the vault folder is now a
          // precondition of reaching this screen at all (it happens
          // before the clone, not after). This screen is reached only
          // once Localsync already has real access to that same folder
          // Obsidian is showing.
          Text(
            // 2026-08-14: was hardcoded to a literal "Localsync" vault
            // name - stale now that step 1's instructions never tell
            // the user to type that specific name (see
            // vaultCreationSteps). Uses the actual picked folder's
            // name, same value OPEN OBSIDIAN below now deep-links to.
            // 2026-08-28: branched on syncMode - a Tier 0 user may have
            // no $kNoteAppName installed at all (see
            // startLinkingGenericFolder's doc comment), so "vault in
            // Obsidian" was an actively wrong claim for that flow, not
            // just unpolished copy.
            widget.ctrl.syncMode == SyncMode.genericFolder
                ? 'Your files have been synced into\n'
                    '"${widget.ctrl.pickedVaultPath?.split('/').last ?? 'folder'}".'
                : 'Your notes have been downloaded into\n'
                    '"${widget.ctrl.pickedVaultPath?.split('/').last ?? kContainerName}" '
                    'vault in $kNoteAppName.',
            style: TextStyle(color: kTextMid, fontSize: 15, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // 2026-08-28: the whole "Finish up in Obsidian" section below
          // (trust-plugins prompt, indexing wait, community-plugins
          // skip) only makes sense for an actual Obsidian vault - a
          // Tier 0 generic-folder user has nothing to finish inside
          // Obsidian, and may not have it installed at all, so this
          // entire block is skipped for that mode rather than just
          // reworded. Falls straight to the leave-setup swipe below.
          if (widget.ctrl.syncMode != SyncMode.genericFolder) ...[
            // 2026-08-15: real device feedback - reaching this screen and
            // tapping OPEN OBSIDIAN used to hand the user off with zero
            // guidance for what happens next inside Obsidian. Confirmed
            // live: because the clone just brought in the desktop vault's
            // real .obsidian/plugins/ folder, Obsidian shows a one-time
            // "trust this vault's plugins" prompt before it'll index -
            // this never appeared on page 3's empty, plugin-free vault,
            // only here, after real content exists. Wording below is the
            // exact on-screen text from the live run (also matches the
            // user's own older sync research - "Trust author and enable
            // plugins" - which flagged this same step in other contexts,
            // just never mapped onto this specific screen before now).
            Text('Finish up in Obsidian:',
                style: TextStyle(
                    color: kStar, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            // 2026-08-15: expanded to include the two swipe actions
            // themselves (3.0, 3.5) and the background-switch back to
            // Localsync (3.4) per explicit direction, so the checklist is
            // a complete, self-contained record of every physical action
            // in the sequence - not just the three that happen inside
            // Obsidian. 3.0 (OPEN OBSIDIAN) is now embedded directly in
            // the checklist as a real swipe-up gesture, same as page 3's
            // 1.1, instead of a separate button below.
            // 2026-08-18: "3.5 swipe, delete" - dropped the trailing
            // checklist line entirely, matching page 2's I'VE CREATED IT
            // (no checklist line at all for the confirm action, just the
            // standalone gif control below).
            _StepChecklist(
              key: const ValueKey(3),
              groupNumber: 3,
              startIndex: 0,
              swipeActions: {0: widget.ctrl.openObsidianNow},
              steps: const [
                'swipe up to open $kNoteAppName',
                'tap Trust author and enable plugins',
                'wait for Indexing vault... to finish',
                'tap X to skip Community plugins (set up later)',
                'return to Localsync app',
              ],
            ),
            const SizedBox(height: 16),
          ],
          Center(
            // 2026-08-18: "bottom needs the same progress_person/dog
            // and when swiped the progress_running.gif takes over" -
            // same asset pair as page 2's I'VE CREATED IT, for
            // consistency between the two confirm actions. _leaveSetup,
            // not a bare pop - see this file's header comment for the
            // black-screen crash this fixes.
            child: SwapGifSwipeConfirm(
              animatedAssetPath: 'assets/gifs/progress_running.gif',
              onConfirm: () => _leaveSetup(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final Color color;
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
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.drawCircle(offset, p.size * (1 - progress * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Failed ─────────────────────────────────────────────────────────────────────

class _FailedView extends StatefulWidget {
  final LinkingController ctrl;
  const _FailedView({required this.ctrl});

  @override
  State<_FailedView> createState() => _FailedViewState();
}

class _FailedViewState extends State<_FailedView> {
  final _discovery = DiscoveryService();
  bool _discovering = false;

  // 2026-08-23: real feedback, live - "why should I go setting up IP
  // addresses... this is way too complicated for new users." Real gap:
  // auto-discovery (mDNS) already existed, but only in Settings, never
  // surfaced at the actual point of failure during setup - a user
  // hitting connectionRefused had no way to know it existed at all.
  // This runs the same DiscoveryService Settings already uses, and on
  // success updates the IP AND retries setup automatically - no
  // terminal command, no manually reading an IP address, ever, for the
  // common case where the desktop is genuinely reachable and just
  // advertising via mDNS.
  Future<void> _findAndRetry() async {
    setState(() => _discovering = true);
    final ip = await _discovery.findDesktopIp();
    if (!mounted) return;
    setState(() => _discovering = false);
    if (ip == null) {
      // 2026-08-23: real feedback, live - "the desktop won't be found
      // if the hotspot isn't turned on or the USB cable isn't plugged
      // in - what's the plan for that?" No software fix exists for a
      // connection that doesn't exist yet - that's a real prerequisite,
      // not a gap. What was fixable: "check it's on the same network"
      // was vague. Names the two actual things to check instead.
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
    widget.ctrl.updateDesktopIp(ip);
    widget.ctrl.startLinking();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final failure = ctrl.lastFailure!;
    final isPairingFailure = failure.error == LinkingError.pairingNotComplete ||
        failure.error == LinkingError.sshAuthFailed;

    // 2026-08-16: "drag only in bottom left corner, not possible on
    // entire screen?" - reported three times running a Row/Column/
    // Expanded-based layout, including after wrapping the trigger in
    // SizedBox.expand. Rather than keep guessing at which loose
    // constraint in that chain wasn't resolving to the real available
    // space, the pairing-failure branch is rebuilt around a Stack: the
    // drag canvas is a Positioned.fill BACKGROUND layer (guaranteed to
    // receive the Stack's true resolved size), diagnostic text is
    // pinned to the top, CANCEL pinned to the bottom - both float over
    // the canvas rather than competing with it for space in a Column.
    final diagnostics = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text('Something stopped',
            style: TextStyle(
                color: kStar, fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),

        // What happened
        DiagCard(
          label: 'WHAT HAPPENED',
          text: failure.diagnosis,
          accent: Colors.redAccent,
        ),
        const SizedBox(height: 12),

        // 2026-08-16: "I just told you text is verbose and to use
        // infographics for workflow processes" - for the pairing
        // failures, the fix is the drag graphic directly below, so a
        // text card spelling out "drag the key into the lock" on top of
        // it was pure redundancy. Dropped the card, replaced with a
        // plain arrow pointing straight at the thing to do - zero
        // reading required. Other failure types keep the text card
        // since there's no graphic answering them.
        if (!isPairingFailure) ...[
          // 2026-08-21: same fix as home_screen.dart's sync-error
          // dialog - "check all text which is verbose, change to point
          // form" - these resolution strings are already one point per
          // line, DiagCard just wasn't presenting them as a list.
          DiagCard(
            label: 'HOW TO FIX IT',
            text: failure.resolution,
            accent: kGreen,
            icon: Icons.lightbulb_outline,
            bulleted: true,
          ),
          // 2026-08-23: real feedback, live - manual IP steps are the
          // fallback now, not the only option. Auto-discovery does the
          // whole thing (find + retry) in one tap for the common case
          // where the desktop is genuinely reachable and advertising.
          if (failure.error == LinkingError.connectionRefused) ...[
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
                        color: kGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kGreen),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ] else ...[
          const SizedBox(height: 4),
          Center(
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: kGreen, size: 32),
          ),
        ],

        if (failure.debugDetail != null &&
            failure.debugDetail!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          DiagCard(
            label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
            text: failure.debugDetail!,
            accent: Colors.redAccent,
            maxLength: 300,
          ),
        ],
      ],
    );

    final cancelButton = Center(
      child: TextButton(
        onPressed: () => _leaveSetup(context),
        child: Text('CANCEL',
            style: TextStyle(color: kTextDim, fontSize: 11, letterSpacing: 1)),
      ),
    );

    if (!isPairingFailure) {
      // No drag graphic involved for this failure type - plain scrolling
      // content is enough, same shape as before this rework.
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: SingleChildScrollView(child: diagnostics)),
            const SizedBox(height: 32),
            // 2026-08-16: TRY AGAIN (re-runs the whole 8-step setup
            // sequence) only makes sense for failures unrelated to
            // pairing - direct feedback that showing it alongside PAIR
            // NOW was confusing, and correctly so: retrying setup
            // without pairing first here would just fail the same way
            // again.
            _PrimaryButton(label: 'TRY AGAIN', onPressed: ctrl.startLinking),
            const SizedBox(height: 12),
            cancelButton,
          ],
        ),
      );
    }

    // 2026-08-15: "I want to use the images to drag for the pair now" -
    // PAIR NOW replaced with the same drag-the-key gesture used inside
    // PairingScreen itself. No real async work here (just a
    // navigation), so onConfirm is a no-op and the actual push happens
    // in onSettled, once the drag/glow animation has genuinely finished
    // playing - same onSettled contract as GifSwipeTrigger/CommitScreen,
    // so the transition never cuts the animation off mid-flight.
    //
    // 2026-08-16: "messed up with images now over the top area with
    // text" - a Positioned.fill canvas vertically centered in the whole
    // screen inevitably overlapped the diagnostic text pinned above it,
    // since nothing reserved that space. ContentAboveDragCanvas measures
    // the real content (and CANCEL) height and positions the canvas
    // exactly between them instead of guessing a fixed offset.
    //
    // 2026-08-16, follow-up: the SingleChildScrollView here was the real
    // bug behind "images are way down the bottom of the page... keyboard
    // appears and now I can't see the phonekey image... unable to
    // progress" on PairingScreen's identical setup - SingleChildScrollView
    // fills whatever height it's given rather than shrink-wrapping to its
    // child, so the measured "content height" was tracking the available
    // screen height (which shrinks with the keyboard) instead of the
    // actual short diagnostic text. Plain Padding, no ScrollView.
    //
    // 2026-08-23: briefly replaced with a plain tap button, reverted
    // same day - "stop changing my nice design... return the phonelock
    // dragging to the laptoplock." Restored verbatim from git history.
    // autoResumeSetup: true kept in onSettled below - a real, separate
    // fix (no repeated setup after pairing succeeds) added after this
    // code was first written, unrelated to drag-vs-button.
    return ContentAboveDragCanvas(
      canvas: KeyPairingTrigger(
        runningLabel: 'OPENING PAIRING…',
        onConfirm: () async {},
        // 2026-08-20: real bug, found live - this used to hardcode
        // '172.20.10.11' independently of ctrl.desktopIp, so a user
        // who'd corrected their address via the new Desktop IP setting
        // (home_screen.dart) would still hit this stale value here on
        // retry. ctrl is already the live LinkingController - use its
        // real, current values instead of a second, disconnected copy.
        onSettled: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PairingScreen(
              desktopUser: ctrl.desktopUser,
              desktopIp: ctrl.desktopIp,
              autoResumeSetup: true,
            ),
          ),
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: diagnostics,
      ),
      bottomPinned: Padding(
        padding: const EdgeInsets.all(20),
        child: cancelButton,
      ),
    );
  }
}

// 2026-08-20: _DiagCard moved to widgets/diag_card.dart (as DiagCard, no
// underscore) so home_screen.dart's sync-error dialog can share the
// exact same labeled-card layout instead of dumping one undifferentiated
// block of text.

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
                decoration: BoxDecoration(
                  color: kGreen,
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

// ── Device glyph (pictogram for source/destination) ──────────────────────────────

// ── Scope checklist row ──────────────────────────────────────────────────────

// 2026-08-28: real feedback, live - moved here from SyncChoiceScreen the
// same day it was added there (see this class's own callers for the
// full story). Stage 1's own technical-setup context, unlike the warm
// first-hello screen, is the right place for a Settings reminder.
class _SettingsReminder extends StatelessWidget {
  final VoidCallback onTap;
  const _SettingsReminder({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, color: Colors.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('First time? Check your desktop connection',
                        style: TextStyle(
                            color: kStar, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Desktop username, IP address, and folder path',
                        style: TextStyle(color: kTextMid, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: kTextDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeRow extends StatelessWidget {
  final String label;
  const _ScopeRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 2026-08-25: 15 -> 13, matching the shield/clock rows below -
          // same "only a few shades and colours, for consistency" pass.
          Text(label, style: TextStyle(color: kTextMid, fontSize: 13)),
          Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
        ],
      ),
    );
  }
}

class _DeviceGlyph extends StatelessWidget {
  final IconData? icon;
  // 2026-08-20: desktop glyph now uses pairing_laptop_plain.svg (same
  // body as the pairing screen's keyway lock, just without the cut -
  // this view isn't about key-pairing specifically) instead of the
  // generic Icons.computer_rounded, for visual consistency with the
  // rest of the pairing flow. svgAsset takes precedence over icon when
  // both are given - icon stays supported for callers that don't have
  // a custom asset (the vault side, still Icons.folder_rounded or
  // similar).
  final String? svgAsset;
  final String label;
  final String caption;
  final bool accent;
  final double width;
  final double iconSize;
  final Animation<double>? pulse;
  final bool hovering;
  // 2026-08-24: "text needs to stay level between glyphs" - iconSize
  // used to drive both the actual rendered SVG size AND the reserved
  // slot height above the label, so shrinking one glyph's icon (the
  // phone-key, to fit its lock) also pulled its label up out of line
  // with the other glyph's label. svgSize/iconTopPad let the *rendered*
  // icon be smaller and offset within a slot that's still iconSize
  // tall, so label position stays identical across differently-sized
  // icons.
  final double? svgSize;
  final double iconTopPad;
  const _DeviceGlyph({
    this.icon,
    this.svgAsset,
    required this.label,
    required this.caption,
    this.accent = false,
    this.width = 140,
    this.iconSize = 56,
    this.pulse,
    this.hovering = false,
    this.svgSize,
    this.iconTopPad = 0,
  }) : assert(icon != null || svgAsset != null,
            'must provide either icon or svgAsset');

  @override
  Widget build(BuildContext context) {
    // 2026-08-11: "images and text too small, plenty of space to
    // enlarge" - real device review. width/iconSize now computed
    // responsively by the caller ("enlarge to max size so still fitting
    // in left right phone edges") instead of a fixed guess.
    // 2026-08-11 (second pass): label color was inconsistent - the
    // accent (vault) glyph's label rendered kStar (near-white) while
    // the desktop glyph's rendered kTextMid (grey). Label now always
    // kTextMid; accent still differentiates the icon color only.
    // 2026-08-11 (third pass): "text colours aren't the same" persisted
    // even after that fix - root cause was the pulse animation wrapping
    // the *whole* glyph (icon+label+caption) in a fading Opacity, so
    // the desktop side visibly washed out relative to the solid vault
    // side despite using the identical color value. Pulse now wraps
    // only the icon. Icon also always sits in a matching padding box so
    // both glyphs have identical layout heights regardless of
    // drop-target hover state - fixes the "notebook image isn't the
    // same height as desktop" report.
    // 2026-08-17: hover cue switched from a green border to the same
    // pulsing glow (PulsingGlow) the pairing screen's lock uses once
    // the key seats, so the two "something just connected" moments in
    // the app read as the same effect.
    final color = accent ? kGreen : kTextDim;
    final renderSize = svgSize ?? iconSize;
    Widget iconWidget = svgAsset != null
        ? SvgPicture.asset(svgAsset!, width: renderSize, height: renderSize)
        : Icon(icon, size: renderSize, color: color);
    if (pulse != null) {
      iconWidget = AnimatedBuilder(
        animation: pulse!,
        builder: (_, child) => Opacity(
          opacity: 0.6 + (pulse!.value * 0.4),
          child: child,
        ),
        child: iconWidget,
      );
    }
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: iconSize + 16,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: iconTopPad),
                child: PulsingGlow(
                  active: hovering,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: iconWidget,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  color: kTextMid, fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(caption,
              style: TextStyle(color: kTextMid, fontSize: 14),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Primary button ─────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          foregroundColor: kVoid,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2),
        ),
        child: Text(label),
      ),
    );
  }
}
