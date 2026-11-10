import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/diagnostics_report.dart';

void main() {
  test('report has version, step, credit line; URI round-trips', () {
    const d = DiagnosticsInput(
        appVersion: '1.0.9 (112)', platform: 'iOS 18', step: 'Merging',
        error: 'Timed out');
    final r = buildDiagnosticsReport(d);
    expect(r, contains('1.0.9 (112)'));
    expect(r, contains('Step: Merging'));
    expect(r, contains('Credit me as:'));
    final u = diagnosticsContactUri(r);
    expect(u.queryParameters['msg'], r);
  });
}
