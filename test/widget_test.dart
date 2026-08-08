import 'package:flutter_test/flutter_test.dart';

import 'package:synclocal/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const SynclocalApp(localVaultPath: '/tmp/synclocal_test_vault'));
    await tester.pump();
  });
}
