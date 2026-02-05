// lib/preassessment/flows/region_select/region_select_screen.dart
//
// ✅ Updated in full
// - NO re-wrapping IntakeDraftController (prevents "used after disposed")
// - Uses context.read for draft (list won’t rebuild on answer changes)
// - Pushes DynamicFlowScreen directly; it inherits the existing provider scope
// - Keeps your label resolver + fallback display label

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/intake_draft_controller.dart';
import '../../domain/intake_schema.dart';
import '../../domain/flow_definition.dart';
import '../regions/dynamic_flow_screen.dart';

import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/ankle/ankle_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/knee/knee_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/hip/hip_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/lumbar/lumbar_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/cervical/cervical_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/thoracic/thoracic_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/shoulder/shoulder_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/elbow/elbow_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/wrist/wrist_flow_v1.dart';

import 'package:kineticdx_app_v3/preassessment/domain/labels/preassessment_label_resolver.dart';

class RegionSelectScreen extends StatefulWidget {
  const RegionSelectScreen({super.key});

  @override
  State<RegionSelectScreen> createState() => _RegionSelectScreenState();
}

class _RegionSelectScreenState extends State<RegionSelectScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedOverlayId;
  String? _hoveredOverlayId;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Map<String, FlowDefinition> _buildFlows() {
    return <String, FlowDefinition>{
      'region.ankle': ankleFlowV1,
      'region.knee': kneeFlowV1,
      'region.hip': hipFlowV1,
      'region.lumbar': lumbarFlowV1,
      'region.cervical': cervicalFlowV1,
      'region.thoracic': thoracicFlowV1,
      'region.shoulder': shoulderFlowV1,
      'region.elbow': elbowFlowV1,
      'region.wrist': wristFlowV1,
    };
  }

  Future<void> _handleRegionTap(
    BuildContext context, {
    required String regionId,
    required String side,
    required String overlayId,
  }) async {
    if (_selectedOverlayId != null) return; // prevent double taps

    final draft = context.read<IntakeDraftController>();
    final flows = _buildFlows();
    final flow = flows[regionId];
    if (flow == null) return;

    setState(() {
      _selectedOverlayId = overlayId;
    });

    // Write regionSelection immediately so backend sees it even if navigation fails.
    draft.setRegionSelection(
      RegionSelectionBlock(
        bodyArea: regionId,
        side: side,
        regionSetVersion: 1,
        selectedAt: null,
      ),
    );

    // Play fade-out animation, then navigate to the dynamic flow.
    await _fadeController.forward();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DynamicFlowScreen(
          flow: flow,
          answers: draft.answers, // legacy snapshot param (ok)
          onAnswerChanged: (qid, v) => draft.setAnswer(qid, v),
          t: (k) => resolvePreassessmentLabel(flow.flowId, k),
          onContinue: null, // default goes to GoalsScreen
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _selectedOverlayId = null;
      _fadeController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Select area')),
      body: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(
            parent: _fadeController,
            curve: Curves.easeInOut,
          ),
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final width = constraints.maxWidth;

                Color overlayColorFor(String overlayId) {
                  if (overlayId == _selectedOverlayId) {
                    return theme.colorScheme.error.withOpacity(0.20);
                  }
                  if (overlayId == _hoveredOverlayId) {
                    return theme.colorScheme.error.withOpacity(0.12);
                  }
                  return Colors.transparent;
                }

                String _areaLabelFor(String? overlayId) {
                  if (overlayId == null) return '—';
                  switch (overlayId) {
                    case 'cervical.center':
                      return 'Neck';
                    case 'thoracic.center':
                      return 'Mid back';
                    case 'lumbar.center':
                      return 'Lower back';
                    case 'shoulder.right':
                      return 'Right shoulder';
                    case 'shoulder.left':
                      return 'Left shoulder';
                    case 'elbow.right':
                      return 'Right elbow';
                    case 'elbow.left':
                      return 'Left elbow';
                    case 'wrist.right':
                      return 'Right wrist';
                    case 'wrist.left':
                      return 'Left wrist';
                    case 'hip.right':
                      return 'Right hip';
                    case 'hip.left':
                      return 'Left hip';
                    case 'knee.right':
                      return 'Right knee';
                    case 'knee.left':
                      return 'Left knee';
                    case 'ankle.right':
                      return 'Right ankle';
                    case 'ankle.left':
                      return 'Left ankle';
                    default:
                      return '—';
                  }
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Area title + dynamic label box (shows hovered region)
                    Positioned(
                      top: height * 0.02,
                      left: width * 0.25,
                      right: width * 0.25,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Area',
                            style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ) ??
                                const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.9),
                              border: Border.all(
                                color:
                                    theme.colorScheme.outline.withOpacity(0.5),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _areaLabelFor(_hoveredOverlayId),
                              style: theme.textTheme.bodyMedium ??
                                  const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Base body map image
                    Image.asset(
                      'assets/body_map_person.png',
                      fit: BoxFit.contain,
                    ),

                    // Cervical / neck
                    Positioned(
                      top: height * 0.20,
                      left: width * 0.40,
                      right: width * 0.40,
                      height: height * 0.06,
                      child: MouseRegion(
                        onEnter: (_) => setState(
                            () => _hoveredOverlayId = 'cervical.center'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.cervical',
                            side: 'side.unknown',
                            overlayId: 'cervical.center',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('cervical.center'),
                              shape: BoxShape.rectangle,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Thoracic / mid back — doubled size, centered
                    Positioned(
                      top: height * 0.30,
                      left: width * (19 / 50),
                      width: width * (6 / 25),
                      height: height * 0.04,
                      child: MouseRegion(
                        onEnter: (_) => setState(
                            () => _hoveredOverlayId = 'thoracic.center'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.thoracic',
                            side: 'side.unknown',
                            overlayId: 'thoracic.center',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('thoracic.center'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Lumbar / lower back
                    Positioned(
                      top: height * 0.35,
                      left: width * 0.40,
                      right: width * 0.40,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'lumbar.center'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.lumbar',
                            side: 'side.unknown',
                            overlayId: 'lumbar.center',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('lumbar.center'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // -------------------- UPPER LIMBS --------------------
                    // Right shoulder (0.1 closer to body = shift right)
                    Positioned(
                      top: height * 0.25,
                      left: width * 0.27,
                      width: width * 0.18,
                      height: height * 0.08,
                      child: MouseRegion(
                        onEnter: (_) => setState(
                            () => _hoveredOverlayId = 'shoulder.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.shoulder',
                            side: 'side.right',
                            overlayId: 'shoulder.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('shoulder.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left shoulder (0.1 closer to body = shift left)
                    Positioned(
                      top: height * 0.25,
                      right: width * 0.27,
                      width: width * 0.18,
                      height: height * 0.08,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'shoulder.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.shoulder',
                            side: 'side.left',
                            overlayId: 'shoulder.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('shoulder.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Right elbow (down 0.1, right 0.2)
                    Positioned(
                      top: height * 0.30,
                      left: width * 0.20,
                      width: width * 0.22,
                      height: height * 0.08,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'elbow.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.elbow',
                            side: 'side.right',
                            overlayId: 'elbow.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('elbow.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left elbow (down 0.1, left 0.2)
                    Positioned(
                      top: height * 0.30,
                      right: width * 0.20,
                      width: width * 0.22,
                      height: height * 0.08,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'elbow.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.elbow',
                            side: 'side.left',
                            overlayId: 'elbow.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('elbow.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Right wrist / hand
                    Positioned(
                      top: height * 0.45,
                      left: width * 0.18,
                      width: width * 0.22,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'wrist.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.wrist',
                            side: 'side.right',
                            overlayId: 'wrist.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('wrist.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left wrist / hand
                    Positioned(
                      top: height * 0.45,
                      right: width * 0.18,
                      width: width * 0.22,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'wrist.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.wrist',
                            side: 'side.left',
                            overlayId: 'wrist.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('wrist.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // -------------------- HIPS / LOWER LIMBS --------------------
                    // Right hip
                    Positioned(
                      top: height * 0.45,
                      left: width * 0.35,
                      width: width * 0.14,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'hip.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.hip',
                            side: 'side.right',
                            overlayId: 'hip.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('hip.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left hip
                    Positioned(
                      top: height * 0.45,
                      right: width * 0.35,
                      width: width * 0.14,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'hip.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.hip',
                            side: 'side.left',
                            overlayId: 'hip.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('hip.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Right knee
                    Positioned(
                      top: height * 0.55,
                      left: width * 0.35,
                      width: width * 0.12,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'knee.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.knee',
                            side: 'side.right',
                            overlayId: 'knee.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('knee.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left knee
                    Positioned(
                      top: height * 0.55,
                      right: width * 0.35,
                      width: width * 0.12,
                      height: height * 0.10,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'knee.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.knee',
                            side: 'side.left',
                            overlayId: 'knee.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('knee.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Right ankle / foot
                    Positioned(
                      top: height * 0.73,
                      left: width * 0.35,
                      width: width * 0.10,
                      height: height * 0.12,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'ankle.right'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.ankle',
                            side: 'side.right',
                            overlayId: 'ankle.right',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('ankle.right'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left ankle / foot
                    Positioned(
                      top: height * 0.73,
                      right: width * 0.35,
                      width: width * 0.10,
                      height: height * 0.12,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredOverlayId = 'ankle.left'),
                        onExit: (_) => setState(() => _hoveredOverlayId = null),
                        child: GestureDetector(
                          onTap: () => _handleRegionTap(
                            context,
                            regionId: 'region.ankle',
                            side: 'side.left',
                            overlayId: 'ankle.left',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: overlayColorFor('ankle.left'),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Side labels (above head, ~0.12 height): "Right side" on left, "Left side" on right
                    Positioned(
                      top: height * 0.12,
                      left: width * 0.02,
                      child: const Text(
                        'Right side',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Positioned(
                      top: height * 0.12,
                      right: width * 0.02,
                      child: const Text(
                        'Left side',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
