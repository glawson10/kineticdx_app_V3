import 'package:flutter/material.dart';

import '../../../models/soap_note.dart'; // ClinicalTestResult
import '../../../models/clinical_tests.dart'; // ClinicalTestDefinition + registry

/// UI model used by the selector widget.
class SelectedClinicalTest {
  final ClinicalTestDefinition definition;
  ClinicalTestResult result;
  String comments;

  SelectedClinicalTest({
    required this.definition,
    this.result = ClinicalTestResult.notTested,
    this.comments = '',
  });
}

/// Widget that lets you choose tests for a region and mark them as + / -.
class ClinicalTestSelector extends StatefulWidget {
  final BodyRegion initialRegion;
  final List<SelectedClinicalTest> initialSelection;
  final ValueChanged<List<SelectedClinicalTest>> onChanged;

  const ClinicalTestSelector({
    super.key,
    required this.initialRegion,
    this.initialSelection = const [],
    required this.onChanged,
  });

  @override
  State<ClinicalTestSelector> createState() => _ClinicalTestSelectorState();
}

class _ClinicalTestSelectorState extends State<ClinicalTestSelector> {
  late BodyRegion _selectedRegion;
  String _search = '';
  late List<SelectedClinicalTest> _selectedTests;

  @override
  void initState() {
    super.initState();
    _selectedRegion = widget.initialRegion;
    _selectedTests = List<SelectedClinicalTest>.from(widget.initialSelection);
  }

  void _notifyParent() {
    widget.onChanged(List.unmodifiable(_selectedTests));
  }

  void _onAddTest(ClinicalTestDefinition def) {
    final already = _selectedTests.any((t) => t.definition.id == def.id);
    if (already) return;

    setState(() {
      _selectedTests.add(SelectedClinicalTest(definition: def));
    });

    _notifyParent();
  }

  void _onRemoveTest(SelectedClinicalTest sel) {
    setState(() {
      _selectedTests.removeWhere((t) => t.definition.id == sel.definition.id);
    });
    _notifyParent();
  }

  // ---------------------------
  // Search: name, synonyms, structures
  // ---------------------------
  List<ClinicalTestDefinition> _filteredTests() {
    final all = ClinicalTestRegistry.testsForRegion(_selectedRegion);

    if (_search.trim().isEmpty) return all;

    final q = _search.toLowerCase();

    return all.where((t) {
      final nameMatch = t.name.toLowerCase().contains(q);

      final synonymsMatch = t.synonyms
          .any((s) => s.toLowerCase().contains(q));

      final structureMatch = t.primaryStructures
          .any((s) => s.toLowerCase().contains(q));

      final purposeMatch = t.purpose.toLowerCase().contains(q);

      return nameMatch || synonymsMatch || structureMatch || purposeMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tests = _filteredTests();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------------
        // Region selector
        // ---------------------
        Row(
          children: [
            const Text('Body region',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            DropdownButton<BodyRegion>(
              value: _selectedRegion,
              onChanged: (region) {
                if (region == null) return;
                setState(() {
                  _selectedRegion = region;
                });
              },
              items: BodyRegion.values.map((region) {
                return DropdownMenuItem(
                  value: region,
                  child: Text(region.name),
                );
              }).toList(),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ---------------------
        // Search box
        // ---------------------
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search tests (name / synonym / structure)',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _search = value;
            });
          },
        ),

        const SizedBox(height: 12),

        // ---------------------
        // List of available tests
        // ---------------------
        Text(
          'Available tests (${tests.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        SizedBox(
          height: 220,
          child: Card(
            margin: EdgeInsets.zero,
            child: ListView.builder(
              itemCount: tests.length,
              itemBuilder: (context, index) {
                final t = tests[index];
                final alreadySelected =
                    _selectedTests.any((sel) => sel.definition.id == t.id);

                return ListTile(
                  dense: true,
                  leading: t.isCommon
                      ? const Icon(Icons.star, size: 16)
                      : const SizedBox(width: 16),
                  title: Text(t.name),

                  subtitle: (t.synonyms.isNotEmpty)
                      ? Text(
                          t.synonyms.join(', '),
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,

                  trailing: alreadySelected
                      ? const Icon(Icons.check, color: Colors.green)
                      : IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _onAddTest(t),
                        ),
                  onTap: () => _onAddTest(t),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ---------------------
        // Selected tests
        // ---------------------
        Text(
          'Selected tests',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),

        if (_selectedTests.isEmpty)
          const Text(
            'No tests selected yet.',
            style: TextStyle(color: Colors.grey),
          ),
        if (_selectedTests.isNotEmpty)
          Column(
            children: _selectedTests.map((sel) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------------
                      // Header row
                      // ---------------------
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sel.definition.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _onRemoveTest(sel),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // ---------------------
                      // Result chips
                      // ---------------------
                      Wrap(
                        spacing: 8,
                        children: ClinicalTestResult.values.map((r) {
                          final selected = sel.result == r;
                          String label;
                          switch (r) {
                            case ClinicalTestResult.positive:
                              label = 'Positive';
                              break;
                            case ClinicalTestResult.negative:
                              label = 'Negative';
                              break;
                            case ClinicalTestResult.notTested:
                              label = 'Not tested';
                              break;
                          }
                          return ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                sel.result = r;
                              });
                              _notifyParent();
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 8),

                      // ---------------------
                      // Comments box
                      // ---------------------
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Comments (side, angle, pain, etc.)',
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(text: sel.comments),
                        minLines: 1,
                        maxLines: 3,
                        onChanged: (value) {
                          sel.comments = value;
                          _notifyParent();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
