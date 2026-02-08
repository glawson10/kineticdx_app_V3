import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../models/clinical_tests.dart';
import '../data/initial_assessment_note.dart';
import '../data/soap_notes_repo.dart';
import '../data/notes_permissions.dart';
import 'widgets/special_tests_picker.dart';

/// Minimal Initial Assessment editor wired to clinic-scoped SOAP notes.
///
/// Path: clinics/{clinicId}/patients/{patientId}/soapNotes/{noteId}
class InitialAssessmentEditorScreen extends StatefulWidget {
  final String clinicId;
  final String patientId;
  final String? noteId;

  const InitialAssessmentEditorScreen({
    super.key,
    required this.clinicId,
    required this.patientId,
    this.noteId,
  });

  @override
  State<InitialAssessmentEditorScreen> createState() =>
      _InitialAssessmentEditorScreenState();
}

class _InitialAssessmentEditorScreenState
    extends State<InitialAssessmentEditorScreen> {
  final SoapNotesRepository _repo = SoapNotesRepository();

  InitialAssessmentNote? _note;
  bool _saving = false;
  bool _creating = false;

  final TextEditingController _presentingComplaint = TextEditingController();
  final TextEditingController _primaryDiagnosis = TextEditingController();
  final TextEditingController _planSummary = TextEditingController();

  BodyRegion _bodyRegion = BodyRegion.cervical;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _presentingComplaint.dispose();
    _primaryDiagnosis.dispose();
    _planSummary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final perms = clinicCtx.session.permissions;
    final canView = canViewClinicalNotes(perms);
    final canEdit = canEditClinicalNotes(perms);
    if (!canView) {
      return const Scaffold(
        body: Center(child: Text('No access to clinical notes.')),
      );
    }

    final uid = clinicCtx.uidOrNull?.trim() ?? '';
    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Missing user identity.')),
      );
    }

    if (widget.noteId == null) {
      return FutureBuilder<InitialAssessmentNote>(
        future: _createIfNeeded(uid),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            final error = snap.error;
            debugPrint('ERROR in FutureBuilder (create note):');
            debugPrint('Error: $error');
            debugPrint('ClinicId: ${widget.clinicId}, PatientId: ${widget.patientId}');
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Failed to create note:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$error', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  const Text('Check the browser console (F12) for more details.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }
          return _buildScaffold(
            context,
            snap.data!,
            canEdit: canEdit,
            uid: uid,
          );
        },
      );
    }

    return StreamBuilder<InitialAssessmentNote>(
      stream: _repo.watchInitialAssessment(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        noteId: widget.noteId!,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildScaffold(
          context,
          snap.data!,
          canEdit: canEdit,
          uid: uid,
        );
      },
    );
  }

  Future<InitialAssessmentNote> _createIfNeeded(String uid) async {
    if (_creating) {
      final existing = _note;
      if (existing != null) return existing;
    }
    _creating = true;
    try {
      debugPrint('Creating InitialAssessmentNote for clinic: ${widget.clinicId}, patient: ${widget.patientId}');
      final created = await _repo.createInitialAssessment(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        createdByUid: uid,
        bodyRegion: _bodyRegion,
      );
      _note = created;
      debugPrint('Successfully created note: ${created.id}');
      return created;
    } catch (e, stack) {
      debugPrint('ERROR in _createIfNeeded:');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Scaffold _buildScaffold(
    BuildContext context,
    InitialAssessmentNote note, {
    required bool canEdit,
    required String uid,
  }) {
    final readOnly = !canEdit || note.status == 'final';
    _note ??= note;
    _bodyRegion = note.bodyRegion;
    _presentingComplaint.text = note.presentingComplaint;
    _primaryDiagnosis.text = note.primaryDiagnosis;
    _planSummary.text = note.planSummary;

    final missing = _missingRequired(note);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Initial Assessment'),
        actions: [
          IconButton(
            tooltip: 'Finalize',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: (readOnly || note.status == 'final' || missing.isNotEmpty)
                ? null
                : () => _finalize(note, uid),
          ),
          IconButton(
            tooltip: 'Save',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: readOnly ? null : () => _save(note, uid),
          ),
        ],
      ),
      body: Column(
        children: [
          if (missing.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Missing required: ${missing.join(", ")}',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(readOnly),
                const SizedBox(height: 16),
                _buildSubjectiveCard(readOnly),
                const SizedBox(height: 16),
                _buildSpecialTestsCard(note, readOnly),
                const SizedBox(height: 16),
                _buildAssessmentCard(readOnly),
                const SizedBox(height: 16),
                _buildPlanCard(readOnly),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool readOnly) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Text('Region:'),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<BodyRegion>(
                value: _bodyRegion,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: BodyRegion.values
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(_regionLabel(r)),
                      ),
                    )
                    .toList(),
                onChanged: readOnly
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _bodyRegion = v;
                          if (_note != null) {
                            _note = InitialAssessmentNote(
                              id: _note!.id,
                              clinicId: _note!.clinicId,
                              patientId: _note!.patientId,
                              noteType: _note!.noteType,
                              bodyRegion: v,
                              status: _note!.status,
                              createdAt: _note!.createdAt,
                              updatedAt: _note!.updatedAt,
                              finalizedAt: _note!.finalizedAt,
                              createdByUid: _note!.createdByUid,
                              updatedByUid: _note!.updatedByUid,
                              presentingComplaint: _note!.presentingComplaint,
                              historyOfPresentingComplaint:
                                  _note!.historyOfPresentingComplaint,
                              painIntensityNow: _note!.painIntensityNow,
                              painIntensityBest: _note!.painIntensityBest,
                              painIntensityWorst: _note!.painIntensityWorst,
                              painIrritability: _note!.painIrritability,
                              painNature: _note!.painNature,
                              aggravatingFactors: _note!.aggravatingFactors,
                              easingFactors: _note!.easingFactors,
                              pattern24h: _note!.pattern24h,
                              redFlags: _note!.redFlags,
                              yellowFlags: _note!.yellowFlags,
                              pastMedicalHistory: _note!.pastMedicalHistory,
                              meds: _note!.meds,
                              imaging: _note!.imaging,
                              goals: _note!.goals,
                              functionalLimitations:
                                  _note!.functionalLimitations,
                              observation: _note!.observation,
                              neuroScreenSummary: _note!.neuroScreenSummary,
                              functionalTests: _note!.functionalTests,
                              palpation: _note!.palpation,
                              rangeOfMotion: _note!.rangeOfMotion,
                              strength: _note!.strength,
                              neuroMyotomesSummary:
                                  _note!.neuroMyotomesSummary,
                              neuroDermatomesSummary:
                                  _note!.neuroDermatomesSummary,
                              neuroReflexesSummary:
                                  _note!.neuroReflexesSummary,
                              regionSpecificObjective:
                                  _note!.regionSpecificObjective,
                              specialTests: _note!.specialTests,
                              primaryDiagnosis: _note!.primaryDiagnosis,
                              differentialDiagnoses:
                                  _note!.differentialDiagnoses,
                              contributingFactors: _note!.contributingFactors,
                              clinicalReasoning: _note!.clinicalReasoning,
                              severity: _note!.severity,
                              irritability: _note!.irritability,
                              stage: _note!.stage,
                              outcomeMeasures: _note!.outcomeMeasures,
                              planSummary: _note!.planSummary,
                              educationAdvice: _note!.educationAdvice,
                              exercises: _note!.exercises,
                              manualTherapy: _note!.manualTherapy,
                              followUp: _note!.followUp,
                              referrals: _note!.referrals,
                              consentConfirmed: _note!.consentConfirmed,
                              homeAdvice: _note!.homeAdvice,
                            );
                          }
                        });
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectiveCard(bool readOnly) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subjective',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _presentingComplaint,
              readOnly: readOnly,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Presenting complaint *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialTestsCard(
    InitialAssessmentNote note,
    bool readOnly,
  ) {
    return SizedBox(
      height: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Special tests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SpecialTestsPicker(
                  clinicId: widget.clinicId,
                  bodyRegion: _bodyRegion,
                  value: note.specialTests,
                  readOnly: readOnly,
                  onChanged: readOnly
                      ? (_) {}
                      : (updated) {
                          // Defer setState to next frame to avoid white flash when selecting a test
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _note = InitialAssessmentNote(
                                id: note.id,
                                clinicId: note.clinicId,
                                patientId: note.patientId,
                                noteType: note.noteType,
                                bodyRegion: _bodyRegion,
                                status: note.status,
                                createdAt: note.createdAt,
                                updatedAt: note.updatedAt,
                                finalizedAt: note.finalizedAt,
                                createdByUid: note.createdByUid,
                                updatedByUid: note.updatedByUid,
                                presentingComplaint: _presentingComplaint.text,
                                historyOfPresentingComplaint:
                                    note.historyOfPresentingComplaint,
                                painIntensityNow: note.painIntensityNow,
                                painIntensityBest: note.painIntensityBest,
                                painIntensityWorst: note.painIntensityWorst,
                                painIrritability: note.painIrritability,
                                painNature: note.painNature,
                                aggravatingFactors: note.aggravatingFactors,
                                easingFactors: note.easingFactors,
                                pattern24h: note.pattern24h,
                                redFlags: note.redFlags,
                                yellowFlags: note.yellowFlags,
                                pastMedicalHistory: note.pastMedicalHistory,
                                meds: note.meds,
                                imaging: note.imaging,
                                goals: note.goals,
                                functionalLimitations:
                                    note.functionalLimitations,
                                observation: note.observation,
                                neuroScreenSummary: note.neuroScreenSummary,
                                functionalTests: note.functionalTests,
                                palpation: note.palpation,
                                rangeOfMotion: note.rangeOfMotion,
                                strength: note.strength,
                                neuroMyotomesSummary:
                                    note.neuroMyotomesSummary,
                                neuroDermatomesSummary:
                                    note.neuroDermatomesSummary,
                                neuroReflexesSummary:
                                    note.neuroReflexesSummary,
                                regionSpecificObjective:
                                    note.regionSpecificObjective,
                                specialTests: updated,
                                primaryDiagnosis: _primaryDiagnosis.text,
                                differentialDiagnoses:
                                    note.differentialDiagnoses,
                                contributingFactors: note.contributingFactors,
                                clinicalReasoning: note.clinicalReasoning,
                                severity: note.severity,
                                irritability: note.irritability,
                                stage: note.stage,
                                outcomeMeasures: note.outcomeMeasures,
                                planSummary: _planSummary.text,
                                educationAdvice: note.educationAdvice,
                                exercises: note.exercises,
                                manualTherapy: note.manualTherapy,
                                followUp: note.followUp,
                                referrals: note.referrals,
                                consentConfirmed: note.consentConfirmed,
                                homeAdvice: note.homeAdvice,
                              );
                            });
                          });
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssessmentCard(bool readOnly) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assessment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _primaryDiagnosis,
              readOnly: readOnly,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Primary diagnosis *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(bool readOnly) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _planSummary,
              readOnly: readOnly,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Plan summary *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _missingRequired(InitialAssessmentNote note) {
    final missing = <String>[];
    if (_presentingComplaint.text.trim().isEmpty) {
      missing.add('presenting complaint');
    }
    if (_primaryDiagnosis.text.trim().isEmpty) {
      missing.add('primary diagnosis');
    }
    if (_planSummary.text.trim().isEmpty) {
      missing.add('plan summary');
    }
    return missing;
  }

  Future<void> _save(InitialAssessmentNote note, String uid) async {
    setState(() => _saving = true);
    try {
      final updated = InitialAssessmentNote(
        id: note.id,
        clinicId: note.clinicId,
        patientId: note.patientId,
        noteType: note.noteType,
        bodyRegion: _bodyRegion,
        status: note.status,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        finalizedAt: note.finalizedAt,
        createdByUid: note.createdByUid,
        updatedByUid: uid,
        presentingComplaint: _presentingComplaint.text.trim(),
        historyOfPresentingComplaint: note.historyOfPresentingComplaint,
        painIntensityNow: note.painIntensityNow,
        painIntensityBest: note.painIntensityBest,
        painIntensityWorst: note.painIntensityWorst,
        painIrritability: note.painIrritability,
        painNature: note.painNature,
        aggravatingFactors: note.aggravatingFactors,
        easingFactors: note.easingFactors,
        pattern24h: note.pattern24h,
        redFlags: note.redFlags,
        yellowFlags: note.yellowFlags,
        pastMedicalHistory: note.pastMedicalHistory,
        meds: note.meds,
        imaging: note.imaging,
        goals: note.goals,
        functionalLimitations: note.functionalLimitations,
        observation: note.observation,
        neuroScreenSummary: note.neuroScreenSummary,
        functionalTests: note.functionalTests,
        palpation: note.palpation,
        rangeOfMotion: note.rangeOfMotion,
        strength: note.strength,
        neuroMyotomesSummary: note.neuroMyotomesSummary,
        neuroDermatomesSummary: note.neuroDermatomesSummary,
        neuroReflexesSummary: note.neuroReflexesSummary,
        regionSpecificObjective: note.regionSpecificObjective,
        specialTests: note.specialTests,
        primaryDiagnosis: _primaryDiagnosis.text.trim(),
        differentialDiagnoses: note.differentialDiagnoses,
        contributingFactors: note.contributingFactors,
        clinicalReasoning: note.clinicalReasoning,
        severity: note.severity,
        irritability: note.irritability,
        stage: note.stage,
        outcomeMeasures: note.outcomeMeasures,
        planSummary: _planSummary.text.trim(),
        educationAdvice: note.educationAdvice,
        exercises: note.exercises,
        manualTherapy: note.manualTherapy,
        followUp: note.followUp,
        referrals: note.referrals,
        consentConfirmed: note.consentConfirmed,
        homeAdvice: note.homeAdvice,
      );
      await _repo.updateInitialAssessment(
        note: updated,
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        updatedByUid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved initial assessment.')),
      );
    } catch (e, stack) {
      debugPrint('ERROR in _save:');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      debugPrint('ClinicId: ${widget.clinicId}, PatientId: ${widget.patientId}, NoteId: ${note.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalize(InitialAssessmentNote note, String uid) async {
    final missing = _missingRequired(note);
    if (missing.isNotEmpty) return;

    try {
      await _save(note, uid);
      await _repo.finalizeInitialAssessment(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        noteId: note.id,
        updatedByUid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note finalized.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finalize failed: $e')),
      );
    }
  }

  String _regionLabel(BodyRegion region) {
    switch (region) {
      case BodyRegion.cervical:
        return 'Cervical';
      case BodyRegion.thoracic:
        return 'Thoracic';
      case BodyRegion.lumbar:
        return 'Lumbar';
      case BodyRegion.shoulder:
        return 'Shoulder';
      case BodyRegion.elbow:
        return 'Elbow';
      case BodyRegion.wristHand:
        return 'Wrist/Hand';
      case BodyRegion.hip:
        return 'Hip';
      case BodyRegion.knee:
        return 'Knee';
      case BodyRegion.ankleFoot:
        return 'Ankle/Foot';
      case BodyRegion.other:
        return 'Other';
    }
  }
}

