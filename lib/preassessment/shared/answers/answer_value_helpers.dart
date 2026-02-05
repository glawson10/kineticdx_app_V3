// answer_value_helpers.dart
//
// Helpers for your typed AnswerValue union.
// Assumes stored answers look like:
// { "some.questionId": { "t": "single", "v": "option.id" } }

typedef AnswerMap = Map<String, dynamic>;

String? readText(AnswerMap answers, String qid) {
  final a = answers[qid];
  if (a is Map && a['t'] == 'text') {
    final v = (a['v'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }
  return null;
}

bool? readBool(AnswerMap answers, String qid) {
  final a = answers[qid];
  if (a is Map && a['t'] == 'bool') return a['v'] == true;
  return null;
}

String? readSingle(AnswerMap answers, String qid) {
  final a = answers[qid];
  if (a is Map && a['t'] == 'single') {
    final v = (a['v'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }
  return null;
}

List<String> readMulti(AnswerMap answers, String qid) {
  final a = answers[qid];
  if (a is Map && a['t'] == 'multi') {
    final v = a['v'];
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
  }
  return const [];
}

/// Map a single optionId to label with safe fallback.
String labelSingle(String? optionId, Map<String, String> labels, {String fallback = '—'}) {
  if (optionId == null) return fallback;
  return labels[optionId] ?? optionId; // fallback to ID if unknown
}

/// Map multi optionIds to labels with safe fallback, de-duped, stable order.
List<String> labelsMulti(List<String> optionIds, Map<String, String> labels) {
  final out = <String>[];
  final seen = <String>{};
  for (final id in optionIds) {
    final key = id.trim();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(labels[key] ?? key);
  }
  return out;
}

/// Join list for display.
String joinOrDash(List<String> items) => items.isEmpty ? '—' : items.join(', ');
