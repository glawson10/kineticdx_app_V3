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
class _AssessmentTab extends StatelessWidget {
  final _SoapNoteEditScreenState root;
  final bool readOnly;

  const _AssessmentTab({required this.root, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextFormField(
            controller: root._diagnosisCtrl,
            maxLines: 2,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Diagnosis'),
          ),
          TextFormField(
            controller: root._assessmentSummaryCtrl,
            maxLines: 5,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Assessment summary'),
          ),
          TextFormField(
            controller: root._contributingFactorsCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Contributing factors'),
          ),
          TextFormField(
            controller: root._keyImpairmentsCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Key impairments'),
          ),
        ],
      ),
    );
  }
}

// Plan Tab
class _PlanTab extends StatelessWidget {
  final _SoapNoteEditScreenState root;
  final bool readOnly;

  const _PlanTab({required this.root, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('Patient goals', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextFormField(
            controller: root._goal1Ctrl,
            maxLines: 1,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Goal 1'),
          ),
          TextFormField(
            controller: root._goal2Ctrl,
            maxLines: 1,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Goal 2'),
          ),
          TextFormField(
            controller: root._goal3Ctrl,
            maxLines: 1,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Goal 3'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: root._treatmentTodayCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Treatment today'),
          ),
          TextFormField(
            controller: root._homeExerciseCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Home exercise programme'),
          ),
          TextFormField(
            controller: root._educationCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Education / advice'),
          ),
          TextFormField(
            controller: root._followUpCtrl,
            maxLines: 2,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Follow-up plan'),
          ),
          TextFormField(
            controller: root._planShortTermCtrl,
            maxLines: 2,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Short-term plan (1-2 weeks)'),
          ),
          TextFormField(
            controller: root._planMediumTermCtrl,
            maxLines: 2,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Medium-term plan (4-8 weeks)'),
          ),
          TextFormField(
            controller: root._contingencyPlanCtrl,
            maxLines: 3,
            readOnly: readOnly,
            decoration: const InputDecoration(labelText: 'Contingency plan'),
          ),
        ],
      ),
    );
  }
}
