// lib/preassessment/screens/intake_start_screen.dart
//
// ✅ Updated in full:
// - Supports BOTH link-based entry (?c=...&t=...) AND in-app entry (clinicIdOverride)
// - Provider is the single owner of IntakeDraftController
// - DEV bypass supported via:
//    • bypassServer (existing)
//    • devBypassOverride (new, preferred for in-app launches)
//    • ?dev=1 / ?dev=true (URL)
// - Token can be supplied via tokenOverride (for clinician starts, etc.)
// - ✅ Adds flowIdOverride (e.g. "generalVisit") to start a specific flow from clinician UI
// - ✅ In dev bypass: best-effort create clinics/{clinicId}/intakeSessions/{sessionId}
//   and sets flowId/flowCategory when provided.
// - Passes flow args into IntakeFlowHost so downstream screens can route correctly
// - Friendly errors + prevents double boot/navigation

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import './intake_flow_host.dart';
import '../state/intake_draft_controller.dart';

class IntakeStartScreen extends StatefulWidget {
  /// If launching from inside the app (not a link), pass clinicIdOverride.
  final String? clinicIdOverride;

  /// Optional token override (useful for in-app/testing starts).
  /// NOTE: in bypass mode, token is ignored.
  final String? tokenOverride;

  /// Legacy/explicit bypass flag (kept for compatibility).
  final bool bypassServer;

  /// New explicit bypass flag (preferred for in-app launches).
  final bool? devBypassOverride;

  /// ✅ Optional: start a specific flow without region selection routing.
  /// Example: "generalVisit"
  final String? flowIdOverride;

  const IntakeStartScreen({
    super.key,
    this.clinicIdOverride,
    this.tokenOverride,
    this.bypassServer = false,
    this.devBypassOverride,
    this.flowIdOverride,
  });

  @override
  State<IntakeStartScreen> createState() => _IntakeStartScreenState();
}

class _IntakeStartScreenState extends State<IntakeStartScreen> {
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

  /// Reads query params from BOTH:
  /// - normal URL query:    https://host/intake/start?c=...&t=...
  /// - hash fragment query: https://host/#/intake/start?c=...&t=...
  String _qp(String key) {
    try {
      final base = Uri.base;

      final v1 = (base.queryParameters[key] ?? '').trim();
      if (v1.isNotEmpty) return v1;

      final frag = base.fragment.trim();
      if (frag.isEmpty) return '';

      final fragUri = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
      final v2 = (fragUri.queryParameters[key] ?? '').trim();
      return v2;
    } catch (_) {
      return '';
    }
  }

  bool _shouldBypassServer() {
    if (widget.devBypassOverride == true) return true;
    if (widget.bypassServer) return true;

    final devFlag = _qp('dev').toLowerCase();
    return devFlag == '1' || devFlag == 'true';
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

    return 'Server error.\n\ncode: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}';
  }

  // ---------------------------------------------------------------------------
  // ✅ DEV bypass support: try to ensure a Firestore session doc exists
  // ---------------------------------------------------------------------------

  Future<void> _ensureDevSessionDoc({
    required String clinicId,
    required String sessionId,
    required String? flowIdOverride,
  }) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('intakeSessions')
          .doc(sessionId);

      final snap = await ref.get();
      if (snap.exists) return;

      final flowId = (flowIdOverride ?? '').trim(); // may be empty
      final isGeneral = flowId == 'generalVisit';
      final flowCategory = isGeneral ? 'general' : 'region';

