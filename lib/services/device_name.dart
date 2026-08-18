// services/device_name.dart
//
// 2026-08-18: "device name will source the phone's default name if no
// manual device name is entered" - falls back to the phone's own name
// (e.g. "Ken's iPhone", via iOS Settings -> General -> About -> Name)
// instead of the generic "Localsync" string, when the user hasn't set
// one themselves. Real platform limitation, worth knowing if this ever
// looks wrong on-device: iOS 16+ restricts UIDevice.name to a generic
// value like "iPhone" for apps without an MDM entitlement this app
// doesn't have - device_info_plus's `.name` may come back generic
// rather than personalized depending on iOS version. Not fixable from
// this app's side; the manual "Device name" field in the kebab menu is
// the reliable path either way.

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<String> defaultDeviceName() async {
  if (kIsWeb) return 'Localsync';
  try {
    final info = await DeviceInfoPlugin().iosInfo;
    final name = info.name.trim();
    return name.isEmpty ? 'Localsync' : name;
  } catch (_) {
    return 'Localsync';
  }
}
