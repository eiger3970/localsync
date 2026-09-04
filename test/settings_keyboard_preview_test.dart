// Local visual verification only. Renders the real SettingsScreen with a
// simulated keyboard open (viewInsets.bottom set directly, same as iOS
// reports it) to check whether the Save button (now bottomNavigationBar)
// actually stays visible above it. Run with:
//   flutter test test/settings_keyboard_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
    // 2026-09-04: real bug, found while building a different preview -
    // this test constructs SettingsScreen with an empty desktopIp,
    // which triggers the real auto-fill-on-open discovery added earlier
    // today (settings_screen.dart's initState). That calls
    // connectivity_plus's real platform channel, unmocked here, throwing
    // MissingPluginException and leaving the retry's Future.delayed
    // timers pending past tearDown - the actual cause of this test's
    // "Timer still pending" failure, previously (wrongly) assumed to be
    // unrelated pre-existing noise.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (MethodCall call) async => ['none']);
  });

  testWidgets('Save button position with a simulated keyboard open',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    // 2026-09-04: real bug, found while building a different preview -
    // an empty desktopIp here triggers the real auto-fill-on-open
    // discovery added earlier today, which calls connectivity_plus's
    // unmocked platform channel and leaves retry timers pending past
    // tearDown - the actual root cause of this test's long-standing
    // "Timer still pending" failure, wrongly assumed before to be
    // unrelated pre-existing noise. This test's real purpose (Save
    // button position above the keyboard) has nothing to do with
    // discovery - a non-empty IP sidesteps that code path entirely
    // instead of fighting its timing. The connectivity mock in setUp()
    // above stays too, as a defensive backstop.
    final ctrl = LinkingController(
      desktopUser: '',
      desktopIp: '172.20.10.11',
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

    final screenHeightLogical =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Real iPhone number-pad keyboard height is roughly 291 logical pt.
    const keyboardHeight = 291.0;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * 3);
    await tester.pump();

    final saveRect =
        tester.getRect(find.widgetWithText(ElevatedButton, 'Save'));
    // ignore: avoid_print
    print('SAVE_BUTTON_POSITION: screenHeight=$screenHeightLogical '
        'keyboardTop=${screenHeightLogical - keyboardHeight} '
        'saveButtonTop=${saveRect.top} saveButtonBottom=${saveRect.bottom} '
        'isAboveKeyboard=${saveRect.bottom <= screenHeightLogical - keyboardHeight}');
  });
}
