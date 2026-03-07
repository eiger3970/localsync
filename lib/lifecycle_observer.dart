import 'package:flutter/widgets.dart';
import 'features/linking/linking_controller.dart';

/// Watches iOS app lifecycle transitions and resumes the [LinkingController]
/// when synclocal returns to foreground from a parked state.
///
/// Register this in main.dart via WidgetsBinding.instance.addObserver().
class SynclocalLifecycleObserver extends WidgetsBindingObserver {
  final LinkingController linkingController;

  SynclocalLifecycleObserver({required this.linkingController});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App returned to foreground — resume linking machine if parked.
      linkingController.resumeFromBackground();
    }
  }
}
