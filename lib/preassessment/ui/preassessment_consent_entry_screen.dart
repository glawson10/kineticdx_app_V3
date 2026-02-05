// lib/preassessment/screens/preassessment_consent_entry_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/intake_draft_controller.dart';
import '../domain/answer_value.dart';
import '../domain/intake_schema.dart';
import '../screens/intake_flow_host.dart';

class PreassessmentConsentEntryScreen extends StatefulWidget {
  const PreassessmentConsentEntryScreen({
    super.key,
    required this.fallbackClinicId,
  });

  final String? fallbackClinicId;

  @override
  State<PreassessmentConsentEntryScreen> createState() =>
      _PreassessmentConsentEntryScreenState();
}

class _PreassessmentConsentEntryScreenState
    extends State<PreassessmentConsentEntryScreen> {
  bool _booted = false;

  late String _clinicId;
  String _bookingRequestId = '';
  Map<String, dynamic> _prefill = const <String, dynamic>{};

  Map<String, dynamic> _args(BuildContext context) {
    final a = ModalRoute.of(context)?.settings.arguments;
    return (a is Map) ? Map<String, dynamic>.from(a) : <String, dynamic>{};
  }

  String _resolveClinicId(BuildContext context) {
    final args = _args(context);

    final fromArgs = (args['clinicId'] ?? '').toString().trim();
    if (fromArgs.isNotEmpty) return fromArgs;

    final fb = (widget.fallbackClinicId ?? '').trim();
    if (fb.isNotEmpty) return fb;

    final qp = Uri.base.queryParameters;
    final fromUrl = (qp['clinicId'] ?? qp['clinic'] ?? '').trim();
    if (fromUrl.isNotEmpty) return fromUrl;

    throw StateError('Missing clinicId for preassessment.');
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
      IntakeDraftController draft, Map<String, dynamic> prefill) {
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
            (dob != null) ? Timestamp.fromDate(dob) : existing.dateOfBirth,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;

    _clinicId = _resolveClinicId(context);

    final args = _args(context);
    _bookingRequestId = (args['bookingRequestId'] ?? '').toString().trim();

    final raw = args['prefillPatient'];
    _prefill =
        (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Future<String?> _resolveIntakeSessionIdIfNeeded() async {
    if (_bookingRequestId.isEmpty) return null;

    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
    final callable =
        functions.httpsCallable('resolveIntakeSessionFromBookingRequestFn');

    final res = await callable.call({
      'clinicId': _clinicId,
      'bookingRequestId': _bookingRequestId,
    });

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};

    final intakeSessionId = (data['intakeSessionId'] ?? '').toString().trim();
    return intakeSessionId.isEmpty ? null : intakeSessionId;
  }

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<IntakeDraftController>(
      create: (_) {
        final draft = IntakeDraftController(clinicId: _clinicId);
        if (_prefill.isNotEmpty) {
          _applyPrefill(draft, _prefill);
        }

        // ✅ If coming from in-app public booking, resolve the real intakeSessionId
        // and adopt it so Review won't show "draft".
        if (_bookingRequestId.isNotEmpty) {
          () async {
            try {
              final sid = await _resolveIntakeSessionIdIfNeeded();
              if (sid != null && sid.isNotEmpty) {
                draft.setServerSessionId(sid);
              }
            } catch (e) {
              // Don't crash the flow; Consent can still show.
              // But Review will stay draft if this fails.
              debugPrint(
                  '[PreassessmentConsentEntryScreen] resolve session failed: $e');
            }
          }();
        }

        return draft;
      },
      child: const IntakeFlowHost(),
    );
  }
}
