// services/theme_service.dart
//
// 2026-08-21: "skins" IAP - the ChangeNotifier half of theme.dart's
// AppTheme static holder. AppTheme.current is where widgets actually
// read the live palette from (no BuildContext needed); this is what
// persists the choice and tells the tree to rebuild when it changes -
// see main.dart's Consumer<ThemeService> wrapping MaterialApp.
//
// Free/paid split (not enforced yet - no purchase gate wired in,
// same "code-complete but not live" state as purchase_service.dart):
// terminalGreenPalette is the default, free skin. Anything else in
// theme.dart's allPalettes is intended to sit behind a skins IAP once
// there's a real product ID for it.

import 'package:flutter/foundation.dart';
import '../theme.dart';
import 'database_service.dart';

class ThemeService extends ChangeNotifier {
  final _db = DatabaseService();

  AppPalette _palette = terminalGreenPalette;
  AppPalette get palette => _palette;

  Future<void> load() async {
    final savedId = await _db.getSelectedSkin();
    _palette = savedId != null ? paletteById(savedId) : terminalGreenPalette;
    AppTheme.set(_palette);
    notifyListeners();
  }

  Future<void> select(AppPalette palette) async {
    _palette = palette;
    AppTheme.set(palette);
    notifyListeners();
    await _db.setSelectedSkin(palette.id);
  }
}
