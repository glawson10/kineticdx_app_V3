// lib/preassessment/domain/intake_schema.dart
//
// Phase 3 Intake (Pre-assessment) schema definitions.
// - Clinic-scoped: clinics/{clinicId}/intakeSessions/{sessionId}
// - Patient-reported only (no diagnoses / clinical reasoning)
// - Immutable after submission
//
// NOTE: Firestore Timestamp type is used directly in models.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'answer_value.dart';

/// IntakeSession schema version.
/// Keep in sync with backend validation (Cloud Functions).
class IntakeSchemaVersions {
  static const int intakeSessionV1 = 1;
}

/// Lifecycle for an intake session.
enum IntakeStatus {
  draft,
  submitted,
  locked;

  static IntakeStatus fromString(String v) {
    switch (v) {
      case 'draft':
        return IntakeStatus.draft;
      case 'submitted':
        return IntakeStatus.submitted;
      case 'locked':
        return IntakeStatus.locked;
      default:
        throw StateError('Unknown IntakeStatus: $v');
    }
  }

  String toWire() {
    switch (this) {
      case IntakeStatus.draft:
        return 'draft';
      case IntakeStatus.submitted:
        return 'submitted';
      case IntakeStatus.locked:
        return 'locked';
    }
  }
}

/// Access mode for draft ownership.
/// IMPORTANT: Choose one strategy and enforce in rules/functions.
/// - token: public/patient entry via one-time link token (recommended for public intake)
/// - authUid: patient is authenticated, ownerUid is their Firebase Auth UID
enum IntakeAccessMode {
  token,
  authUid;

  static IntakeAccessMode fromString(String v) {
    switch (v) {
      case 'token':
        return IntakeAccessMode.token;
      case 'authUid':
        return IntakeAccessMode.authUid;
      default:
        throw StateError('Unknown IntakeAccessMode: $v');
    }
  }

  String toWire() {
    switch (this) {
      case IntakeAccessMode.token:
        return 'token';
      case IntakeAccessMode.authUid:
        return 'authUid';
    }
  }
}

/// Consent / policy understanding block.
/// Store explicit booleans and policy version pinning.
class ConsentBlock {
  final String policyBundleId;
  final int policyBundleVersion;
  final String locale;

  final bool termsAccepted;
  final bool privacyAccepted;
  final bool dataStorageAccepted;
  final bool notEmergencyAck;
  final bool noDiagnosisAck;
  final bool consentToContact;

  /// Set only on submit.
  final Timestamp? acceptedAt;

  const ConsentBlock({
    required this.policyBundleId,
    required this.policyBundleVersion,
    required this.locale,
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.dataStorageAccepted,
    required this.notEmergencyAck,
    required this.noDiagnosisAck,
    required this.consentToContact,
    required this.acceptedAt,
  });

  Map<String, dynamic> toMap() => {
        'policyBundleId': policyBundleId,
        'policyBundleVersion': policyBundleVersion,
        'locale': locale,
        'termsAccepted': termsAccepted,
        'privacyAccepted': privacyAccepted,
        'dataStorageAccepted': dataStorageAccepted,
        'notEmergencyAck': notEmergencyAck,
        'noDiagnosisAck': noDiagnosisAck,
        'consentToContact': consentToContact,
        'acceptedAt': acceptedAt,
      };

  static ConsentBlock fromMap(Map<String, dynamic> m) {
    return ConsentBlock(
      policyBundleId: (m['policyBundleId'] as String?) ?? '',
      policyBundleVersion: (m['policyBundleVersion'] as int?) ?? 0,
      locale: (m['locale'] as String?) ?? 'en',
      termsAccepted: (m['termsAccepted'] as bool?) ?? false,
      privacyAccepted: (m['privacyAccepted'] as bool?) ?? false,
      dataStorageAccepted: (m['dataStorageAccepted'] as bool?) ?? false,
      notEmergencyAck: (m['notEmergencyAck'] as bool?) ?? false,
      noDiagnosisAck: (m['noDiagnosisAck'] as bool?) ?? false,
      consentToContact: (m['consentToContact'] as bool?) ?? false,
      acceptedAt: m['acceptedAt'] is Timestamp ? (m['acceptedAt'] as Timestamp) : null,
    );
  }

  /// Convenience: minimal validation for "ready to submit".
  bool get isComplete =>
      termsAccepted &&
      privacyAccepted &&
      dataStorageAccepted &&
      notEmergencyAck &&
      noDiagnosisAck;
}

