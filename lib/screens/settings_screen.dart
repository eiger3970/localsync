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
            const _SettingLabel(
              icon: Icons.dns_outlined,
              text: 'Your desktop\'s address - not this phone\'s. '
                  'Changes between Tether and Hotspot.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: kStar),
              decoration: InputDecoration(
                labelText: 'Desktop IP',
                hintText: 'e.g. 172.20.10.2',
                errorText: _ipError,
              ),
            ),
            const SizedBox(height: 28),
            const _SettingLabel(
              icon: Icons.storage_outlined,
              text: 'Which bare repo the next vault you link will sync to. '
                  'A second, genuinely separate vault needs its own path '
                  'here before you tap "Add another vault" - doesn\'t '
                  'change any vault already linked.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathCtrl,
              style: const TextStyle(color: kStar, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Bare repo path',
                hintText: '/home/user/Git_bare_repo/name.git',
                errorText: _pathError,
              ),
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

class _SettingLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SettingLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kTextMid, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: kTextMid, fontSize: 13)),
        ),
      ],
    );
  }
}
