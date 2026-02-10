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
    _selectedOverlays = _overlaysFromSelected(_selected);
  }

  @override
  void didUpdateWidget(covariant GeneralVisitBodyAreasQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.value?.asMulti ?? const <String>[]).toSet();
    if (!setEquals(_selected, next)) {
      _selected = next;
      _selectedOverlays = _overlaysFromSelected(_selected);
    }
  }

  /// When loading from saved value we only have optionIds; show all overlays for each (both sides).
  Set<String> _overlaysFromSelected(Set<String> optionIds) {
    final out = <String>{};
    for (final optionId in optionIds) {
      out.addAll(_overlayIdsForOptionId(optionId));
    }
    return out;
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

  /// Overlay IDs that map to this optionId (for syncing list selection with chart).
  List<String> _overlayIdsForOptionId(String optionId) {
    switch (optionId) {
      case 'area.neck':
        return ['cervical.center'];
      case 'area.upperBack':
        return ['thoracic.center'];
      case 'area.lowerBack':
        return ['lumbar.center'];
      case 'area.shoulder':
        return ['shoulder.left', 'shoulder.right'];
      case 'area.elbow':
        return ['elbow.left', 'elbow.right'];
      case 'area.wristHand':
        return ['wrist.left', 'wrist.right'];
      case 'area.hip':
        return ['hip.left', 'hip.right'];
      case 'area.knee':
        return ['knee.left', 'knee.right'];
      case 'area.ankleFoot':
        return ['ankle.left', 'ankle.right'];
      default:
        return [];
    }
  }

  void _onSelectFromList(String overlayId) {
    final optionId = _optionIdForOverlay(overlayId);
    if (optionId.isEmpty) return;
    setState(() {
      if (_selectedOverlays.contains(overlayId)) {
        _selectedOverlays.remove(overlayId);
      } else {
        _selectedOverlays.add(overlayId);
      }
      // Keep optionId in _selected if any overlay for that option is selected.
      final hasAny = _selectedOverlays
          .any((o) => _optionIdForOverlay(o) == optionId);
      if (hasAny) {
        _selected.add(optionId);
      } else {
        _selected.remove(optionId);
      }
      widget.onChanged(
        _selected.isEmpty ? null : AnswerValue.multi(_selected.toList()),
      );
    });
  }

  /// List entries: label, optionId, and overlayId. Selecting a row toggles only that overlay (left or right).
  static const List<({String label, String optionId, String overlayId})> _areaListEntries = [
    (label: 'Neck', optionId: 'area.neck', overlayId: 'cervical.center'),
    (label: 'Mid back', optionId: 'area.upperBack', overlayId: 'thoracic.center'),
    (label: 'Lower back', optionId: 'area.lowerBack', overlayId: 'lumbar.center'),
    (label: 'Shoulder (left)', optionId: 'area.shoulder', overlayId: 'shoulder.left'),
    (label: 'Shoulder (right)', optionId: 'area.shoulder', overlayId: 'shoulder.right'),
    (label: 'Elbow (left)', optionId: 'area.elbow', overlayId: 'elbow.left'),
    (label: 'Elbow (right)', optionId: 'area.elbow', overlayId: 'elbow.right'),
    (label: 'Wrist / hand (left)', optionId: 'area.wristHand', overlayId: 'wrist.left'),
    (label: 'Wrist / hand (right)', optionId: 'area.wristHand', overlayId: 'wrist.right'),
    (label: 'Hip (left)', optionId: 'area.hip', overlayId: 'hip.left'),
    (label: 'Hip (right)', optionId: 'area.hip', overlayId: 'hip.right'),
    (label: 'Knee (left)', optionId: 'area.knee', overlayId: 'knee.left'),
    (label: 'Knee (right)', optionId: 'area.knee', overlayId: 'knee.right'),
    (label: 'Ankle / foot (left)', optionId: 'area.ankleFoot', overlayId: 'ankle.left'),
    (label: 'Ankle / foot (right)', optionId: 'area.ankleFoot', overlayId: 'ankle.right'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

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
      helper: 'Tap the body or choose from the list below. You can select multiple areas.',
      child: SizedBox(
        height: mapHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;

            // Centered content: chart + list side by side, aligned with body regions
            const double maxContentWidth = 720;
            final contentWidth = width > maxContentWidth ? maxContentWidth : width;
            final chartWidth = contentWidth * 0.48;
            final listWidth = contentWidth * 0.52;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Body chart (left) – image centered so overlay hit areas align with figure
                    SizedBox(
                      width: chartWidth,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Base body map image
                          Image.asset(
                            'assets/body_map_person.png',
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),

                // Cervical / neck
                Positioned(
                  // Mobile values are tuned visually; desktop offset slightly upwards
                  top: isMobile ? height * 0.15 : height * 0.17,
                  left: chartWidth * 0.40,
                  right: chartWidth * 0.40,
                  height: isMobile ? height * 0.08 : height * 0.06,
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
                  top: isMobile ? height * 0.25 : height * 0.27,
                  left: chartWidth * (19 / 50),
                  width: chartWidth * (6 / 25),
                  height: isMobile ? height * 0.05 : height * 0.04,
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
                  top: isMobile ? height * 0.38 : height * 0.35,
                  left: chartWidth * 0.40,
                  right: chartWidth * 0.40,
                  height: isMobile ? height * 0.12 : height * 0.10,
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

                // Right shoulder (aligned with body chart limbs)
                Positioned(
                  top: isMobile ? height * 0.25 : height * 0.22,
                  left: chartWidth * 0.29,
                  width: chartWidth * 0.18,
                  height: isMobile ? height * 0.10 : height * 0.08,
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
                  top: isMobile ? height * 0.25 : height * 0.22,
                  right: chartWidth * 0.29,
                  width: chartWidth * 0.18,
                  height: isMobile ? height * 0.10 : height * 0.08,
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
                  top: isMobile ? height * 0.38 : height * 0.30,
                  left: chartWidth * 0.25,
                  width: chartWidth * 0.22,
                  height: isMobile ? height * 0.10 : height * 0.08,
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
                  top: isMobile ? height * 0.38 : height * 0.30,
                  right: chartWidth * 0.25,
                  width: chartWidth * 0.22,
                  height: isMobile ? height * 0.10 : height * 0.08,
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
                  left: chartWidth * 0.20,
                  width: chartWidth * 0.22,
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
                  right: chartWidth * 0.20,
                  width: chartWidth * 0.22,
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
                  left: chartWidth * 0.35,
                  width: chartWidth * 0.14,
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
                  right: chartWidth * 0.35,
                  width: chartWidth * 0.14,
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
                  top: height * 0.59,
                  left: chartWidth * 0.35,
                  width: chartWidth * 0.12,
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
                  top: height * 0.59,
                  right: chartWidth * 0.35,
                  width: chartWidth * 0.12,
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
                  top: height * 0.77,
                  left: chartWidth * 0.37,
                  width: chartWidth * 0.10,
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
                  top: height * 0.77,
                  right: chartWidth * 0.37,
                  width: chartWidth * 0.10,
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
                  ),
                ),
                    // Area list (right): all body parts with left/right labels; select from list or chart
                    SizedBox(
                      width: listWidth,
                      height: height,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final entry in _areaListEntries) ...[
                                    Material(
                                      color: _selectedOverlays.contains(entry.overlayId)
                                          ? theme.colorScheme.primaryContainer
                                              .withValues(alpha: 0.6)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        onTap: () =>
                                            _onSelectFromList(entry.overlayId),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _selectedOverlays.contains(entry.overlayId)
                                                    ? Icons.check_circle
                                                    : Icons.circle_outlined,
                                                size: 20,
                                                color: _selectedOverlays.contains(
                                                        entry.overlayId)
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.outline,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  entry.label,
                                                  style: theme.textTheme.bodyMedium
                                                      ?.copyWith(
                                                        fontWeight: _selectedOverlays.contains(
                                                                entry.overlayId)
                                                            ? FontWeight.w600
                                                            : null,
                                                      ) ??
                                                      TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: _selectedOverlays.contains(
                                                                entry.overlayId)
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

