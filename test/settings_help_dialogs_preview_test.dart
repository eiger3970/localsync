// Local visual verification only. Renders the real SettingsScreen and
// opens each of the three command-based help dialogs (IP address manual
// setup, Desktop sync folder manual setup, Desktop vault path) to check
// the 2026-09-03 fixes: command box wraps into full view instead of
// hiding off-screen, and each dialog places the command box exactly
// where its own step text refers to it. Run with:
//   flutter test test/settings_help_dialogs_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

Future<void> _openDialogAndCapture(
  WidgetTester tester, {
  required String tooltip,
  required int index,
  required String goldenName,
  String? detailsGoldenName,
  String? commandGoldenName,
}) async {
  // pumpAndSettle() never returns here - the screen's own sparkle/
  // twinkle icons (AnimatedBuilder on a repeating AnimationController,
  // see the satellite/star icons above the IP and username fields) keep
  // scheduling new frames forever. Fixed-duration pumps only.
  final buttonFinder = find.byTooltip(tooltip).at(index);
  await tester.ensureVisible(buttonFinder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(buttonFinder);
  // Frame-by-frame instead of one big jump, so the dialog's entrance
  // transition lands exactly on a frame boundary (a single large pump
  // can leave the tween mid-frame, tripping the golden capture's
  // debugNeedsPaint check) - the repeating sparkle animation elsewhere
  // on screen is why this can't just be pumpAndSettle().
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  await expectLater(
    find.byType(AlertDialog),
    matchesGoldenFile('goldens/$goldenName'),
  );

  // 2026-09-03: real feedback, live - "the long command gives people
  // eye bleed, tuck away in a dropdown." Same ensureVisible-then-tap-
  // then-ensureVisible-then-capture pattern as the "Show full details"
  // toggle below - proves the primary command is genuinely hidden by
  // default (the golden above has none) and that tapping "Show command"
  // actually reveals it, not just that the collapsed state looks right.
  if (commandGoldenName != null) {
    final showCmdFinder = find.text('Show command');
    await tester.ensureVisible(showCmdFinder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(showCmdFinder);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.ensureVisible(find.text('Hide command'));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/$commandGoldenName'),
    );

    // Collapse it again before any "Show full details" capture below,
    // so that golden reflects a realistic state (command still hidden,
    // only the secondary details expanded) rather than both open at
    // once - not a state a real user demoing "full details" would be in.
    await tester.tap(find.text('Hide command'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // 2026-09-03: real feedback, live - "show me the new toggle." Taps
  // the "Show full details" row the StatefulBuilder in _showHelp adds
  // when detailsCommand is set, then captures a second golden with the
  // second command revealed - proves the toggle itself renders and
  // actually expands, not just that the collapsed default looks right.
  //
  // 2026-09-03, follow-up: the first version of this skipped
  // ensureVisible - the toggle sits below the dialog's initial scroll
  // position, so tester.tap() found and fired it (test taps dispatch by
  // widget, not real screen coordinates - see the "outside root render
  // tree bounds" warning this produces without ensureVisible), but the
  // capture afterward was still scrolled to the TOP, missing both the
  // toggle and everything it revealed - the "after" golden came out
  // identical to the "before" one. ensureVisible before the tap AND
  // before the final capture (its label moves from "Show" to "Hide",
  // so the finder has to be re-resolved after tapping) actually scrolls
  // the dialog's SingleChildScrollView, same as a real user would.
  if (detailsGoldenName != null) {
    final toggleFinder = find.text('Show full details');
    await tester.ensureVisible(toggleFinder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(toggleFinder);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.ensureVisible(find.text('Hide full details'));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/$detailsGoldenName'),
    );
  }

  await tester.tap(find.text('Got it'));
  await tester.pump(const Duration(milliseconds: 300)); // dialog route out
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
    // 2026-09-03: real gap this test exposed - SettingsScreen now
    // auto-runs IP discovery on init when the field is empty (see
    // settings_screen.dart's initState), which calls
    // Connectivity().checkConnectivity() with no mock registered here,
    // throwing MissingPluginException and failing the whole test. 'none'
    // (empty list) is the honest answer for a test environment with no
    // real network - findDesktopIp() already treats that as "nothing to
    // discover" and returns null cleanly, same as a real offline device.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (MethodCall call) async => <String>[]);
  });

  testWidgets('command-box wrapping and step ordering, all three dialogs',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = LinkingController(
      desktopUser: '',
      desktopIp: '',
      bareRepoPath: '',
    );
    final repoProvider = RepositoryProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ctrl),
          ChangeNotifierProvider.value(value: repoProvider),
          ChangeNotifierProvider.value(value: ThemeService()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(neededForPairing: true),
        ),
      ),
    );
    await tester.pump();

    // IP address field's "Manual setup" dialog - step 1 says "find your
    // interface in the command's output above."
    await _openDialogAndCapture(
      tester,
      tooltip: 'How do I find this?',
      index: 0,
      goldenName: 'settings_help_ip_address.png',
      commandGoldenName: 'settings_help_ip_address_command.png',
      detailsGoldenName: 'settings_help_ip_address_details.png',
    );

    // Desktop sync folder field's "Manual setup" dialog - new step 1
    // explicitly says "run the command above."
    await _openDialogAndCapture(
      tester,
      tooltip: 'How do I find this?',
      index: 1,
      goldenName: 'settings_help_sync_folder.png',
      commandGoldenName: 'settings_help_sync_folder_command.png',
      detailsGoldenName: 'settings_help_sync_folder_details.png',
    );

    // Desktop vault path field's dialog - point-form intro, then step 1
    // "run the command above" with the command actually above it.
    await _openDialogAndCapture(
      tester,
      tooltip: 'What is this?',
      index: 1,
      goldenName: 'settings_help_vault_path.png',
      commandGoldenName: 'settings_help_vault_path_command.png',
      detailsGoldenName: 'settings_help_vault_path_details.png',
    );
  });
}
