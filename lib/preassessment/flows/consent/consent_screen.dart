import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/intake_draft_controller.dart';
import '../../domain/intake_schema.dart';
import '../../privacy/PrivacyPolicyScreen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _requiredAll = false;
  bool _contactOk = false;
  bool _showDetails = false;

  bool _hydrated = false;

  // ✅ boot: resolve intakeSessionId when coming from public booking (bookingRequestId)
  bool _sessionBooted = false;
  String? _sessionBootError;

  // ---- Pre overlay behavior ----
  bool _showPreOverlay = true;
  bool _preVisible = true;
  Timer? _preHoldTimer;
  Timer? _preFadeOutTimer;

  static const Duration _fade = Duration(milliseconds: 800);
  static const Duration _preHold = Duration(seconds: 6);
  static const Duration _extraPause = Duration(milliseconds: 300);

  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _startPreOverlaySequence();
    // ✅ do NOT call context.read() here; wait for post-frame in build/didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    _hydrated = true;

    final draft = context.read<IntakeDraftController>();
    final c = draft.session.consent;

    _requiredAll = c.termsAccepted &&
        c.privacyAccepted &&
        c.dataStorageAccepted &&
        c.notEmergencyAck &&
        c.noDiagnosisAck;

    _contactOk = c.consentToContact;

    // ✅ boot session after first frame so ModalRoute is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootSessionIfNeeded();
    });
  }

  Map<String, dynamic> _routeArgs() {
    final a = ModalRoute.of(context)?.settings.arguments;
    return (a is Map) ? Map<String, dynamic>.from(a) : <String, dynamic>{};
  }

  bool _isDraftSessionId(String? sessionId) {
    final s = (sessionId ?? '').trim().toLowerCase();
    return s.isEmpty || s == 'draft';
  }

  Future<void> _bootSessionIfNeeded() async {
    if (_sessionBooted) return;
    _sessionBooted = true;

    final args = _routeArgs();
    final bookingRequestId = (args['bookingRequestId'] ?? '').toString().trim();

    // If no bookingRequestId, this is likely a token-link flow (handled in /intake/start).
    if (bookingRequestId.isEmpty) return;

    final draft = context.read<IntakeDraftController>();
    final clinicId = draft.session.clinicId;
    final currentSid = draft.session.sessionId;

    // If we already have a real session id, nothing to do.
    if (!_isDraftSessionId(currentSid)) return;

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn =
          functions.httpsCallable('resolveIntakeSessionFromBookingRequestFn');

      final res = await fn.call(<String, dynamic>{
        'clinicId': clinicId,
        'bookingRequestId': bookingRequestId,
      });

      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data)
          : <String, dynamic>{};

      final intakeSessionId = (data['intakeSessionId'] ?? '').toString().trim();

      if (intakeSessionId.isEmpty) {
        throw StateError(
            'resolveIntakeSessionFromBookingRequestFn returned no intakeSessionId');
      }

      // ✅ adopt server session id into draft (so ReviewScreen can submit)
      draft.setServerSessionId(intakeSessionId);

      if (!mounted) return;
      setState(() => _sessionBootError = null);

      debugPrint(
        '[ConsentScreen] booted sessionId="$intakeSessionId" '
        '(was "${currentSid.trim()}") from bookingRequestId="$bookingRequestId"',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _sessionBootError = '${e.code}: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sessionBootError = e.toString());
    }
  }

  void _startPreOverlaySequence() {
    _preHoldTimer = Timer(_preHold, () {
      if (!mounted) return;
      setState(() => _preVisible = false);

      _preFadeOutTimer = Timer(_fade + _extraPause, () {
        if (!mounted) return;
        setState(() => _showPreOverlay = false);
      });
    });
  }

  @override
  void dispose() {
    _preHoldTimer?.cancel();
    _preFadeOutTimer?.cancel();
    super.dispose();
  }

  bool get _canContinue => _requiredAll;

  void _saveConsentToDraft() {
    final draft = context.read<IntakeDraftController>();
    final current = draft.session.consent;

    draft.setConsent(
      ConsentBlock(
        policyBundleId:
            current.policyBundleId.isEmpty ? 'default' : current.policyBundleId,
        policyBundleVersion:
            current.policyBundleVersion == 0 ? 1 : current.policyBundleVersion,
        locale: current.locale.isEmpty ? 'en' : current.locale,
        termsAccepted: _requiredAll,
        privacyAccepted: _requiredAll,
        dataStorageAccepted: _requiredAll,
        notEmergencyAck: _requiredAll,
        noDiagnosisAck: _requiredAll,
        consentToContact: _contactOk,
        acceptedAt: current.acceptedAt,
      ),
    );
  }

  void _continue() {
    if (!_canContinue || _isNavigating) return;
    _isNavigating = true;

    _saveConsentToDraft();

    // ✅ navigate using the nested IntakeFlowHost navigator
    Navigator.of(context).pushReplacementNamed('/patient-details');
  }

  Future<String> _resolveClinicName(String clinicId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .get();
      final data = snap.data();
      final profile = data?['profile'];
      final name = profile is Map ? profile['name'] : null;
      final s = (name == null) ? '' : name.toString().trim();
      return s.isEmpty ? 'Your Clinic' : s;
    } catch (_) {
      return 'Your Clinic';
    }
  }

  Future<void> _openPrivacyPolicy() async {
    if (_isNavigating) return;

    final draft = context.read<IntakeDraftController>();
    final clinicId = draft.session.clinicId;

    final clinicName = await _resolveClinicName(clinicId);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivacyPolicyScreen(
          clinicId: clinicId,
          clinicName: clinicName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color navy = Color(0xFF0B1B3B);

    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('Consent')),
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sessionBootError != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _sessionBootError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Before we continue',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: navy,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "This questionnaire helps your clinician prepare for your appointment.\n"
                      "Please read the points below carefully before continuing.",
                      style: TextStyle(fontSize: 16, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What you are agreeing to (required)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            _bullet(
                              'You agree to the Terms of Use and the clinic’s Privacy Policy.',
                            ),
                            _bullet(
                              'You consent to securely storing your answers and sharing them with authorised clinic staff.',
                            ),
                            _bullet(
                                'You understand this is not emergency care.'),
                            _bullet(
                              'You understand this does not provide a diagnosis or treatment plan.',
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              value: _requiredAll,
                              onChanged: (v) =>
                                  setState(() => _requiredAll = v ?? false),
                              title: const Text(
                                'I understand and agree to the items above',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text('Required'),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: CheckboxListTile(
                          value: _contactOk,
                          onChanged: (v) =>
                              setState(() => _contactOk = v ?? false),
                          title: const Text(
                            'You may contact me about my booking / pre-assessment',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('Optional'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showDetails = !_showDetails),
                      icon: Icon(
                        _showDetails
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.blue,
                      ),
                      label: Text(
                        _showDetails
                            ? "Hide details about data protection"
                            : "Learn more about data protection and consent",
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                    if (_showDetails)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(top: 4, bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Your personal and health information is handled in accordance with UK GDPR / EU GDPR. "
                              "Data is encrypted in transit and at rest, and access is limited to authorised clinic staff. "
                              "Your information is collected on behalf of your clinic to support assessment preparation.\n\n"
                              "You may request access, correction, or deletion of your information, and you can withdraw consent "
                              "by contacting your clinic.",
                              style: TextStyle(fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _openPrivacyPolicy,
                              child: const Text(
                                "View Full Privacy Policy",
                                style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'If your symptoms suddenly worsen (for example: severe dizziness, trouble speaking, new weakness in arms or legs, '
                                'or loss of bladder/bowel control), seek urgent medical attention.',
                                style: TextStyle(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!_canContinue)
                      Text(
                        'Please accept the required consent to continue.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_canContinue && !_isNavigating) ? _continue : null,
                  child: const Text("I Agree and Continue"),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (_showPreOverlay)
          AnimatedOpacity(
            opacity: _preVisible ? 1.0 : 0.0,
            duration: _fade,
            child: Container(
              color: Colors.white,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Pre-assessment Questionnaire',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: navy,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Everyone’s journey is different\n'
                      'Help us understand your needs\n'
                      'to guide you in the right direction.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: navy,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8, color: Colors.black54),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
