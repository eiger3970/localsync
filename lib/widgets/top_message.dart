import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart' show rootNavigatorKey;
import '../theme.dart';

/// 2026-11-11 owner: "I just want notes all at top or all at bottom." Messages used to be a mix (the Conflicts banner
/// at the top, sync results as bottom SnackBars, the bottom is where the PUSH zone sits). Every message now shows as
/// a banner at the top: showTopBar takes the same SnackBar object the call sites already build.

/// True while a banner that must stay until the user acts (the "Conflict fixed" PUSH step) is up. Other messages
/// then wait behind it instead of replacing it. A fuse in the owner of the flag clears it if it is never closed.
bool topBarPersistent = false;
int _topBarToken = 0;

/// 2026-11-13 owner: "Downloaded latest notes pushes the PULL and PUSH icons down". A MaterialBanner sits in the page's
/// layout, so the whole page moved. Normal messages are now drawn over the page (an overlay), so nothing moves. Only
/// the "Conflict fixed" step (topBarPersistent) is still a layout banner.
OverlayEntry? _topEntry;
void _removeTopEntry() {
  _topEntry?.remove();
  _topEntry = null;
}

extension TopMessages on ScaffoldMessengerState {
  void showTopBar(SnackBar bar) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay != null && !topBarPersistent) {
      hideCurrentMaterialBanner();
      _removeTopEntry();
      final mine = ++_topBarToken;
      final action = bar.action;
      late final OverlayEntry entry;
      void close() {
        if (_topEntry == entry) _removeTopEntry();
      }
      entry = OverlayEntry(
        builder: (ctx) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: bar.backgroundColor ?? kSurface,
            elevation: 4,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(children: [
                  Expanded(
                      child: DefaultTextStyle(
                          style: Theme.of(ctx).textTheme.bodyMedium ?? const TextStyle(),
                          child: bar.content)),
                  if (action != null)
                    TextButton(
                      onPressed: () {
                        close();
                        action.onPressed();
                      },
                      child: Text(action.label, style: TextStyle(color: action.textColor ?? kGreen)),
                    ),
                  IconButton(onPressed: close, icon: Icon(Icons.close, color: kTextDim, size: 20)),
                ]),
              ),
            ),
          ),
        ),
      );
      _topEntry = entry;
      overlay.insert(entry);
      Timer(bar.duration, () {
        if (_topBarToken == mine) close();
      });
      return;
    }
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
    _removeTopEntry();
    if (!topBarPersistent) hideCurrentMaterialBanner();
  }
}
