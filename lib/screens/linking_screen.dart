// screens/linking_screen.dart
//
// UI for the vault setup sequence (see linking_controller.dart).
// One park point — opening Obsidian's vault picker — shows plain
// instructions, no tech language. Error screen shows plain diagnosis +
// exact fix steps.

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
import '../services/repository_provider.dart';
import '../widgets/content_above_drag_canvas.dart';
import '../widgets/pulsing_glow.dart';
import '../widgets/controllable_gif.dart';
import '../widgets/diag_card.dart';
import '../widgets/key_pairing_trigger.dart';
import '../widgets/sparkle_background.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import 'home_screen.dart';
import 'pairing_screen.dart';

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
        title: Text(
            '${kGenericAppLabel.toUpperCase()} ${kContainerName.toUpperCase()} SETUP'),
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
      return const LinearProgressIndicator(
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
        valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
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

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 2026-08-11: real device review - the drag pictogram is "the
          // top priority for a user, the rest is sub information", so it
          // now leads the screen instead of the heading. Pictogram
          // replacing the old wall of text (2026-08-09) - built-in
          // Material icons only, no flutter_svg: this session already
          // lost build time twice to native-dependency issues, not worth
          // repeating for a cosmetic asset. Real branded artwork went to
          // the app icon instead (assets/icon/icon.png), not here.
          // 2026-08-11: "page 1 desktop is green but page 2 desktop is
          // grey and vice versa" - this screen had accent backwards
          // relative to the home screen: home screen colors the
          // draggable *source* green (desktop) and leaves the drop
          // *target* (vault) neutral grey until hovered; this screen
          // had it flipped (vault green, desktop grey). Now matches
          // home screen's convention - desktop (source) is accent,
          // vault (target) is neutral grey with a green border only
          // while something is being dragged over it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: rowPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2026-08-19: sparkle hint scoped to just this glyph -
                // see the build()-level comment above for why the
                // whole-screen wrap was removed.
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
                              svgAsset: 'assets/pairing/pairing_laptop_plain.svg',
                              label: 'Your desktop',
                              caption: '${ctrl.desktopUser}@${ctrl.desktopIp}',
                              accent: true,
                              width: glyphWidth,
                              iconSize: glyphIcon,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _DeviceGlyph(
                            svgAsset: 'assets/pairing/pairing_laptop_plain.svg',
                            label: 'Your desktop',
                            caption: '${ctrl.desktopUser}@${ctrl.desktopIp}',
                            accent: true,
                            width: glyphWidth,
                            iconSize: glyphIcon,
                          ),
                        ),
                        // 2026-08-11: pulse now lives inside _DeviceGlyph
                        // itself (icon only, not the label/caption text) -
                        // fixes the pulse fading the desktop label's color
                        // relative to the vault glyph's solid one.
                        child: _DeviceGlyph(
                          svgAsset: 'assets/pairing/pairing_laptop_plain.svg',
                          label: 'Your desktop',
                          caption: '${ctrl.desktopUser}@${ctrl.desktopIp}',
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
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: kGreen, size: 26),
                ),
                DragTarget<bool>(
                  onWillAcceptWithDetails: (_) {
                    setState(() => _dragHover = true);
                    return true;
                  },
                  onLeave: (_) => setState(() => _dragHover = false),
                  onAcceptWithDetails: (_) {
                    setState(() => _dragHover = false);
                    ctrl.startLinking();
                  },
                  builder: (context, candidate, rejected) => _DeviceGlyph(
                    icon: Icons.auto_stories_rounded,
                    label: '$kGenericAppLabel $kContainerName',
                    caption: 'this phone',
                    width: glyphWidth,
                    iconSize: glyphIcon,
                    hovering: _dragHover,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                // 2026-08-18: "Drag to begin text no longer needed" -
                // the sparkle background on the desktop glyph itself
                // (above) carries that hint visually, same reasoning as
                // dropping the swipe-confirm captions elsewhere once
                // their gif art made the gesture clear.
                SizedBox(height: 16),
                // Heading moved below the pictogram+hint (2026-08-11,
                // was the page's top line before) - reworded to name
                // the source explicitly ("desktop Obsidian vault")
                // since "Connect your Obsidian vault" read as ambiguous
                // on real device review - which vault, desktop or
                // phone?
                Text(
                    'Bring your desktop $kGenericAppLabel $kContainerName to this phone',
                    style: TextStyle(
                        color: kStar,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
                SizedBox(height: 20),
                // Answers "what exactly gets downloaded" directly, in
                // place of the old vaguer paragraph - fixed 2026-08-09
                // per real user feedback that START DOWNLOAD gave no
                // sense of scope before committing to it. 2026-08-11:
                // user specifically asked for this as a checklist (item
                // name + green tick) rather than a paragraph - each
                // item is still named explicitly, so it's less text
                // without losing the precision a safety/scope guarantee
                // needs.
                SizedBox(
                  width: 220,
                  child: Column(
                    children: [
                      _ScopeRow(label: 'Notes'),
                      _ScopeRow(label: 'Folders'),
                      _ScopeRow(label: 'Attachments'),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // 2026-08-11: shield icon enlarged ~50% (14 -> 21px)
                // per explicit direction. Wording also fixed - "nothing
                // else on this phone is touched" read as if localsync
                // might be reading/scanning existing phone data, when
                // the real direction is desktop -> phone, write-only.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: kTextDim, size: 21),
                    SizedBox(width: 6),
                    Text('No other files on this phone are read or changed.',
                        style: TextStyle(color: kTextDim, fontSize: 12)),
                  ],
                ),
                SizedBox(height: 12),
                // 2026-08-10: "START DOWNLOAD" alone gave no sense this
                // is a real, one-time data copy - relabelled to name
                // the actual action (now the drag gesture), plus a
                // duration expectation. 2026-08-11: added a clock glyph
                // alongside the text as a lighter-weight visual cue
                // than replacing the sentence outright - exact wording
                // ("once", "a few minutes") still needs to be read, not
                // just glanced at.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule_outlined, color: kTextMid, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'This runs once. Larger vaults may take a few minutes.',
                      style:
                          TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ],
            ),
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
                color: kStar, fontSize: 16, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            ctrl.stepSubtitle,
            style: const TextStyle(
                color: kTextDim, fontSize: 11, letterSpacing: 0.3, height: 1.6),
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

  // 2026-08-19: "keep the step to force close, but remove the open and
  // force close again" - 1.11/1.12 (reopen, force-close-again) are
  // gone from vaultCreationSteps entirely now, so 1.10 (force close)
  // is both the sole critical step and the last one in the list.
  static const _criticalIndices = [9]; // 1.10

  String? _validateVaultCreationDone() {
    final checked = _vaultCreationChecked;
    if (checked == null) return null;
    final allCriticalDone =
        _criticalIndices.every((i) => i < checked.length && checked[i]);
    if (allCriticalDone) return null;
    return 'Complete and tick 1.10';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    // Derive a plain heading from the current park point
    final heading = switch (ctrl.step) {
      LinkingStep.awaitingVaultCreation => 'Create your $kContainerName',
      LinkingStep.pickingVaultFolder => 'Select your $kContainerName',
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
                  style: const TextStyle(
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
                      style: const TextStyle(
                          color: kStar, fontSize: 16, height: 2.0),
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
                ] else if (ctrl.step ==
                    LinkingStep.pickingVaultFolder) ...[
                  // 2026-08-15: VAULT FOLDER moved into checklist item
                  // 2.1 itself (firstItemTapAction above) - the standalone
                  // button that used to sit here is gone. Only the busy
                  // indicator remains, shown once the tap in the
                  // checklist has fired.
                  if (ctrl.pickingFolder)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulsingDots(),
                        SizedBox(width: 16),
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
                    decoration:
                        _checked[i] ? TextDecoration.lineThrough : null,
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
    if (alreadySaved) return;

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
      obsidianVaultPath: 'On My iPhone/$kNoteAppName/'
          '${vaultPath.split('/').last}',
      autoSync: true,
      status: SyncStatus.ok,
      lastSync: DateTime.now(),
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
                    child:
                        const Icon(Icons.check_circle, color: kGreen, size: 50),
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
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your notes have arrived!',
                  style: TextStyle(
                      color: kStar, fontSize: 28, fontWeight: FontWeight.w800)),
              SizedBox(width: 10),
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
              ControllableGif(
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
            'Your notes have been downloaded into\n'
            '"${widget.ctrl.pickedVaultPath?.split('/').last ?? kContainerName}" '
            'vault in $kNoteAppName.',
            style: const TextStyle(color: kTextMid, fontSize: 15, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
          const Text('Finish up in Obsidian:',
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

class _FailedView extends StatelessWidget {
  final LinkingController ctrl;
  const _FailedView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
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
        const Text('Something stopped',
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
          DiagCard(
            label: 'HOW TO FIX IT',
            text: failure.resolution,
            accent: kGreen,
          ),
        ] else ...[
          const SizedBox(height: 4),
          const Center(
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
        child: const Text('CANCEL',
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
    return ContentAboveDragCanvas(
      canvas: KeyPairingTrigger(
        runningLabel: 'OPENING PAIRING…',
        onConfirm: () async {},
        onSettled: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PairingScreen(
              desktopUser: 'rapi5',
              desktopIp: '172.20.10.11',
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
                decoration: const BoxDecoration(
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

// ── Device glyph (pictogram for source/destination) ──────────────────────────────

// ── Scope checklist row ──────────────────────────────────────────────────────

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
          Text(label, style: const TextStyle(color: kTextMid, fontSize: 15)),
          const Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
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
    Widget iconWidget = svgAsset != null
        ? SvgPicture.asset(svgAsset!, width: iconSize, height: iconSize)
        : Icon(icon, size: iconSize, color: color);
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
          PulsingGlow(
            active: hovering,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: iconWidget,
            ),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: kTextMid, fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(caption,
              style: const TextStyle(color: kTextMid, fontSize: 14),
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
