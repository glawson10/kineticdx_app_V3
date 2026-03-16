// lib/preassessment/screens/general_questionnaire_token_screen.dart
//
// Public token entry for the General Questionnaire.
// Resolves token -> intakeSessionId via Cloud Function and starts the flow.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/answer_value.dart';
import '../domain/intake_schema.dart';
import '../state/intake_draft_controller.dart';
import './intake_flow_host.dart';

class GeneralQuestionnaireTokenScreen extends StatefulWidget {
  const GeneralQuestionnaireTokenScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<GeneralQuestionnaireTokenScreen> createState() =>
      _GeneralQuestionnaireTokenScreenState();
}

class _GeneralQuestionnaireTokenScreenState
    extends State<GeneralQuestionnaireTokenScreen> {
  bool _loading = true;
  String? _error;
  bool _booted = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _boot();
    });
  }

  DateTime? _parseDob(dynamic dobIso) {
    if (dobIso == null) return null;
    final s = dobIso.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  void _applyPrefill(
    IntakeDraftController draft,
    Map<String, dynamic> prefill,
  ) {
    final firstName = (prefill['firstName'] ?? '').toString().trim();
    final lastName = (prefill['lastName'] ?? '').toString().trim();
    final email = (prefill['email'] ?? '').toString().trim();
    final phone = (prefill['phone'] ?? '').toString().trim();
    final address = (prefill['address'] ?? '').toString().trim();
    final dob = _parseDob(prefill['dobIso']);
    final existing = draft.session.patientDetails;

    draft.setPatientDetails(
      PatientDetailsBlock(
        firstName: firstName.isNotEmpty ? firstName : existing.firstName,
        lastName: lastName.isNotEmpty ? lastName : existing.lastName,
        dateOfBirth:
            dob != null ? Timestamp.fromDate(dob) : existing.dateOfBirth,
        email: email.isNotEmpty ? email : existing.email,
        phone: phone.isNotEmpty ? phone : existing.phone,
        isProxy: existing.isProxy,
        proxyName: existing.proxyName,
        proxyRelationship: existing.proxyRelationship,
        confirmedAt: null,
      ),
    );

    if (firstName.isNotEmpty) {
      draft.setAnswer('patient.firstName', AnswerValue.text(firstName));
    }
    if (lastName.isNotEmpty) {
      draft.setAnswer('patient.lastName', AnswerValue.text(lastName));
    }
    if (email.isNotEmpty) {
      draft.setAnswer('patient.email', AnswerValue.text(email));
    }
    if (phone.isNotEmpty) {
      draft.setAnswer('patient.phone', AnswerValue.text(phone));
    }
    if (address.isNotEmpty) {
      draft.setAnswer('patient.address', AnswerValue.text(address));
    }
  }

  String _friendlyFunctionsError(FirebaseFunctionsException e) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();

    if (code == 'failed-precondition' && msg.contains('expired')) {
      return 'This link has expired.\n\nPlease ask the clinic to resend the form.';
    }
    if (code == 'failed-precondition' &&
        (msg.contains('used') || msg.contains('submitted'))) {
      return 'This link has already been submitted.\n\nIf you need to change anything, please contact the clinic.';
    }
    if (code == 'not-found') {
      return 'This link is invalid.\n\nPlease use the full link from the email.';
    }

    // Catch-all for internal/backend issues (eg. missing index, transient errors)
    if (code == 'internal' || code == 'unknown') {
      return 'We could not start your questionnaire right now.\n\n'
          'Please try again in a few minutes. If the problem continues, contact the clinic so they can check their system.';
    }

    return 'Server error.\n\ncode: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}';
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = widget.token.trim();
      if (token.isEmpty) {
        throw Exception(
          'Missing link token.\n\nPlease use the full link from the email.',
        );
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('resolveIntakeLinkTokenFn');

      final resp = await fn.call(<String, dynamic>{
        'token': token,
      });

      if (resp.data is! Map) {
        throw Exception('Server returned unexpected payload: ${resp.data}');
      }

      final data = Map<String, dynamic>.from(resp.data as Map);
      final clinicId = (data['clinicId'] ?? '').toString().trim();
      final sessionId = (data['intakeSessionId'] ?? '').toString().trim();
      final flowId = (data['flowId'] ?? '').toString().trim();
      final flowVersion = data['flowVersion'] is int ? data['flowVersion'] as int : 1;
      final bookingRequestId =
          (data['bookingRequestId'] ?? '').toString().trim();
      final prefillPatient =
          data['prefillPatient'] is Map
              ? Map<String, dynamic>.from(data['prefillPatient'] as Map)
              : const <String, dynamic>{};
      final flowDefinitionId = (data['flowDefinitionId'] ?? '').toString().trim();
      final clinicalProfileId = (data['clinicalProfileId'] ?? '').toString().trim();
      final summaryEngine = (data['summaryEngine'] ?? '').toString().trim();
      final decisionSupportProfile = (data['decisionSupportProfile'] ?? '').toString().trim();
      final supportsDifferentialHypothesis = data['supportsDifferentialHypothesis'] == true;
      final templateId = (data['templateId'] ?? '').toString().trim();

      if (clinicId.isEmpty) {
        throw Exception('Server did not return a clinicId.');
      }
      if (sessionId.isEmpty) {
        throw Exception('Server did not return a sessionId.');
      }

      if (!mounted) return;

      final flowSnapshot = IntakeFlowSnapshot(
        templateId: templateId.isEmpty ? null : templateId,
        flowDefinitionId: flowDefinitionId.isEmpty ? null : flowDefinitionId,
        clinicalProfileId: clinicalProfileId.isEmpty ? null : clinicalProfileId,
        flowId: flowId.isEmpty ? null : flowId,
        flowVersion: flowVersion,
        summaryEngine: summaryEngine.isEmpty ? null : summaryEngine,
        decisionSupportProfile: decisionSupportProfile.isEmpty ? null : decisionSupportProfile,
        supportsDifferentialHypothesis: supportsDifferentialHypothesis,
      );

      _navigateToFlowHost(
        clinicId: clinicId,
        sessionId: sessionId,
        flowIdOverride: flowId.isNotEmpty ? flowId : 'generalVisit',
        flowSnapshot: flowSnapshot,
        bookingRequestId: bookingRequestId,
        prefillPatient: prefillPatient,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyFunctionsError(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      if (mounted && !_navigated) {
        setState(() => _loading = false);
      }
    }
  }

  void _navigateToFlowHost({
    required String clinicId,
    required String sessionId,
    required String flowIdOverride,
    required IntakeFlowSnapshot flowSnapshot,
    required String bookingRequestId,
    required Map<String, dynamic> prefillPatient,
  }) {
    if (_navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider<IntakeDraftController>(
            create: (_) {
              final draft = IntakeDraftController(clinicId: clinicId);
              draft.setSessionId(sessionId);
              draft.setFlowIdOverride(flowIdOverride);
              draft.setFlowSnapshot(flowSnapshot);
              if (prefillPatient.isNotEmpty) {
                _applyPrefill(draft, prefillPatient);
              }
              return draft;
            },
            child: IntakeFlowHost(
              flowArgs: <String, dynamic>{
                'clinicId': clinicId,
                'intakeSessionId': sessionId,
                'flowIdOverride': flowIdOverride,
                'flowDefinitionId': flowSnapshot.flowDefinitionId,
                'clinicalProfileId': flowSnapshot.clinicalProfileId,
                if (bookingRequestId.isNotEmpty)
                  'bookingRequestId': bookingRequestId,
                if (prefillPatient.isNotEmpty)
                  'prefillPatient': prefillPatient,
              },
            ),
          ),
        ),
      );
    });
  }

  void _retry() {
    _booted = false;
    _navigated = false;
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starting questionnaire')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparing your questionnaire...'),
                  ],
                )
              : (_error != null)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
