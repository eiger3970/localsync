// Loads real system fonts before any golden test runs, so
// matchesGoldenFile captures actually-readable text instead of the
// placeholder tofu boxes flutter test renders by default (it doesn't
// load fonts unless told to). Registers DejaVu Sans under 'Roboto' -
// this app's default TextStyles set no fontFamily, which resolves to
// Material's bundled Roboto that test mode never loads - and DejaVu
// Sans Mono under 'monospace', which the inline command text explicitly
// requests. Local dev/preview only, not shipped.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() async {
    await _loadFont('Roboto', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    await _loadFont(
        'monospace', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  });
  await testMain();
}

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}
