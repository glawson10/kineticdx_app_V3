// lib/preassessment/screens/general_questionnaire_token_screen.dart
//
// Public token entry for the General Questionnaire.
// Resolves token -> intakeSessionId via Cloud Function and starts the flow.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/intake_draft_controller.dart';
import './intake_flow_host.dart';

class GeneralQuestionnaireTokenScreen extends StatefulWidget {
  const GeneralQuestionnaireTokenScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<GeneralQuestionnaireTokenScreen> createState() =>
      _GeneralQuestionnaireTokenScreenState();
}

class _GeneralQuestionnaireTokenScreenState
    extends State<GeneralQuestionnaireTokenScreen> {
  bool _loading = true;
  String? _error;
  bool _booted = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _boot();
    });
  }

  String _friendlyFunctionsError(FirebaseFunctionsException e) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();

    if (code == 'failed-precondition' && msg.contains('expired')) {
      return 'This link has expired.\n\nPlease ask the clinic to resend the form.';
    }
    if (code == 'failed-precondition' &&
        (msg.contains('used') || msg.contains('submitted'))) {
      return 'This link has already been submitted.\n\nIf you need to change anything, please contact the clinic.';
    }
    if (code == 'not-found') {
      return 'This link is invalid.\n\nPlease use the full link from the email.';
    }

    // Catch-all for internal/backend issues (eg. missing index, transient errors)
    if (code == 'internal' || code == 'unknown') {
      return 'We could not start your questionnaire right now.\n\n'
          'Please try again in a few minutes. If the problem continues, contact the clinic so they can check their system.';
    }

    return 'Server error.\n\ncode: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}';
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = widget.token.trim();
      if (token.isEmpty) {
        throw Exception(
          'Missing link token.\n\nPlease use the full link from the email.',
        );
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('resolveIntakeLinkTokenFn');

      final resp = await fn.call(<String, dynamic>{
        'token': token,
      });

      if (resp.data is! Map) {
        throw Exception('Server returned unexpected payload: ${resp.data}');
      }

      final data = Map<String, dynamic>.from(resp.data as Map);
      final clinicId = (data['clinicId'] ?? '').toString().trim();
      final sessionId = (data['intakeSessionId'] ?? '').toString().trim();
      final flowId = (data['flowId'] ?? '').toString().trim();

      if (clinicId.isEmpty) {
        throw Exception('Server did not return a clinicId.');
      }
      if (sessionId.isEmpty) {
        throw Exception('Server did not return a sessionId.');
      }

      if (!mounted) return;

      _navigateToFlowHost(
        clinicId: clinicId,
        sessionId: sessionId,
        flowIdOverride: flowId.isNotEmpty ? flowId : 'generalVisit',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyFunctionsError(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      if (mounted && !_navigated) {
        setState(() => _loading = false);
      }
    }
  }

  void _navigateToFlowHost({
    required String clinicId,
    required String sessionId,
    required String flowIdOverride,
  }) {
    if (_navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider<IntakeDraftController>(
            create: (_) {
              final draft = IntakeDraftController(clinicId: clinicId);
              draft.setSessionId(sessionId);
              return draft;
            },
            child: IntakeFlowHost(
              flowArgs: <String, dynamic>{
                'clinicId': clinicId,
                'intakeSessionId': sessionId,
                'flowIdOverride': flowIdOverride,
              },
            ),
          ),
        ),
      );
    });
  }

  void _retry() {
    _booted = false;
    _navigated = false;
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starting questionnaire')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparing your questionnaire...'),
                  ],
                )
              : (_error != null)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
