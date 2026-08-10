// screens/add_repository_screen.dart
// Form to configure a new git bare repository connection.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../models/repository.dart';
import '../services/repository_provider.dart';
import '../services/vault_folder_service.dart';

class AddRepositoryScreen extends StatefulWidget {
  const AddRepositoryScreen({super.key});

  @override
  State<AddRepositoryScreen> createState() => _AddRepositoryScreenState();
}

class _AddRepositoryScreenState extends State<AddRepositoryScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _hostCtrl    = TextEditingController(text: '172.20.10.11');
  final _portCtrl    = TextEditingController(text: '22');
  final _userCtrl    = TextEditingController(text: 'rapi5');
  final _pathCtrl    = TextEditingController(
    text: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/synclocal_test.git',
  );
  final _vaultFolder = VaultFolderService();
  VaultFolderResult? _pickedVault;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _hostCtrl, _portCtrl, _userCtrl, _pathCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ADD REPOSITORY')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('REPOSITORY NAME'),
              _field(_nameCtrl, hint: '${kNoteAppName}_$kContainerName', validator: _required),
              const SizedBox(height: 20),
              _label('DESKTOP HOST (IP ADDRESS)'),
              _field(_hostCtrl, hint: '172.20.10.11', validator: _required),
              const SizedBox(height: 20),
              _label('SSH PORT'),
              _field(_portCtrl, hint: '22', keyboardType: TextInputType.number),
              const SizedBox(height: 20),
              _label('SSH USERNAME'),
              _field(_userCtrl, hint: 'rapi5', validator: _required),
              const SizedBox(height: 20),
              _label('GIT BARE REPO PATH ON DESKTOP'),
              _field(
                _pathCtrl,
                hint: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/synclocal_test.git',
                validator: _required,
              ),
              const SizedBox(height: 20),
              // Rewritten 2026-08-09 alongside the vault-folder-picker
              // rework: this used to be a free-text field computed from
              // getApplicationDocumentsDirectory() on save, same wrong
              // assumption models/repository.dart's localPath field
              // itself already moved past - there's no single fixed
              // Synclocal-owned folder anymore. Obsidian creates and
              // owns each vault folder; this screen now requests real
              // access to it the same way linking_screen.dart's setup
              // flow does.
              _label('OBSIDIAN VAULT FOLDER'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSurface,
                  border: Border.all(color: kBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pickedVault?.path ?? 'No folder selected',
                        style: TextStyle(
                          color: _pickedVault != null ? kStar : kTextDim,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _pickVault,
                      child: const Text('SELECT',
                          style: TextStyle(color: kTeal, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Must already exist as a $kContainerName in $kNoteAppName - create it\n'
                'there first (Create a vault → Continue without sync).',
                style: const TextStyle(color: kTextMid, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: kVoid, strokeWidth: 2),
                      )
                    : const Text('CONNECT'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SSH public key must be in ~/.ssh/authorized_keys on your desktop.',
                style: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 1.5)),
  );

  Widget _field(
    TextEditingController ctrl, {
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: ctrl,
    validator: validator,
    keyboardType: keyboardType,
    style: const TextStyle(color: kStar, fontSize: 12),
    decoration: InputDecoration(hintText: hint),
  );

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _pickVault() async {
    final result = await _vaultFolder.pickFolder();
    if (result == null) return;
    setState(() => _pickedVault = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final vault = _pickedVault;
    if (vault == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select the $kNoteAppName $kContainerName folder first')),
      );
      return;
    }
    setState(() => _saving = true);

    final repo = Repository(
      name:              _nameCtrl.text.trim(),
      remoteHost:        _hostCtrl.text.trim(),
      remotePort:        int.tryParse(_portCtrl.text.trim()) ?? 22,
      remoteUser:        _userCtrl.text.trim(),
      remotePath:        _pathCtrl.text.trim(),
      localPath:         vault.path,
      vaultBookmark:     vault.bookmark,
      obsidianVaultPath: 'On My iPhone/$kNoteAppName/${_nameCtrl.text.trim()}',
    );

    await context.read<RepositoryProvider>().addRepository(repo);

    if (mounted) Navigator.pop(context);
  }
}
