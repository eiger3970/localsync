// screens/add_repository_screen.dart
// Form to configure a new git bare repository connection.

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/repository_provider.dart';

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
    text: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
  );
  final _vaultCtrl   = TextEditingController(
    text: 'On My iPhone/Synclocal',
  );
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _hostCtrl, _portCtrl, _userCtrl, _pathCtrl, _vaultCtrl]) {
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
              _field(_nameCtrl, hint: 'Obsidian_vault', validator: _required),
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
                hint: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
                validator: _required,
              ),
              const SizedBox(height: 20),
              _label('OBSIDIAN VAULT PATH ON PHONE'),
              _field(
                _vaultCtrl,
                hint: 'On My iPhone/Synclocal',
                validator: _required,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // This app has exactly one real local git working directory
    // (Synclocal's own exposed Documents folder - see STRUCTURE.md) -
    // not something a user could meaningfully type in as an iOS sandbox
    // path, so it's computed here rather than exposed as a form field.
    // Every Repository record needs it for sync to actually work (see
    // models/repository.dart's localPath field, added 2026-08-09).
    final localPath = (await getApplicationDocumentsDirectory()).path;

    final repo = Repository(
      name:             _nameCtrl.text.trim(),
      remoteHost:       _hostCtrl.text.trim(),
      remotePort:       int.tryParse(_portCtrl.text.trim()) ?? 22,
      remoteUser:       _userCtrl.text.trim(),
      remotePath:       _pathCtrl.text.trim(),
      localPath:        localPath,
      obsidianVaultPath: _vaultCtrl.text.trim(),
    );

    await context.read<RepositoryProvider>().addRepository(repo);

    if (mounted) Navigator.pop(context);
  }
}
