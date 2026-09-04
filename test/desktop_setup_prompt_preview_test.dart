// Local visual verification only. Renders the real DesktopSetupPromptScreen
// and confirms Continue navigates to LinkingScreen and marks the "seen" flag
// so a returning user skips straight past it next time (see
// sync_files_preview_screen.dart / sync_obsidian_preview_screen.dart's
// _proceed()). Run with:
//   flutter test test/desktop_setup_prompt_preview_test.dart --update-goldens
//
// 2026-09-04: real feedback, live - "why is [tap to copy] here, this seems
// to just add confusion and an unnecessary step?" The URL is no longer
// tappable/copyable (see desktop_setup_prompt_screen.dart's own note) - the
// old "tapping the URL copies it to the clipboard" test and its Clipboard
// mock are gone with it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/desktop_setup_prompt_screen.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/services/database_service.dart';
import 'package:localsync/services/purchase_service.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

// LinkingScreen (what Continue navigates to) reads LinkingController,
// RepositoryProvider, and PurchaseService via Provider - same wrapper the
// settings dialogs' own preview test uses, needed here so tapping through
// doesn't crash on a missing provider once it actually builds.
Widget _wrapped(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => LinkingController(
              desktopUser: '', desktopIp: '', bareRepoPath: '')),
      ChangeNotifierProvider(create: (_) => RepositoryProvider()),
      ChangeNotifierProvider(create: (_) => ThemeService()),
      Provider.value(value: PurchaseService()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('renders the real screen and captures it', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrapped(const DesktopSetupPromptScreen()));
    await tester.pump();

    expect(find.text('First, set up your desktop'), findsOneWidget);
    expect(find.text('kworld.space/localsync'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await expectLater(
      find.byType(DesktopSetupPromptScreen),
      matchesGoldenFile('goldens/desktop_setup_prompt.png'),
    );
  });

  testWidgets('Continue navigates to LinkingScreen and marks seen',
      (tester) async {
    expect(await DatabaseService().getSeenDesktopSetupPrompt(), isFalse);

    await tester.pumpWidget(_wrapped(const DesktopSetupPromptScreen()));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    // LinkingScreen's own sparkle/twinkle icons keep scheduling new
    // frames forever - pumpAndSettle() never returns once we're on it.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(LinkingScreen), findsOneWidget);
    expect(await DatabaseService().getSeenDesktopSetupPrompt(), isTrue);
  });
}
