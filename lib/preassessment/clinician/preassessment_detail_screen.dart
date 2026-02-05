import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:kineticdx_app_v3/preassessment/domain/labels/preassessment_label_resolver.dart';

class PreassessmentDetailScreen extends StatefulWidget {
  final String clinicId;
  final String intakeSessionId;

  const PreassessmentDetailScreen({
    super.key,
    required this.clinicId,
    required this.intakeSessionId,
  });

  @override
  State<PreassessmentDetailScreen> createState() =>
      _PreassessmentDetailScreenState();
}

class _PreassessmentDetailScreenState extends State<PreassessmentDetailScreen> {
  String get clinicId => widget.clinicId;
  String get intakeSessionId => widget.intakeSessionId;

  // ✅ Turn this on only when you explicitly want the debug CARD in the UI.
  static const bool _showDecisionSupportDebug = false;

  CollectionReference<Map<String, dynamic>> _intakeSessionsRef(
      String clinicId) {
    return FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('intakeSessions');
  }

  DocumentReference<Map<String, dynamic>> _decisionSupportRef(
    String clinicId,
    String intakeSessionId,
  ) {
    return FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('decisionSupport')
        .doc(intakeSessionId);
  }

  // ---------------------------
  // Decision Support compute + DEBUG (console only)
  // ---------------------------

  String _safeStr(Object? v) => (v == null) ? '' : v.toString();

  void _debugPrintMap(String title, Map<String, dynamic> m) {
    debugPrint('🧩 $title');
    for (final e in m.entries) {
      debugPrint('   • ${e.key}: ${_safeStr(e.value)}');
    }
  }

  String _formatFnError(Object e) {
    if (e is FirebaseFunctionsException) {
      return 'code=${e.code} message=${e.message} details=${_safeStr(e.details)}';
    }
    return e.toString();
  }

  Future<void> _computeDecisionSupport(BuildContext context) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

