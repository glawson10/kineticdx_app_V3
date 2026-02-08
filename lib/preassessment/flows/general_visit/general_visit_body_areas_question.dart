import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import '../../widgets/question_widgets/question_card.dart';

/// Body-map based multi-select for generalVisit.history.bodyAreas.
///
/// - Pure UI only: stores optionIds using existing multiChoice schema.
/// - OptionId mapping:
///   - area.neck       <- cervical.center
///   - area.upperBack  <- thoracic.center
///   - area.lowerBack  <- lumbar.center
///   - area.shoulder   <- shoulder.{left,right}
///   - area.elbow      <- elbow.{left,right}
///   - area.wristHand  <- wrist.{left,right}
///   - area.hip        <- hip.{left,right}
///   - area.knee       <- knee.{left,right}
///   - area.ankleFoot  <- ankle.{left,right}
class GeneralVisitBodyAreasQuestion extends StatefulWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const GeneralVisitBodyAreasQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  State<GeneralVisitBodyAreasQuestion> createState() =>
      _GeneralVisitBodyAreasQuestionState();
}

class _GeneralVisitBodyAreasQuestionState
    extends State<GeneralVisitBodyAreasQuestion> {
  String? _hoveredOverlayId;
  late Set<String> _selected;
  late Set<String> _selectedOverlays;

  @override
  void initState() {
    super.initState();
    _selected = (widget.value?.asMulti ?? const <String>[]).toSet();
    _selectedOverlays = <String>{};
  }

  @override
  void didUpdateWidget(covariant GeneralVisitBodyAreasQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.value?.asMulti ?? const <String>[]).toSet();
    if (!setEquals(_selected, next)) {
      _selected = next;
    }
  }

  String _optionIdForOverlay(String overlayId) {
    switch (overlayId) {
      case 'cervical.center':
        return 'area.neck';
      case 'thoracic.center':
        return 'area.upperBack';
      case 'lumbar.center':
        return 'area.lowerBack';
      case 'shoulder.right':
      case 'shoulder.left':
        return 'area.shoulder';
      case 'elbow.right':
      case 'elbow.left':
        return 'area.elbow';
      case 'wrist.right':
      case 'wrist.left':
        return 'area.wristHand';
      case 'hip.right':
      case 'hip.left':
        return 'area.hip';
      case 'knee.right':
      case 'knee.left':
        return 'area.knee';
      case 'ankle.right':
      case 'ankle.left':
        return 'area.ankleFoot';
      default:
        return '';
    }
  }

  bool _isOverlaySelected(String overlayId) {
    return _selectedOverlays.contains(overlayId);
  }

  void _onTapOverlay(String overlayId) {
    final optId = _optionIdForOverlay(overlayId);
    if (optId.isEmpty) return;
    setState(() {
      if (_selectedOverlays.contains(overlayId)) {
        _selectedOverlays.remove(overlayId);
      } else {
        _selectedOverlays.add(overlayId);
      }

      // Recompute option selection based on any overlay for that optionId.
      final hasAnyForOption = _selectedOverlays
          .any((o) => _optionIdForOverlay(o) == optId);

      if (hasAnyForOption) {
        _selected.add(optId);
      } else {
        _selected.remove(optId);
      }

      widget.onChanged(
        _selected.isEmpty ? null : AnswerValue.multi(_selected.toList()),
      );
    });
  }

  String _areaLabelFor(String? overlayId) {
    switch (overlayId) {
      case 'cervical.center':
        return 'Neck';
      case 'thoracic.center':
        return 'Mid back';
      case 'lumbar.center':
        return 'Lower back';
      case 'shoulder.right':
      case 'shoulder.left':
        return 'Shoulder';
      case 'elbow.right':
      case 'elbow.left':
        return 'Elbow';
      case 'wrist.right':
      case 'wrist.left':
        return 'Wrist / hand';
      case 'hip.right':
      case 'hip.left':
        return 'Hip';
      case 'knee.right':
      case 'knee.left':
        return 'Knee';
      case 'ankle.right':
      case 'ankle.left':
        return 'Ankle / foot';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color overlayColorFor(String overlayId) {
      if (_isOverlaySelected(overlayId)) {
        return theme.colorScheme.error.withValues(alpha: 0.35);
      }
      if (overlayId == _hoveredOverlayId) {
        return theme.colorScheme.error.withValues(alpha: 0.22);
      }
      return Colors.transparent;
    }

    bool isOverlayActive(String overlayId) {
      return _isOverlaySelected(overlayId) || overlayId == _hoveredOverlayId;
    }

    Decoration regionDecoration(
      String overlayId, {
      BorderRadius? borderRadius,
    }) {
      final baseColor = overlayColorFor(overlayId);
      if (baseColor.opacity == 0.0) {
        return BoxDecoration(
          color: Colors.transparent,
          borderRadius: borderRadius,
        );
      }

      return BoxDecoration(
        borderRadius: borderRadius,
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            baseColor,
            baseColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ),
      );
    }

    // Use roughly half the viewport height so it feels substantial
    // but still smaller than the full-screen region selector.
    final mapHeight = MediaQuery.of(context).size.height * 0.5;

    return QuestionCard(
      title: widget.t(widget.q.promptKey),
      errorText: widget.errorText,
      helper: 'Tap the body to choose all areas involved.',
      child: SizedBox(
        height: mapHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Area title + dynamic label box (shows hovered region)
                Positioned(
                  top: height * 0.02,
                  left: width * 0.20,
                  right: width * 0.20,
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
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: _hoveredOverlayId == null ? 0.0 : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.9),
                            border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _areaLabelFor(_hoveredOverlayId),
                            style: theme.textTheme.bodyMedium ??
                                const TextStyle(fontSize: 14),
                          ),
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
                    onEnter: (_) =>
                        setState(() => _hoveredOverlayId = 'cervical.center'),
                    onExit: (_) => setState(() => _hoveredOverlayId = null),
                    child: GestureDetector(
                      onTap: () => _onTapOverlay('cervical.center'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity:
                            isOverlayActive('cervical.center') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'cervical.center',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Thoracic / mid back
                Positioned(
                  top: height * 0.30,
                  left: width * (19 / 50),
                  width: width * (6 / 25),
                  height: height * 0.04,
                  child: MouseRegion(
                    onEnter: (_) =>
                        setState(() => _hoveredOverlayId = 'thoracic.center'),
                    onExit: (_) => setState(() => _hoveredOverlayId = null),
                    child: GestureDetector(
                      onTap: () => _onTapOverlay('thoracic.center'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity:
                            isOverlayActive('thoracic.center') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'thoracic.center',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('lumbar.center'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('lumbar.center') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'lumbar.center',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Right shoulder
                Positioned(
                  top: height * 0.25,
                  left: width * 0.27,
                  width: width * 0.18,
                  height: height * 0.08,
                  child: MouseRegion(
                    onEnter: (_) =>
                        setState(() => _hoveredOverlayId = 'shoulder.right'),
                    onExit: (_) => setState(() => _hoveredOverlayId = null),
                    child: GestureDetector(
                      onTap: () => _onTapOverlay('shoulder.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity:
                            isOverlayActive('shoulder.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'shoulder.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Left shoulder
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
                      onTap: () => _onTapOverlay('shoulder.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('shoulder.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'shoulder.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Right elbow
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
                      onTap: () => _onTapOverlay('elbow.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('elbow.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'elbow.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Left elbow
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
                      onTap: () => _onTapOverlay('elbow.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('elbow.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'elbow.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('wrist.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('wrist.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'wrist.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('wrist.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('wrist.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'wrist.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

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
                      onTap: () => _onTapOverlay('hip.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('hip.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'hip.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('hip.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('hip.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'hip.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('knee.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('knee.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'knee.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('knee.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('knee.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'knee.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('ankle.right'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('ankle.right') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'ankle.right',
                            borderRadius: BorderRadius.circular(40),
                          ),
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
                      onTap: () => _onTapOverlay('ankle.left'),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        opacity: isOverlayActive('ankle.left') ? 1.0 : 0.0,
                        child: Container(
                          decoration: regionDecoration(
                            'ankle.left',
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

