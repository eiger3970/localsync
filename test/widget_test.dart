import 'package:flutter_test/flutter_test.dart';

import 'package:localsync/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalSyncApp());
    await tester.pump();
  });
}
