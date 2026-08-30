// Local visual verification only - not part of the real suite's regression
// coverage. Renders the real HomeScreen app bar to a PNG so the
// centerTitle:false fix can actually be seen before pushing/sideloading,
// instead of guessing again. Run with:
//   flutter test test/appbar_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/home_screen.dart';
import 'package:localsync/services/repository_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // RepositoryProvider's constructor kicks off an auto-sync check that
    // touches path_provider (real plugin, no test-env implementation) -
    // irrelevant to this visual capture, just needs to not throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('capture real HomeScreen app bar with a short repo name',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = RepositoryProvider();
    await provider.addRepository(const Repository(
      name: 'Documents Pictures Videos and Backup Files Needed On Phone',
      remoteHost: '172.20.10.11',
      remoteUser: 'rapi5',
      remotePath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/x.git',
      localPath: '',
      obsidianVaultPath: '',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    final nameRect = tester.getRect(find.text('Documents Pictures Videos and Backup Files Needed On Phone'));
    final kebabRect = tester.getRect(find.byIcon(Icons.more_vert));
    final helpRect = tester.getRect(find.byIcon(Icons.help_outline));
    final logoRect = tester.getRect(find.byType(Image).first);
    final rowRect =
        tester.getRect(find.byKey(const ValueKey('appBarRepoStatusRow')));
    final titleExpandedRect =
        tester.getRect(find.byKey(const ValueKey('titleExpanded')));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('APPBAR_MEASUREMENTS (logical dp): screenWidth=$screenWidth '
        'logoRight=${logoRect.right} '
        'rowLeft=${rowRect.left} rowRight=${rowRect.right} rowWidth=${rowRect.width} '
        'titleExpandedLeft=${titleExpandedRect.left} titleExpandedRight=${titleExpandedRect.right} '
        'nameBoxLeft=${nameRect.left} nameBoxRight=${nameRect.right} '
        'nameBoxWidth=${nameRect.width} '
        'kebabLeft=${kebabRect.left} kebabRight=${kebabRect.right} '
        'helpLeft=${helpRect.left} helpRight=${helpRect.right} '
        'gapBetweenNameBoxAndKebab=${kebabRect.left - nameRect.right} '
        'gapKebabToHelp=${helpRect.left - kebabRect.right} '
        'gapHelpToRightEdge=${screenWidth - helpRect.right}');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appbar_preview.png'),
    );
  });
}
