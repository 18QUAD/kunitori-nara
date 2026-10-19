import 'dart:convert';
import 'dart:js_interop';

@JS('window.kunitoriDiagnostics.record')
external void _record(String event, String json, bool important);
@JS('window.kunitoriDiagnostics.report')
external String _report();
@JS('window.kunitoriDiagnostics.download')
external void _download();

void recordDiagnostic(
  String event,
  Map<String, Object?> state, {
  bool important = true,
}) {
  try {
    _record(event, jsonEncode(state), important);
  } catch (_) {}
}

String diagnosticReport() {
  try {
    return _report();
  } catch (_) {
    return '{"storageAvailable":false}';
  }
}

void downloadDiagnostics() {
  try {
    _download();
  } catch (_) {}
}
