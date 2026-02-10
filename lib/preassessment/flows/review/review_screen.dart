// lib/preassessment/flows/review/review_screen.dart
//
// ✅ Updated in full:
// - Removes the FloatingActionButton (+) that was sending users back to RegionSelect
// - Keeps provider-safe navigation helpers
// - Dev sessions (sessionId starting with "dev_") are allowed to submit even if the Firestore doc
//   couldn't be created client-side (submitIntakeSessionFn auto-creates if missing).
// - Link-based sessions still require a real non-draft sessionId (from consumeIntakeInviteFn).
// - Captures server-returned intakeSessionId, debugPrints old->new, and adopts it into the draft
//   BEFORE resetting, so public booking no longer gets stuck thinking it's "draft".
// - Keeps white fade transitions + existing UI

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'package:kineticdx_app_v3/preassessment/domain/answer_value.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'package:kineticdx_app_v3/preassessment/domain/intake_schema.dart';

import 'package:kineticdx_app_v3/preassessment/state/intake_draft_controller.dart';
import 'package:kineticdx_app_v3/preassessment/flows/regions/dynamic_flow_screen.dart';
import 'package:kineticdx_app_v3/preassessment/flows/thank_you/thank_you_screen.dart';

// Region flows
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/ankle/ankle_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/cervical/cervical_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/elbow/elbow_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/hip/hip_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/knee/knee_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/lumbar/lumbar_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/shoulder/shoulder_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/thoracic/thoracic_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/wrist/wrist_flow_v1.dart';

// General (non-region) visit flow
import 'package:kineticdx_app_v3/preassessment/domain/flows/general_visit/general_visit_flow_v1.dart';

class ReviewScreen extends StatefulWidget {
  final String Function(String key) t;