/// Patient details block (patient-reported).
/// This is NOT the clinic patient record. It is Phase-3 snapshot data.
class PatientDetailsBlock {
  final String firstName;
  final String lastName;
  final Timestamp? dateOfBirth;

  final String email;
  final String phone;

  /// Optional proxy fields (if completing on behalf of someone else)
  final bool isProxy;
  final String? proxyName;
  final String? proxyRelationship;

  /// Set only on submit.
  final Timestamp? confirmedAt;

  const PatientDetailsBlock({
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.email,
    required this.phone,
    required this.isProxy,
    required this.proxyName,
    required this.proxyRelationship,
    required this.confirmedAt,
  });

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'dateOfBirth': dateOfBirth,
        'email': email,
        'phone': phone,
        'isProxy': isProxy,
        'proxyName': proxyName,
        'proxyRelationship': proxyRelationship,
        'confirmedAt': confirmedAt,
      };

  static PatientDetailsBlock fromMap(Map<String, dynamic> m) {
    return PatientDetailsBlock(
      firstName: (m['firstName'] as String?) ?? '',
      lastName: (m['lastName'] as String?) ?? '',
      dateOfBirth: m['dateOfBirth'] is Timestamp ? (m['dateOfBirth'] as Timestamp) : null,
      email: (m['email'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      isProxy: (m['isProxy'] as bool?) ?? false,
      proxyName: m['proxyName'] as String?,
      proxyRelationship: m['proxyRelationship'] as String?,
      confirmedAt: m['confirmedAt'] is Timestamp ? (m['confirmedAt'] as Timestamp) : null,
    );
  }
}

/// Region selection block used to route into a flow.
/// Keep routing stable via regionSetVersion.
class RegionSelectionBlock {
  final String bodyArea; // optionId like "region.ankle"
  final String side; // optionId like "side.left|side.right|side.bilateral|side.unknown"
  final int regionSetVersion;

  /// Set when selected.
  final Timestamp? selectedAt;

  const RegionSelectionBlock({
    required this.bodyArea,
    required this.side,
    required this.regionSetVersion,
    required this.selectedAt,
  });

  Map<String, dynamic> toMap() => {
        'bodyArea': bodyArea,
        'side': side,
        'regionSetVersion': regionSetVersion,
        'selectedAt': selectedAt,
      };

  static RegionSelectionBlock fromMap(Map<String, dynamic> m) {
    return RegionSelectionBlock(
      bodyArea: (m['bodyArea'] as String?) ?? '',
      side: (m['side'] as String?) ?? '',
      regionSetVersion: (m['regionSetVersion'] as int?) ?? 1,
      selectedAt: m['selectedAt'] is Timestamp ? (m['selectedAt'] as Timestamp) : null,
    );
  }
}

/// Triage outcome (Phase-3-safe).
/// Reasons are codes (e.g. "redflag.hotRedFeverish") not diagnoses.
class IntakeTriageBlock {
  final String status; // "green" | "amber" | "red"
  final List<String> reasons;

  const IntakeTriageBlock({
    required this.status,
    required this.reasons,
  });

  Map<String, dynamic> toMap() => {
        'status': status,
        'reasons': reasons,
      };

  static IntakeTriageBlock fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      return const IntakeTriageBlock(status: 'green', reasons: <String>[]);
    }
    return IntakeTriageBlock(
      status: (m['status'] as String?) ?? 'green',
      reasons: (m['reasons'] as List?)?.whereType<String>().toList() ?? <String>[],
    );
  }
}

/// Draft ownership / access boundary.
class IntakeAccessBlock {
  final IntakeAccessMode mode;
  final String? ownerUid;
  final String? tokenHash;
  final Timestamp? expiresAt;

  const IntakeAccessBlock({
    required this.mode,
    required this.ownerUid,
    required this.tokenHash,
    required this.expiresAt,
  });

  Map<String, dynamic> toMap() => {
        'mode': mode.toWire(),
        'ownerUid': ownerUid,
        'tokenHash': tokenHash,
        'expiresAt': expiresAt,
      };

