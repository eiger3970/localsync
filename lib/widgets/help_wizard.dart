// widgets/help_wizard.dart
//
// 2026-08-27: the nervous-user help flows designed and validated as an
// HTML mockup this session (Home: "not sure what to do", Conflicts:
// "there's a conflict, what do I do"). Flow B (Conflicts) is a
// tap-through, one-question-per-card wizard - Yes/No or Continue as the
// only buttons, matching the user's explicit ask to avoid a wall of
// text. Flow A (Home) is not that any more - see _FlowAPickerDialog's
// own header comment for why it's shaped differently.

import 'package:flutter/material.dart';
import '../theme.dart';

enum _NodeType { question, action, end }

enum _Tone { good, caution }

class _WizardNode {
  final _NodeType type;
  final String text;
  final String? fine;
  final String? yes;
  final String? no;
  final String? next;
  final _Tone? tone;
  const _WizardNode({
    required this.type,
    required this.text,
    this.fine,
    this.yes,
    this.no,
    this.next,
    this.tone,
  });
}

const Map<String, _WizardNode> _flowB = {
  'q1': _WizardNode(
      type: _NodeType.question,
      text: 'Any conflicts?',
      yes: 'pick',
      no: 'end_no'),
  // 2026-08-27: real feedback, live - "is that a does not equal sign?
  // I don't understand this sentence... have a path or link." Reworded
  // in plain English with the real path (vault_backup.dart's
  // kLocalSyncFolderName + "Conflict Backups"). A real tappable link
  // isn't possible - deep-linking to a specific Obsidian folder was
  // already tried and found unreliable on real-device testing (see
  // conflicts_screen.dart's own history) - so the exact path text is
  // the honest substitute.
  'pick': _WizardNode(
      type: _NodeType.action,
      text: 'Pick version',
      fine: "Not picked isn't deleted - saved in LocalSync/Conflict "
          'Backups.',
      next: 'q2'),
  'q2': _WizardNode(
      type: _NodeType.question,
      text: 'More conflicts?',
      yes: 'pick',
      no: 'push'),
  'push': _WizardNode(type: _NodeType.action, text: 'PUSH', next: 'end_done'),
  'end_done': _WizardNode(type: _NodeType.end, text: 'Done', tone: _Tone.good),
  'end_no':
      _WizardNode(type: _NodeType.end, text: 'Nothing to do', tone: _Tone.good),
};

const String _start = 'q1';

/// Opens the branching help wizard for [flow] ('A' = Home, 'B' = Conflicts).
void showHelpWizard(BuildContext context, String flow) {
  if (flow == 'A') {
    showDialog(context: context, builder: (_) => const _FlowAPickerDialog());
    return;
  }
  showDialog(
    context: context,
    builder: (_) => _HelpWizardDialog(flow: flow),
  );
}

// ── Flow A: Home screen ──────────────────────────────────────────────────

class _WorkflowStep {
  final String label;
  final String? note;
  const _WorkflowStep(this.label, [this.note]);
}

// 2026-08-27: real feedback, live, several rounds - "what if the desktop
// was edited? what if both were?" exposed a genuine bug (checked against
// sync_service.dart: push() fails cleanly on divergence, it never
// merges - conflicts only ever come from pull()), and "unsure if any
// live buttons needed here, as the habit for the user is to main page
// swipe up or down" changed the whole interaction shape. This dialog
// asks the one real question up front (which device changed -
// alphabetical) and shows the resulting sequence as a read-only summary
// to read, then dismiss - no per-step buttons, because PUSH/PULL are a
// swipe on the real Home screen, not something this dialog can do.
//
// The desktop-side note text is deliberately generic ("its own sync
// step") - LocalSync is phone-only, there's no desktop app to name.
//
// 2026-08-27, third pass - real feedback, live, several points at once:
// - "Flow B" isn't a name a real user has ever seen anywhere in this
//   app - it was leftover from this session's own design-doc shorthand.
//   Dropped the footnote that referenced it entirely rather than invent
//   a made-up in-app name for something that doesn't need naming - a
//   real conflict still surfaces on its own via the Conflicts screen,
//   same as always.
// - Notes reworded per direct wording, spelling out "(computer/desktop/
//   laptop)" since "your OTHER device" alone still left room to wonder
//   what device that even means.
const _desktopPushNote = 'Your OTHER device (computer/desktop/laptop) must '
    'send its data first - phone LocalSync app is after this step.';
const _desktopPullNote = 'Your OTHER device (computer/desktop/laptop) must '
    'receive the data - not this LocalSync app.';

