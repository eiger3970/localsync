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
import '../constants.dart';
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
              onPressed: canLeave ? () => Navigator.pop(context) : null,
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
                Draggable<bool>(
                  data: true,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Opacity(
                      opacity: 0.85,
                      child: _DeviceGlyph(
                        icon: Icons.computer_rounded,
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
                      icon: Icons.computer_rounded,
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
                    icon: Icons.computer_rounded,
                    label: 'Your desktop',
                    caption: '${ctrl.desktopUser}@${ctrl.desktopIp}',
                    accent: true,
                    width: glyphWidth,
                    iconSize: glyphIcon,
                    pulse: _pulseCtrl,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // 2026-08-11: "this text needs to be immediately below
                // the drag images at the top" - real device review.
                // Also shortened from "Drag your desktop onto the vault
                // to begin" to "Drag to begin" per explicit direction.
                const Text('Drag to begin',
                    style:
                        TextStyle(color: kTextDim, fontSize: 12, height: 1.5),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                // Heading moved below the pictogram+hint (2026-08-11,
                // was the page's top line before) - reworded to name
                // the source explicitly ("desktop Obsidian vault")
                // since "Connect your Obsidian vault" read as ambiguous
                // on real device review - which vault, desktop or
                // phone?
                Text(
                    'Bring your desktop $kGenericAppLabel $kContainerName to this phone',
                    style: const TextStyle(
                        color: kStar,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                // Answers "what exactly gets downloaded" directly, in
                // place of the old vaguer paragraph - fixed 2026-08-09
                // per real user feedback that START DOWNLOAD gave no
                // sense of scope before committing to it. 2026-08-11:
                // user specifically asked for this as a checklist (item
                // name + green tick) rather than a paragraph - each
                // item is still named explicitly, so it's less text
                // without losing the precision a safety/scope guarantee
                // needs.
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
                // 2026-08-11: shield icon enlarged ~50% (14 -> 21px)
                // per explicit direction. Wording also fixed - "nothing
                // else on this phone is touched" read as if synclocal
                // might be reading/scanning existing phone data, when
                // the real direction is desktop -> phone, write-only.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.shield_outlined, color: kTextDim, size: 21),
                    SizedBox(width: 6),
                    Text('No other files on this phone are read or changed.',
                        style: TextStyle(color: kTextDim, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
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
                  children: const [
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

class _ParkedView extends StatelessWidget {
  final LinkingController ctrl;
  const _ParkedView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 8),

                // Heading
                Text(
                  heading,
                  style: const TextStyle(
                      color: kStar, fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),

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
                  )
                else if (ctrl.step == LinkingStep.pickingVaultFolder)
                  _StepChecklist(
                    key: const ValueKey(2),
                    groupNumber: 2,
                    steps: ctrl.vaultFolderSteps,
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
                const SizedBox(height: 32),

                if (ctrl.step == LinkingStep.awaitingVaultCreation) ...[
                  // 2026-08-11 (second pass): text moved inside the swiped
                  // element itself (a pill button) rather than a separate
                  // caption below an icon box, and each action now swipes
                  // in its own direction - up for OPEN OBSIDIAN, right for
                  // I'VE CREATED IT - rather than both using the same up
                  // gesture. Drag distance is no longer clamped to a small
                  // fixed pixel range either: "can the swipe be as long as
                  // the user swipes rather than cutting off... this is a
                  // disconnect with the user" - it now follows the finger
                  // for the real screen's extent, not an arbitrary short
                  // cap.
                  // 2026-08-11 (third pass): laid out side by side rather
                  // than stacked, per explicit direction.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SwipeToConfirm(
                        direction: Axis.vertical,
                        label: 'OPEN ${kNoteAppName.toUpperCase()}',
                        onConfirm: ctrl.openObsidianNow,
                      ),
                      const SizedBox(width: 24),
                      _SwipeToConfirm(
                        direction: Axis.horizontal,
                        label: 'I\'VE CREATED IT',
                        onConfirm: ctrl.confirmVaultCreated,
                      ),
                    ],
                  ),
                ] else if (ctrl.step ==
                    LinkingStep.pickingVaultFolder) ...[
                  // 2026-08-14: was just a static button for the whole
                  // ~30s the native picker + bookmark resolution took -
                  // nothing on screen changed between tapping it and
                  // _step eventually moving to cloning, reading as
                  // frozen. Swaps to the same pulsing-dots pattern
                  // _RunningView uses the instant the tap registers.
                  if (ctrl.pickingFolder)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulsingDots(),
                        SizedBox(width: 16),
                        Text('Opening picker…',
                            style: TextStyle(color: kTextMid, fontSize: 14)),
                      ],
                    )
                  else
                    _PrimaryButton(
                      label: 'VAULT FOLDER',
                      onPressed: ctrl.pickVaultFolder,
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
  const _StepChecklist(
      {super.key, required this.groupNumber, required this.steps});

  @override
  State<_StepChecklist> createState() => _StepChecklistState();
}

class _StepChecklistState extends State<_StepChecklist> {
  late final List<bool> _checked = List.filled(widget.steps.length, false);

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
            CheckboxListTile(
              value: _checked[i],
              onChanged: (checked) =>
                  setState(() => _checked[i] = checked ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              activeColor: kGreen,
              checkColor: kVoid,
              title: Text(
                '${widget.groupNumber}.${i + 1}  ${widget.steps[i]}',
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
      name: '${kGenericAppLabel}_$kContainerName',
      remoteHost: ctrl.desktopIp,
      remoteUser: ctrl.desktopUser,
      remotePath: ctrl.bareRepoPath,
      remotePort: ctrl.sshPort,
      localPath: vaultPath,
      vaultBookmark: vaultBookmark,
      obsidianVaultPath: 'On My iPhone/$kNoteAppName/Synclocal',
      autoSync: true,
      status: SyncStatus.ok,
      lastSync: DateTime.now(),
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
                    child:
                        const Icon(Icons.check_circle, color: kGreen, size: 88),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Your notes have arrived! 🎉',
              style: TextStyle(
                  color: kStar, fontSize: 28, fontWeight: FontWeight.w800)),
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
          Text(
            // 2026-08-14: was hardcoded to a literal "Synclocal" vault
            // name - stale now that step 1's instructions never tell
            // the user to type that specific name (see
            // vaultCreationSteps). Uses the actual picked folder's
            // name, same value OPEN OBSIDIAN below now deep-links to.
            'Your notes have been downloaded into your\n'
            '"${widget.ctrl.pickedVaultPath?.split('/').last ?? kContainerName}" '
            'vault in $kNoteAppName.',
            style: const TextStyle(color: kTextMid, fontSize: 15, height: 1.7),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _PrimaryButton(
            label: 'OPEN ${kNoteAppName.toUpperCase()}',
            onPressed: widget.ctrl.openObsidianNow,
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'SYNCLOCAL HOME',
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
                  color: kStar, fontSize: 20, fontWeight: FontWeight.w600)),
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
            accent: kGreen,
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
                    desktopIp: '172.20.10.11',
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
                      color: kTextDim, fontSize: 11, letterSpacing: 1)),
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
  final Color accent;
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
              style: const TextStyle(color: kStar, fontSize: 15, height: 1.7)),
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

// ── Swipe-to-confirm ─────────────────────────────────────────────────────────

// 2026-08-11: single-action equivalent of the desktop->vault drag on
// pages 1-2, for actions with no natural second element to drag onto
// (open an app, confirm a manual step). Text lives inside the swiped
// pill itself rather than as a separate caption below an icon, each
// instance swipes in its own real direction (vertical or horizontal),
// and the drag distance isn't artificially capped - it tracks the
// finger for the real extent of the gesture, snapping back only on
// release if it didn't clear the threshold. Per direct feedback: a
// short hard cutoff read as "the program's limitation" rather than a
// gesture that responds naturally to the user.
class _SwipeToConfirm extends StatefulWidget {
  final Axis direction;
  final String label;
  final VoidCallback onConfirm;
  const _SwipeToConfirm({
    required this.direction,
    required this.label,
    required this.onConfirm,
  });

  @override
  State<_SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<_SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 64;
  // Generous, not a tight cutoff - just enough to stop the pill flying
  // fully off-screen on an aggressive swipe.
  static const double _maxDrag = 320;
  late final AnimationController _snapCtrl;
  Animation<double>? _snapAnim;
  double _drag = 0; // negative for up, positive for right
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  bool get _isUp => widget.direction == Axis.vertical;

  double get _offset => _dragging ? _drag : (_snapAnim?.value ?? 0);

  void _onUpdate(double delta) {
    setState(() {
      _drag = _isUp
          ? (_drag + delta).clamp(-_maxDrag, 0.0)
          : (_drag + delta).clamp(0.0, _maxDrag);
    });
  }

  void _onEnd() {
    final reached = (_isUp ? -_drag : _drag) >= _threshold;
    _snapAnim = Tween<double>(begin: _drag, end: 0)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    setState(() => _dragging = false);
    _snapCtrl
      ..reset()
      ..forward();
    if (reached) widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _snapCtrl,
      builder: (_, __) {
        final offset = _offset;
        final progress =
            ((_isUp ? -offset : offset) / _threshold).clamp(0.0, 1.0);
        final color = Color.lerp(kTextMid, kGreen, progress)!;

        final arrows = Icon(
          _isUp
              ? Icons.keyboard_double_arrow_up_rounded
              : Icons.keyboard_double_arrow_right_rounded,
          color: color,
          size: 20,
        );
        final text = Text(widget.label,
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1));

        final pill = AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: _isUp
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [arrows, const SizedBox(height: 6), text],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [text, const SizedBox(width: 8), arrows],
                ),
        );

        return GestureDetector(
          onVerticalDragStart:
              _isUp ? (_) => setState(() => _dragging = true) : null,
          onVerticalDragUpdate: _isUp ? (d) => _onUpdate(d.delta.dy) : null,
          onVerticalDragEnd: _isUp ? (_) => _onEnd() : null,
          onHorizontalDragStart:
              _isUp ? null : (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: _isUp ? null : (d) => _onUpdate(d.delta.dx),
          onHorizontalDragEnd: _isUp ? null : (_) => _onEnd(),
          child: Transform.translate(
            offset: _isUp ? Offset(0, offset) : Offset(offset, 0),
            child: pill,
          ),
        );
      },
    );
  }
}

class _DeviceGlyph extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final bool accent;
  final double width;
  final double iconSize;
  final Animation<double>? pulse;
  final bool hovering;
  const _DeviceGlyph({
    required this.icon,
    required this.label,
    required this.caption,
    this.accent = false,
    this.width = 140,
    this.iconSize = 56,
    this.pulse,
    this.hovering = false,
  });

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
    // only the icon. Icon also always sits in a matching padding+border
    // box (transparent unless hovering) so both glyphs have identical
    // layout heights regardless of drop-target hover state - fixes the
    // "notebook image isn't the same height as desktop" report.
    final color = accent ? kGreen : kTextDim;
    Widget iconWidget = Icon(icon, size: iconSize, color: color);
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(
                color: hovering ? kGreen : Colors.transparent,
                width: 2,
              ),
            ),
            child: iconWidget,
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
