// lib/preassessment/state/intake_draft_controller.dart
//
// Local-only draft state for a Phase 3 intake session.
// This is NOT the authoritative store (submission is authoritative).
//
// ✅ Updated in full:
// - Keeps setServerSessionId(String) used by ReviewScreen
// - Makes setSessionId() safe (trim + ignore empty + no-op if unchanged)
// - Fixes reset(preserveServerSessionId: true) so it preserves ANY non-draft id
//   (including dev_* ids) — exactly what ReviewScreen expects.
// - ✅ Adds flowIdOverride support so clinician starts can bypass region selection
//   and route directly into generalVisit (or other future flows).
//
// NOTES:
// - This controller is intentionally light: it stores local blocks + answers.
// - Routing decisions should read draft.flowIdOverride (see IntakeFlowHost update).

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kineticdx_app_v3/preassessment/domain/answer_value.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'package:kineticdx_app_v3/preassessment/domain/intake_schema.dart';

class IntakeDraftController extends ChangeNotifier {
  IntakeDraftController({
    required String clinicId,
    String? patientId,
  })  : _clinicId = clinicId,
        _patientId = patientId,
        _session = _newDraft(clinicId: clinicId, patientId: patientId);

  final String _clinicId;
  final String? _patientId;

  IntakeSession _session;

  /// ✅ Optional: start a specific flow regardless of region selection.
  /// Example: 'generalVisit'
  String? _flowIdOverride;
  String? get flowIdOverride => _flowIdOverride;

  /// Current draft intake session snapshot (local).
  IntakeSession get session => _session;

  /// Convenience: immutable answers map.
  Map<String, AnswerValue> get answers => Map.unmodifiable(_session.answers);

  // ---------------------------------------------------------------------------
  // Draft lifecycle
  // ---------------------------------------------------------------------------

  bool _isNonDraftSessionId(String? sessionId) {
    final sid = (sessionId ?? '').trim();
    return sid.isNotEmpty && sid.toLowerCase() != 'draft';
  }

  bool _isMeaningfulFlowOverride(String? flowId) {
    final f = (flowId ?? '').trim();
    if (f.isEmpty) return false;
    if (f.toLowerCase() == 'default') return false;
    return true;
  }

  /// Resets the draft back to a brand new local session.
  ///
  /// If [preserveServerSessionId] is true and the current sessionId looks like a
  /// real session id (i.e., not empty and not 'draft'), we keep it.
  ///
  /// This is useful for:
  /// - Link-based sessions (consumeIntakeInviteFn) where the server already created
  ///   intakeSessions/{sessionId} and client must submit back into SAME id.
  /// - Dev sessions (dev_*) where server submit auto-creates if missing, and we
  ///   still want to keep whatever id we have / receive.
  ///
  /// ✅ Flow override is preserved by default, because it represents the intent
  /// of the start path (e.g. clinician chose General Visit).
  void reset({
    bool preserveServerSessionId = false,
    bool preserveFlowOverride = true,
  }) {
    final previousSessionId = _session.sessionId;
    final previousFlowOverride = _flowIdOverride;

    _session = _newDraft(clinicId: _clinicId, patientId: _patientId);

    if (preserveServerSessionId && _isNonDraftSessionId(previousSessionId)) {
      _session = _copyWith(sessionId: previousSessionId.trim());
    }

    if (preserveFlowOverride && _isMeaningfulFlowOverride(previousFlowOverride)) {
      _flowIdOverride = previousFlowOverride?.trim();
    } else {
      _flowIdOverride = null;
    }

    notifyListeners();
  }

  /// Alias for readability.
  void startNewDraft({
    bool preserveServerSessionId = false,
    bool preserveFlowOverride = true,
  }) =>
      reset(
        preserveServerSessionId: preserveServerSessionId,
        preserveFlowOverride: preserveFlowOverride,
      );

  // ---------------------------------------------------------------------------
  // Flow override
  // ---------------------------------------------------------------------------

  /// ✅ Called by IntakeStartScreen when clinician begins a specific flow
  /// (e.g. generalVisit) from inside the app.
  void setFlowIdOverride(String flowId) {
    final f = flowId.trim();
    if (f.isEmpty) return;

    final current = (_flowIdOverride ?? '').trim();
    if (current == f) return;

    _flowIdOverride = f;
    notifyListeners();
  }

