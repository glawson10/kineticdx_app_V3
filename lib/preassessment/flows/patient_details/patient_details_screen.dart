import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../state/intake_draft_controller.dart';
import '../../domain/answer_value.dart';
import '../../domain/intake_schema.dart';

class PatientDetailsScreen extends StatefulWidget {
  const PatientDetailsScreen({super.key});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  DateTime? _dob;

  String _ageRange = '18-25';
  String _sex = 'female';
  String _workType = 'desk';

  final _reasonForVisit = TextEditingController();

  bool _pmhSmoking = false;
  bool _pmhHighBp = false;
  bool _pmhHighChol = false;
  bool _pmhDiabetes = false;
  bool _pmhCancerHistory = false;

  final _otherPmh = TextEditingController();

  bool _isProxy = false;
  final _proxyName = TextEditingController();
  final _proxyRelationship = TextEditingController();

  bool _prefilled = false;
  bool _isNavigating = false;

  // ---------------------------------------------------------------------------
  // Flow routing helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _routeArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) return Map<String, dynamic>.from(args);
    return const <String, dynamic>{};
  }

  String _safeStr(Object? v) => v == null ? '' : v.toString().trim();

  /// We treat the flow override as the single source of truth for routing here.
  /// IntakeStartScreen passes it into IntakeFlowHost(flowArgs: ...),
  /// IntakeFlowHost then forwards it into each route settings.arguments.
  String _resolveFlowIdOverride() {
    final args = _routeArgs();
    return _safeStr(args['flowIdOverride']);
  }

  String _nextRouteForFlow(String flowIdOverride) {
    final f = flowIdOverride.trim().toLowerCase();
    if (f == 'generalvisit' || f == 'general_visit' || f == 'general-visit') {
      return '/general-visit-start';
    }
    return '/region-select';
  }

  // ---------------------------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;

    final draft = context.read<IntakeDraftController>();
    final p = draft.session.patientDetails;

    if (_first.text.isEmpty) _first.text = p.firstName;
    if (_last.text.isEmpty) _last.text = p.lastName;
    if (_email.text.isEmpty) _email.text = p.email;
    if (_phone.text.isEmpty) _phone.text = p.phone;

    if (_dob == null && p.dateOfBirth != null) {
      _dob = p.dateOfBirth!.toDate();
    }

    _isProxy = p.isProxy;
    if (_proxyName.text.isEmpty) _proxyName.text = p.proxyName ?? '';
    if (_proxyRelationship.text.isEmpty) {
      _proxyRelationship.text = p.proxyRelationship ?? '';
    }

    String? readSingle(String qid) {
      final v = draft.getAnswer(qid);
      return v?.v?.toString();
    }

    bool? readBool(String qid) {
      final v = draft.getAnswer(qid);
      final raw = v?.v;
      return raw is bool ? raw : null;
    }

    if (_reasonForVisit.text.isEmpty) {
      final t = readSingle('patient.reasonForVisit');
      if (t != null) _reasonForVisit.text = t;
    }
    if (_otherPmh.text.isEmpty) {
      final t = readSingle('patient.pmh.other');
      if (t != null) _otherPmh.text = t;
    }

    final ar = readSingle('patient.ageRange');
    if (ar != null && ar.trim().isNotEmpty) _ageRange = ar;

    final sx = readSingle('patient.sex');
    if (sx != null && sx.trim().isNotEmpty) _sex = sx;

    final wt = readSingle('patient.workType');
    if (wt != null && wt.trim().isNotEmpty) _workType = wt;

    _pmhSmoking = readBool('patient.pmh.smoking') ?? _pmhSmoking;
    _pmhHighBp = readBool('patient.pmh.highBloodPressure') ?? _pmhHighBp;
    _pmhHighChol = readBool('patient.pmh.highCholesterol') ?? _pmhHighChol;
    _pmhDiabetes = readBool('patient.pmh.diabetes') ?? _pmhDiabetes;
    _pmhCancerHistory =
        readBool('patient.pmh.cancerHistory') ?? _pmhCancerHistory;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _reasonForVisit.dispose();
    _otherPmh.dispose();
    _proxyName.dispose();
    _proxyRelationship.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty;

  void _setSingle(IntakeDraftController draft, String qid, String value) {
    draft.setAnswer(qid, AnswerValue.single(value));
  }

  void _setText(IntakeDraftController draft, String qid, String value) {
    final trimmed = value.trim();
    draft.setAnswer(qid, trimmed.isEmpty ? null : AnswerValue.text(trimmed));
  }

  void _setBool(IntakeDraftController draft, String qid, bool value) {
    draft.setAnswer(qid, AnswerValue.bool(value));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 30, now.month, now.day);
    final firstDate = DateTime(now.year - 120);
    final lastDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(lastDate) ? lastDate : initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select date of birth',
    );

    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  void _continue() {
    if (_isNavigating || !_canContinue) return;

    setState(() => _isNavigating = true);

    try {
      final draft = context.read<IntakeDraftController>();

      // Persist patient block into draft session
      draft.setPatientDetails(
        PatientDetailsBlock(
          firstName: _first.text.trim(),
          lastName: _last.text.trim(),
          dateOfBirth: _dob != null ? Timestamp.fromDate(_dob!) : null,
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          isProxy: _isProxy,
          proxyName: _isProxy ? _proxyName.text.trim() : null,
          proxyRelationship: _isProxy ? _proxyRelationship.text.trim() : null,
          confirmedAt: null,
        ),
      );

      // Persist misc patient answers
      _setSingle(draft, 'patient.ageRange', _ageRange);
      _setSingle(draft, 'patient.sex', _sex);
      _setSingle(draft, 'patient.workType', _workType);
      _setText(draft, 'patient.reasonForVisit', _reasonForVisit.text);

      _setBool(draft, 'patient.pmh.smoking', _pmhSmoking);
      _setBool(draft, 'patient.pmh.highBloodPressure', _pmhHighBp);
      _setBool(draft, 'patient.pmh.highCholesterol', _pmhHighChol);
      _setBool(draft, 'patient.pmh.diabetes', _pmhDiabetes);
      _setBool(draft, 'patient.pmh.cancerHistory', _pmhCancerHistory);
      _setText(draft, 'patient.pmh.other', _otherPmh.text);

      _setText(draft, 'patient.firstName', _first.text);
      _setText(draft, 'patient.lastName', _last.text);
      _setText(draft, 'patient.email', _email.text);
      _setText(draft, 'patient.phone', _phone.text);

      // Optional breadcrumb (nice for server logic / debugging)
      final flowIdOverride = _resolveFlowIdOverride();
      if (flowIdOverride.isNotEmpty) {
        _setSingle(draft, 'meta.flowId', flowIdOverride);
      }

      final next = _nextRouteForFlow(flowIdOverride);

      // ✅ Branch: generalVisit -> /general-visit-start, else -> /region-select
      Navigator.of(context).pushReplacementNamed(next);
    } finally {
      // If we navigate, this widget will unmount; if not, we re-enable the button.
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<IntakeDraftController>();
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    final flowIdDebug = _resolveFlowIdOverride();

    return Scaffold(
      appBar: AppBar(title: const Text('Your details')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        children: [
          TextField(
            controller: _first,
            decoration: const InputDecoration(labelText: 'First name *'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _last,
            decoration: const InputDecoration(labelText: 'Last name *'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDob,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date of birth (optional)',
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dob == null
                          ? 'Tap to select'
                          : '${_dob!.year.toString().padLeft(4, '0')}-'
                              '${_dob!.month.toString().padLeft(2, '0')}-'
                              '${_dob!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _ageRange,
            items: const [
              DropdownMenuItem(value: 'under-18', child: Text('Under 18')),
              DropdownMenuItem(value: '18-25', child: Text('18–25')),
              DropdownMenuItem(value: '26-35', child: Text('26–35')),
              DropdownMenuItem(value: '36-45', child: Text('36–45')),
              DropdownMenuItem(value: '46-55', child: Text('46–55')),
              DropdownMenuItem(value: '56-65', child: Text('56–65')),
              DropdownMenuItem(value: '65+', child: Text('65+')),
            ],
            onChanged: (v) => setState(() => _ageRange = v ?? _ageRange),
            decoration: const InputDecoration(labelText: 'Age range'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            items: const [
              DropdownMenuItem(value: 'female', child: Text('Female')),
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(
                value: 'other',
                child: Text('Other / prefer not to say'),
              ),
            ],
            onChanged: (v) => setState(() => _sex = v ?? _sex),
            decoration: const InputDecoration(labelText: 'Sex'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _workType,
            items: const [
              DropdownMenuItem(
                  value: 'desk', child: Text('Desk-based / office')),
              DropdownMenuItem(
                  value: 'manual', child: Text('Manual / active job')),
              DropdownMenuItem(
                  value: 'mixed', child: Text('Mixed / varied work')),
              DropdownMenuItem(
                  value: 'healthcare', child: Text('Healthcare / care work')),
              DropdownMenuItem(
                  value: 'education', child: Text('Education / teaching')),
              DropdownMenuItem(
                  value: 'transport', child: Text('Driving / transport')),
              DropdownMenuItem(
                  value: 'construction', child: Text('Construction / trades')),
              DropdownMenuItem(
                  value: 'retail', child: Text('Retail / hospitality')),
              DropdownMenuItem(value: 'student', child: Text('Student')),
              DropdownMenuItem(value: 'retired', child: Text('Retired')),
              DropdownMenuItem(
                  value: 'unemployed', child: Text('Currently unemployed')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _workType = v ?? _workType),
            decoration: const InputDecoration(labelText: 'Occupation type'),
          ),
          const SizedBox(height: 16),
          Text(
            'What is the reason for your visit?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonForVisit,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText:
                  'Describe your issue (when it started, what makes it better/worse, etc.)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Past medical history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Smoking'),
            value: _pmhSmoking,
            onChanged: (v) => setState(() => _pmhSmoking = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('High blood pressure'),
            value: _pmhHighBp,
            onChanged: (v) => setState(() => _pmhHighBp = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('High cholesterol'),
            value: _pmhHighChol,
            onChanged: (v) => setState(() => _pmhHighChol = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Diabetes'),
            value: _pmhDiabetes,
            onChanged: (v) => setState(() => _pmhDiabetes = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('History of cancer'),
            value: _pmhCancerHistory,
            onChanged: (v) => setState(() => _pmhCancerHistory = v ?? false),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _otherPmh,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Any other medical history / surgeries (optional)',
              hintText: 'e.g., asthma, thyroid issues, knee surgery (2018)…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I am completing this for someone else'),
            value: _isProxy,
            onChanged: (v) => setState(() => _isProxy = v),
          ),
          if (_isProxy) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _proxyName,
              decoration: const InputDecoration(labelText: 'Proxy name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _proxyRelationship,
              decoration: const InputDecoration(labelText: 'Relationship'),
              textInputAction: TextInputAction.done,
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (_canContinue && !_isNavigating) ? _continue : null,
              child: _isNavigating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ),
          if (!_canContinue) ...[
            const SizedBox(height: 10),
            Text(
              'First name and last name are required.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
