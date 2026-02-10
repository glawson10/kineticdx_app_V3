import 'package:flutter/material.dart';

import '../../data/body_chart.dart';
import 'body_chart_canvas.dart';

/// Main body chart editor widget with front/back tabs, symptom picker, and drawing canvas.
class BodyChartEditor extends StatefulWidget {
  final BodyChartState value;
  final ValueChanged<BodyChartState> onChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final bool readOnly;

  const BodyChartEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.readOnly = false,
  });

  @override
  State<BodyChartEditor> createState() => _BodyChartEditorState();
}

class _BodyChartEditorState extends State<BodyChartEditor> {
  BodyChartSide _currentSide = BodyChartSide.front;
  SymptomType _currentSymptomType = SymptomType.pain;

  @override
  Widget build(BuildContext context) {
    final currentStrokes = _currentSide == BodyChartSide.front
        ? widget.value.frontStrokes
        : widget.value.backStrokes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.draw, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Body chart',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Mark areas of pain, stiffness or altered sensation',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            // Symptom type picker
            if (!widget.readOnly) _buildSymptomTypePicker(),
            if (!widget.readOnly) const SizedBox(height: 16),

            // Side selector (Front / Back)
            _buildSideSelector(),
            const SizedBox(height: 16),

            // Drawing canvas
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 0.5, // body charts are typically tall/narrow
                    child: BodyChartCanvas(
                      assetPath: _currentSide == BodyChartSide.front
                          ? 'assets/body_front.png'
                          : 'assets/body_back.png',
                      strokes: currentStrokes,
                      currentSymptomType: _currentSymptomType,
                      onStrokesChanged: (updatedStrokes) {
                        if (widget.readOnly) return;
                        final newState = _currentSide == BodyChartSide.front
                            ? widget.value.copyWithFront(updatedStrokes)
                            : widget.value.copyWithBack(updatedStrokes);
                        widget.onChanged(newState);
                      },
                      onInteractionStart: widget.onInteractionStart,
                      onInteractionEnd: widget.onInteractionEnd,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Color legend
            _buildLegend(),

            const SizedBox(height: 12),

            // Undo / Clear buttons
            if (!widget.readOnly) _buildActionButtons(currentStrokes),
          ],
        ),
      ),
    );
  }

  Widget _buildSideSelector() {
    return SegmentedButton<BodyChartSide>(
      segments: const [
        ButtonSegment(
          value: BodyChartSide.front,
          label: Text('Front'),
          icon: Icon(Icons.person),
        ),
        ButtonSegment(
          value: BodyChartSide.back,
          label: Text('Back'),
          icon: Icon(Icons.person_outline),
        ),
      ],
      selected: {_currentSide},
      onSelectionChanged: widget.readOnly
          ? null
          : (Set<BodyChartSide> selected) {
              setState(() {
                _currentSide = selected.first;
              });
            },
    );
  }

  Widget _buildSymptomTypePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SymptomType.values.map((type) {
        final isSelected = _currentSymptomType == type;
        return ChoiceChip(
          label: Text(type.label),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _currentSymptomType = type;
              });
            }
          },
          avatar: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Color(type.colorValue),
              shape: BoxShape.circle,
            ),
          ),
          selectedColor: Color(type.colorValue).withOpacity(0.2),
          labelStyle: TextStyle(
            color: isSelected ? Color(type.colorValue) : null,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: SymptomType.values.map((type) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: type.strokeWidth,
              decoration: BoxDecoration(
                color: Color(type.colorValue),
                borderRadius: BorderRadius.circular(type.strokeWidth / 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              type.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons(List<BodyChartStroke> currentStrokes) {
    final canUndo = currentStrokes.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canUndo ? _clear : null,
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
          ),
        ),
      ],
    );
  }

  void _undo() {
    final currentStrokes = _currentSide == BodyChartSide.front
        ? widget.value.frontStrokes
        : widget.value.backStrokes;

    if (currentStrokes.isEmpty) return;

    final updatedStrokes = List<BodyChartStroke>.from(currentStrokes)
      ..removeLast();

    final newState = _currentSide == BodyChartSide.front
        ? widget.value.copyWithFront(updatedStrokes)
        : widget.value.copyWithBack(updatedStrokes);

    widget.onChanged(newState);
  }

  void _clear() {
    final newState = _currentSide == BodyChartSide.front
        ? widget.value.copyWithFront([])
        : widget.value.copyWithBack([]);

    widget.onChanged(newState);
  }
}