      await ref.set({
        'schemaVersion': 1,
        'clinicId': clinicId,
        'status': 'draft',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'submittedAt': null,
        'lockedAt': null,

        // ✅ Only set flowId if explicitly overridden.
        // Otherwise let the intake flow decide via normal region selection later.
        if (flowId.isNotEmpty) ...{
          'flowId': flowId,
          'flowVersion': 1,
          'flowCategory': flowCategory,
          'flow': {'flowId': flowId, 'flowVersion': 1},
        },

        // placeholders
        'consent': null,
        'patientDetails': null,

        // ✅ General visit skips region selection; region flows will fill it later.
        'regionSelection': null,

        'answers': {},

        // summary placeholders
        'triage': null,
        'summary': null,
        'summaryStatus': 'pending',
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // ✅ Critical: DO NOT fail dev startup if Firestore rules deny this.
      debugPrint('⚠️ _ensureDevSessionDoc skipped: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('⚠️ _ensureDevSessionDoc skipped: $e');
    }
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ Prefer in-app clinic override
      final clinicIdOverride = (widget.clinicIdOverride ?? '').trim();
      final clinicIdFromUrl =
          (_qp('c').isNotEmpty ? _qp('c') : _qp('clinicId')).trim();
      final clinicId =
          clinicIdOverride.isNotEmpty ? clinicIdOverride : clinicIdFromUrl;

      // token can come from override or URL
      final tokenFromUrl = _qp('t').trim();
      final token = (widget.tokenOverride ?? '').trim().isNotEmpty
          ? (widget.tokenOverride ?? '').trim()
          : tokenFromUrl;

      // ✅ flow override can be supplied in-app, or via URL (?flow=generalVisit)
      final flowOverrideFromUrl = _qp('flow').trim();
      final flowIdOverride = (widget.flowIdOverride ?? '').trim().isNotEmpty
          ? (widget.flowIdOverride ?? '').trim()
          : flowOverrideFromUrl;

      if (clinicId.isEmpty) {
        throw Exception(
          'Missing clinicId.\n\n'
          'If launching from inside the app, pass clinicIdOverride.\n'
          'If launching from a link, ensure ?c=... is present.',
        );
      }

      // ----------------------------
      // ✅ BYPASS (in-app / dev)
      // ----------------------------
      if (_shouldBypassServer()) {
        final localSessionId = 'dev_${DateTime.now().millisecondsSinceEpoch}';

        // ✅ Best-effort: create the Firestore session doc if permitted.
        await _ensureDevSessionDoc(
          clinicId: clinicId,
          sessionId: localSessionId,
          flowIdOverride: flowIdOverride.isNotEmpty ? flowIdOverride : null,
        );

        if (!mounted) return;
        _navigateToFlowHost(
          clinicId: clinicId,
          sessionId: localSessionId,
          flowIdOverride: flowIdOverride.isNotEmpty ? flowIdOverride : null,
        );
        return;
      }

      // ----------------------------
      // LINK FLOW requires token
      // ----------------------------
      if (token.isEmpty) {
        throw Exception('Missing link token.\n\nPlease use the full link from the email.');
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('consumeIntakeInviteFn');

      final resp = await fn.call(<String, dynamic>{
        'clinicId': clinicId,
        'token': token,
      });

      if (resp.data is! Map) {
        throw Exception('Server returned unexpected payload: ${resp.data}');
      }

      final data = Map<String, dynamic>.from(resp.data as Map);
      final sessionId = (data['sessionId'] ?? '').toString().trim();
      if (sessionId.isEmpty) {
        throw Exception('Server did not return a sessionId.');
      }

      // If the server returned a flow, prefer that. Otherwise use override (rare).
      final serverFlowId = (data['flowId'] ?? '').toString().trim();
      final effectiveFlowId =
          serverFlowId.isNotEmpty ? serverFlowId : flowIdOverride;

      if (!mounted) return;

      _navigateToFlowHost(
        clinicId: clinicId,
        sessionId: sessionId,
        flowIdOverride: effectiveFlowId.isNotEmpty ? effectiveFlowId : null,
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
    String? flowIdOverride,
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
                if (flowIdOverride != null && flowIdOverride.trim().isNotEmpty)
                  'flowIdOverride': flowIdOverride.trim(),
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
      appBar: AppBar(title: const Text('Starting pre-assessment')),
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
