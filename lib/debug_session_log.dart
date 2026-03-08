import 'package:flutter/foundation.dart';

void debugSessionLog(String source, String message, [Map<String, dynamic>? data, String? level]) {
  if (kDebugMode) {
    final buf = StringBuffer('[Session] $source: $message');
    if (data != null && data.isNotEmpty) buf.write(' $data');
    debugPrint(buf.toString());
  }
}
