import '../features/linking/linking_state.dart';

abstract class VaultService {
  Future<StepResult> createVaultDirectory();
  Future<bool> vaultExists();
  Future<String> vaultPath();
}

class VaultServiceImpl implements VaultService {
  final String vaultName;
  VaultServiceImpl({required this.vaultName});

  @override
  Future<String> vaultPath() async => vaultName;

  @override
  Future<bool> vaultExists() async => false;

  @override
  Future<StepResult> createVaultDirectory() async {
    if (vaultName.isEmpty) {
      return const StepFailure(LinkingError.vaultNameEmpty);
    }
    return StepSuccess(message: 'Vault name validated: $vaultName');
  }
}
