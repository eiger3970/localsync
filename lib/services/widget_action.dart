// services/widget_action.dart
//
// Reads (and clears) the Home Screen widget's pending Push/Pull tap -
// see AppDelegate.swift's PendingWidgetAction for the native side.
//
// 2026-09-24: real feedback, live - "Widgets push and pull causes a home
// screen black out, rather than gif and graphics showing the push or
// pull." main.dart only asked for the pending action once, on a cold
// start. A tap while LocalSync was already in the background (the usual
// case) resumed the app, the native side stored the action, and nothing
// on the Dart side ever asked for it again - AutoSyncOnResume ran its
// silent push+pull instead, with no gif and no result SnackBar. Both
// the cold-start check and the resume check now go through here.

import 'package:flutter/services.dart';

const _channel = MethodChannel('localsync/widget_action');

/// 'action_push' / 'action_pull' / 'action_desktop' if the widget was tapped since the last
/// read, else null. Never throws (no native side in tests/desktop).
Future<String?> takePendingWidgetAction() async {
  try {
    final action = await _channel.invokeMethod<String>('getPendingAction');
    if (action == 'push' || action == 'pull' || action == 'desktop') {
      return 'action_$action';
    }
  } catch (_) {}
  return null;
}
