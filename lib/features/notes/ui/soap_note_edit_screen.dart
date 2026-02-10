import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../models/clinical_tests.dart';
import '../../../models/soap_note.dart';
import '../../../models/region_objective_templates.dart';
import '../data/soap_notes_repo.dart';
import '../data/notes_permissions.dart';
import 'clinical_test_selector.dart';
import 'region_objective_editor.dart';

/// Holds interactive edit state so updates notify only listeners (tab content),
/// not the whole screen — avoids white flash on every selection.
class NoteEditState extends ChangeNotifier {
  double painNow = 0;
  double painBest = 0;
  double painWorst = 10;
  String irritability = 'moderate';

  Map<String, bool> redFlags = {
    'Unexplained weight loss': false,
    'Night pain / sweats': false,
    'Recent trauma': false,
    'History of cancer': false,
    'Neurological changes': false,
    'Bladder / bowel changes': false,
  };
  final Map<String, bool> otherRedFlags = {};

  List<RegionObjective> regionObjectives = [];
  final Set<BodyRegion> selectedObjectiveRegions = {};

  void setPainNow(double v) {
    if (painNow == v) return;
    painNow = v;
    notifyListeners();
  }

  void setPainBest(double v) {
    if (painBest == v) return;
    painBest = v;
    notifyListeners();
  }

  void setPainWorst(double v) {
    if (painWorst == v) return;
    painWorst = v;
    notifyListeners();
  }

  void setIrritability(String v) {
    if (irritability == v) return;
    irritability = v;
    notifyListeners();
  }

  void setRedFlag(String key, bool value) {
    if (redFlags[key] == value) return;
    redFlags[key] = value;
    notifyListeners();
  }

  void setOtherRedFlag(String key, bool value) {
    if (otherRedFlags[key] == value) return;
    otherRedFlags[key] = value;
    notifyListeners();
  }

  void removeOtherRedFlag(String key) {
    if (otherRedFlags.remove(key) != null) notifyListeners();
  }

  void addOtherRedFlag(String key, {bool checked = false}) {
    otherRedFlags[key] = checked;
    notifyListeners();
  }

  void addRegion(BodyRegion region, RegionObjectiveTemplate t) {
    if (regionObjectives.any((r) => r.region == region)) return;
    regionObjectives.add(t.createEmptyRegionObjective(region));
    selectedObjectiveRegions.add(region);
    notifyListeners();
  }

  void removeSelectedRegion(BodyRegion region) {
    selectedObjectiveRegions.remove(region);
    notifyListeners();
  }

  void updateRegionObjective(RegionObjective updated) {
    final idx = regionObjectives.indexWhere((r) => r.region == updated.region);
    if (idx >= 0) {
      regionObjectives[idx] = updated;
      notifyListeners();
    }
  }
}

/// Main SOAP note editor using the SoapNote model.
/// Clinic-scoped under clinics/{clinicId}/patients/{patientId}/soapNotes/{noteId}
class SoapNoteEditScreen extends StatefulWidget {
  final String clinicId;
  final String patientId;
  final String? noteId;
  final BodyRegion? initialRegion;

  const SoapNoteEditScreen({
    super.key,
    required this.clinicId,
    required this.patientId,
    this.noteId,
    this.initialRegion,
  });

  @override
  State<SoapNoteEditScreen> createState() => _SoapNoteEditScreenState();
}

class _SoapNoteEditScreenState extends State<SoapNoteEditScreen> with TickerProviderStateMixin {
  final SoapNotesRepository _repo = SoapNotesRepository();
  final _formKey = GlobalKey<FormState>();

  SoapNote? _note;
  bool _saving = false;
  bool _creating = false;

  late BodyRegion _bodyRegion;

  // Subjective controllers
  final _presentingComplaintCtrl = TextEditingController();
  final _onsetCtrl = TextEditingController();
  final _aggsCtrl = TextEditingController();
  final _easesCtrl = TextEditingController();
  final _pattern24hCtrl = TextEditingController();
  final _pmhCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  final _socialCtrl = TextEditingController();
  final _goal1Ctrl = TextEditingController();
  final _goal2Ctrl = TextEditingController();
  final _goal3Ctrl = TextEditingController();

  /// Interactive state: updates here notify only tab listeners (no full-screen rebuild).
  late final NoteEditState _editState = NoteEditState();
  final TextEditingController _otherRedFlagCtrl = TextEditingController();

  // Objective controllers
  final _globalObjectiveCtrl = TextEditingController();

