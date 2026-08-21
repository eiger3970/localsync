// screens/settings_screen.dart
//
// 2026-08-20: replaces the one-off "Desktop IP" dialog with a real
// screen, now that there are two related network/repo-target settings
// instead of one - Desktop IP (database_service.dart's getDesktopIp/
// setDesktopIp) and Bare repo path (getBareRepoPath/setBareRepoPath,
// added for genuine multi-repo support: bareRepoPath used to be a
// build-time constant, meaning every "Add another vault" attempt
// pointed at the exact same bare repo regardless of which folder was
// picked - a real architectural gap, not just a UI inconvenience).
//
// Both fields write straight to the live LinkingController (via
// updateDesktopIp/updateBareRepoPath) so a change takes effect
// immediately, no app restart - and persist through RepositoryProvider
// so it survives a relaunch too.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_controller.dart';
import '../services/repository_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _ipPattern =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  late final TextEditingController _ipCtrl;
  late final TextEditingController _pathCtrl;
  String? _ipError;
  String? _pathError;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<LinkingController>();
    _ipCtrl = TextEditingController(text: ctrl.desktopIp);
    _pathCtrl = TextEditingController(text: ctrl.bareRepoPath);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ip = _ipCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    setState(() {
      _ipError = _ipPattern.hasMatch(ip) ? null : 'Not a valid IP address';
      _pathError = path.isEmpty ? 'Can\'t be empty' : null;
    });
    if (_ipError != null || _pathError != null) return;

    final linkingCtrl = context.read<LinkingController>();
    final provider = context.read<RepositoryProvider>();
    await provider.setDesktopIp(ip);
    linkingCtrl.updateDesktopIp(ip);
    await provider.setBareRepoPath(path);
    linkingCtrl.updateBareRepoPath(path);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        title: const Text('Settings', style: TextStyle(color: kStar)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-08-20: real feedback, live - "looks complicated, less
            // verbose is better." Both labels cut to one short line,
            // same trim already applied elsewhere in this app for the
            // same complaint.
            // 2026-08-20: real bug, live - label/helper text rendered
            // smaller than the input text itself (Material's default
            // InputDecoration sizing), backwards from what's readable.
            // Explicit styles here match this app's established
            // kStar/kTextMid readability fixes rather than trusting
            // the theme's small defaults for these two roles.
            // 2026-08-21: real feedback, live - labels still read as
            // body text next to a full-screen field, not as section
            // headers. Bumped to the 18px/w700 size already used for
            // section headers elsewhere (see home_screen.dart's
            // _SectionTitle-equivalent header text). Renamed "Desktop
            // IP" -> "IP address - desktop" (matches user's own
            // requested wording, applied everywhere this string
            // appears - see home_screen.dart's Settings menu subtitle).
            // "Bare repo path" -> "Git bare repo path" - user's own
            // notes (Knowledge_base_Raspberry_Pi.md, Knowledge_base_
            // obsidian.md) consistently say "Git bare repo", never
            // "bare repository", confirmed by grep before renaming
            // rather than guessed. Icons are built-in Material glyphs,
            // not custom SVG - same tradeoff already decided with the
            // user on 2026-08-18 for the Conflicts screen's icon row
            // (real risk of an invisible SVG rendering bug with no way
            // to preview before a sideload) - ask if genuine custom
            // icon art is wanted instead, budget the same iteration
            // cost as the pairing-screen SVGs took.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 10),
                  child: Icon(Icons.wifi, color: kTextMid, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: kStar, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'IP address - desktop',
                      labelStyle: const TextStyle(
                          color: kStar, fontSize: 18, fontWeight: FontWeight.w700),
                      // 2026-08-21: real feedback, live - "I don't like
                      // this text, make it clearer" on "Changes with
                      // Tether/Hotspot". Spells out what actually
                      // triggers a change instead of a fragment.
                      helperText:
                          'Changes when you switch between Tether or Hotspot',
                      helperStyle: const TextStyle(color: kTextMid, fontSize: 13),
                      hintText: 'e.g. 172.20.10.2',
                      errorText: _ipError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 10),
                  child: Icon(Icons.account_tree, color: kTextMid, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathCtrl,
                    style: const TextStyle(color: kStar, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Git bare repo path',
                      labelStyle: const TextStyle(
                          color: kStar, fontSize: 18, fontWeight: FontWeight.w700),
                      // 2026-08-21: real feedback, live - "what does
                      // this even mean, make it clearer" on "For the
                      // next vault you link". Spells out the actual
                      // scope (only future links, not existing ones) -
                      // see RepositoryProvider's own comment on
                      // setBareRepoPath for the same explanation.
                      helperText: 'Only used the next time you tap "Add '
                          'another vault" - already-linked vaults keep '
                          'their own path',
                      helperStyle: const TextStyle(color: kTextMid, fontSize: 13),
                      hintText: '/home/user/Git_bare_repo/name.git',
                      errorText: _pathError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