const Map<String, List<_WorkflowStep>> _flowASteps = {
  'both': [
    _WorkflowStep('Phone PUSH'),
    _WorkflowStep('Desktop PUSH', _desktopPushNote),
    _WorkflowStep('Phone PULL'),
    _WorkflowStep('Done'),
  ],
  'desktop': [
    _WorkflowStep('Desktop PUSH', _desktopPushNote),
    _WorkflowStep('Phone PULL'),
    _WorkflowStep('Done'),
  ],
  'phone': [
    _WorkflowStep('Phone PUSH'),
    _WorkflowStep('Desktop PULL', _desktopPullNote),
    _WorkflowStep('Done'),
  ],
};

// 2026-08-27, fourth pass - real feedback, live: "bottom of flowchart
// might need a hint of any conflicts... kebab icon -> Conflicts."
// Checked before adding: no separate user manual exists anywhere in
// this repo - conflict-solving guidance already lives ON the Conflicts
// screen itself (its safety-steps row + its own ? wizard, Flow B just
// below). So this points to the real navigation path to reach it,
// using the actual UI, not a made-up name like the removed footnote
// did. Only 'both' and 'desktop' get it - 'phone' never runs Phone
// PULL, so it never actually risks a conflict.
const _conflictHint = 'If conflicts show: tap ⋮ then Conflicts.';
const Map<String, String?> _flowAHint = {
  'both': _conflictHint,
  'desktop': _conflictHint,
  'phone': null,
};

class _ChoiceDef {
  final String key;
  final String label;
  final List<IconData> icons;
  const _ChoiceDef(this.key, this.label, this.icons);
}

// Alphabetical, per direct instruction.
const _choices = [
  _ChoiceDef('both', 'BOTH\nEDITED', [Icons.computer, Icons.smartphone]),
  _ChoiceDef('desktop', 'DESKTOP\nEDITED', [Icons.computer]),
  _ChoiceDef('phone', 'PHONE\nEDITED', [Icons.smartphone]),
];

class _FlowAPickerDialog extends StatefulWidget {
  const _FlowAPickerDialog();

  @override
  State<_FlowAPickerDialog> createState() => _FlowAPickerDialogState();
}

class _FlowAPickerDialogState extends State<_FlowAPickerDialog> {
  // _pending: the button mid-settle-animation, before the workflow swap.
  // _picked: the workflow actually showing, once the settle finishes.
  String? _pending;
  String? _picked;

