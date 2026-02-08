// lib/features/auth/clinic_entry_screen.dart
//
// Root "/" screen: find your clinic by ID, or continue to last used clinic.
// No auth required. Navigates to /c/{clinicId} for clinic-specific login.

import 'package:flutter/material.dart';

import '../../app/last_clinic_store.dart';

class ClinicEntryScreen extends StatefulWidget {
  const ClinicEntryScreen({super.key});

  static const String routeName = '/';

  @override
  State<ClinicEntryScreen> createState() => _ClinicEntryScreenState();
}

class _ClinicEntryScreenState extends State<ClinicEntryScreen> {
  final _controller = TextEditingController();
  String? _lastClinicId;
  bool _loadingLast = true;

  @override
  void initState() {
    super.initState();
    _loadLastClinic();
  }

  Future<void> _loadLastClinic() async {
    final last = await LastClinicStore.getLastClinicForEntry();
    if (mounted) {
      setState(() {
        _lastClinicId = last;
        _loadingLast = false;
      });
    }
  }

  void _navigateToClinicPortal(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return;

    LastClinicStore.setLastClinicForEntry(c);

    final path = '/c/$c';
    Navigator.of(context).pushReplacementNamed(path);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surface,
                  cs.surfaceContainerHighest.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.health_and_safety_outlined,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'KineticDx',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Find your clinic',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Enter your clinic code or ID to sign in to your workspace.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _controller,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Clinic code / ID',
                              hintText: 'e.g. your-clinic-id',
                              prefixIcon: const Icon(Icons.business_outlined),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (_) => _navigateToClinicPortal(_controller.text),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                _navigateToClinicPortal(_controller.text),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Continue'),
                          ),
                          if (_loadingLast) ...[
                            const SizedBox(height: 24),
                            const Center(
                                child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))),
                          ] else if (_lastClinicId != null &&
                              _lastClinicId!.trim().isNotEmpty) ...[
                            Builder(
                              builder: (context) {
                                final lastId = _lastClinicId ?? '';
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 24),
                                    const Divider(),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Last clinic',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton(
                                      onPressed: () =>
                                          _navigateToClinicPortal(lastId),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text('Continue to $lastId'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
