import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 2026-11-11 owner: "I just want notes all at top or all at bottom." Messages used to be a mix (the Conflicts banner
/// at the top, sync results as bottom SnackBars, the bottom is where the PUSH zone sits). Every message now shows as
/// a banner at the top: showTopBar takes the same SnackBar object the call sites already build.

/// True while a banner that must stay until the user acts (the "Conflict fixed" PUSH step) is up. Other messages
/// then wait behind it instead of replacing it. A fuse in the owner of the flag clears it if it is never closed.
bool topBarPersistent = false;
int _topBarToken = 0;

extension TopMessages on ScaffoldMessengerState {
  void showTopBar(SnackBar bar) {
    if (!topBarPersistent) hideCurrentMaterialBanner();
    final mine = ++_topBarToken;
    final action = bar.action;
    showMaterialBanner(MaterialBanner(
      backgroundColor: bar.backgroundColor ?? kSurface,
      content: bar.content,
      actions: [
        if (action != null)
          TextButton(
            onPressed: () {
              hideCurrentMaterialBanner();
              action.onPressed();
            },
            child: Text(action.label, style: TextStyle(color: action.textColor ?? kGreen)),
          ),
        // 2026-11-11 owner: "is the OK still needed?" - the bar closes itself; a banner must have one action, so a
        // small close icon stays, no word.
        IconButton(
          onPressed: hideCurrentMaterialBanner,
          icon: Icon(Icons.close, color: kTextDim, size: 20),
        ),
      ],
    ));
    Timer(bar.duration, () {
      if (_topBarToken == mine && !topBarPersistent) hideCurrentMaterialBanner();
    });
  }

  void hideCurrentTopBar() {
    if (!topBarPersistent) hideCurrentMaterialBanner();
  }
}
