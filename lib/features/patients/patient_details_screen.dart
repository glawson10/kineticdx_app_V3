import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../models/patient.dart';
import 'uploads/patient_uploads_tab.dart';

// IMPORTANT: your functions are deployed in europe-west3 (REGION in index.ts)
final FirebaseFunctions _functions =
    FirebaseFunctions.instanceFor(region: 'europe-west3');

enum PatientDetailsMode { create, edit }

class PatientDetailsScreen extends StatefulWidget {
  final String clinicId;
  final PatientDetailsMode mode;

  /// Required in edit mode.
  final String? patientId;

  const PatientDetailsScreen({
    super.key,
    required this.clinicId,
    required this.mode,
    this.patientId,
  });

  static Route routeCreate({required String clinicId}) {
    return MaterialPageRoute(
      builder: (_) => PatientDetailsScreen(
        clinicId: clinicId,
        mode: PatientDetailsMode.create,
      ),
    );
  }

  static Route routeEdit(
      {required String clinicId, required String patientId}) {
    return MaterialPageRoute(
      builder: (_) => PatientDetailsScreen(
        clinicId: clinicId,
        mode: PatientDetailsMode.edit,
        patientId: patientId,
      ),
    );
  }

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  // Basic identity/contact controllers
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _preferredName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  DateTime? _dob;
  bool _active = true;
  bool _archived = false;

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // Admin helpers
  final _tags = TextEditingController(); // comma-separated
  final _alerts = TextEditingController(); // comma-separated
  final _adminNotes = TextEditingController();

  // Contact preference: null | "sms" | "email" | "call"
  String? _preferredMethod;

  // Address (light MVP)
  final _addrLine1 = TextEditingController();
  final _addrCity = TextEditingController();
  final _addrPostcode = TextEditingController();
  final _addrCountry = TextEditingController();

  // Emergency contact (light MVP)
  final _emergName = TextEditingController();
  final _emergRelationship = TextEditingController();
  final _emergPhone = TextEditingController();