  const ReviewScreen({
    super.key,
    required this.t,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _submitting = false;
  String? _submitError;

  String Function(String key) get t => widget.t;

  // White fade between screens
  static const Duration _routeFade = Duration(milliseconds: 500);
  bool _whiteTransitionOn = false;
  bool _whiteVisible = false;
  bool _isNavigating = false;

  String _safeText(String key, {String? fallback}) {
    final v = t(key);
    if (v == key) return fallback ?? key;
    return v;
  }

  String? _timestampDobToIsoDate(Timestamp? ts) {
    if (ts == null) return null;
    final d = ts.toDate();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // Debug-only: ensure callable payload contains only JSON-ish types.
  void _assertCallableEncodable(dynamic value, [String path = r'$']) {
    final okPrimitive =
        value == null || value is bool || value is num || value is String;
    if (okPrimitive) return;

    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _assertCallableEncodable(value[i], '$path[$i]');
      }
      return;
    }

    if (value is Map) {
      for (final entry in value.entries) {
        final k = entry.key;
        if (k is! String) {
          throw StateError(
            'Callable payload has non-string map key at $path: $k (${k.runtimeType})',
          );
        }
        _assertCallableEncodable(entry.value, '$path.$k');
      }
      return;
    }

    throw StateError(
      'Callable payload contains non-encodable type at $path: '
      '${value.runtimeType} => $value',
    );
  }

  FlowDefinition? _flowForBodyArea(String bodyArea) {
    switch (bodyArea) {
      case 'ankle':
      case 'region.ankle':
        return ankleFlowV1;
      case 'cervical':
      case 'region.cervical':
        return cervicalFlowV1;
      case 'elbow':
      case 'region.elbow':
        return elbowFlowV1;
      case 'hip':
      case 'region.hip':
        return hipFlowV1;
      case 'knee':
      case 'region.knee':
        return kneeFlowV1;
      case 'lumbar':
      case 'region.lumbar':
        return lumbarFlowV1;
      case 'shoulder':
      case 'region.shoulder':
        return shoulderFlowV1;
      case 'thoracic':
      case 'region.thoracic':
        return thoracicFlowV1;
      case 'wrist':
      case 'region.wrist':
        return wristFlowV1;
      default:
        return null;
    }
  }

  /// Resolve the active flow definition for this session.
  ///
  /// Priority:
  /// - meta.flowId == 'generalVisit' → generalVisitFlowV1
  /// - otherwise, infer from regionSelection.bodyArea (region flows)
  FlowDefinition? _resolveFlow(IntakeDraftController draft) {
    final answers = draft.answers;
    final metaFlow = answers['meta.flowId'];
    final metaFlowId = metaFlow?.asSingle ?? metaFlow?.asText ?? '';

    if (metaFlowId.trim() == 'generalVisit') {
      return generalVisitFlowV1;
    }

    final bodyArea = draft.session.regionSelection.bodyArea;
    return _flowForBodyArea(bodyArea);
  }

  String _formatAnswer({
    required QuestionDef q,
    required AnswerValue v,
  }) {
    switch (q.valueType) {
      case QuestionValueType.boolType:
        final b = v.asBool;
        if (b == null) return 'Unknown';
        return b ? 'Yes' : 'No';

      case QuestionValueType.intType:
        final i = v.asInt;
        return i?.toString() ?? 'Unknown';

      case QuestionValueType.numType:
        final n = v.asNum;
        return n?.toString() ?? 'Unknown';

      case QuestionValueType.textType:
        final s = v.asText;
        if (s == null || s.trim().isEmpty) {
          return 'None';
        }
        return s.trim();

      case QuestionValueType.singleChoice:
        final id = v.asSingle;
        if (id == null || id.isEmpty) {
          return 'None';
        }
        final opt = q.options.where((o) => o.id == id).toList();
        if (opt.isEmpty) return id;
        return _safeText(opt.first.labelKey, fallback: id);

      case QuestionValueType.multiChoice:
        final ids = v.asMulti;
        if (ids == null || ids.isEmpty) {
          return 'None';
        }
        final labels = ids.map((id) {
          final opt = q.options.where((o) => o.id == id).toList();
          if (opt.isEmpty) return id;
          return _safeText(opt.first.labelKey, fallback: id);
        }).toList();
        return labels.join(', ');

      case QuestionValueType.dateType:
        return v.asDate ?? 'None';

      case QuestionValueType.mapType:
        final m = v.asMap;
        if (m == null) return 'None';
        return m.toString();
    }
  }

  String _qid(String flowId, String suffix) => '$flowId.$suffix';

  List<MapEntry<String, String>> _goalLines({
    required String flowId,
    required Map<String, AnswerValue> answers,
  }) {
    final out = <MapEntry<String, String>>[];

    final g1 = answers[_qid(flowId, 'goals.goal1')]?.asText?.trim();
    final g2 = answers[_qid(flowId, 'goals.goal2')]?.asText?.trim();
    final g3 = answers[_qid(flowId, 'goals.goal3')]?.asText?.trim();
    final more =
        answers[_qid(flowId, 'history.additionalInfo')]?.asText?.trim();

    if (g1 != null && g1.isNotEmpty) out.add(MapEntry('Goal 1', g1));
    if (g2 != null && g2.isNotEmpty) out.add(MapEntry('Goal 2', g2));
    if (g3 != null && g3.isNotEmpty) out.add(MapEntry('Goal 3', g3));
    if (more != null && more.isNotEmpty) out.add(MapEntry('More info', more));

    return out;
  }

  Future<void> _fadeToWhite() async {
    if (!mounted) return;

    setState(() {
      _whiteTransitionOn = true;
      _whiteVisible = false;
    });

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    setState(() => _whiteVisible = true);
    await Future<void>.delayed(_routeFade);
  }

  /// ✅ Provider-safe: build inside the route so it inherits provider from caller.
  Future<void> _pushWithWhiteFadeBuilder(WidgetBuilder builder) async {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;

    await _fadeToWhite();
    if (!mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: _routeFade,
        pageBuilder: (routeCtx, __, ___) => builder(routeCtx),
        transitionsBuilder: (_, anim, __, child) {
          return Container(
            color: Colors.white,
            child: FadeTransition(opacity: anim, child: child),
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _whiteVisible = false;
      _whiteTransitionOn = false;
      _isNavigating = false;
    });
  }

  Future<void> _replaceAllWithWhiteFade(Widget next) async {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;

    await _fadeToWhite();
    if (!mounted) return;

    await Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: _routeFade,
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, anim, __, child) {
          return Container(
            color: Colors.white,
            child: FadeTransition(opacity: anim, child: child),
          );
        },
      ),
      (_) => false,
    );

