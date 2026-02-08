import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/clinic_context.dart';
import '../../../../data/repositories/clinic_registry_repository.dart';
import '../../../../models/clinical_test_registry_item.dart';
import '../../../../models/clinical_tests.dart';
import '../../data/initial_assessment_note.dart';

/// Special tests picker for Initial Assessment notes.
///
/// - Clinic scoped (reads from clinics/{clinicId}/clinicalTestRegistry)
/// - Filters tests by [bodyRegion] and [activeOnly]
/// - Stores selections as [SpecialTestResult] with registry testId
class SpecialTestsPicker extends StatefulWidget {
  final String clinicId;
  final BodyRegion bodyRegion;
  final List<SpecialTestResult> value;
  final ValueChanged<List<SpecialTestResult>> onChanged;
  final bool readOnly;

  const SpecialTestsPicker({
    super.key,
    required this.clinicId,
    required this.bodyRegion,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<SpecialTestsPicker> createState() => _SpecialTestsPickerState();
}

class _SpecialTestsPickerState extends State<SpecialTestsPicker> {
  final ClinicRegistryRepository _repo = ClinicRegistryRepository();
  final TextEditingController _search = TextEditingController();
  late Stream<List<ClinicalTestRegistryItem>> _testsStream;

  @override
  void initState() {
    super.initState();
    _testsStream = _repo.streamClinicalTests(
      clinicId: widget.clinicId,
      activeOnly: true,
    );
  }

  @override
  void didUpdateWidget(SpecialTestsPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) {
      _testsStream = _repo.streamClinicalTests(
        clinicId: widget.clinicId,
        activeOnly: true,
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search special tests',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() => _search.clear()),
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<ClinicalTestRegistryItem>>(
            stream: _testsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final tests = _filterAndSort(snap.data!);
              if (tests.isEmpty) {
                return const Center(
                  child: Text(
                    'No active tests for this region.\n'
                    'Configure tests under Clinic Settings → Clinical test registry.',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final selectedById = {
                for (final s in widget.value) s.testId: s,
              };

              return ListView.separated(
                itemCount: tests.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final t = tests[index];
                  final selected = selectedById[t.id];
                  final isSelected = selected != null;

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    title: Text(
                      t.name,
                      style: TextStyle(
                        fontWeight:
                            _isCommon(t.id) ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    subtitle: _subtitle(t),
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: widget.readOnly
                          ? null
                          : (v) {
                              if (v == true) {
                                _addTest(t.id);
                              } else {
                                _removeTest(t.id);
                              }
                            },
                    ),
                    onTap: widget.readOnly
                        ? null
                        : () {
                            if (isSelected) {
                              _editSelectedTest(selected);
                            } else {
                              _addTest(t.id);
                            }
                          },
                    trailing: isSelected
                        ? _ResultChips(
                            result: selected!,
                            onChanged: widget.readOnly
                                ? null
                                : (updated) => _updateResult(updated),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<ClinicalTestRegistryItem> _filterAndSort(
    List<ClinicalTestRegistryItem> all,
  ) {
    final regionKey = widget.bodyRegion.name.toLowerCase();
    final query = _search.text.trim().toLowerCase();

    final filtered = all.where((t) {
      if (!t.bodyRegions
          .map((e) => e.toLowerCase())
          .contains(regionKey)) {
        return false;
      }
      if (query.isEmpty) return true;
      final hay = [
        t.name,
        t.shortName ?? '',
        t.category,
        ...t.tags,
        ...t.bodyRegions,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aCommon = _isCommon(a.id);
      final bCommon = _isCommon(b.id);
      if (aCommon != bCommon) {
        return aCommon ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  bool _isCommon(String testId) {
    final def = ClinicalTestRegistry.byId(testId);
    return def?.isCommon == true || (def == null && false);
  }

  Widget _subtitle(ClinicalTestRegistryItem t) {
    final short = (t.shortName?.isNotEmpty == true) ? ' (${t.shortName})' : '';
    final tags = t.tags.isEmpty ? '' : ' • ${t.tags.join(", ")}';
    return Text('${t.category}$short$tags');
  }

  void _addTest(String testId) {
    final next = List<SpecialTestResult>.from(widget.value)
      ..add(
        SpecialTestResult(
          testId: testId,
          result: 'nt',
          side: 'N/A',
          notes: '',
          painScore: 0,
        ),
      );
    widget.onChanged(next);
  }

  void _removeTest(String testId) {
    final next =
        widget.value.where((e) => e.testId != testId).toList(growable: false);
    widget.onChanged(next);
  }

  void _updateResult(SpecialTestResult updated) {
    final next = widget.value
        .map((e) => e.testId == updated.testId ? updated : e)
        .toList(growable: false);
    widget.onChanged(next);
  }

  Future<void> _editSelectedTest(SpecialTestResult? current) async {
    if (current == null) return;

    final updated = await showDialog<SpecialTestResult>(
      context: context,
      builder: (context) {
        return _EditSpecialTestResultDialog(initial: current);
      },
    );
    if (updated == null) return;
    _updateResult(updated);
  }
}

class _ResultChips extends StatelessWidget {
  final SpecialTestResult result;
  final ValueChanged<SpecialTestResult>? onChanged;

  const _ResultChips({
    required this.result,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnChanged = onChanged;
    if (effectiveOnChanged == null) {
      return _buildStatic(context);
    }
    return Wrap(
      spacing: 4,
      children: [
        DropdownButton<String>(
          value: result.result,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'pos', child: Text('pos')),
            DropdownMenuItem(value: 'neg', child: Text('neg')),
            DropdownMenuItem(value: 'nt', child: Text('nt')),
            DropdownMenuItem(value: 'na', child: Text('n/a')),
          ],
          onChanged: (v) {
            if (v == null) return;
            effectiveOnChanged(
              SpecialTestResult(
                testId: result.testId,
                result: v,
                side: result.side,
                notes: result.notes,
                painScore: result.painScore,
              ),
            );
          },
        ),
        DropdownButton<String>(
          value: result.side,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'L', child: Text('L')),
            DropdownMenuItem(value: 'R', child: Text('R')),
            DropdownMenuItem(value: 'B', child: Text('B')),
            DropdownMenuItem(value: 'N/A', child: Text('N/A')),
          ],
          onChanged: (v) {
            if (v == null) return;
            effectiveOnChanged(
              SpecialTestResult(
                testId: result.testId,
                result: result.result,
                side: v,
                notes: result.notes,
                painScore: result.painScore,
              ),
            );
          },
        ),
        Text('Pain: ${result.painScore}/10'),
      ],
    );
  }

  Widget _buildStatic(BuildContext context) {
    return Text(
      '${result.result.toUpperCase()} • ${result.side} • pain ${result.painScore}/10',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _EditSpecialTestResultDialog extends StatefulWidget {
  final SpecialTestResult initial;

  const _EditSpecialTestResultDialog({required this.initial});

  @override
  State<_EditSpecialTestResultDialog> createState() =>
      _EditSpecialTestResultDialogState();
}

class _EditSpecialTestResultDialogState
    extends State<_EditSpecialTestResultDialog> {
  late String _result;
  late String _side;
  late double _pain;
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _result = widget.initial.result;
    _side = widget.initial.side;
    _pain = widget.initial.painScore.toDouble();
    _notes.text = widget.initial.notes;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit special test'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Result'),
                  value: _result,
                  items: const [
                    DropdownMenuItem(value: 'pos', child: Text('Positive')),
                    DropdownMenuItem(value: 'neg', child: Text('Negative')),
                    DropdownMenuItem(value: 'nt', child: Text('Not tested')),
                    DropdownMenuItem(value: 'na', child: Text('N/A')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _result = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Side'),
                  value: _side,
                  items: const [
                    DropdownMenuItem(value: 'L', child: Text('Left')),
                    DropdownMenuItem(value: 'R', child: Text('Right')),
                    DropdownMenuItem(value: 'B', child: Text('Bilateral')),
                    DropdownMenuItem(value: 'N/A', child: Text('N/A')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _side = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Pain'),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 10,
                  divisions: 10,
                  value: _pain,
                  label: _pain.toStringAsFixed(0),
                  onChanged: (v) => setState(() => _pain = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              SpecialTestResult(
                testId: widget.initial.testId,
                result: _result,
                side: _side,
                notes: _notes.text.trim(),
                painScore: _pain.round(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