  bool _loadedOnce = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _preferredName.dispose();
    _email.dispose();
    _phone.dispose();
    _tags.dispose();
    _alerts.dispose();
    _adminNotes.dispose();
    _addrLine1.dispose();
    _addrCity.dispose();
    _addrPostcode.dispose();
    _addrCountry.dispose();
    _emergName.dispose();
    _emergRelationship.dispose();
    _emergPhone.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    if (widget.mode == PatientDetailsMode.edit) {
      if (widget.patientId == null || widget.patientId!.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Missing patientId for edit mode.")),
          );
          Navigator.of(context).pop();
        });
      }
    }
  }

  Stream<bool> _watchIsOwnerOrManager() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(false);

    final ref = FirebaseFirestore.instance
        .collection('clinics')
        .doc(widget.clinicId)
        .collection('memberships')
        .doc(uid);

    return ref.snapshots().map((snap) {
      if (!snap.exists) return false;
      final data = snap.data() ?? {};

      // Prefer roleId if you have it
      final roleId = (data['roleId'] ?? data['role'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (roleId == 'owner' || roleId == 'manager') return true;

      // Fallback: settings.write implies admin-level privileges in your model
      final perms =
          (data['permissions'] is Map) ? (data['permissions'] as Map) : {};
      return perms['settings.write'] == true;
    });
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 30, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );

    if (picked != null) {
      setState(() => _dob = DateTime(picked.year, picked.month, picked.day));
    }
  }

  String _dobIso() {
    final d = _dob;
    if (d == null) return '';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  String _dobLabel() => _dob == null ? "Not set" : _dobIso();

  List<String> _parseCsv(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _validatePhoneOrEmail() {
    final hasEmail = _email.text.trim().isNotEmpty;
    final hasPhone = _phone.text.trim().isNotEmpty;
    if (!hasEmail && !hasPhone) return "Enter at least a phone or email.";
    return null;
  }

  Future<void> _deletePatient() async {
    final patientId = widget.patientId;
    if (patientId == null || patientId.isEmpty) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete patient'),
            content: const Text(
              'This will archive the patient and hide them from the patient list.\n\n'
              'You can still show archived patients using the toggle.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      final callable = _functions.httpsCallable('deletePatientFn');
      await callable.call({
        'clinicId': widget.clinicId,
        'patientId': patientId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Patient deleted.')));

      Navigator.of(context).pop(); // back to finder
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message ?? e.details ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _saveCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneOrEmailError = _validatePhoneOrEmail();
    if (phoneOrEmailError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(phoneOrEmailError)));
      return;
    }

    setState(() => _saving = true);

    try {
      final callable = _functions.httpsCallable("createPatientFn");

      final payload = <String, dynamic>{
        "clinicId": widget.clinicId,
        "firstName": _firstName.text.trim(),
        "lastName": _lastName.text.trim(),
        "preferredName": _preferredName.text.trim().isEmpty
            ? null
            : _preferredName.text.trim(),
        "dateOfBirth": _dob == null ? null : _dobIso(),
        "email": _email.text.trim().isEmpty ? null : _email.text.trim(),
        "phone": _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      };

      final res = await callable.call(payload);
      final patientId = (res.data as Map?)?["patientId"]?.toString();

      if (!mounted) return;

      if (patientId == null || patientId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Created patient but missing patientId.")),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        PatientDetailsScreen.routeEdit(
          clinicId: widget.clinicId,
          patientId: patientId,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${e.code}: ${e.message ?? e.details ?? ''}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Create failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneOrEmailError = _validatePhoneOrEmail();
    if (phoneOrEmailError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(phoneOrEmailError)));
      return;
    }

    setState(() => _saving = true);

    try {
      final patientId = widget.patientId!;
      final callable = _functions.httpsCallable("updatePatientFn");

      final payload = <String, dynamic>{
        "clinicId": widget.clinicId,
        "patientId": patientId,
        "firstName": _firstName.text.trim(),
        "lastName": _lastName.text.trim(),
        "preferredName": _preferredName.text.trim().isEmpty
            ? null
            : _preferredName.text.trim(),
        "dateOfBirth": _dob == null ? null : _dobIso(),
        "email": _email.text.trim().isEmpty ? null : _email.text.trim(),
        "phone": _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        "preferredMethod": _preferredMethod,
        "address": {
          "line1":
              _addrLine1.text.trim().isEmpty ? null : _addrLine1.text.trim(),
          "city": _addrCity.text.trim().isEmpty ? null : _addrCity.text.trim(),
          "postcode": _addrPostcode.text.trim().isEmpty
              ? null
              : _addrPostcode.text.trim(),
          "country": _addrCountry.text.trim().isEmpty
              ? null
              : _addrCountry.text.trim(),
        },
        "emergencyContact": {
          "name":
              _emergName.text.trim().isEmpty ? null : _emergName.text.trim(),
          "relationship": _emergRelationship.text.trim().isEmpty
              ? null
              : _emergRelationship.text.trim(),
          "phone":
              _emergPhone.text.trim().isEmpty ? null : _emergPhone.text.trim(),
        },
        "tags": _parseCsv(_tags.text),
        "alerts": _parseCsv(_alerts.text),
        "adminNotes":
            _adminNotes.text.trim().isEmpty ? null : _adminNotes.text.trim(),
        "active": _active,
        "archived": _archived,
      };

      await callable.call(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved.")),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${e.code}: ${e.message ?? e.details ?? ''}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _populateFromPatient(Patient p) {
    _firstName.text = p.firstName;
    _lastName.text = p.lastName;
    _preferredName.text = p.preferredName ?? "";
    _email.text = p.email ?? "";
    _phone.text = p.phone ?? "";
    _dob = p.dateOfBirth;

    _preferredMethod = p.preferredContactMethod;

    _active = p.active;
    _archived = p.archived;

    _tags.text = p.tags.join(", ");
    _alerts.text = p.alerts.join(", ");
    _adminNotes.text = p.adminNotes ?? "";

    _addrLine1.text = p.address?.line1 ?? "";
    _addrCity.text = p.address?.city ?? "";
    _addrPostcode.text = p.address?.postcode ?? "";
    _addrCountry.text = p.address?.country ?? "";

    _emergName.text = p.emergencyContact?.name ?? "";
    _emergRelationship.text = p.emergencyContact?.relationship ?? "";
    _emergPhone.text = p.emergencyContact?.phone ?? "";
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Identity", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: "First name *"),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? "Required" : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: "Last name *"),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? "Required" : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _preferredName,
            decoration: const InputDecoration(labelText: "Preferred name"),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text("DOB: ${_dobLabel()}")),
              TextButton.icon(
                onPressed: _pickDob,
                icon: const Icon(Icons.calendar_month),
                label: const Text("Select"),
              ),
              if (_dob != null)
                TextButton(
                  onPressed: () => setState(() => _dob = null),
                  child: const Text("Clear"),
                ),
            ],
          ),
          const SizedBox(height: 24),

          Text("Contact", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: "Email"),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: "Phone"),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // Save
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () {
                    if (widget.mode == PatientDetailsMode.create) {
                      _saveCreate();
                    } else {
                      _saveUpdate();
                    }
                  },
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(
              widget.mode == PatientDetailsMode.create
                  ? "Create patient"
                  : "Save changes",
            ),
          ),
        ],
      ),
    );
  }

  bool _canReadUploads(BuildContext context) {
    try {
      final session = context.read<ClinicContext>().sessionOrNull;
      if (session == null) return false;
      return session.permissions.has('clinical.read') ||
          session.permissions.has('patients.read');
    } catch (_) {
      return false;
    }
  }

  bool _canWriteUploads(BuildContext context) {
    try {
      final session = context.read<ClinicContext>().sessionOrNull;
      if (session == null) return false;
      return session.permissions.has('patients.write');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.mode == PatientDetailsMode.edit;
    final showUploadsTab = isEdit && _canReadUploads(context);

    return StreamBuilder<bool>(
      stream: _watchIsOwnerOrManager(),
      builder: (context, permSnap) {
        final canDelete = permSnap.data == true;

        if (isEdit && showUploadsTab) {
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text("Patient details"),
                actions: [
                  if (canDelete)
                    IconButton(
                      tooltip: 'Delete patient',
                      onPressed: _deletePatient,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
                bottom: TabBar(
                  tabs: const [
                    Tab(text: 'Details'),
                    Tab(text: 'Uploads'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _editModeBody(),
                  PatientUploadsTab(
                    clinicId: widget.clinicId,
                    patientId: widget.patientId!,
                    canWrite: _canWriteUploads(context),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(isEdit ? "Patient details" : "New patient"),
            actions: [
              if (isEdit && canDelete)
                IconButton(
                  tooltip: 'Delete patient',
                  onPressed: _deletePatient,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: isEdit ? _editModeBody() : _buildForm(),
        );
      },
    );
  }

  Widget _editModeBody() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("clinics")
          .doc(widget.clinicId)
          .collection("patients")
          .doc(widget.patientId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text("Error: ${snap.error}"));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final doc = snap.data!;
        if (!doc.exists) {
          return const Center(child: Text("Patient not found."));
        }

        final patient = Patient.fromFirestore(doc.id, doc.data()!);

        if (!_loadedOnce && !_saving) {
          _loadedOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _populateFromPatient(patient);
            setState(() {});
          });
        }

        return _buildForm();
      },
    );
  }
}