  // Assessment controllers
  final _diagnosisCtrl = TextEditingController();
  final _assessmentSummaryCtrl = TextEditingController();
  final _contributingFactorsCtrl = TextEditingController();
  final _keyImpairmentsCtrl = TextEditingController();
  final _differentialDiagnosesCtrl = TextEditingController();

  // Plan controllers
  final _treatmentTodayCtrl = TextEditingController();
  final _homeExerciseCtrl = TextEditingController();
  final _educationCtrl = TextEditingController();
  final _followUpCtrl = TextEditingController();
  final _planShortTermCtrl = TextEditingController();
  final _planMediumTermCtrl = TextEditingController();
  final _contingencyPlanCtrl = TextEditingController();

  List<SelectedClinicalTest> _selectedTests = [];

  /// Tab controller that persists across rebuilds to prevent tab reset
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _bodyRegion = widget.initialRegion ?? BodyRegion.lumbar;
    _tabController = TabController(length: 4, vsync: this);
    // New note: prime objective with one region so user sees template immediately.
    if (widget.noteId == null) {
      final t = regionObjectiveTemplates[_bodyRegion];
      if (t != null) {
        _editState.regionObjectives = [t.createEmptyRegionObjective(_bodyRegion)];
        _editState.selectedObjectiveRegions.add(_bodyRegion);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _presentingComplaintCtrl.dispose();
    _onsetCtrl.dispose();
    _aggsCtrl.dispose();
    _easesCtrl.dispose();
    _pattern24hCtrl.dispose();
    _pmhCtrl.dispose();
    _medicationsCtrl.dispose();
    _socialCtrl.dispose();
    _goal1Ctrl.dispose();
    _goal2Ctrl.dispose();
    _goal3Ctrl.dispose();
    _globalObjectiveCtrl.dispose();
    _diagnosisCtrl.dispose();
    _assessmentSummaryCtrl.dispose();
    _contributingFactorsCtrl.dispose();
    _keyImpairmentsCtrl.dispose();
    _differentialDiagnosesCtrl.dispose();
    _treatmentTodayCtrl.dispose();
    _homeExerciseCtrl.dispose();
    _educationCtrl.dispose();
    _followUpCtrl.dispose();
    _planShortTermCtrl.dispose();
    _planMediumTermCtrl.dispose();
    _contingencyPlanCtrl.dispose();
    _otherRedFlagCtrl.dispose();
    super.dispose();
  }

  void _initFromExisting(SoapNote note) {
    if (_note != null) return; // Already initialized
    _note = note;
    _bodyRegion = note.bodyRegion;

    // Subjective
    final subj = note.subjective;
    _presentingComplaintCtrl.text = subj.presentingComplaint;
    _onsetCtrl.text = subj.mechanismOfInjury ?? '';
    if (subj.painCurrent != null) _editState.painNow = subj.painCurrent!.toDouble();
    if (subj.painBest != null) _editState.painBest = subj.painBest!.toDouble();
    if (subj.painWorst != null) _editState.painWorst = subj.painWorst!.toDouble();
    _editState.irritability = subj.irritability.name;
    _pattern24hCtrl.text = subj.pattern24h ?? '';
    _pmhCtrl.text = subj.pastHistory ?? '';
    _medicationsCtrl.text = subj.medications ?? '';
    _socialCtrl.text = subj.socialHistory ?? '';
    _aggsCtrl.text = subj.aggravatingFactors.map((f) => f.label).join('\n');
    _easesCtrl.text = subj.easingFactors.map((f) => f.label).join('\n');
    if (subj.patientGoals.isNotEmpty) {
      _goal1Ctrl.text = subj.patientGoals[0].description;
      if (subj.patientGoals.length > 1) _goal2Ctrl.text = subj.patientGoals[1].description;
      if (subj.patientGoals.length > 2) _goal3Ctrl.text = subj.patientGoals[2].description;
    }

    // Objective
    _globalObjectiveCtrl.text = note.objective.globalNotes ?? '';
    _editState.regionObjectives = List<RegionObjective>.from(note.objective.regions);
    _editState.selectedObjectiveRegions
      ..clear()
      ..addAll(_editState.regionObjectives.map((r) => r.region));
    if (_editState.regionObjectives.isEmpty && note.bodyRegion != BodyRegion.other) {
      final t = regionObjectiveTemplates[note.bodyRegion];
      if (t != null) {
        _editState.regionObjectives = [t.createEmptyRegionObjective(note.bodyRegion)];
        _editState.selectedObjectiveRegions.add(note.bodyRegion);
      }
    }

    // Red flags - load standard and other flags
    _editState.redFlags = {
      'Unexplained weight loss': false,
      'Night pain / sweats': false,
      'Recent trauma': false,
      'History of cancer': false,
      'Neurological changes': false,
      'Bladder / bowel changes': false,
    };
    _editState.otherRedFlags.clear();
    for (final flag in note.screening.redFlags) {
      if (_editState.redFlags.containsKey(flag.label)) {
        _editState.redFlags[flag.label] = flag.present;
      } else {
        _editState.otherRedFlags[flag.label] = flag.present;
      }
    }

    // Assessment
    final a = note.analysis;
    _diagnosisCtrl.text = a.primaryDiagnosis;
    _assessmentSummaryCtrl.text = a.reasoningSummary ?? '';
    _contributingFactorsCtrl.text = a.contributingFactorsText ?? '';
    _keyImpairmentsCtrl.text = a.keyImpairments.join('\n');
    _differentialDiagnosesCtrl.text = a.secondaryDiagnoses.join('\n');

    // Plan
    final p = note.plan;
    _treatmentTodayCtrl.text = p.treatmentToday ?? '';
    _homeExerciseCtrl.text = p.homeExercise ?? '';
    _educationCtrl.text = p.educationAdvice ?? '';
    _followUpCtrl.text = p.followUpPlan ?? '';
    _planShortTermCtrl.text = p.planShortTermSummary ?? '';
    _planMediumTermCtrl.text = p.planMediumTermSummary ?? '';
    _contingencyPlanCtrl.text = p.contingencyPlan ?? '';

    // Clinical tests
    _selectedTests = note.clinicalTests.map((entry) {
      final def = ClinicalTestRegistry.byId(entry.testId);
      if (def == null) {
        // Create minimal fallback
        return SelectedClinicalTest(
          definition: ClinicalTestDefinition(
            id: entry.testId,
            name: entry.displayName,
            synonyms: const [],
            region: entry.region,
            category: TestCategory.other,
            primaryStructures: const [],
            purpose: '',
          ),
          result: entry.result,
          comments: entry.comments ?? '',
        );
      }
      return SelectedClinicalTest(
        definition: def,
        result: entry.result,
        comments: entry.comments ?? '',
      );
    }).toList();
  }

  List<String> _splitList(String raw) {
    return raw
        .split(RegExp(r'[\n;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  TernaryLevel _irritabilityEnum() {
    switch (_editState.irritability) {
      case 'mild':
        return TernaryLevel.low;
      case 'severe':
        return TernaryLevel.high;
      default:
        return TernaryLevel.moderate;
    }
  }

  SoapNote _buildSoapNote(String uid) {
    final now = DateTime.now();
    final existing = _note;

    // Screening - combine standard and other red flags
    final allRedFlags = <FlagItem>[];
    allRedFlags.addAll(_editState.redFlags.entries
        .where((e) => e.value)
        .map((e) => FlagItem(
              id: e.key.toLowerCase().replaceAll(' ', '_'),
              label: e.key,
              present: true,
            )));
    allRedFlags.addAll(_editState.otherRedFlags.entries
        .where((e) => e.value)
        .map((e) => FlagItem(
              id: 'other_${e.key.toLowerCase().replaceAll(' ', '_')}',
              label: e.key,
              present: true,
            )));
    
    final screening = ScreeningSection(
      redFlags: allRedFlags,
    );

    // Subjective
    final subjective = SubjectiveSection(
      presentingComplaint: _presentingComplaintCtrl.text.trim(),
      mechanismOfInjury: _onsetCtrl.text.trim().isEmpty ? null : _onsetCtrl.text.trim(),
      painCurrent: _editState.painNow.round(),
      painBest: _editState.painBest.round(),
      painWorst: _editState.painWorst.round(),
      irritability: _irritabilityEnum(),
      aggravatingFactors: _splitList(_aggsCtrl.text)
          .map((e) => FactorItem(label: e))
          .toList(),
      easingFactors: _splitList(_easesCtrl.text)
          .map((e) => FactorItem(label: e))
          .toList(),
      pattern24h: _pattern24hCtrl.text.trim().isEmpty ? null : _pattern24hCtrl.text.trim(),
      pastHistory: _pmhCtrl.text.trim().isEmpty ? null : _pmhCtrl.text.trim(),
      medications: _medicationsCtrl.text.trim().isEmpty ? null : _medicationsCtrl.text.trim(),
      socialHistory: _socialCtrl.text.trim().isEmpty ? null : _socialCtrl.text.trim(),
      patientGoals: [
        if (_goal1Ctrl.text.trim().isNotEmpty) GoalItem(description: _goal1Ctrl.text.trim()),
        if (_goal2Ctrl.text.trim().isNotEmpty) GoalItem(description: _goal2Ctrl.text.trim()),
        if (_goal3Ctrl.text.trim().isNotEmpty) GoalItem(description: _goal3Ctrl.text.trim()),
      ],
    );

    // Objective
    final objective = ObjectiveSection(
      globalNotes: _globalObjectiveCtrl.text.trim().isEmpty
          ? null
          : _globalObjectiveCtrl.text.trim(),
      regions: _editState.regionObjectives,
    );

    // Analysis
    final analysis = AnalysisSection(
      primaryDiagnosis: _diagnosisCtrl.text.trim(),
      reasoningSummary: _assessmentSummaryCtrl.text.trim().isEmpty
          ? null
          : _assessmentSummaryCtrl.text.trim(),
      contributingFactorsText: _contributingFactorsCtrl.text.trim().isEmpty
          ? null
          : _contributingFactorsCtrl.text.trim(),
      keyImpairments: _splitList(_keyImpairmentsCtrl.text),
      secondaryDiagnoses: _splitList(_differentialDiagnosesCtrl.text),
    );

    // Plan
    final plan = PlanSection(
      treatmentToday: _treatmentTodayCtrl.text.trim().isEmpty
          ? null
          : _treatmentTodayCtrl.text.trim(),
      homeExercise: _homeExerciseCtrl.text.trim().isEmpty
          ? null
          : _homeExerciseCtrl.text.trim(),
      educationAdvice: _educationCtrl.text.trim().isEmpty
          ? null
          : _educationCtrl.text.trim(),
      followUpPlan: _followUpCtrl.text.trim().isEmpty
          ? null
          : _followUpCtrl.text.trim(),
      planShortTermSummary: _planShortTermCtrl.text.trim().isEmpty
          ? null
          : _planShortTermCtrl.text.trim(),
      planMediumTermSummary: _planMediumTermCtrl.text.trim().isEmpty
          ? null
          : _planMediumTermCtrl.text.trim(),
      contingencyPlan: _contingencyPlanCtrl.text.trim().isEmpty
          ? null
          : _contingencyPlanCtrl.text.trim(),
    );

    // Clinical tests
    final clinicalTests = _selectedTests.map((sel) {
      return ClinicalTestEntry(
        testId: sel.definition.id,
        displayName: sel.definition.name,
        region: sel.definition.region,
        result: sel.result,
        comments: sel.comments.isEmpty ? null : sel.comments,
      );
    }).toList();

    return SoapNote(
      id: existing?.id ?? '',
      clinicId: widget.clinicId,
      patientId: widget.patientId,
      clinicianId: uid,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      screening: screening,
      subjective: subjective,
      objective: objective,
      analysis: analysis,
      plan: plan,
      clinicalTests: clinicalTests,
      bodyRegion: _bodyRegion,
      status: existing?.status ?? 'draft',
    );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final clinicCtx = context.read<ClinicContext>();
    final uid = clinicCtx.uidOrNull?.trim() ?? '';
    if (uid.isEmpty) return;

    setState(() => _saving = true);

    try {
      final note = _buildSoapNote(uid);

      if (_note == null) {
        // Create new
        await _repo.createSoapNote(
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          createdByUid: uid,
          bodyRegion: _bodyRegion,
        );
        // Then update with full data
        final created = await _repo.watchSoapNote(
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          noteId: note.id,
        ).first;
        final updated = created.copyWith(
          screening: note.screening,
          subjective: note.subjective,
          objective: note.objective,
          analysis: note.analysis,
          plan: note.plan,
          clinicalTests: note.clinicalTests,
          bodyRegion: note.bodyRegion,
        );
        await _repo.updateSoapNote(
          note: updated,
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          updatedByUid: uid,
        );
      } else {
        // Update existing
        await _repo.updateSoapNote(
          note: note,
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          updatedByUid: uid,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved SOAP note.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<SoapNote> _createIfNeeded(String uid) async {
    if (_creating && _note != null) return _note!;
    _creating = true;
    try {
      final created = await _repo.createSoapNote(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        createdByUid: uid,
        bodyRegion: _bodyRegion,
      );
      _note = created;
      _initFromExisting(created);
      return created;
    } catch (e, stack) {
      debugPrint('ERROR in _createIfNeeded:');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final perms = clinicCtx.session.permissions;
    final canView = canViewClinicalNotes(perms);
    final canEdit = canEditClinicalNotes(perms);
    if (!canView) {
      return const Scaffold(body: Center(child: Text('No access to clinical notes.')));
    }

    final uid = clinicCtx.uidOrNull?.trim() ?? '';
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Missing user identity.')));
    }

    final isEditing = widget.noteId != null;
    final readOnly = !canEdit || (_note?.status == 'final');

    if (!isEditing) {
      return FutureBuilder<SoapNote>(
        future: _createIfNeeded(uid),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Failed to create note:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${snap.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }
          return _buildScaffold(context, snap.data!, readOnly: readOnly);
        },
      );
    }

    return StreamBuilder<SoapNote>(
      stream: _repo.watchSoapNote(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        noteId: widget.noteId!,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: Text('Note not found')));
        }
        final note = snap.data!;
        if (_note == null) _initFromExisting(note);
        return _buildScaffold(context, note, readOnly: readOnly);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, SoapNote note, {required bool readOnly}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == null ? 'New SOAP note' : 'Edit SOAP note'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Subjective'),
            Tab(text: 'Objective'),
            Tab(text: 'Assessment'),
            Tab(text: 'Plan'),
          ],
        ),
        actions: [
          if (!readOnly)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: _saving ? null : _onSave,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _SubjectiveTab(root: this, editState: _editState, readOnly: readOnly),
            _ObjectiveTab(
              root: this,
              editState: _editState,
              readOnly: readOnly,
              onSelectedTestsChanged: (selected) =>
                  setState(() => _selectedTests = selected),
            ),
            _AssessmentTab(root: this, readOnly: readOnly),
            _PlanTab(root: this, readOnly: readOnly),
          ],
        ),
      ),
    );
  }
}