  void _pick(String key) {
    setState(() => _pending = key);
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _picked = key);
    });
  }

  // 2026-08-27: dropped the close (X) button and the back link - real
  // feedback, live: "why is the x at top right, unnecessary, user taps
  // main screen to return... same user action consistent throughout
  // app." showDialog is barrier-dismissible by default (never opted out
  // of that here), so tapping outside already closed this - the X and
  // the back link were redundant controls duplicating a gesture that
  // already worked, not a missing feature.
  // 2026-08-27: real feedback, live - "touching left and right edge of
  // screen, using maximum space." insetPadding trimmed way down from
  // AlertDialog's default (40px horizontal) and content sizes to
  // whatever that leaves, instead of a fixed 280 that left wide margins
  // on a real phone screen.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      content: SizedBox(
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child:
              _picked == null ? _buildChoices() : _buildWorkflow(_picked!),
        ),
      ),
    );
  }

  Widget _buildChoices() {
    return Row(
      key: const ValueKey('choices'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < _choices.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _choiceButton(_choices[i])),
        ],
      ],
    );
  }

  // 2026-08-27: real feedback, live - "made larger... maximum space,"
  // and "plain white doesn't instantly tell me these are live buttons,
  // background needs to be different (lighter) than the phone's black
  // background." Padding/icon/text sizes bumped up, and the fill moved
  // from kSurface (same color as the dialog itself - zero contrast) to
  // kBorder, reused here as a fill rather than just a stroke color, so
  // real contrast against the dialog without inventing a new token.
  Widget _choiceButton(_ChoiceDef choice) {
    final isPending = _pending == choice.key;
    final isFading = _pending != null && !isPending;
    final color = isPending ? kGreen : kStar;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isFading ? 0 : 1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 250),
        scale: isPending ? 1.08 : 1.0,
        child: Material(
          color: kBorder,
          borderRadius: BorderRadius.circular(10),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pending == null ? () => _pick(choice.key) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
              decoration: BoxDecoration(
                border: Border.all(
                    color: isPending ? kGreen : kTextMid, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < choice.icons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Icon(choice.icons[i], size: 27, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(choice.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          height: 1.3)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 2026-08-27: real feedback, live, several fixes at once -
  // - Centered (was left-aligned, arrows and the WORKFLOW label read as
  //   randomly offset instead of belonging to the chain below them).
  // - No back link - see the build() comment above.
  // - No footer note about "Flow B" - it named an internal design-doc
  //   flow, not anything a real user has ever seen in this app.
  Widget _buildWorkflow(String key) {
    final steps = _flowASteps[key]!;
    final hint = _flowAHint[key];
    return Column(
      key: ValueKey('workflow-$key'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('WORKFLOW',
            style: TextStyle(
                color: kGreen,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        for (int i = 0; i < steps.length; i++) ...[
          _stepBox(steps[i], isLast: i == steps.length - 1),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward, size: 22, color: kStar),
            ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 14),
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextMid, fontSize: 14)),
        ],
      ],
    );
  }

  // 2026-08-27: real feedback, live -
  // - Shrink-wrapped to content instead of stretching edge to edge -
  //   "rectangles are too wide, make look like workflow chart shapes"
  //   (matches the diamond/rectangle/pill vocabulary the HTML mockup's
  //   flowcharts already established).
  // - Done no longer painted green - it read as a live, tappable button
  //   when nothing here is tappable. Same neutral style as every other
  //   step; only the corner radius hints "this is the end," like a
  //   flowchart terminator, without borrowing the accent color that
  //   means "safe/confirmed" everywhere else in this app.
  // - Fine print bumped from 10px/kTextDim to 12px/kTextMid - real
  //   feedback, live: "text too small and dark grey."
  // 2026-08-27: real feedback, live - "rectangles aren't distinguishable
  // enough, give them a lighter background colour than the window
  // background." Same fix as _choiceButton above: fill moved from
  // kSurface to kBorder, stroke moved from kBorder to kTextMid so it
  // still reads against the new fill instead of disappearing into it.
  Widget _stepBox(_WorkflowStep step, {required bool isLast}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        decoration: BoxDecoration(
          color: kBorder,
          border: Border.all(color: kTextMid, width: 1.5),
          borderRadius: BorderRadius.circular(isLast ? 20 : 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(step.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: kStar, fontSize: 13, fontWeight: FontWeight.w600)),
            if (step.note != null) ...[
              const SizedBox(height: 5),
              Text(step.note!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kTextMid, fontSize: 14, height: 1.35)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Flow B: Conflicts screen (unchanged tap-through engine) ─────────────

class _HelpWizardDialog extends StatefulWidget {
  final String flow;
  const _HelpWizardDialog({required this.flow});

  @override
  State<_HelpWizardDialog> createState() => _HelpWizardDialogState();
}

class _HelpWizardDialogState extends State<_HelpWizardDialog> {
  late String _nodeId;

  @override
  void initState() {
    super.initState();
    _nodeId = _start;
  }

  void _go(String id) => setState(() => _nodeId = id);

  String _eyebrow(_WizardNode node) {
    switch (node.type) {
      case _NodeType.question:
        return 'DECISION';
      case _NodeType.action:
        return 'DO THIS';
      case _NodeType.end:
        switch (node.tone!) {
          case _Tone.good:
            return 'DONE, SAFE';
          case _Tone.caution:
            return 'SAFE, ONE MORE STEP';
        }
    }
  }

  Color _eyebrowColor(_WizardNode node) {
    if (node.type == _NodeType.question) return kTextMid;
    if (node.type == _NodeType.action) return kBlue;
    switch (node.tone!) {
      case _Tone.good:
        return kGreen;
      case _Tone.caution:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = _flowB[_nodeId]!;
    // 2026-08-27: dropped the close (X) here too - same fix as
    // _FlowAPickerDialog above, for the same reason: showDialog is
    // already barrier-dismissible, tapping outside already worked, and
    // this app should use one consistent dismiss gesture, not two.
    return AlertDialog(
      backgroundColor: kSurface,
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                Text(_eyebrow(node),
                    style: TextStyle(
                        color: _eyebrowColor(node),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const SizedBox(height: 10),
                Text(node.text,
                    style: TextStyle(
                        color: kStar,
                        fontSize: 17,
                        fontWeight: node.type == _NodeType.action
                            ? FontWeight.w600
                            : FontWeight.normal)),
                // 2026-08-27: real feedback, live - "Pick version, text
                // below is too dark and small." Same fix Flow A's fine
                // print already got, never carried over here - kTextDim
                // -> kTextMid, 12.5 -> 14.
                if (node.fine != null) ...[
                  const SizedBox(height: 8),
                  Text(node.fine!,
                      style: TextStyle(color: kTextMid, fontSize: 14)),
                ],
                const SizedBox(height: 20),
                _buttons(node),
              ],
        ),
      ),
    );
  }

  Widget _buttons(_WizardNode node) {
    if (node.type == _NodeType.question) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kGreen), foregroundColor: kGreen),
              onPressed: () => _go(node.yes!),
              child: const Text('YES'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kTextDim), foregroundColor: kTextMid),
              onPressed: () => _go(node.no!),
              child: const Text('NO'),
            ),
          ),
        ],
      );
    }
    if (node.type == _NodeType.action) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: kGreen, foregroundColor: kVoid),
          onPressed: () => _go(node.next!),
          child: const Text('CONTINUE'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style:
            ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: kVoid),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('GOT IT'),
      ),
    );
  }
}