    if (!mounted) return;
    setState(() {
      _whiteVisible = false;
      _whiteTransitionOn = false;
      _isNavigating = false;
    });
  }

  bool _isDevSessionId(String sessionId) {
    final s = sessionId.trim().toLowerCase();
    return s.startsWith('dev_');
  }

  Future<void> _submit({
    required IntakeDraftController draft,
    required FlowDefinition flow,
  }) async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final s = draft.session;
      final oldSessionId = (s.sessionId).trim();

      final isDraft =
          oldSessionId.isEmpty || oldSessionId.toLowerCase() == 'draft';
      final isDev = _isDevSessionId(oldSessionId);

      // Link-based flows MUST have a real server session id.
      // Dev flows use dev_* session ids; server submit function will auto-create if missing.
      if (isDraft && !isDev) {
        throw Exception(
          'Missing session.\n\n'
          'Please return to the email link and start again.\n'
          '(This usually happens if the session was not claimed from the link.)',
        );
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('submitIntakeSessionFn');

      final payload = <String, dynamic>{
        'clinicId': s.clinicId,
        'sessionId': oldSessionId,
        'intakeSchemaVersion': IntakeSchemaVersions.intakeSessionV1,
        'flowId': flow.flowId,
        'flowVersion': flow.flowVersion,
        'consent': <String, dynamic>{
          'policyBundleId': s.consent.policyBundleId,
          'policyBundleVersion': s.consent.policyBundleVersion,
          'locale': s.consent.locale,
          'termsAccepted': s.consent.termsAccepted,
          'privacyAccepted': s.consent.privacyAccepted,
          'dataStorageAccepted': s.consent.dataStorageAccepted,
          'notEmergencyAck': s.consent.notEmergencyAck,
          'noDiagnosisAck': s.consent.noDiagnosisAck,
          'consentToContact': s.consent.consentToContact,
        },
        'patientDetails': <String, dynamic>{
          'firstName': s.patientDetails.firstName.trim(),
          'lastName': s.patientDetails.lastName.trim(),
          'email': s.patientDetails.email.trim(),
          'phone': s.patientDetails.phone.trim(),
          'dateOfBirth': _timestampDobToIsoDate(s.patientDetails.dateOfBirth),
        },
        'regionSelection': <String, dynamic>{
          'bodyArea': s.regionSelection.bodyArea,
          'side': s.regionSelection.side,
          'regionSetVersion': s.regionSelection.regionSetVersion,
        },
        'answers': s.answers.map((k, v) => MapEntry(k, v.toMap())),
      };

      assert(() {
        _assertCallableEncodable(payload);
        return true;
      }());

      final result = await callable.call(payload);
      if (!mounted) return;

      final map = (result.data is Map)
          ? Map<String, dynamic>.from(result.data as Map)
          : <String, dynamic>{};

      final newSessionId = (map['intakeSessionId'] ?? '').toString().trim();

      debugPrint(
        '[ReviewScreen] submitIntakeSessionFn returned intakeSessionId="$newSessionId" '
        '(was "$oldSessionId")',
      );

      if (newSessionId.isEmpty) {
        throw StateError('submitIntakeSessionFn returned no intakeSessionId');
      }

      draft.setServerSessionId(newSessionId);
      draft.reset(preserveServerSessionId: true);

      await _replaceAllWithWhiteFade(
        ThankYouScreen(intakeSessionId: newSessionId),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _submitError = '${e.code}: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editAnswers({
    required IntakeDraftController draft,
    required FlowDefinition flow,
  }) async {
    await _pushWithWhiteFadeBuilder((routeCtx) {
      return DynamicFlowScreen(
        flow: flow,
        answers: draft.answers,
        onAnswerChanged: (qid, v) => draft.setAnswer(qid, v),
        t: t,
        onContinue: () => Navigator.of(routeCtx).pop(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<IntakeDraftController>();
    final s = draft.session;

    final bodyArea = s.regionSelection.bodyArea;
    final flow = _resolveFlow(draft);

    final answers = draft.answers;
    final metaFlow = answers['meta.flowId'];
    final metaFlowId = metaFlow?.asSingle ?? metaFlow?.asText ?? '';
    final isGeneralVisit = metaFlowId.trim() == 'generalVisit';

    final hasConsent = s.consent.isComplete;
    final hasPatientBasics = s.patientDetails.firstName.trim().isNotEmpty &&
        s.patientDetails.lastName.trim().isNotEmpty;
    final hasRegion = isGeneralVisit ? true : bodyArea.trim().isNotEmpty;

    final canContinue = flow == null ? false : draft.canContinueFlow(flow);

    final sessionId = s.sessionId.trim();
    final isDev = _isDevSessionId(sessionId);
    final hasUsableSessionId =
        sessionId.isNotEmpty && sessionId.toLowerCase() != 'draft';

    final canSubmit = !_submitting &&
        flow != null &&
        hasConsent &&
        hasPatientBasics &&
        hasRegion &&
        canContinue &&
        (hasUsableSessionId || isDev);

    final goalLines = flow == null
        ? const <MapEntry<String, String>>[]
        : _goalLines(flowId: flow.flowId, answers: s.answers);

    final dobIso = _timestampDobToIsoDate(s.patientDetails.dateOfBirth);

    final scaffold = Scaffold(
      appBar: AppBar(
        title:
            Text(_safeText('preassessment.review.title', fallback: 'Review')),
      ),
      // ✅ FAB REMOVED (this was the "+" that returned to RegionSelect)
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_submitError != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _submitError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _SectionCard(
            title: _safeText('preassessment.review.consentTitle',
                fallback: 'Consent'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(
                  _safeText('preassessment.review.policyBundle',
                      fallback: 'Policy bundle'),
                  '${s.consent.policyBundleId} v${s.consent.policyBundleVersion}',
                ),
                const SizedBox(height: 8),
                _BoolLine(
                  label: _safeText('preassessment.review.terms',
                      fallback: 'Terms accepted'),
                  value: s.consent.termsAccepted,
                ),
                _BoolLine(
                  label: _safeText('preassessment.review.privacy',
                      fallback: 'Privacy accepted'),
                  value: s.consent.privacyAccepted,
                ),
                _BoolLine(
                  label: _safeText('preassessment.review.dataStorage',
                      fallback: 'Data storage accepted'),
                  value: s.consent.dataStorageAccepted,
                ),
                _BoolLine(
                  label: _safeText('preassessment.review.notEmergency',
                      fallback: 'Not an emergency'),
                  value: s.consent.notEmergencyAck,
                ),
                _BoolLine(
                  label: _safeText('preassessment.review.noDiagnosis',
                      fallback: 'No diagnosis acknowledgement'),
                  value: s.consent.noDiagnosisAck,
                ),
                _BoolLine(
                  label: _safeText('preassessment.review.contactOk',
                      fallback: 'Consent to contact'),
                  value: s.consent.consentToContact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: _safeText('preassessment.review.patientTitle',
                fallback: 'Patient details'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(
                  _safeText('preassessment.review.name', fallback: 'Name'),
                  '${s.patientDetails.firstName} ${s.patientDetails.lastName}'
                      .trim(),
                ),
                _kv(_safeText('preassessment.review.email', fallback: 'Email'),
                    s.patientDetails.email),
                _kv(_safeText('preassessment.review.phone', fallback: 'Phone'),
                    s.patientDetails.phone),
                _kv(
                  _safeText('preassessment.review.dob',
                      fallback: 'Date of birth'),
                  dobIso ?? 'None',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!isGeneralVisit)
            _SectionCard(
              title: _safeText('preassessment.review.regionTitle',
                  fallback: 'Region'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(
                    _safeText('preassessment.review.bodyArea',
                        fallback: 'Body area'),
                    bodyArea,
                  ),
                  _kv(_safeText('preassessment.review.side', fallback: 'Side'),
                      s.regionSelection.side),
                  if (flow == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _safeText(
                          'preassessment.review.regionFlowMissing',
                          fallback: 'No flow found for selected region.',
                        ),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  else
                    _kv(
                      _safeText(
                        'preassessment.review.flowVersion',
                        fallback: 'Flow',
                      ),
                      '${flow.flowId} v${flow.flowVersion}',
                    ),
                ],
              ),
            )
          else if (flow != null) ...[
            _SectionCard(
              title: _safeText(
                'preassessment.review.regionTitle',
                fallback: 'Visit type',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(
                    'Flow',
                    '${flow.flowId} v${flow.flowVersion}',
                  ),
                ],
              ),
            ),
          ],
          if (goalLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: _safeText('preassessment.review.goalsTitle',
                  fallback: 'Goals & more info'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: goalLines
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _kv(e.key, e.value),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: _safeText('preassessment.review.keyAnswersTitle',
                fallback: 'Key answers'),
            child: flow == null
                ? Text(_safeText('preassessment.review.noKeyAnswers',
                    fallback: 'No key answers available.'))
                : Column(
                    children: flow.keyAnswerIds.map((qid) {
                      final q = flow.byId[qid];
                      final ans = s.answers[qid];

                      final label = q == null
                          ? qid
                          : _safeText(q.promptKey, fallback: qid);

                      final value = (q == null || ans == null)
                          ? 'None'
                          : _formatAnswer(q: q, v: ans);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _kv(label, value),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (flow == null || _submitting || _isNavigating)
                      ? null
                      : () => _editAnswers(draft: draft, flow: flow),
                  child: Text(_safeText('preassessment.review.editAnswers',
                      fallback: 'Edit answers')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: canSubmit
                      ? () => _submit(draft: draft, flow: flow)
                      : null,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_safeText('preassessment.review.submit',
                          fallback: 'Submit')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!canSubmit && !_submitting)
            Text(
              _safeText('preassessment.review.submitDisabledHint',
                  fallback:
                      'Please complete required fields before submitting.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (_whiteTransitionOn)
          IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              opacity: _whiteVisible ? 1.0 : 0.0,
              duration: _routeFade,
              curve: Curves.easeOut,
              child: Container(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(v.isEmpty ? '-' : v)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BoolLine extends StatelessWidget {
  final String label;
  final bool value;

  const _BoolLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 10),
        Icon(
          value ? Icons.check_circle : Icons.cancel,
          size: 18,
          color: value ? Colors.green : Colors.red,
        ),
      ],
    );
  }
}
