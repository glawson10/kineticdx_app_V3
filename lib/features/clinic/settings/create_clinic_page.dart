import 'package:flutter/material.dart';

import '/../data/repositories/clinic_onboarding_repository.dart';
import '/app/clinic_onboarding_gate.dart';

class CreateClinicPage extends StatefulWidget {
  const CreateClinicPage({super.key});

  @override
  State<CreateClinicPage> createState() => _CreateClinicPageState();
}

class _CreateClinicPageState extends State<CreateClinicPage> {
  final _repo = ClinicOnboardingRepository();
  final _name = TextEditingController(text: "My Clinic");

  bool _loading = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _repo.createClinic(name: _name.text.trim());

      if (!mounted) return;

      // ✅ After clinic creation, return to the single source of truth gate.
      // It will:
      // - reload memberships
      // - auto-enter if only one clinic
      // - else show picker once
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ClinicOnboardingGate()),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create clinic")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "No active clinic memberships found.\nCreate your first clinic to continue.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: "Clinic name"),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Create clinic"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