// Subjective Tab — uses ListenableBuilder so only this content rebuilds on pain/red-flag changes
class _SubjectiveTab extends StatelessWidget {
  final _SoapNoteEditScreenState root;
  final NoteEditState editState;
  final bool readOnly;

  const _SubjectiveTab({required this.root, required this.editState, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField('Presenting complaint', root._presentingComplaintCtrl, maxLines: 3, required: true, readOnly: readOnly),
          _buildTextField('Onset & mechanism', root._onsetCtrl, maxLines: 2, readOnly: readOnly),
          ListenableBuilder(
            listenable: editState,
            builder: (_, __) => DropdownButtonFormField<String>(
              value: editState.irritability,
              decoration: const InputDecoration(labelText: 'Irritability'),
              items: const [
                DropdownMenuItem(value: 'mild', child: Text('Mild')),
                DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                DropdownMenuItem(value: 'severe', child: Text('Severe')),
              ],
              onChanged: readOnly ? null : (val) {
                if (val != null) editState.setIrritability(val);
              },
            ),
          ),
          ListenableBuilder(
            listenable: editState,
            builder: (_, __) => Column(
              children: [
                _PainSliderRow(
                  label: 'Pain now',
                  value: editState.painNow,
                  onChanged: readOnly ? null : (v) => editState.setPainNow(v.roundToDouble()),
                ),
                _PainSliderRow(
                  label: 'Best',
                  value: editState.painBest,
                  onChanged: readOnly ? null : (v) => editState.setPainBest(v.roundToDouble()),
                ),
                _PainSliderRow(
                  label: 'Worst',
                  value: editState.painWorst,
                  onChanged: readOnly ? null : (v) => editState.setPainWorst(v.roundToDouble()),
                ),
              ],
            ),
          ),
          _buildTextField('Aggravating factors', root._aggsCtrl, maxLines: 3, readOnly: readOnly),
          _buildTextField('Easing factors', root._easesCtrl, maxLines: 3, readOnly: readOnly),
          _buildTextField('24-hour pattern', root._pattern24hCtrl, maxLines: 2, readOnly: readOnly),
          _buildTextField('Past history', root._pmhCtrl, maxLines: 2, readOnly: readOnly),
          _buildTextField('Medications', root._medicationsCtrl, readOnly: readOnly),
          _buildTextField('Social / work / sport', root._socialCtrl, maxLines: 3, readOnly: readOnly),
          const SizedBox(height: 16),
          const Text('Red flags', style: TextStyle(fontWeight: FontWeight.bold)),
          ListenableBuilder(
            listenable: editState,
            builder: (_, __) => Column(
              children: editState.redFlags.entries.map((e) => CheckboxListTile(
                title: Text(e.key),
                value: e.value,
                onChanged: readOnly ? null : (val) => editState.setRedFlag(e.key, val ?? false),
              )).toList(),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Other red flags', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: editState,
            builder: (_, __) => Column(
              children: editState.otherRedFlags.entries.map((e) => CheckboxListTile(
                title: Text(e.key),
                value: e.value,
                onChanged: readOnly ? null : (val) => editState.setOtherRedFlag(e.key, val ?? false),
                secondary: readOnly ? null : IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => editState.removeOtherRedFlag(e.key),
                ),
              )).toList(),
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: root._otherRedFlagCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Add other red flag',
                      hintText: 'Enter additional red flag',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        editState.addOtherRedFlag(value.trim(), checked: true);
                        root._otherRedFlagCtrl.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: () {
                    final value = root._otherRedFlagCtrl.text.trim();
                    if (value.isNotEmpty && !editState.otherRedFlags.containsKey(value)) {
                      editState.addOtherRedFlag(value, checked: true);
                      root._otherRedFlagCtrl.clear();
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, bool required = false, required bool readOnly}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        readOnly: readOnly,
        validator: required ? (value) => value?.trim().isEmpty == true ? 'Required' : null : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _PainSliderRow extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  const _PainSliderRow({required this.label, required this.value, this.onChanged});

  @override
  State<_PainSliderRow> createState() => _PainSliderRowState();
}

class _PainSliderRowState extends State<_PainSliderRow> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(_PainSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '${widget.label}: ${_currentValue.round()}/10',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 10,
            divisions: 10,
            value: _currentValue.clamp(0.0, 10.0),
            label: '${_currentValue.round()}',
            onChanged: widget.onChanged == null
                ? null
                : (double newValue) {
                    // Round to nearest integer for snapping
                    final rounded = newValue.roundToDouble();
                    // Update local state immediately for smooth UI
                    setState(() {
                      _currentValue = rounded;
                    });
                  },
            onChangeEnd: widget.onChanged == null
                ? null
                : (double newValue) {
                    // Only notify parent when user finishes adjusting
                    final rounded = newValue.roundToDouble();
                    widget.onChanged?.call(rounded);
                  },
          ),
        ),
      ],
    );
  }
}

