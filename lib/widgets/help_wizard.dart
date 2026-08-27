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
  'pick': _WizardNode(
      type: _NodeType.action,
      text: 'Pick version',
      fine: 'Not picked ≠ deleted - saved under Conflict Backups.',
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
const _desktopPushNote =
    'Your OTHER device must send its data - phone LocalSync app is next.';
const _desktopPullNote =
    'Your OTHER device must receive the data - not this LocalSync app.';

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

const Map<String, String?> _flowAFooterNote = {
  'both': 'If conflicts show after pulling, resolve them first - see Flow B.',
  'desktop': null,
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

  void _back() => setState(() {
        _picked = null;
        _pending = null;
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      content: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 280,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _picked == null
                  ? _buildChoices()
                  : _buildWorkflow(_picked!),
            ),
          ),
          // Painted last so it's always on top - a Stack child earlier in
          // the list can otherwise win the hit-test in a real layout,
          // same class of bug flutter test's tap() warned about here.
          Positioned(
            top: -18,
            right: -14,
            child: IconButton(
              icon: Icon(Icons.close, color: kTextDim, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoices() {
    return Row(
      key: const ValueKey('choices'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _choices.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _choiceButton(_choices[i])),
        ],
      ],
    );
  }

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
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pending == null ? () => _pick(choice.key) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(
                    color: isPending ? kGreen : kTextMid, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < choice.icons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Icon(choice.icons[i], size: 18, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(choice.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: color,
                          fontSize: 9.5,
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

  Widget _buildWorkflow(String key) {
    final steps = _flowASteps[key]!;
    final footerNote = _flowAFooterNote[key];
    return Column(
      key: ValueKey('workflow-$key'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WORKFLOW',
            style: TextStyle(
                color: kGreen,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        for (int i = 0; i < steps.length; i++) ...[
          _stepBox(steps[i], isLast: i == steps.length - 1),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward, size: 14, color: kTextDim),
            ),
        ],
        if (footerNote != null) ...[
          const SizedBox(height: 12),
          Text(footerNote, style: TextStyle(color: kTextDim, fontSize: 10)),
        ],
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _back,
          child: Text('< back',
              style: TextStyle(
                  color: kTextDim,
                  fontSize: 10.5,
                  decoration: TextDecoration.underline)),
        ),
      ],
    );
  }

  Widget _stepBox(_WorkflowStep step, {required bool isLast}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: isLast ? kGreen.withValues(alpha: 0.08) : kSurface,
        border: Border.all(color: isLast ? kGreen : kBorder, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(step.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isLast ? kGreen : kStar,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          if (step.note != null) ...[
            const SizedBox(height: 4),
            Text(step.note!,
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextDim, fontSize: 10)),
          ],
        ],
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
    return AlertDialog(
      backgroundColor: kSurface,
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      content: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
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
                if (node.fine != null) ...[
                  const SizedBox(height: 8),
                  Text(node.fine!,
                      style: TextStyle(color: kTextDim, fontSize: 12.5)),
                ],
                const SizedBox(height: 20),
                _buttons(node),
              ],
            ),
          ),
          // Painted last so it's always on top - see the matching note
          // on _FlowAPickerDialog's Stack above.
          Positioned(
            top: -18,
            right: -14,
            child: IconButton(
              icon: Icon(Icons.close, color: kTextDim, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
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