  static IntakeAccessBlock fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      // Default to token mode with null tokenHash for older drafts.
      return const IntakeAccessBlock(
        mode: IntakeAccessMode.token,
        ownerUid: null,
        tokenHash: null,
        expiresAt: null,
      );
    }
    return IntakeAccessBlock(
      mode: IntakeAccessMode.fromString((m['mode'] as String?) ?? 'token'),
      ownerUid: m['ownerUid'] as String?,
      tokenHash: m['tokenHash'] as String?,
      expiresAt: m['expiresAt'] is Timestamp ? (m['expiresAt'] as Timestamp) : null,
    );
  }
}

/// Phase 3 intake session (canonical).
class IntakeSession {
  final String sessionId; // doc id (not stored in doc usually)
  final int schemaVersion;

  final String clinicId;
  final String? patientId;

  final IntakeStatus status;

  final Timestamp createdAt;
  final Timestamp? submittedAt;
  final Timestamp? lockedAt;

  final IntakeAccessBlock access;
  final ConsentBlock consent;
  final PatientDetailsBlock patientDetails;
  final RegionSelectionBlock regionSelection;

  /// Canonical typed answers (questionId -> AnswerValue).
  final Map<String, AnswerValue> answers;

  final IntakeTriageBlock triage;

  final String? pdfSnapshotPath;

  const IntakeSession({
    required this.sessionId,
    required this.schemaVersion,
    required this.clinicId,
    required this.patientId,
    required this.status,
    required this.createdAt,
    required this.submittedAt,
    required this.lockedAt,
    required this.access,
    required this.consent,
    required this.patientDetails,
    required this.regionSelection,
    required this.answers,
    required this.triage,
    required this.pdfSnapshotPath,
  });

  bool get isMutable => status == IntakeStatus.draft;

  Map<String, dynamic> toDoc() => {
        'schemaVersion': schemaVersion,
        'clinicId': clinicId,
        'patientId': patientId,
        'status': status.toWire(),
        'createdAt': createdAt,
        'submittedAt': submittedAt,
        'lockedAt': lockedAt,
        'access': access.toMap(),
        'consent': consent.toMap(),
        'patientDetails': patientDetails.toMap(),
        'regionSelection': regionSelection.toMap(),
        'answers': answers.map((k, v) => MapEntry(k, v.toMap())),
        'triage': triage.toMap(),
        'pdfSnapshotPath': pdfSnapshotPath,
      };

  static IntakeSession fromDoc({
    required String sessionId,
    required Map<String, dynamic> data,
  }) {
    final answersRaw = (data['answers'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final answers = <String, AnswerValue>{};
    for (final entry in answersRaw.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic>) {
        answers[entry.key] = AnswerValue.fromMap(v);
      } else if (v is Map) {
        answers[entry.key] = AnswerValue.fromMap(v.cast<String, dynamic>());
      }
    }

    return IntakeSession(
      sessionId: sessionId,
      schemaVersion: (data['schemaVersion'] as int?) ?? IntakeSchemaVersions.intakeSessionV1,
      clinicId: (data['clinicId'] as String?) ?? '',
      patientId: data['patientId'] as String?,
      status: IntakeStatus.fromString((data['status'] as String?) ?? 'draft'),
      createdAt: (data['createdAt'] is Timestamp) ? (data['createdAt'] as Timestamp) : Timestamp.now(),
      submittedAt: data['submittedAt'] is Timestamp ? (data['submittedAt'] as Timestamp) : null,
      lockedAt: data['lockedAt'] is Timestamp ? (data['lockedAt'] as Timestamp) : null,
      access: IntakeAccessBlock.fromMap(data['access'] is Map ? (data['access'] as Map).cast<String, dynamic>() : null),
      consent: ConsentBlock.fromMap(data['consent'] is Map ? (data['consent'] as Map).cast<String, dynamic>() : <String, dynamic>{}),
      patientDetails: PatientDetailsBlock.fromMap(
          data['patientDetails'] is Map ? (data['patientDetails'] as Map).cast<String, dynamic>() : <String, dynamic>{}),
      regionSelection: RegionSelectionBlock.fromMap(
          data['regionSelection'] is Map ? (data['regionSelection'] as Map).cast<String, dynamic>() : <String, dynamic>{}),
      answers: answers,
      triage: IntakeTriageBlock.fromMap(data['triage'] is Map ? (data['triage'] as Map).cast<String, dynamic>() : null),
      pdfSnapshotPath: data['pdfSnapshotPath'] as String?,
    );
  }

  /// Convenience for reading an answer safely.
  AnswerValue? answer(String questionId) => answers[questionId];
}