// Objective Tab — uses ListenableBuilder so only this content rebuilds on region changes
class _ObjectiveTab extends StatelessWidget {
  final _SoapNoteEditScreenState root;
  final NoteEditState editState;
  final bool readOnly;
  final void Function(List<SelectedClinicalTest> selected)? onSelectedTestsChanged;

  const _ObjectiveTab({
    required this.root,
    required this.editState,
    required this.readOnly,
    this.onSelectedTestsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: root._globalObjectiveCtrl,
            maxLines: 5,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Global objective findings'),
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: editState,
            builder: (_, __) {
              final availableRegions = BodyRegion.values
                  .where((r) => r != BodyRegion.other && regionObjectiveTemplates.containsKey(r))
                  .toList();
              final unselectedRegions = availableRegions
                  .where((r) => !editState.selectedObjectiveRegions.contains(r))
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Body regions:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      if (!readOnly && unselectedRegions.isNotEmpty)
                        DropdownButton<BodyRegion>(
                          hint: const Text('Add region'),
                          items: unselectedRegions
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r.name.replaceFirst(
                                        r.name[0], r.name[0].toUpperCase())),
                                  ))
                              .toList(),
                          onChanged: (r) {
                            if (r != null) {
                              final t = regionObjectiveTemplates[r];
                              if (t != null) editState.addRegion(r, t);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: editState.selectedObjectiveRegions.map((region) {
                      final label = region.name
                          .replaceFirst(region.name[0], region.name[0].toUpperCase());
                      return Chip(
                        label: Text(label),
                        onDeleted: readOnly
                            ? null
                            : () => editState.removeSelectedRegion(region),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  ...editState.selectedObjectiveRegions.map((region) {
                    final obj = editState.regionObjectives
                        .cast<RegionObjective?>()
                        .firstWhere(
                          (r) => r?.region == region,
                          orElse: () {
                            final t = regionObjectiveTemplates[region];
                            return t?.createEmptyRegionObjective(region);
                          },
                        );
                    if (obj == null) return const SizedBox.shrink();
                    final t = regionObjectiveTemplates[region];
                    if (t == null) return const SizedBox.shrink();
                    return RegionObjectiveEditor(
                      regionObjective: obj,
                      template: t,
                      readOnly: readOnly,
                      onChanged: editState.updateRegionObjective,
                    );
                  }),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Clinical tests (structured)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ClinicalTestSelector(
            initialRegion: root._bodyRegion,
            initialSelection: root._selectedTests,
            onChanged: readOnly
                ? (_) {}
                : (selected) => onSelectedTestsChanged?.call(selected),
          ),
        ],
      ),
    );
  }
}

// Assessment Tab
class _AssessmentTab extends StatefulWidget {
  final _SoapNoteEditScreenState root;
  final bool readOnly;

  const _AssessmentTab({required this.root, required this.readOnly});

  @override
  State<_AssessmentTab> createState() => _AssessmentTabState();
}

class _AssessmentTabState extends State<_AssessmentTab> {
  final List<String> _contributingFactorChips = [];
  final List<String> _keyImpairmentItems = [];
  final TextEditingController _newChipCtrl = TextEditingController();
  final TextEditingController _newImpairmentCtrl = TextEditingController();
  bool _showDifferentials = false;

  @override
  void initState() {
    super.initState();
    // Parse existing contributing factors into chips
    final existing = widget.root._contributingFactorsCtrl.text.trim();
    if (existing.isNotEmpty) {
      _contributingFactorChips.addAll(
        existing.split('\n').where((s) => s.trim().isNotEmpty),
      );
    }
    // Parse key impairments into bullet items
    final impairments = widget.root._keyImpairmentsCtrl.text.trim();
    if (impairments.isNotEmpty) {
      _keyImpairmentItems.addAll(
        impairments.split('\n').where((s) => s.trim().isNotEmpty),
      );
    }
  }

  @override
  void dispose() {
    _newChipCtrl.dispose();
    _newImpairmentCtrl.dispose();
    super.dispose();
  }

  void _updateContributingFactors() {
    widget.root._contributingFactorsCtrl.text = _contributingFactorChips.join('\n');
  }

  void _updateKeyImpairments() {
    widget.root._keyImpairmentsCtrl.text = _keyImpairmentItems.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clinical impression section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Clinical impression',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: widget.root._diagnosisCtrl,
                    maxLines: 1,
                    readOnly: widget.readOnly,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Primary diagnosis',
                      hintText: 'e.g., Subacromial pain syndrome',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._assessmentSummaryCtrl,
                    maxLines: 5,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Assessment summary',
                      hintText: 'Based on subjective history, objective findings and response to testing...',
                      helperText: 'Synthesize your clinical reasoning here',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Contributing factors section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Contributing factors',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_contributingFactorChips.isEmpty && widget.readOnly)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No contributing factors documented', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _contributingFactorChips.map((factor) {
                        return Chip(
                          label: Text(factor),
                          deleteIcon: widget.readOnly ? null : const Icon(Icons.close, size: 18),
                          onDeleted: widget.readOnly ? null : () {
                            setState(() {
                              _contributingFactorChips.remove(factor);
                              _updateContributingFactors();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newChipCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Add factor',
                              hintText: 'e.g., Load management, Movement pattern',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                setState(() {
                                  _contributingFactorChips.add(value.trim());
                                  _updateContributingFactors();
                                  _newChipCtrl.clear();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: () {
                            final value = _newChipCtrl.text.trim();
                            if (value.isNotEmpty) {
                              setState(() {
                                _contributingFactorChips.add(value);
                                _updateContributingFactors();
                                _newChipCtrl.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Quick add buttons for common factors
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        'Load management',
                        'Movement pattern',
                        'Strength deficit',
                        'Psychosocial',
                        'Sleep / recovery',
                        'Work demands',
                      ].where((f) => !_contributingFactorChips.contains(f)).map((factor) {
                        return OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _contributingFactorChips.add(factor);
                              _updateContributingFactors();
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(factor, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Key impairments section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Key impairments',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_keyImpairmentItems.isEmpty && widget.readOnly)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No key impairments documented', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                    )
                  else
                    ..._keyImpairmentItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final impairment = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 12, right: 8),
                              child: Icon(Icons.circle, size: 6),
                            ),
                            Expanded(
                              child: Text(
                                impairment,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            if (!widget.readOnly)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    _keyImpairmentItems.removeAt(index);
                                    _updateKeyImpairments();
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newImpairmentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Add impairment',
                        hintText: 'e.g., Reduced shoulder ER strength',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          setState(() {
                            _keyImpairmentItems.add(value.trim());
                            _updateKeyImpairments();
                            _newImpairmentCtrl.clear();
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Differential diagnoses (optional, collapsed by default)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Row(
                  children: [
                    Icon(Icons.list_alt_outlined, size: 20, color: theme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Differential diagnoses',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text('(optional)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
                initiallyExpanded: _showDifferentials,
                onExpansionChanged: (expanded) {
                  setState(() => _showDifferentials = expanded);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TextFormField(
                      controller: widget.root._differentialDiagnosesCtrl,
                      maxLines: 4,
                      readOnly: widget.readOnly,
                      decoration: const InputDecoration(
                        labelText: 'Alternative diagnoses considered',
                        hintText: 'List other conditions considered and why they were ruled out',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Plan Tab
class _PlanTab extends StatefulWidget {
  final _SoapNoteEditScreenState root;
  final bool readOnly;

  const _PlanTab({required this.root, required this.readOnly});

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  String? _goal1Timeframe;
  String? _goal2Timeframe;
  String? _goal3Timeframe;

  bool get _hasGoals =>
      widget.root._goal1Ctrl.text.trim().isNotEmpty ||
      widget.root._goal2Ctrl.text.trim().isNotEmpty ||
      widget.root._goal3Ctrl.text.trim().isNotEmpty;

  bool get _hasTreatmentToday => widget.root._treatmentTodayCtrl.text.trim().isNotEmpty;
  bool get _hasHomeExercise => widget.root._homeExerciseCtrl.text.trim().isNotEmpty;
  bool get _hasFollowUp => widget.root._followUpCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shared goals section
          Text(
            'Shared goals',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Collaboratively set with patient',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          _buildGoalCard(context, 1, widget.root._goal1Ctrl, _goal1Timeframe, (val) => setState(() => _goal1Timeframe = val)),
          const SizedBox(height: 12),
          _buildGoalCard(context, 2, widget.root._goal2Ctrl, _goal2Timeframe, (val) => setState(() => _goal2Timeframe = val)),
          const SizedBox(height: 12),
          _buildGoalCard(context, 3, widget.root._goal3Ctrl, _goal3Timeframe, (val) => setState(() => _goal3Timeframe = val)),
          const SizedBox(height: 24),

          // Treatment today section
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.primaryColor.withOpacity(0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.healing_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Treatment today',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'What you actually did this session',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._treatmentTodayCtrl,
                    maxLines: 4,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Manual therapy, exercise selection, taping, education provided...',
                      helperText: 'Include response to treatment (medico-legally important)',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Home programme section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Home programme',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._homeExerciseCtrl,
                    maxLines: 5,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Exercise prescription',
                      hintText: 'Exercise name, dosage (sets/reps), key cues...',
                      helperText: 'Structure: exercise → dosage → cue',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Education & advice section
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.school_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Education & advice',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Red flags discussed, expectations set, load advice given...',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._educationCtrl,
                    maxLines: 4,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Safety netting, activity modification, pain education...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Time-based planning
          Text(
            'Time-based plan',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '1–2 weeks',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Short-term',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._planShortTermCtrl,
                    maxLines: 3,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Settle symptoms, establish tolerance to load...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '4–8 weeks',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Medium-term',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._planMediumTermCtrl,
                    maxLines: 3,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Strengthen rotator cuff, return to overhead sport...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Follow-up plan
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Follow-up plan',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._followUpCtrl,
                    maxLines: 2,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Review in 1 week, discharge after 4 sessions...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Contingency plan
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_outlined, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Contingency plan',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If progress is not as expected...',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.root._contingencyPlanCtrl,
                    maxLines: 3,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Consider imaging, refer to specialist, modify treatment approach...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Plan completeness indicator
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan completeness',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildCompletenessItem(context, _hasGoals, 'Goals set'),
                  _buildCompletenessItem(context, _hasTreatmentToday, 'Treatment documented'),
                  _buildCompletenessItem(context, _hasHomeExercise, 'Home programme provided'),
                  _buildCompletenessItem(context, _hasFollowUp, 'Follow-up planned'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildGoalCard(BuildContext context, int number, TextEditingController controller, String? timeframe, void Function(String?) onTimeframeChanged) {
    final theme = Theme.of(context);
    final isEmpty = controller.text.trim().isEmpty;
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isEmpty ? theme.dividerColor : theme.primaryColor.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isEmpty ? Colors.grey[300] : theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: TextStyle(
                        color: isEmpty ? Colors.grey[700] : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    maxLines: 2,
                    readOnly: widget.readOnly,
                    decoration: InputDecoration(
                      hintText: number == 1 ? 'e.g., Return to pain-free overhead lifting' : 'Optional goal',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            if (!widget.readOnly && !isEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 40),
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: timeframe,
                      decoration: const InputDecoration(
                        hintText: 'Timeframe (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: '1-2 weeks', child: Text('1-2 weeks')),
                        DropdownMenuItem(value: '4-6 weeks', child: Text('4-6 weeks')),
                        DropdownMenuItem(value: '8-12 weeks', child: Text('8-12 weeks')),
                        DropdownMenuItem(value: '3-6 months', child: Text('3-6 months')),
                      ],
                      onChanged: onTimeframeChanged,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletenessItem(BuildContext context, bool complete, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: complete ? Colors.green : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: complete ? theme.textTheme.bodyMedium?.color : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