  void clearFlowIdOverride() {
    if (_flowIdOverride == null) return;
    _flowIdOverride = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Block setters (Consent / Patient / Region)
  // ---------------------------------------------------------------------------

  void setConsent(ConsentBlock consent) {
    _session = _copyWith(consent: consent);
    notifyListeners();
  }

  void setPatientDetails(PatientDetailsBlock details) {
    _session = _copyWith(patientDetails: details);
    notifyListeners();
  }

  void setRegionSelection(RegionSelectionBlock region) {
    _session = _copyWith(regionSelection: region);
    notifyListeners();
  }

  /// Set the sessionId (server-generated or dev/local).
  void setSessionId(String sessionId) {
    final sid = sessionId.trim();
    if (sid.isEmpty) return;

    final current = _session.sessionId.trim();
    if (current == sid) return;

    _session = _copyWith(sessionId: sid);
    notifyListeners();
  }

  /// ✅ ReviewScreen expects this exact method name.
  /// Semantics: "server-returned id should become the authoritative sessionId in the draft".
  void setServerSessionId(String intakeSessionId) {
    setSessionId(intakeSessionId);
  }

  // ---------------------------------------------------------------------------
  // Answers (questionId -> AnswerValue)
  // ---------------------------------------------------------------------------

  void setAnswer(String questionId, AnswerValue? value) {
    final next = Map<String, AnswerValue>.from(_session.answers);
    if (value == null) {
      next.remove(questionId);
    } else {
      next[questionId] = value;
    }
    _session = _copyWith(answers: next);
    notifyListeners();
  }

  AnswerValue? getAnswer(String questionId) => _session.answers[questionId];

  /// Clears answers belonging to a given flow prefix.
  /// Example: flowIdPrefix = 'ankle' will remove 'ankle.*' answers.
  void clearAnswersForFlow(String flowIdPrefix) {
    final next = Map<String, AnswerValue>.from(_session.answers);
    next.removeWhere((k, _) => k.startsWith('$flowIdPrefix.'));
    _session = _copyWith(answers: next);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Validation (based on FlowDefinition)
  // ---------------------------------------------------------------------------

  /// Returns map of questionId -> errorCode for the given flow.
  Map<String, String> validateFlow(FlowDefinition flow) {
    final errors = <String, String>{};
    for (final q in flow.questions) {
      final err = q.validate(_session.answers[q.questionId]);
      if (err != null) {
        errors[q.questionId] = err;
      }
    }
    return errors;
  }

  bool canContinueFlow(FlowDefinition flow) => validateFlow(flow).isEmpty;

  String? firstInvalidQuestionId(FlowDefinition flow) {
    final errors = validateFlow(flow);
    return errors.isEmpty ? null : errors.keys.first;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static IntakeSession _newDraft({
    required String clinicId,
    required String? patientId,
  }) {
    return IntakeSession(
      sessionId: 'draft', // local placeholder until created server-side
      schemaVersion: IntakeSchemaVersions.intakeSessionV1,
      clinicId: clinicId,
      patientId: patientId,
      status: IntakeStatus.draft,
      createdAt: Timestamp.now(),
      submittedAt: null,
      lockedAt: null,
      access: const IntakeAccessBlock(
        mode: IntakeAccessMode.token,
        ownerUid: null,
        tokenHash: null,
        expiresAt: null,
      ),
      consent: const ConsentBlock(
        policyBundleId: '',
        policyBundleVersion: 0,
        locale: 'en',
        termsAccepted: false,
        privacyAccepted: false,
        dataStorageAccepted: false,
        notEmergencyAck: false,
        noDiagnosisAck: false,
        consentToContact: false,
        acceptedAt: null,
      ),
      patientDetails: const PatientDetailsBlock(
        firstName: '',
        lastName: '',
        dateOfBirth: null,
        email: '',
        phone: '',
        isProxy: false,
        proxyName: null,
        proxyRelationship: null,
        confirmedAt: null,
      ),
      regionSelection: const RegionSelectionBlock(
        bodyArea: '',
        side: '',
        regionSetVersion: 1,
        selectedAt: null,
      ),
      answers: const <String, AnswerValue>{},
      triage: const IntakeTriageBlock(status: 'green', reasons: <String>[]),
      pdfSnapshotPath: null,
    );
  }

  IntakeSession _copyWith({
    String? sessionId,
    int? schemaVersion,
    String? clinicId,
    String? patientId,
    IntakeStatus? status,
    Timestamp? createdAt,
    Timestamp? submittedAt,
    Timestamp? lockedAt,
    IntakeAccessBlock? access,
    ConsentBlock? consent,
    PatientDetailsBlock? patientDetails,
    RegionSelectionBlock? regionSelection,
    Map<String, AnswerValue>? answers,
    IntakeTriageBlock? triage,
    String? pdfSnapshotPath,
  }) {
    return IntakeSession(
      sessionId: sessionId ?? _session.sessionId,
      schemaVersion: schemaVersion ?? _session.schemaVersion,
      clinicId: clinicId ?? _session.clinicId,
      patientId: patientId ?? _session.patientId,
      status: status ?? _session.status,
      createdAt: createdAt ?? _session.createdAt,
      submittedAt: submittedAt ?? _session.submittedAt,
      lockedAt: lockedAt ?? _session.lockedAt,
      access: access ?? _session.access,
      consent: consent ?? _session.consent,
      patientDetails: patientDetails ?? _session.patientDetails,
      regionSelection: regionSelection ?? _session.regionSelection,
      answers: answers ?? _session.answers,
      triage: triage ?? _session.triage,
      pdfSnapshotPath: pdfSnapshotPath ?? _session.pdfSnapshotPath,
    );
  }
}