    final candidates = <String>[
      'computeDecisionSupport',
    ];

    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'intakeSessionId': intakeSessionId,
    };

    debugPrint('🧠 DECISION SUPPORT REQUEST payload=$payload');

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generating decision support…')),
    );

    Object? lastError;

    for (final name in candidates) {
      try {
        debugPrint('⚡ Calling decision support function: $name');

        final callable = functions.httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
        );

        final res = await callable.call(payload);

        debugPrint('✅ Decision support callable OK: $name');
        debugPrint('✅ Decision support result type: ${res.data.runtimeType}');
        if (res.data is Map) {
          _debugPrintMap(
            'Decision support result (map)',
            Map<String, dynamic>.from(res.data as Map),
          );
        } else {
          debugPrint('✅ Decision support result: ${res.data}');
        }

        final dsRef = _decisionSupportRef(clinicId, intakeSessionId);
        await dsRef.get();
        if (mounted) setState(() {});

        messenger.showSnackBar(
          const SnackBar(content: Text('Decision support updated')),
        );
        return;
      } catch (e) {
        lastError = e;
        debugPrint(
            '❌ Decision support callable FAILED: $name → ${_formatFnError(e)}');

        final errText = _formatFnError(e);
        messenger.showSnackBar(
          SnackBar(content: Text('Decision support failed: $errText')),
        );
        return;
      }
    }

    final errText = _safeStr(lastError);
    debugPrint('❌ No callable matched. Last error: $errText');

    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'Decision support failed: no callable matched. Last: $errText'),
      ),
    );
  }

  // ---------------------------
  // UI helpers
  // ---------------------------

  String _triageLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'red':
        return 'RED';
      case 'amber':
        return 'AMBER';
      case 'green':
        return 'GREEN';
      default:
        return (status ?? '').toUpperCase();
    }
  }

  Color _triageColor(BuildContext context, String? status) {
    final s = (status ?? '').toLowerCase();
    if (s == 'red') return Colors.red;
    if (s == 'amber') return Colors.orange;
    if (s == 'green') return Colors.green;
    return Theme.of(context).colorScheme.outline;
  }

  String _categoryForQuestionId(String qid) {
    final parts = qid.split('.');
    if (parts.length < 2) return 'Other';

    final bucket = parts[1];
    switch (bucket) {
      case 'redflags':
        return 'Safety';
      case 'context':
      case 'history':
        return 'Context';
      case 'symptoms':
      case 'pain':
        return 'Symptoms';
      case 'function':
        return 'Function';
      default:
        return 'Other';
    }
  }

  String _prettyValue(String flowId, dynamic answerValue) {
    if (answerValue == null) return '';
    if (answerValue is bool) return answerValue ? 'Yes' : 'No';
    if (answerValue is num) return answerValue.toString();

    if (answerValue is String) {
      final resolved = resolvePreassessmentLabel(flowId, answerValue);
      return resolved == answerValue ? answerValue : resolved;
    }

    if (answerValue is List) {
      final items = answerValue
          .map((x) => _prettyValue(flowId, x))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      return items.join(', ');
    }

    if (answerValue is Map) {
      return answerValue.toString();
    }

    return answerValue.toString();
  }

  String _buildNarrative({
    required String flowId,
    required Map<String, dynamic> answers,
  }) {
    String? pick(String qid) {
      final a = answers[qid];
      if (a is Map) return a['v']?.toString();
      return null;
    }

    List<String> pickMulti(String qid) {
      final a = answers[qid];
      if (a is Map && a['v'] is List) {
        return (a['v'] as List).map((e) => e.toString()).toList();
      }
      return [];
    }

    final painNow = pick('$flowId.pain.now');
    final worst24 = pick('$flowId.pain.worst24h');
    final timeSince = pick('$flowId.history.timeSinceStart');
    final mechanism = pick('$flowId.history.mechanism');

    final aggs = pickMulti('$flowId.function.aggravators');
    final limits = pickMulti('$flowId.function.limits');
    final features = pickMulti('$flowId.symptoms.features');

    final parts = <String>[];

    if (mechanism != null && mechanism.isNotEmpty) {
      parts.add('Onset/mechanism: ${_prettyValue(flowId, mechanism)}.');
    }
    if (timeSince != null && timeSince.isNotEmpty) {
      parts.add('Duration: ${_prettyValue(flowId, timeSince)}.');
    }
    if (painNow != null && painNow.isNotEmpty) {
      parts.add('Pain now: ${_prettyValue(flowId, painNow)}.');
    }
    if (worst24 != null && worst24.isNotEmpty) {
      parts.add('Worst in last 24h: ${_prettyValue(flowId, worst24)}.');
    }
    if (features.isNotEmpty) {
      parts.add('Key symptoms: ${_prettyValue(flowId, features)}.');
    }
    if (aggs.isNotEmpty) {
      parts.add('Aggravated by: ${_prettyValue(flowId, aggs)}.');
    }
    if (limits.isNotEmpty) {
      parts.add('Functional limits: ${_prettyValue(flowId, limits)}.');
    }

    return parts.isEmpty ? '' : parts.join(' ');
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _kv(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ---------------------------
  // Layer B readers (cached decision support)
  // ---------------------------

  List<Map<String, dynamic>> _readDiagnosticHypotheses(
      Map<String, dynamic> ds) {
    dynamic raw = ds['diagnosticHypotheses'];
    raw ??= ds['topDifferentials'];
    raw ??= ds['topDx'];
    raw ??= ds['differentials'];
    raw ??= ds['dx'];

    if (raw == null) return const [];
    if (raw is List) {
      if (raw.isNotEmpty && raw.first is String) {
        return raw
            .whereType<String>()
            .map((s) => <String, dynamic>{
                  'label': s,
                  'confidence': null,
                  'rationale': const [],
                })
            .toList();
      }
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _readRecommendedTests(Map<String, dynamic> ds) {
    dynamic raw = ds['recommendedTests'];
    raw ??= ds['objectiveTests'];
    raw ??= ds['tests'];

    if (raw == null) return const [];
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is String) {
          out.add({'category': item, 'reason': ''});
        } else if (item is Map) {
          out.add(Map<String, dynamic>.from(item));
        } else if (item != null) {
          out.add({'category': item.toString(), 'reason': ''});
        }
      }
      return out;
    }
    return const [];
  }

  Map<String, dynamic> _readTriage(
      Map<String, dynamic> summary, Map<String, dynamic> root) {
    final raw = summary['triage'] ?? root['triage'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  String _prettyJsonTruncated(Map<String, dynamic> m, {int maxChars = 1200}) {
    try {
      final s = const JsonEncoder.withIndent('  ').convert(m);
      if (s.length <= maxChars) return s;
      return '${s.substring(0, maxChars)}\n…(truncated)…';
    } catch (_) {
      final s = m.toString();
      if (s.length <= maxChars) return s;
      return '${s.substring(0, maxChars)}\n…(truncated)…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final intakeRef = _intakeSessionsRef(clinicId).doc(intakeSessionId);
    final dsRef = _decisionSupportRef(clinicId, intakeSessionId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preassessment detail'),
        actions: [
          IconButton(
            tooltip: 'Generate/refresh decision support',
            onPressed: () => _computeDecisionSupport(context),
            icon: const Icon(Icons.bolt),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: intakeRef.snapshots(),
        builder: (context, intakeSnap) {
          if (intakeSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (intakeSnap.hasError) {
            return Center(child: Text('Failed: ${intakeSnap.error}'));
          }
          if (!intakeSnap.hasData || !intakeSnap.data!.exists) {
            return const Center(child: Text('Not found.'));
          }

          final data = intakeSnap.data!.data() ?? {};

          final status = (data['status'] ?? '').toString();
          final flow = (data['flow'] is Map)
              ? (data['flow'] as Map)
              : <String, dynamic>{};
          final flowId = (flow['flowId'] ?? data['flowId'] ?? '').toString();

          final patient = (data['patientDetails'] is Map)
              ? (data['patientDetails'] as Map<String, dynamic>)
              : <String, dynamic>{};

          final regionSel = (data['regionSelection'] is Map)
              ? (data['regionSelection'] as Map<String, dynamic>)
              : <String, dynamic>{};

          final goals = (data['goals'] is Map)
              ? (data['goals'] as Map<String, dynamic>)
              : <String, dynamic>{};

          final answers = (data['answers'] is Map)
              ? (data['answers'] as Map<String, dynamic>)
              : <String, dynamic>{};

          final summary = (data['summary'] is Map)
              ? (data['summary'] as Map<String, dynamic>)
              : <String, dynamic>{};

          final summaryStatus =
              (data['summaryStatus'] ?? summary['status'] ?? '').toString();
          final summaryError =
              (data['summaryError'] ?? summary['error'] ?? '').toString();

          final triage = _readTriage(summary, data);
          final triageStatus =
              (triage['status'] ?? triage['level'] ?? '').toString();
          final triageReasons = (triage['reasons'] is List)
              ? (triage['reasons'] as List).map((e) => e.toString()).toList()
              : <String>[];

          final narrative = (summary['narrative'] ?? '').toString().trim();
          final autoNarrative =
              _buildNarrative(flowId: flowId, answers: answers);

          final List<_AnswerRow> rows = [];
          answers.forEach((qid, av) {
            if (av is! Map) return;
            final v = av['v'];
            final label = resolvePreassessmentLabel(flowId, qid);
            final value = _prettyValue(flowId, v);
            if (value.trim().isEmpty) return;

            rows.add(
              _AnswerRow(
                qid: qid,
                label: label == qid ? qid : label,
                value: value,
                category: _categoryForQuestionId(qid),
              ),
            );
          });

          rows.sort((a, b) {
            final c = a.category.compareTo(b.category);
            if (c != 0) return c;
            return a.qid.compareTo(b.qid);
          });

          final grouped = <String, List<_AnswerRow>>{};
          for (final r in rows) {
            grouped.putIfAbsent(r.category, () => []).add(r);
          }

          final patientName =
              '${(patient['firstName'] ?? '').toString().trim()} ${(patient['lastName'] ?? '').toString().trim()}'
                  .trim();

          final side = (regionSel['side'] ?? '').toString();

          final goalsText =
              (goals['goalsText'] ?? goals['text'] ?? '').toString().trim();
          final extraInfo =
              (goals['extraInfo'] ?? goals['moreInfo'] ?? '').toString().trim();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: dsRef.snapshots(),
            builder: (context, dsSnap) {
              final dsExists = dsSnap.hasData && dsSnap.data!.exists;
              final ds =
                  dsExists ? (dsSnap.data!.data() ?? {}) : <String, dynamic>{};

              final dsStatus = (ds['status'] ?? '').toString();
              final dsError = (ds['error'] ?? '').toString();
              final dsRuleset = (ds['rulesetVersion'] ?? '').toString();
              final dsGeneratedAt = ds['generatedAt'];

              final hypotheses = _readDiagnosticHypotheses(ds);
              final recommendedTests = _readRecommendedTests(ds);

              final hasDecisionSupport = ds.isNotEmpty ||
                  hypotheses.isNotEmpty ||
                  recommendedTests.isNotEmpty;

              if (kDebugMode) {
                debugPrint(
                    '🧷 DETAIL: clinicId=$clinicId sessionId=$intakeSessionId flowId=$flowId');
                debugPrint(
                    '🧷 DETAIL: status=$status summaryStatus=$summaryStatus');
                if (summaryError.isNotEmpty)
                  debugPrint('🧷 DETAIL: summaryError=$summaryError');

                debugPrint('🧷 DS: exists=$dsExists status=$dsStatus');
                if (dsError.isNotEmpty) debugPrint('🧷 DS: error=$dsError');
                debugPrint('🧷 DS: keys=${ds.keys.toList()}');
                debugPrint(
                    '🧷 DS: hypotheses=${hypotheses.length} tests=${recommendedTests.length}');
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName.isEmpty ? 'Patient' : patientName,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _kv('Status', status),
                          _kv('Flow', flowId),
                          _kv('Side', side),
                          if (summaryStatus.isNotEmpty)
                            _kv('Summary status', summaryStatus),
                          if (summaryError.isNotEmpty)
                            _kv('Summary error', summaryError),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  // ✅ use withOpacity for wider Flutter compatibility
                                  color: _triageColor(context, triageStatus)
                                      .withOpacity(.12),
                                  border: Border.all(
                                      color:
                                          _triageColor(context, triageStatus)),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  triageStatus.isEmpty
                                      ? '—'
                                      : _triageLabel(triageStatus),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _triageColor(context, triageStatus),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    _computeDecisionSupport(context),
                                icon: const Icon(Icons.bolt),
                                label: Text(hasDecisionSupport
                                    ? 'Refresh decision support'
                                    : 'Generate decision support'),
                              ),
                            ],
                          ),
                          if (!hasDecisionSupport)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'No decision support yet. Tap “Generate decision support”.',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                              ),
                            ),
                          if (dsError.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Decision support error: $dsError',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (kDebugMode && _showDecisionSupportDebug) ...[
                    _sectionTitle('Debug: decision support payload'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Exists: $dsExists'),
                            if (dsStatus.isNotEmpty) Text('Status: $dsStatus'),
                            if (dsRuleset.isNotEmpty)
                              Text('Ruleset: $dsRuleset'),
                            if (dsGeneratedAt != null)
                              Text('generatedAt: $dsGeneratedAt'),
                            if (dsError.isNotEmpty) Text('error: $dsError'),
                            const SizedBox(height: 8),
                            Text('Keys: ${ds.keys.join(', ')}'),
                            const SizedBox(height: 8),
                            Text('Hypotheses count: ${hypotheses.length}'),
                            Text(
                                'Recommended tests count: ${recommendedTests.length}'),
                            const SizedBox(height: 12),
                            const Text(
                              'decisionSupport JSON (truncated):',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _prettyJsonTruncated(ds),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (triageReasons.isNotEmpty) ...[
                    _sectionTitle('Alert rationale'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: triageReasons
                              .map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('• '),
                                      Expanded(child: Text(r)),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                  _sectionTitle('Clinical Decision Support (Not a Diagnosis)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generated from patient-reported intake data to support assessment planning.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Diagnostic hypotheses',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          if (hypotheses.isEmpty)
                            Text(
                              'No hypotheses yet. Tap “Generate decision support”.',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int i = 0;
                                    i < hypotheses.length && i < 3;
                                    i++)
                                  _HypothesisTile(h: hypotheses[i]),
                              ],
                            ),
                          const SizedBox(height: 14),
                          Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.35),
                            height: 24,
                            thickness: 1,
                          ),
                          const Text(
                            'Recommended test categories',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (recommendedTests.isEmpty)
                            Text(
                              'No recommendations yet.',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: recommendedTests.map((t) {
                                final cat = (t['category'] ??
                                        t['name'] ??
                                        t['label'] ??
                                        '')
                                    .toString()
                                    .trim();
                                final reason =
                                    (t['reason'] ?? '').toString().trim();
                                if (cat.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('• $cat'),
                                      if (reason.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 16, top: 2),
                                          child: Text(
                                            reason,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _sectionTitle('Patient goals & notes'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (goalsText.isNotEmpty) ...[
                            const Text('Goals',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(goalsText),
                          ] else
                            Text(
                              'No goals recorded.',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline),
                            ),
                          if (extraInfo.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Additional details',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(extraInfo),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _sectionTitle('Symptom narrative'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (narrative.isNotEmpty) ...[
                            const Text('Computed summary',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(narrative),
                            const SizedBox(height: 12),
                          ],
                          const Text('From patient answers',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            autoNarrative.isEmpty ? '—' : autoNarrative,
                            style: TextStyle(
                              color: autoNarrative.isEmpty
                                  ? Theme.of(context).colorScheme.outline
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _sectionTitle('Answers'),
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: entry.value.map((r) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(r.label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 4,
                                    child: Text(r.value),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HypothesisTile extends StatelessWidget {
  final Map<String, dynamic> h;

  const _HypothesisTile({required this.h});

  @override
  Widget build(BuildContext context) {
    final label =
        (h['label'] ?? h['name'] ?? h['title'] ?? '').toString().trim();

    final confidenceRaw = h['confidence'] ?? h['score'];
    double? confidence;
    if (confidenceRaw is num) {
      confidence = confidenceRaw.toDouble();
      if (confidence > 1.0) confidence = (confidence / 100.0).clamp(0.0, 1.0);
    }

    final rationale = (h['rationale'] is List)
        ? (h['rationale'] as List).map((e) => e.toString()).toList()
        : (h['reasons'] is List)
            ? (h['reasons'] as List).map((e) => e.toString()).toList()
            : <String>[];

    final title = label.isEmpty ? 'Hypothesis' : label;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (confidence != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 14,
                  ),
                ),
              ),
            if (rationale.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Rationale',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...rationale.map(
                (r) => Text('• $r', style: const TextStyle(fontSize: 14)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnswerRow {
  final String qid;
  final String label;
  final String value;
  final String category;

  _AnswerRow({
    required this.qid,
    required this.label,
    required this.value,
    required this.category,
  });
}
