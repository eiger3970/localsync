// widgets/demo_conflict_card.dart
//
// 2026-09-26: the way into the sample conflict (services/demo_conflict.dart)
// - shown on the Conflicts screen and in Settings -> Upgrades, so anyone
// (including App Review) can try Auto merge and the Visual picker without
// having a real conflict.
import 'package:flutter/material.dart';

import '../screens/conflict_picker_screen.dart';
import '../services/conflict_scanner.dart';
import '../services/demo_conflict.dart';
import '../theme.dart';

Future<void> openDemoConflict(BuildContext context) async {
  final repo = await DemoConflict.prepare();
  final entries = await scanForConflicts(repo.localPath);
  if (entries.isEmpty || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => ConflictPickerScreen(repo: repo, entry: entries.first)),
  );
}

class DemoConflictCard extends StatelessWidget {
  const DemoConflictCard({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openDemoConflict(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface, border: Border.all(color: Colors.amber)),
        child: Row(
          children: [
            Icon(Icons.star, color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Try it: sample conflict',
                      style: TextStyle(
                          color: kStar,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('A practice diary note - your real files are never touched',
                      style: TextStyle(color: kTextMid, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: kTextDim),
          ],
        ),
      ),
    );
  }
}
