import 'package:flutter/widgets.dart';
import 'features/linking/linking_controller.dart';

/// Watches iOS app lifecycle transitions and resumes the [LinkingController]
/// when localsync returns to foreground from a parked state.
///
/// Register this in main.dart via WidgetsBinding.instance.addObserver().
class LocalSyncLifecycleObserver extends WidgetsBindingObserver {
  final LinkingController linkingController;

  LocalSyncLifecycleObserver({required this.linkingController});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App returned to foreground — resume linking machine if parked.
      linkingController.resumeFromBackground();
    }
  }
}
