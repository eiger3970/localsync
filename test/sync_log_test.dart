import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_log.dart';
import 'package:localsync/services/diagnostics_report.dart';

void main() {
  test('sync log keeps events in order and the report includes them', () async {
    SyncLog.add('PULL start (you)');
    SyncLog.add('PULL end (you) SyncOk 2.1s');
    final t = await SyncLog.tail(n: 5);
    expect(t.split('\n').length, greaterThanOrEqualTo(2));
    expect(t.indexOf('PULL start'), lessThan(t.indexOf('PULL end')));
    final r = buildDiagnosticsReport(DiagnosticsInput(appVersion: '1', platform: 'x', step: 's', log: t));
    expect(r, contains('Recent sync log'));
    expect(r, contains('PULL end (you) SyncOk 2.1s'));
  });
}
