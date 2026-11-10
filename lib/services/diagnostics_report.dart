// services/diagnostics_report.dart
//
// 2026-11-10: user-initiated "Send details". Plain-text report the user
// reads in full before sending. Never includes note text or file names
// beyond what the error message itself contains. Nothing is sent
// automatically (no-surveillance rule): the report is opened in the
// existing kworld.space contact form, or copied.

class DiagnosticsInput {
  final String appVersion;
  final String platform;
  final String step;
  final String? error;
  final String? debug;
  const DiagnosticsInput({
    required this.appVersion,
    required this.platform,
    required this.step,
    this.error,
    this.debug,
  });
}

String buildDiagnosticsReport(DiagnosticsInput d, {String? helperName}) {
  final b = StringBuffer()
    ..writeln('LocalSync details (no note text included)')
    ..writeln('App: ${d.appVersion}')
    ..writeln('Device: ${d.platform}')
    ..writeln('Step: ${d.step}');
  if (d.error != null) b.writeln('What happened: ${d.error}');
  if (d.debug != null) b.writeln('Technical: ${d.debug}');
  final name = (helperName ?? '').trim();
  b.writeln('Credit me as: ${name.isEmpty ? '(leave blank to stay anonymous)' : name}');
  return b.toString();
}

Uri diagnosticsContactUri(String report) =>
    Uri.parse('https://kworld.space/contact?help=1&app=localsync&msg='
        '${Uri.encodeComponent(report)}');
