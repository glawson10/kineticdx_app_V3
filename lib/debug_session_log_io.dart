import 'dart:convert';
import 'dart:io';

void debugSessionLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  try {
    final payload = <String, dynamic>{
      'sessionId': '03f0b0',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      'data': data,
      'hypothesisId': hypothesisId,
    };
    File('debug-03f0b0.log').writeAsStringSync('${jsonEncode(payload)}\n', mode: FileMode.append);
  } catch (_) {}
}
